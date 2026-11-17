"""GeoMDB: tambalan keamanan GeoNode — perbaikan resmi GeoNode yang dibawa mundur ke versi yang belum memilikinya.

Dipasang oleh tambal_preserve.py (perintah tambal-aman) sebagai geonode/security/geomdb_aman.py. Baris pemanggilnya
(bertanda `# geomdb-aman`) hanya dipasang pada kode yang masih rentan; GeoNode yang sudah memperbaikinya tidak diubah.

  K1  injeksi perintah lewat nama layer unggahan (GHSA-9fpx-fr6j-2vh6 / CVE-2026-33050; resmi diperbaiki di
      importer 1.1.4 dan GeoNode 5.0.3+): argumen ogr2ogr dikutip shlex dan dijalankan TANPA shell.
  K2  SSRF lewat pendaftaran layanan & /proxy (CVE-2026-39922; resmi: is_safe_url, GeoNode 5.0.3+): alamat yang
      mengarah ke jaringan lokal/privat ditolak.
  K3  XML unggahan (metadata/SLD) yang membawa konten aktif ditolak: DOCTYPE/DTD, processing instruction, XSLT,
      elemen skrip, atribut on*, URI javascript: (setara assert_safe_xml, GeoNode 5.1.1).
  K4  XSS tersimpan di abstrak & isian HTML lain (GHSA-r4hm-p9f9-fj9v / CVE-2026-55649; resmi: GeoNode 5.0.3):
      HTML dibersihkan dengan daftar tag aman saat sumber daya disimpan.

Pengecualian alamat untuk K2 (mis. layanan WMS di jaringan kantor): variabel lingkungan GEOMDB_URL_TEPERCAYA,
daftar host atau host:port dipisah koma.
"""
import ipaddress
import os
import re
import shlex
import socket
import subprocess
from html import escape
from html.parser import HTMLParser
from urllib.parse import urlsplit

VERSI = "1"

# ── K1: ogr2ogr tanpa shell ──────────────────────────────────────────────────────────────────────────────────────


def kutip(nilai):
    """Satu argumen baris perintah yang aman (nama berkas / nama layer dari pengguna)."""
    return shlex.quote(str(nilai))


_PSQL = " | PGPASSWORD="  # sambungan pipa OGR2OGR_COPY_WITH_DUMP=True: ogr2ogr -f PGDump /vsistdout/ | psql ...


class _Pipa:
    """Dua proses tersambung (ogr2ogr | psql) dengan antarmuka communicate() seperti satu Popen bershell."""

    def __init__(self, p1, p2):
        self.p1, self.p2 = p1, p2

    def communicate(self):
        self.p1.stdout.close()  # psql yang selesai lebih dulu membuat ogr2ogr menerima SIGPIPE, seperti di shell
        keluar, galat2 = self.p2.communicate()
        galat1 = self.p1.stderr.read()
        self.p1.wait()
        return keluar, (galat1 or b"") + (galat2 or b"")

    @property
    def returncode(self):
        return self.p2.returncode


def jalankan_ogr2ogr(ogr_exe, opsi):
    """Pengganti Popen(" ".join([ogr_exe] + opsi.split(" ")), shell=True): string opsi dipecah dengan shlex dan
    dijalankan tanpa shell, sehingga nama layer/berkas tidak pernah ditafsirkan sebagai perintah."""
    bagian_psql = None
    i = opsi.rfind(_PSQL)
    if i != -1:
        opsi, bagian_psql = opsi[:i], opsi[i + len(" | "):]
    p1 = subprocess.Popen([ogr_exe] + shlex.split(opsi), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if not bagian_psql:
        return p1
    argv, env = shlex.split(bagian_psql), dict(os.environ)
    while argv and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", argv[0]):  # PGPASSWORD=... di depan perintah
        kunci, nilai = argv.pop(0).split("=", 1)
        env[kunci] = nilai
    p2 = subprocess.Popen(argv, stdin=p1.stdout, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    return _Pipa(p1, p2)


# ── K2: URL ke jaringan lokal ditolak ────────────────────────────────────────────────────────────────────────────

_URL_GANJIL = re.compile(r"[\\\s\x00-\x1f\x7f]")  # karakter yang membuat pengurai URL berbeda pendapat soal host


def _urai_url(url):
    """(skema, host, port, userinfo) seperti urllib3 (yang dipakai requests) membacanya; None bila tidak sah."""
    try:
        from urllib3.util import parse_url

        u = parse_url(url)
        return u.scheme, u.host, u.port, u.auth
    except ImportError:
        u = urlsplit(url)
        return u.scheme, u.hostname, u.port, (u.username or u.password)
    except Exception:  # noqa: BLE001 — URL rusak
        return None


def _ip_publik(ip):
    obj = ipaddress.ip_address(ip.split("%")[0])
    return not (obj.is_loopback or obj.is_private or obj.is_link_local or obj.is_multicast or obj.is_reserved
                or obj.is_unspecified)


def _tepercaya_env():
    return {h.strip().lower() for h in os.environ.get("GEOMDB_URL_TEPERCAYA", "").split(",") if h.strip()}


def url_aman(url, tepercaya=()):
    """True bila URL http(s) ini hanya mengarah ke alamat publik (atau host tepercaya). Setara is_safe_url
    GeoNode 5.1.1: skema http/https, tanpa userinfo, setiap alamat IP hasil resolusi DNS harus publik."""
    if not isinstance(url, str) or not url or _URL_GANJIL.search(url):
        return False
    hasil = _urai_url(url)
    if not hasil:
        return False
    skema, host, port, auth = hasil
    if skema not in ("http", "https") or not host or auth:
        return False
    host = host.strip("[]").lower()
    port = port or {"http": 80, "https": 443}[skema]
    daftar = {h.lower() for h in tepercaya if h} | _tepercaya_env()
    if host in daftar or "%s:%s" % (host, port) in daftar:
        return True
    try:
        ips = {info[4][0] for info in socket.getaddrinfo(host, None)}
    except (socket.gaierror, UnicodeError):
        return False
    return bool(ips) and all(_ip_publik(ip) for ip in ips)


def _host(url):
    try:
        return (urlsplit(url).hostname or "").lower()
    except ValueError:
        return ""


def host_internal():
    """Host milik GeoNode sendiri yang sah dituju walau beralamat privat: situs & GeoServer (internal/publik)."""
    hosts = set()
    try:
        from django.conf import settings

        hosts.add(_host(getattr(settings, "SITEURL", "")))
        for ogc in getattr(settings, "OGC_SERVER", {}).values():
            for kunci in ("LOCATION", "PUBLIC_LOCATION", "WEB_UI_LOCATION"):
                hosts.add(_host(ogc.get(kunci, "") or ""))
    except Exception:  # noqa: BLE001 — tanpa Django: tidak ada pengecualian tambahan
        pass
    return {h for h in hosts if h}


def proxy_ditolak(raw_url, allowed_hosts=()):
    """Untuk /proxy GeoNode: True bila URL tujuan mengarah ke jaringan lokal dan bukan host GeoNode sendiri."""
    tepercaya = host_internal() | {str(h).lower() for h in (allowed_hosts or ()) if h}
    return not url_aman(raw_url, tepercaya)


# ── K3: XML unggahan tanpa konten aktif ──────────────────────────────────────────────────────────────────────────

class XMLTidakAman(ValueError):
    pass


_XSLT = {"http://www.w3.org/1999/XSL/Transform", "http://www.w3.org/TR/WD-xsl"}
_ELEMEN_BERBAHAYA = {"script", "iframe", "object", "embed", "applet", "foreignobject", "handler"}
_URI_AKTIF = ("javascript:", "vbscript:", "data:text/html")


def periksa_xml(data):
    """Kembalikan elemen akar bila XML aman; XMLTidakAman bila memuat DTD/entitas, PI, XSLT, skrip, atau URI aktif."""
    from lxml import etree

    if isinstance(data, str):
        data = data.encode("utf-8", "surrogatepass")
    pengurai = etree.XMLParser(resolve_entities=False, no_network=True, load_dtd=False, dtd_validation=False,
                               huge_tree=False)
    try:
        akar = etree.fromstring(data, parser=pengurai)
    except etree.XMLSyntaxError as e:
        raise XMLTidakAman("XML tidak well-formed: %s" % e)
    info = akar.getroottree().docinfo
    if info is not None and info.doctype:
        raise XMLTidakAman("deklarasi DOCTYPE/DTD tidak diizinkan pada XML unggahan")
    for pi in akar.xpath("//processing-instruction()"):
        raise XMLTidakAman("processing instruction <?%s ...?> tidak diizinkan" % pi.target)
    for el in akar.iter():
        if not isinstance(el.tag, str):
            continue
        nama = etree.QName(el)
        if nama.namespace in _XSLT:
            raise XMLTidakAman("elemen XSLT <%s> tidak diizinkan" % nama.localname)
        if nama.localname.lower() in _ELEMEN_BERBAHAYA:
            raise XMLTidakAman("elemen <%s> tidak diizinkan" % nama.localname)
        for atr, nilai in el.attrib.items():
            lokal = etree.QName(atr).localname if atr.startswith("{") else atr
            if len(lokal) > 2 and lokal.lower().startswith("on"):
                raise XMLTidakAman("atribut %s tidak diizinkan" % lokal)
            if "".join((nilai or "").split()).lower().startswith(_URI_AKTIF):
                raise XMLTidakAman("URI aktif (javascript:/vbscript:/data:text/html) tidak diizinkan")
    return akar


# ── K4: HTML aman pada isian metadata ────────────────────────────────────────────────────────────────────────────

TAG_BOLEH = {"a", "abbr", "b", "blockquote", "br", "code", "div", "em", "h1", "h2", "h3", "h4", "h5", "h6", "hr",
             "i", "li", "ol", "p", "pre", "s", "span", "strong", "sub", "sup", "table", "tbody", "td", "tfoot", "th",
             "thead", "tr", "u", "ul"}
_TAG_KOSONG = {"br", "hr"}
_TAG_BUANG_ISI = {"script", "style", "iframe", "object", "embed", "applet", "noscript", "template", "svg", "math",
                  "textarea", "select", "frame", "frameset", "title", "xmp", "noembed", "noframes"}
_ATRIBUT_BOLEH = {"a": {"href", "title"}, "abbr": {"title"}, "td": {"colspan", "rowspan"},
                  "th": {"colspan", "rowspan"}}
_HREF_BOLEH = ("http:", "https:", "mailto:", "/", "#")
ISIAN_HTML = ("abstract", "purpose", "constraints_other", "supplemental_information", "data_quality_statement")
_MIRIP_HTML = re.compile(r"<\s*[A-Za-z!/?]|&#|javascript:", re.I)


class _Pembersih(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.keluar, self.terbuka, self.buang, self.berubah = [], [], 0, False

    def handle_starttag(self, tag, attrs, kosong=False):
        tag = tag.lower()
        if tag in _TAG_BUANG_ISI:
            self.berubah = True
            if not kosong:
                self.buang += 1
            return
        if self.buang:
            return
        if tag not in TAG_BOLEH:
            self.berubah = True
            return
        atribut = []
        for nama, nilai in attrs:
            nama, nilai = (nama or "").lower(), nilai or ""
            if nama not in _ATRIBUT_BOLEH.get(tag, ()):
                self.berubah = True
                continue
            if nama == "href" and not "".join(nilai.split()).lower().startswith(_HREF_BOLEH):
                self.berubah = True
                continue
            atribut.append(' %s="%s"' % (nama, escape(nilai, quote=True)))
        if tag == "a":
            atribut.append(' rel="noopener noreferrer"')
        self.keluar.append("<%s%s>" % (tag, "".join(atribut)))
        if tag not in _TAG_KOSONG:
            self.terbuka.append(tag)
            if kosong:
                self.handle_endtag(tag)

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs, kosong=True)

    def handle_endtag(self, tag):
        tag = tag.lower()
        if tag in _TAG_BUANG_ISI:
            self.buang = max(0, self.buang - 1)
            return
        if self.buang or tag not in TAG_BOLEH or tag in _TAG_KOSONG or tag not in self.terbuka:
            return
        while self.terbuka:
            t = self.terbuka.pop()
            self.keluar.append("</%s>" % t)
            if t == tag:
                break

    def handle_data(self, data):
        if not self.buang:
            self.keluar.append(escape(data, quote=False))

    def handle_comment(self, data):
        self.berubah = True

    def handle_decl(self, decl):
        self.berubah = True

    def handle_pi(self, data):
        self.berubah = True

    def unknown_decl(self, data):
        self.berubah = True

    def hasil(self):
        self.close()
        return "".join(self.keluar) + "".join("</%s>" % t for t in reversed(self.terbuka))


def bersihkan_html(teks):
    """HTML dengan tag/atribut aman saja (skrip, event handler, URI javascript:, iframe, gaya dibuang).
    Teks yang tidak mengandung markup apa pun dikembalikan apa adanya (tidak di-escape)."""
    if not isinstance(teks, str) or not _MIRIP_HTML.search(teks):
        return teks
    p = _Pembersih()
    p.feed(teks)
    hasil = p.hasil()
    return hasil if p.berubah else teks


def bersihkan_resource(instance):
    """Dipanggil di awal ResourceBase.save(): isian HTML dibersihkan sebelum disimpan."""
    for nama in ISIAN_HTML:
        try:
            nilai = getattr(instance, nama, None)
            bersih = bersihkan_html(nilai)
            if bersih is not nilai and bersih != nilai:
                setattr(instance, nama, bersih)
        except Exception:  # noqa: BLE001 — pembersihan tidak boleh menggagalkan penyimpanan
            pass
