#!/usr/bin/env python3
"""Tambal GeoNode untuk GeoMDB — dijalankan DI DALAM lingkungan Python GeoNode (kontainer django/celery, atau
virtualenv GeoNode tanpa Docker). Skrip pendamping tambal-geonode-preserve.sh menjalankannya di semua kontainer.

    python tambal_preserve.py cek              # status kedua tambalan, tidak mengubah apa pun
    python tambal_preserve.py tambal           # pasang tambalan GeoMDB (preserve)
    python tambal_preserve.py tambal-unggah    # pasang tambalan unggah metadata (beserta tambalan GeoMDB)
    python tambal_preserve.py tambal-mdb       # pasang tambalan CSW ISO 19115-3 (MDB)
    python tambal_preserve.py pulihkan-unggah  # lepas tambalan unggah metadata; tambalan GeoMDB tetap
    python tambal_preserve.py pulihkan-mdb     # lepas tambalan CSW ISO 19115-3
    python tambal_preserve.py pulihkan         # kembalikan kode asli GeoNode (lepas semua tambalan)

1. Tambalan GeoMDB (preserve), GeoNode 4.2.5 s.d. master: geonode/catalogue/models.py menyimpan hasil
   etree.tostring() — bytes — ke kolom teks metadata_xml untuk record ber-preserve, sehingga isinya menjadi
   "b'<gmd:...'": record CSW-nya tak terbaca (HTTP 500) dan setiap penyimpanan berikutnya gagal dengan
   "Start tag expected, '<' not found". Tambalannya satu baris: encoding="unicode" (seperti jalur non-preserve).

2. Tambalan unggah metadata, GeoNode 5.x: memasang geonode/catalogue/geomdb_unggah.py (dari berkas geomdb_unggah.py
   di sebelah skrip ini, atau jalur di variabel GEOMDB_MODUL) beserta baris pemanggilnya, bertanda "# geomdb-unggah".
   XML ISO yang diunggah lewat UI GeoNode otomatis dipertahankan (preserve) dan dirapikan; lihat docstring modul itu.

3. Tambalan CSW ISO 19115-3 (MDB), GeoNode 5.x (pycsw 3): memasang geonode/catalogue/geomdb_mdb.py (dari
   geomdb_mdb.py / variabel GEOMDB_MDB_MODUL) dan folder geonode/catalogue/geomdb_xslt/ (dari folder xslt-mdb /
   variabel GEOMDB_XSLT) beserta satu baris di catalogue/views.py, bertanda "# geomdb-mdb". CSW lalu bisa menyajikan
   outputSchema http://standards.iso.org/iso/19115/-3/mdb/2.0, hasil konversi XSLT seperti GeoNetwork. Butuh paket
   saxonche (Saxon-HE, XSLT 2.0): dipasang lewat pip bila belum ada (perlu internet), lalu diuji di proses terpisah
   sebelum kode GeoNode diubah; bila tidak berfungsi, tidak ada yang diubah.

Kode keluar: 0 berhasil / sudah sesuai · 1 galat · 2 kode tidak dikenali, tidak diubah · 3 tambalan GeoMDB belum
terpasang (hanya pada cek)
"""
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile

LAMA = "md_doc = etree.tostring(dlxml.fromstring(instance.metadata_xml))"
BARU = 'md_doc = etree.tostring(dlxml.fromstring(instance.metadata_xml), encoding="unicode")'
CADANGAN = ".geomdb-asli"
CADANGAN_UNGGAH = ".geomdb-unggah-asli"
# Fungsinya catalogue_post_save() (4.2 – 5.1) atau update_csw_metadata() (master); keduanya memeriksa preserve
# lalu menyimpan md_doc ke metadata_xml — itu yang dijadikan pengaman, bukan nama fungsinya.
CIRI = ("metadata_uploaded_preserve", "metadata_xml=md_doc")

TANDA = "# geomdb-unggah"
MODUL = "geomdb_unggah.py"
IMPOR = "from geonode.catalogue import geomdb_unggah"

TANDA_MDB = "# geomdb-mdb"
MODUL_MDB = "geomdb_mdb.py"
FOLDER_MDB = "geomdb_xslt"
CADANGAN_MDB = ".geomdb-mdb-asli"
IMPOR_MDB = "from geonode.catalogue import geomdb_mdb"
SAXONCHE = "saxonche==13.1.1"
# Penanda "saxonche dipasang oleh penambal ini" disimpan di lingkungan Python (sys.prefix), bukan di folder kode:
# kontainer GeoNode sering berbagi kode (volume) tetapi masing-masing punya venv sendiri.
PENANDA_SAXONCHE = "geomdb-saxonche-dipasang.txt"


def lokasi():
    """geonode/catalogue/models.py milik GeoNode yang terpasang — tanpa mengimpor Django."""
    spec = importlib.util.find_spec("geonode")
    if spec is None or not spec.submodule_search_locations:
        raise RuntimeError("paket 'geonode' tidak ditemukan di Python ini")
    return os.path.join(list(spec.submodule_search_locations)[0], "catalogue", "models.py")


def paket():
    return os.path.dirname(os.path.dirname(lokasi()))


def versi_geonode():
    try:
        import geonode  # ringan: hanya informasi versi
        v = getattr(geonode, "__version__", None)
    except Exception:  # noqa: BLE001 — versi hanya informasi
        return "?"
    if isinstance(v, tuple):  # GeoNode: (5, 0, 0, 'dev', 0) → "5.0.0-dev"
        return ".".join(str(x) for x in v[:3]) + ("-%s" % v[3] if len(v) > 3 and v[3] != "final" else "")
    return str(v or "?")


def _baris(potongan):
    """Satu baris UTUH berisi `potongan` (hanya indentasi di depannya) — varian seperti
    "...metadata_xml)).decode()" (GeoNode yang sudah memperbaikinya sendiri) tidak ikut cocok."""
    return re.compile(r"^[ \t]*" + re.escape(potongan) + r"[ \t]*\r?$", re.M)


def _cocok_di_fungsi(teks, potongan):
    """Match baris `potongan` bila muncul tepat sekali (juga sebagai sub-teks), di dalam fungsi tingkat atas
    yang memuat semua CIRI; selain itu None."""
    hasil = list(_baris(potongan).finditer(teks))
    if len(hasil) != 1 or teks.count(potongan) != 1:
        return None
    posisi = hasil[0].start()
    awal = teks.rfind("\ndef ", 0, posisi)
    akhir = teks.find("\ndef ", posisi)
    badan = teks[awal:akhir if akhir != -1 else len(teks)]
    return hasil[0] if awal != -1 and all(c in badan for c in CIRI) else None


def status(teks):
    """Status tambalan GeoMDB pada isi catalogue/models.py."""
    if _cocok_di_fungsi(teks, LAMA) and BARU not in teks:
        return "belum"
    if _cocok_di_fungsi(teks, BARU) and LAMA not in teks:
        return "sudah"
    if LAMA not in teks and BARU not in teks and BAGIAN_UNGGAH[0].cari_blok(teks.splitlines(True)) is not None:
        return "sudah-unggah"  # baris itu sudah diambil alih tambalan unggah (yang mencakup tambalan GeoMDB)
    return "tidak-dikenali"


def _ganti(teks, dari, ke):
    m = _cocok_di_fungsi(teks, dari)
    return teks[:m.start()] + m.group(0).replace(dari, ke) + teks[m.end():]


def _baca(jalur):
    with open(jalur, encoding="utf-8", newline="") as fh:
        return fh.read()


def _tulis(jalur, teks, mode=0o644):
    """Tulis atomik, izin berkas tetap, setelah dipastikan Python bisa mengompilasinya (tanpa menulis .pyc)."""
    compile(teks, jalur, "exec")  # SyntaxError -> tidak ada yang ditulis
    fd, sementara = tempfile.mkstemp(dir=os.path.dirname(jalur), prefix=".tambal-", suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as fh:
        fh.write(teks)
    if os.path.exists(jalur):
        shutil.copymode(jalur, sementara)
    else:
        os.chmod(sementara, mode)
    os.replace(sementara, jalur)


# ── Tambalan unggah metadata ─────────────────────────────────────────────────────────────────────────────────────

def _isi(baris):
    return baris.strip()


def _indentasi(baris):
    return baris[:len(baris) - len(baris.lstrip())]


def _akhir_baris(baris):
    return "\r\n" if baris.endswith("\r\n") else "\n"


class Bagian:
    """Satu perubahan di satu berkas GeoNode: `jangkar` (baris asli yang dikenali, urutan prioritas) diganti /
    disisipi `baris` (masing-masing diberi indentasi jangkar dan TANDA)."""

    def __init__(self, berkas, cara, jangkar, baris, pulih=None, ciri=False, tanda=TANDA):
        self.berkas, self.cara, self.jangkar, self.baris, self.tanda = berkas, cara, jangkar, baris, tanda
        self.pulih = pulih or (jangkar[0] if cara == "ganti" else None)
        self.ciri = ciri  # jangkar wajib berada di fungsi pembuat record CSW (lihat CIRI)

    def blok(self):
        return [b + "  " + self.tanda for b in self.baris]

    def cari_blok(self, baris):
        """Indeks awal blok sisipan yang utuh dan berada di tempatnya; None bila tidak ada."""
        blok = self.blok()
        kunci = [i for i, b in enumerate(baris) if _isi(b) == blok[-1]]
        if len(kunci) != 1:
            return None
        awal = kunci[0] - len(blok) + 1
        if awal < 0 or [_isi(b) for b in baris[awal:kunci[0] + 1]] != blok:
            return None
        if self.cara == "sesudah" and (awal == 0 or _isi(baris[awal - 1]) not in self.jangkar):
            return None
        if self.cara == "sebelum" and (kunci[0] + 1 >= len(baris) or _isi(baris[kunci[0] + 1]) not in self.jangkar):
            return None
        return awal

    def cari_jangkar(self, baris):
        """Indeks satu-satunya baris jangkar; None bila tidak ada / lebih dari satu."""
        cocok = [i for i, b in enumerate(baris) if _isi(b) in self.jangkar]
        if len(cocok) != 1:
            return None
        if self.ciri and not any(_cocok_di_fungsi("".join(baris), j) for j in self.jangkar):
            return None
        return cocok[0]

    def keadaan(self, baris):
        sisa = any(_isi(b) == self.blok()[-1] for b in baris)
        if self.cari_blok(baris) is not None:
            return "sudah"
        if not sisa and self.cari_jangkar(baris) is not None:
            return "belum"
        return "tidak-dikenali"

    def pasang(self, baris):
        i = self.cari_jangkar(baris)
        ind, akhir = _indentasi(baris[i]), _akhir_baris(baris[i])
        blok = [ind + b + akhir for b in self.blok()]
        if self.cara == "ganti":
            return baris[:i] + blok + baris[i + 1:]
        if self.cara == "sesudah":
            return baris[:i + 1] + blok + baris[i + 1:]
        return baris[:i] + blok + baris[i:]

    def lepas(self, baris, pulih=None):
        awal = self.cari_blok(baris)
        akhir = awal + len(self.baris)
        if self.cara == "ganti":
            asli = _indentasi(baris[awal]) + (pulih or self.pulih) + _akhir_baris(baris[akhir - 1])
            return baris[:awal] + [asli] + baris[akhir:]
        return baris[:awal] + baris[akhir:]


BAGIAN_UNGGAH = [
    # XML ber-preserve dirapikan (fileIdentifier = UUID, deklarasi, tautan GeoNode) — mencakup tambalan GeoMDB
    Bagian("catalogue/models.py", "ganti", [LAMA, BARU],
           [IMPOR, "md_doc = geomdb_unggah.xml_preserve(instance)"], pulih=BARU, ciri=True),
    # tampilan XSL metadata ber-preserve (bug bytes yang sama: str + bytes)
    Bagian("catalogue/metadataxsl/views.py", "ganti",
           ["md_doc = etree.tostring(dlxml.fromstring(resource.metadata_xml))"],
           [IMPOR, "md_doc = geomdb_unggah.xml_tersimpan(resource)"]),
    # XML ISO yang diunggah otomatis dipertahankan
    Bagian("resource/manager.py", "sesudah", ["_resource.metadata_xml = _md_file_content"],
           [IMPOR, "geomdb_unggah.saat_unggah(_resource, _md_file_content)"]),
    # Data Quality = lineage dari blok dataQualityInfo mana pun + ringkasan laporan kualitas
    Bagian("layers/metadata.py", "ganti", ['vals["data_quality_statement"] = mdata.dataquality.lineage'],
           [IMPOR, 'vals["data_quality_statement"] = geomdb_unggah.pernyataan_kualitas(exml, mdata.dataquality.lineage)']),
    # form metadata: potret sebelum disimpan ...
    Bagian("metadata/api/views.py", "sebelum", ["errors = ("],
           [IMPOR, "_gm_sebelum = geomdb_unggah.potret(resource)"]),
    # ... lalu perubahan ditulis ke XML & record CSW diperbarui
    Bagian("metadata/api/views.py", "sesudah",
           ["resource.save()  # we want to trigger all the post_save signals", "update_csw_metadata(resource)"],
           ["geomdb_unggah.setelah_form(resource, _gm_sebelum)"]),
]


BAGIAN_MDB = [
    # profil pycsw iso19115p3 + konversi XSLT, setelah konfigurasi pycsw GeoNode selesai disusun
    Bagian("catalogue/views.py", "sesudah", ["mdict = config_updater(mdict) if config_updater else mdict"],
           [IMPOR_MDB, "mdict = geomdb_mdb.atur(mdict)"], tanda=TANDA_MDB),
]


class Paket:
    """Tambalan yang memasang modul (dan folder data) ke geonode/catalogue/ beserta baris pemanggilnya."""

    def __init__(self, nama, bagian, modul, env_modul, cadangan, folder=None, sumber_folder=None, env_folder=None):
        self.nama, self.bagian, self.modul, self.env_modul, self.cadangan = nama, bagian, modul, env_modul, cadangan
        self.folder, self.sumber_folder, self.env_folder = folder, sumber_folder, env_folder

    def tujuan_modul(self):
        return os.path.join(paket(), "catalogue", self.modul)

    def tujuan_folder(self):
        return os.path.join(paket(), "catalogue", self.folder) if self.folder else None


UNGGAH = Paket("unggah metadata", BAGIAN_UNGGAH, MODUL, "GEOMDB_MODUL", CADANGAN_UNGGAH)
MDB = Paket("CSW ISO 19115-3", BAGIAN_MDB, MODUL_MDB, "GEOMDB_MDB_MODUL", CADANGAN_MDB,
            folder=FOLDER_MDB, sumber_folder="xslt-mdb", env_folder="GEOMDB_XSLT")


def _cari(env, nama, cek):
    """Berkas/folder sumber: variabel lingkungan `env`, di sebelah skrip ini, atau di folder kerja."""
    kandidat = [os.environ.get(env)]
    if globals().get("__file__"):
        kandidat.append(os.path.join(os.path.dirname(os.path.abspath(__file__)), nama))
    kandidat.append(os.path.join(os.getcwd(), nama))
    return next((k for k in kandidat if k and cek(k)), None)


def _sumber_modul(pk=UNGGAH):
    return _cari(pk.env_modul, pk.modul, os.path.isfile)


def _sumber_folder(pk):
    return _cari(pk.env_folder, pk.sumber_folder, os.path.isdir) if pk.folder else None


def _isi_folder(akar):
    """{jalur relatif: isi} semua berkas di folder (tanpa __pycache__)."""
    isi = {}
    for d, sub, berkas in os.walk(akar):
        sub[:] = [x for x in sub if x != "__pycache__"]
        for b in berkas:
            jalur = os.path.join(d, b)
            with open(jalur, "rb") as fh:
                isi[os.path.relpath(jalur, akar).replace(os.sep, "/")] = fh.read()
    return isi


def _jalur(b):
    return os.path.join(paket(), *b.berkas.split("/"))


def _berkas(pk):
    """{jalur: daftar baris} untuk semua berkas yang disentuh tambalan (berkas yang tidak ada: None)."""
    hasil = {}
    for b in pk.bagian:
        jalur = _jalur(b)
        if jalur not in hasil:
            hasil[jalur] = _baca(jalur).splitlines(True) if os.path.isfile(jalur) else None
    return hasil


def keadaan(pk):
    """([(bagian, keadaan)], keadaan modul + folder: belum|sudah|beda)."""
    berkas = _berkas(pk)
    bagian = [(b, "tidak-ada" if berkas[_jalur(b)] is None else b.keadaan(berkas[_jalur(b)])) for b in pk.bagian]
    sumber, sumber_folder = _sumber_modul(pk), _sumber_folder(pk)
    tujuan, tujuan_folder = pk.tujuan_modul(), pk.tujuan_folder()
    if not os.path.isfile(tujuan) or (tujuan_folder and not os.path.isdir(tujuan_folder)):
        modul = "belum"
    elif (sumber and _baca(sumber) != _baca(tujuan)) or (
            sumber_folder and _isi_folder(sumber_folder) != _isi_folder(tujuan_folder)):
        modul = "beda"
    else:
        modul = "sudah"
    return bagian, modul


def keadaan_unggah():
    return keadaan(UNGGAH)


def ringkasan(pk, bagian, modul):
    nilai = {k for _, k in bagian}
    if nilai == {"sudah"}:
        return "SUDAH ditambal" + (" (%s perlu diperbarui)" % " / ".join(filter(None, [pk.modul, pk.folder]))
                                   if modul != "sudah" else "") + "."
    if nilai == {"belum"}:
        return "BELUM ditambal."
    if "tidak-ada" in nilai and nilai <= {"tidak-ada", "belum"}:
        return "tidak bisa dipasang: butuh GeoNode 5.x (berkas tidak ada: %s)." % ", ".join(
            sorted({b.berkas for b, k in bagian if k == "tidak-ada"}))
    rinci = ", ".join("%s=%s" % (b.berkas, k) for b, k in bagian)
    return "SEBAGIAN / tidak dikenali (%s)." % rinci


def ringkasan_unggah(bagian, modul):
    return ringkasan(UNGGAH, bagian, modul)


def _simpan_semua(perubahan, cadangan):
    """Tulis {jalur: (teks_lama, teks_baru)} sekaligus; bila satu gagal, yang sudah ditulis dikembalikan."""
    selesai = []
    try:
        for jalur, (lama, baru) in perubahan.items():
            if cadangan:
                shutil.copy2(jalur, jalur + cadangan)
            _tulis(jalur, baru)
            selesai.append(jalur)
    except Exception:
        for jalur in selesai:
            _tulis(jalur, perubahan[jalur][0])
        raise


def _salin_folder(sumber, tujuan):
    """Ganti folder tujuan dengan salinan sumber (izin baca untuk semua: worker GeoNode bisa bukan root)."""
    sementara = tempfile.mkdtemp(dir=os.path.dirname(tujuan), prefix=".tambal-")
    try:
        for rel, isi in _isi_folder(sumber).items():
            jalur = os.path.join(sementara, *rel.split("/"))
            os.makedirs(os.path.dirname(jalur), exist_ok=True)
            with open(jalur, "wb") as fh:
                fh.write(isi)
            os.chmod(jalur, 0o644)
        for d, _, _ in os.walk(sementara):
            os.chmod(d, 0o755)
        if os.path.isdir(tujuan):
            shutil.rmtree(tujuan)
        os.replace(sementara, tujuan)
    except Exception:
        shutil.rmtree(sementara, ignore_errors=True)
        raise


def _hapus_modul(pk):
    """Hapus modul, folder & .pyc-nya. Kembalian: daftar jalur yang dihapus."""
    dihapus = []
    tujuan = pk.tujuan_modul()
    if os.path.isfile(tujuan):
        os.remove(tujuan)
        dihapus.append(tujuan)
    cache = os.path.join(os.path.dirname(tujuan), "__pycache__")
    for nama in os.listdir(cache) if os.path.isdir(cache) else ():
        if nama.startswith(pk.modul[:-3] + "."):  # geomdb_unggah.cpython-312.pyc dst.
            os.remove(os.path.join(cache, nama))
    if pk.folder and os.path.isdir(pk.tujuan_folder()):
        shutil.rmtree(pk.tujuan_folder())
        dihapus.append(pk.tujuan_folder())
    return dihapus


def pasang(pk):
    if pk is MDB and not ada_profil_mdb():
        print("Tidak bisa dipasang: pycsw di GeoNode ini belum punya profil iso19115p3 (butuh GeoNode 5.x / pycsw 3).")
        return 2
    sumber, sumber_folder = _sumber_modul(pk), _sumber_folder(pk)
    if not sumber:
        print("GALAT: %s tidak ditemukan (letakkan di sebelah skrip ini atau isi variabel %s)." % (pk.modul, pk.env_modul))
        return 1
    if pk.folder and not sumber_folder:
        print("GALAT: folder %s tidak ditemukan (letakkan di sebelah skrip ini atau isi variabel %s)."
              % (pk.sumber_folder, pk.env_folder))
        return 1
    bagian, modul = keadaan(pk)
    asing = [(b, k) for b, k in bagian if k not in ("sudah", "belum")]
    if asing:
        print("Tambalan %s %s Tidak ada yang diubah." % (pk.nama, ringkasan(pk, bagian, modul)))
        return 2
    saxonche_baru = False
    if pk is MDB:
        kode, saxonche_baru = prasyarat_mdb(sumber_folder)
        if kode:
            return kode
    tujuan, tujuan_folder = pk.tujuan_modul(), pk.tujuan_folder()
    baru_dibuat = not os.path.isfile(tujuan)
    if saxonche_baru:
        with open(os.path.join(sys.prefix, PENANDA_SAXONCHE), "w", encoding="utf-8") as fh:
            fh.write("saxonche dipasang oleh tambal_preserve.py (tambal-mdb); dilepas lagi oleh pulihkan-mdb\n")
    if modul != "sudah":  # modul dulu: baris yang dipasang sesudahnya mengimpornya
        if tujuan_folder:
            _salin_folder(sumber_folder, tujuan_folder)
        _tulis(tujuan, _baca(sumber))
    if all(k == "sudah" for _, k in bagian):
        print("Diperbarui: %s" % ", ".join(filter(None, [tujuan, tujuan_folder])) if modul != "sudah"
              else "Tambalan %s sudah terpasang - tidak ada yang diubah." % pk.nama)
        return 0
    berkas = _berkas(pk)
    perubahan = {}
    for b, k in bagian:
        if k == "belum":
            jalur = _jalur(b)
            berkas[jalur] = b.pasang(berkas[jalur])
            perubahan[jalur] = (_baca(jalur), "".join(berkas[jalur]))
    try:
        _simpan_semua(perubahan, pk.cadangan)
    except Exception:
        if baru_dibuat:
            _hapus_modul(pk)
        raise
    bagian, modul = keadaan(pk)
    if any(k != "sudah" for _, k in bagian) or modul != "sudah":
        print("Verifikasi gagal: %s" % ringkasan(pk, bagian, modul))
        return 1
    print("Ditambal (%s): %s" % (pk.nama, ", ".join(sorted(os.path.relpath(j, paket()) for j in perubahan))))
    print("Modul: %s%s. Asli dicadangkan sebagai *%s" % (
        tujuan, " + folder %s" % tujuan_folder if tujuan_folder else "", pk.cadangan))
    return 0


def lepas(pk, pulih_katalog=BARU):
    """Lepas bagian yang terpasang. Kembalian: (kode keluar, ada perubahan)."""
    bagian, _ = keadaan(pk)
    berkas = _berkas(pk)
    perubahan = {}
    for b, k in bagian:
        if k == "sudah":
            jalur = _jalur(b)
            berkas[jalur] = b.lepas(berkas[jalur], pulih_katalog if b is BAGIAN_UNGGAH[0] else None)
            perubahan.setdefault(jalur, [_baca(jalur), None])[1] = "".join(berkas[jalur])
    _simpan_semua({j: tuple(v) for j, v in perubahan.items()}, None)
    sisa, _ = keadaan(pk)
    if not any(k == "sudah" for _, k in sisa):  # tak ada lagi yang mengimpornya
        for jalur in _hapus_modul(pk):
            perubahan.setdefault(jalur, None)
        penanda = os.path.join(sys.prefix, PENANDA_SAXONCHE)
        if pk is MDB and os.path.isfile(penanda):
            hasil = subprocess.run([sys.executable, "-m", "pip", "uninstall", "-y", "-q", "saxonche"],
                                   capture_output=True, text=True)
            if hasil.returncode:
                print("Paket saxonche gagal dilepas (dibiarkan): %s" % (hasil.stderr or hasil.stdout).strip()[-300:])
            else:
                os.remove(penanda)
                print("Paket saxonche (dipasang oleh tambalan ini) dilepas.")
    if perubahan:
        print("Dilepas (%s): %s" % (pk.nama, ", ".join(sorted(os.path.relpath(j, paket()) for j in perubahan))))
    elif not any(k == "tidak-dikenali" for _, k in sisa):
        print("Tambalan %s tidak terpasang - tidak ada yang dilepas." % pk.nama)
    asing = [(b, k) for b, k in sisa if k == "tidak-dikenali"]
    if asing:
        print("Tidak dikenali, dibiarkan: %s" % ", ".join(b.berkas for b, _ in asing))
        return 2, bool(perubahan)
    return 0, bool(perubahan)


def tambal_unggah():
    return pasang(UNGGAH)


def lepas_unggah(pulih_katalog=BARU):
    return lepas(UNGGAH, pulih_katalog)


# ── Tambalan CSW ISO 19115-3: prasyarat ──────────────────────────────────────────────────────────────────────────

# Dijalankan di proses terpisah: pustaka native saxonche yang tidak cocok dengan CPU/OS bisa mematikan proses
# (mis. illegal instruction) — lebih baik penambalnya yang tahu daripada worker GeoNode yang mati.
UJI_SAXON = r'''
import sys
from saxonche import PySaxonProcessor
p = PySaxonProcessor(license=False)
x = p.new_xslt30_processor().compile_stylesheet(stylesheet_file=sys.argv[1])
gmd = ('<gmd:MD_Metadata xmlns:gmd="http://www.isotc211.org/2005/gmd" xmlns:gco="http://www.isotc211.org/2005/gco">'
       '<gmd:fileIdentifier><gco:CharacterString>uji-geomdb</gco:CharacterString></gmd:fileIdentifier>'
       '<gmd:dateStamp><gco:DateTime>2026-01-01T00:00:00</gco:DateTime></gmd:dateStamp></gmd:MD_Metadata>')
h = x.transform_to_string(xdm_node=p.parse_xml(xml_text=gmd))
ok = "http://standards.iso.org/iso/19115/-3/mdb/2.0" in h and "uji-geomdb" in h
print(p.version)
sys.exit(0 if ok else 3)
'''


def _uji_saxon(xsl):
    try:
        hasil = subprocess.run([sys.executable, "-c", UJI_SAXON, xsl], capture_output=True, text=True, timeout=300)
    except subprocess.TimeoutExpired:
        return False, "uji Saxon melebihi 300 detik"
    if hasil.returncode == 0:
        return True, hasil.stdout.strip()
    if hasil.returncode < 0:
        return False, "proses uji Saxon mati oleh sinyal %d (CPU/OS tidak didukung pustaka native saxonche?)" % (
            -hasil.returncode)
    return False, (hasil.stderr or hasil.stdout).strip()[-500:]


def ada_profil_mdb():
    try:
        return importlib.util.find_spec("pycsw.plugins.profiles.iso19115p3.iso19115p3") is not None
    except ImportError:
        return False


def prasyarat_mdb(sumber_folder):
    """saxonche terpasang & berfungsi. Kembalian: (kode keluar, saxonche baru dipasang)."""
    xsl = os.path.join(sumber_folder, "geomdb-ke-mdb.xsl")
    baru = False
    if importlib.util.find_spec("saxonche") is None:
        print("Memasang %s (Saxon-HE, pemroses XSLT 2.0; unduhan sekitar 40 MB) ..." % SAXONCHE)
        hasil = subprocess.run([sys.executable, "-m", "pip", "install", "-q", "--no-cache-dir",
                                "--disable-pip-version-check", SAXONCHE], capture_output=True, text=True)
        if hasil.returncode:
            print("GALAT: pip gagal memasang %s:\n%s" % (SAXONCHE, (hasil.stderr or hasil.stdout).strip()[-800:]))
            print("Server tanpa internet: unduh wheel-nya di komputer lain (pip download %s --only-binary=:all: "
                  "--platform manylinux_2_24_x86_64 --python-version <versi python GeoNode>), salin ke kontainer, "
                  "lalu pip install berkas .whl itu dan ulangi penambalan." % SAXONCHE)
            return 1, False
        importlib.invalidate_caches()
        baru = True
    ok, info = _uji_saxon(xsl)
    if not ok:
        print("GALAT: Saxon tidak berfungsi di sini: %s" % info)
        if baru:
            subprocess.run([sys.executable, "-m", "pip", "uninstall", "-y", "-q", "saxonche"], capture_output=True)
        print("Tambalan CSW ISO 19115-3 tidak dipasang; tidak ada kode GeoNode yang diubah.")
        return 1, False
    print("Saxon berfungsi: %s" % info)
    return 0, baru


def main(aksi):
    jalur = lokasi()
    teks = _baca(jalur)
    st = status(teks)
    print("GeoNode %s | %s" % (versi_geonode(), jalur))
    if aksi == "cek":
        print("Tambalan GeoMDB (preserve): " + {
            "belum": "BELUM ditambal - preserve akan merusak record CSW.",
            "sudah": "SUDAH ditambal.",
            "sudah-unggah": "SUDAH ditambal (bagian dari tambalan unggah).",
            "tidak-dikenali": "Kode tidak dikenali (mungkin GeoNode sudah memperbaikinya) - tidak perlu/tidak bisa "
                              "ditambal otomatis."}[st])
        print("Tambalan unggah metadata: " + ringkasan(UNGGAH, *keadaan(UNGGAH)))
        bagian, modul = keadaan(MDB)
        if not ada_profil_mdb() and not any(k == "sudah" for _, k in bagian):
            print("Tambalan CSW ISO 19115-3 (MDB): tidak bisa dipasang: butuh GeoNode 5.x (pycsw 3).")
        else:
            saxonche = "terpasang" if importlib.util.find_spec("saxonche") else "TIDAK terpasang"
            print("Tambalan CSW ISO 19115-3 (MDB): %s Paket saxonche %s." % (ringkasan(MDB, bagian, modul), saxonche))
        return {"belum": 3, "sudah": 0, "sudah-unggah": 0, "tidak-dikenali": 2}[st]
    if aksi == "tambal-unggah":
        return pasang(UNGGAH)
    if aksi == "pulihkan-unggah":
        return lepas(UNGGAH)[0]
    if aksi == "tambal-mdb":
        return pasang(MDB)
    if aksi == "pulihkan-mdb":
        return lepas(MDB)[0]
    if aksi == "pulihkan":
        kode_mdb, _ = lepas(MDB) if any(k == "sudah" for _, k in keadaan(MDB)[0]) or os.path.isfile(
            MDB.tujuan_modul()) else (0, False)
    if st == "tidak-dikenali":
        print("Kode tidak dikenali - tidak diubah.")
        return 2
    if aksi == "tambal":
        if st in ("sudah", "sudah-unggah"):
            print("Sudah ditambal - tidak ada yang diubah.")
            return 0
        shutil.copy2(jalur, jalur + CADANGAN)  # berkas asli saat ini (diperbarui tiap kali menambal)
        _tulis(jalur, _ganti(teks, LAMA, BARU))
        if status(_baca(jalur)) != "sudah":
            shutil.copy2(jalur + CADANGAN, jalur)
            print("Verifikasi gagal - berkas asli dikembalikan.")
            return 1
        print("Ditambal. Asli dicadangkan di %s" % (jalur + CADANGAN))
        return 0
    if aksi == "pulihkan":
        kode, berubah = lepas(UNGGAH, pulih_katalog=LAMA) if st == "sudah-unggah" else (0, False)
        st = status(_baca(jalur))
        if st == "sudah":
            # Balikkan baris yang diubah (bukan menyalin cadangan: cadangan bisa berasal dari versi GeoNode lama)
            _tulis(jalur, _ganti(_baca(jalur), BARU, LAMA))
            st = status(_baca(jalur))
            berubah = True
        if st != "belum":
            print("Verifikasi gagal.")
            return 1
        if berubah:
            print("Kode asli GeoNode dikembalikan.")
        else:
            print("Belum ditambal - tidak ada yang dikembalikan.")
        # sisa tambalan unggah di berkas lain (bila catalogue/models.py tak lagi memuatnya)
        if any(k == "sudah" for _, k in keadaan(UNGGAH)[0]):
            kode, _ = lepas(UNGGAH)
        return kode or kode_mdb
    print("pemakaian: python tambal_preserve.py cek|tambal|tambal-unggah|tambal-mdb|pulihkan-unggah|pulihkan-mdb|pulihkan")
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "cek"))
    except (OSError, RuntimeError, SyntaxError) as e:
        print("GALAT: %s" % e)
        sys.exit(1)
