"""GeoMDB - tambalan unggah metadata GeoNode 5.x.

Dipasang oleh ``tambal_preserve.py tambal-unggah`` sebagai ``geonode/catalogue/geomdb_unggah.py`` dan dipanggil dari
baris-baris bertanda ``# geomdb-unggah`` di kode GeoNode:

- resource/manager.py            saat_unggah()          XML ISO 19139 yang diunggah (UI "Upload Metadata" atau .xml
                                                         yang ikut diunggah bersama data) otomatis dipertahankan
                                                         apa adanya (metadata_uploaded_preserve).
- catalogue/models.py            xml_preserve()         XML yang dipertahankan dirapikan sebelum disajikan CSW:
                                                         fileIdentifier = UUID dataset, deklarasi <?xml?> dibuang,
                                                         lineage disatukan ke blok kualitas pertama,
                                                         tautan GeoNode (halaman, unduhan, WMS/WFS/WCS) ditambahkan
                                                         bila belum ada.
- layers/metadata.py             pernyataan_kualitas()  "Data Quality" di halaman GeoNode = lineage (dari blok
                                                         dataQualityInfo mana pun) + ringkasan laporan kualitas.
- metadata/api/views.py          potret(), setelah_form()
                                                         Judul, abstrak, kata kunci, kategori, dan tanggal yang diubah
                                                         lewat form metadata GeoNode ditulis ke XML yang
                                                         dipertahankan, lalu record CSW diperbarui (GeoNode
                                                         5.0.x-5.1.0 tidak memperbarui CSW setelah form disimpan).
- catalogue/metadataxsl/views.py xml_tersimpan()        tampilan XSL metadata ber-preserve (bug bytes GeoNode).

Setiap fungsi yang dipanggil GeoNode menangkap galatnya sendiri: kegagalan di sini tidak boleh menggagalkan
penyimpanan dataset. Paling buruk, perilakunya kembali seperti GeoNode biasa yang sudah ditambal preserve.
"""
import html
import logging
import re
from datetime import date, datetime

from lxml import etree

VERSI = "3"
LOGGER = logging.getLogger(__name__)

GMD = "http://www.isotc211.org/2005/gmd"
GCO = "http://www.isotc211.org/2005/gco"
GMI = "http://www.isotc211.org/2005/gmi"
GMX = "http://www.isotc211.org/2005/gmx"
XLINK = "http://www.w3.org/1999/xlink"
NS = {"gmd": GMD, "gco": GCO, "gmi": GMI, "gmx": GMX, "xlink": XLINK}
AKAR_ISO = {(GMD, "MD_Metadata"), (GMI, "MI_Metadata")}
KODE_TANGGAL = "http://standards.iso.org/iso/19139/resources/gmxCodelists.xml#CI_DateTypeCode"
KODE_KATA_KUNCI = "http://standards.iso.org/iso/19139/resources/gmxCodelists.xml#MD_KeywordTypeCode"
BATAS_KUALITAS = 2000  # maxLength data_quality_statement pada skema metadata GeoNode 5

_DEKLARASI = re.compile(r"^﻿?\s*<\?xml\b[^>]*\?>\s*", re.I)
_TAG = re.compile(r"<[^<>]+>")

# Urutan elemen anak menurut skema ISO 19139, untuk menyisipkan elemen baru di tempat yang sah.
URUTAN = {
    "MD_Metadata": [
        "fileIdentifier", "language", "characterSet", "parentIdentifier", "hierarchyLevel", "hierarchyLevelName",
        "contact", "dateStamp", "metadataStandardName", "metadataStandardVersion", "dataSetURI", "locale",
        "spatialRepresentationInfo", "referenceSystemInfo", "metadataExtensionInfo", "identificationInfo",
        "contentInfo", "distributionInfo", "dataQualityInfo", "portrayalCatalogueInfo", "metadataConstraints",
        "applicationSchemaInfo", "metadataMaintenance", "series", "describes", "propertyType", "featureType",
        "featureAttribute", "acquisitionInformation",
    ],
    "MD_DataIdentification": [
        "citation", "abstract", "purpose", "credit", "status", "pointOfContact", "resourceMaintenance",
        "graphicOverview", "resourceFormat", "descriptiveKeywords", "resourceSpecificUsage", "resourceConstraints",
        "aggregationInfo", "spatialRepresentationType", "spatialResolution", "language", "characterSet",
        "topicCategory", "environmentDescription", "extent", "supplementalInformation",
    ],
    "CI_Citation": [
        "title", "alternateTitle", "date", "edition", "editionDate", "identifier", "citedResponsibleParty",
        "presentationForm", "series", "otherCitationDetails", "collectiveTitle", "ISBN", "ISSN",
    ],
    "CI_Date": ["date", "dateType"],
    "MD_Distribution": ["distributionFormat", "distributor", "transferOptions"],
    "MD_DigitalTransferOptions": ["unitsOfDistribution", "transferSize", "onLine", "offLine"],
    "MD_Keywords": ["keyword", "type", "thesaurusName"],
}
URUTAN["MI_Metadata"] = URUTAN["MD_Metadata"]

LABEL_LAPORAN = {
    "DQ_CompletenessCommission": "Kelengkapan (komisi)",
    "DQ_CompletenessOmission": "Kelengkapan (omisi)",
    "DQ_ConceptualConsistency": "Konsistensi konseptual",
    "DQ_DomainConsistency": "Konsistensi domain",
    "DQ_FormatConsistency": "Konsistensi format",
    "DQ_TopologicalConsistency": "Konsistensi topologi",
    "DQ_AbsoluteExternalPositionalAccuracy": "Akurasi posisi absolut",
    "DQ_GriddedDataPositionalAccuracy": "Akurasi posisi data grid",
    "DQ_RelativeInternalPositionalAccuracy": "Akurasi posisi relatif",
    "DQ_AccuracyOfATimeMeasurement": "Akurasi pengukuran waktu",
    "DQ_TemporalConsistency": "Konsistensi temporal",
    "DQ_TemporalValidity": "Validitas temporal",
    "DQ_ThematicClassificationCorrectness": "Ketepatan klasifikasi tematik",
    "DQ_NonQuantitativeAttributeAccuracy": "Akurasi atribut non-kuantitatif",
    "DQ_QuantitativeAttributeAccuracy": "Akurasi atribut kuantitatif",
    "QE_Usability": "Kebergunaan",
}


# ── XML dasar ────────────────────────────────────────────────────────────────────────────────────────────────────

def _q(nama):
    """'gmd:title' -> '{http://www.isotc211.org/2005/gmd}title'."""
    awalan, lokal = nama.split(":")
    return "{%s}%s" % (NS[awalan], lokal)


def _lokal(el):
    return etree.QName(el).localname


def _urai(teks):
    """Elemen metadata dari teks/bytes XML. Deklarasi <?xml encoding?> dan BOM aman (lxml menolak deklarasi encoding
    pada str); pembungkus CSW GetRecordByIdResponse dilepas. Entitas eksternal & DTD tidak dimuat."""
    if isinstance(teks, str):
        teks = _DEKLARASI.sub("", teks, count=1).encode("utf-8")
    pengurai = etree.XMLParser(resolve_entities=False, no_network=True, load_dtd=False, huge_tree=False)
    akar = etree.fromstring(teks, pengurai)
    if _lokal(akar) == "GetRecordByIdResponse":
        anak = [a for a in akar if isinstance(a.tag, str)]
        if anak:
            akar = anak[0]
    return akar


def _serial(akar):
    if hasattr(etree, "indent"):  # lxml >= 4.5; hanya merapikan spasi antar-elemen
        etree.indent(akar, space="  ")
    return etree.tostring(akar, encoding="unicode")


def teks_xml(teks):
    """XML sebagai str tanpa deklarasi (aman untuk lxml & kolom metadata_xml)."""
    return etree.tostring(_urai(teks), encoding="unicode")


def apakah_iso(teks):
    """True bila teks adalah metadata ISO 19139 (gmd:MD_Metadata / gmi:MI_Metadata)."""
    try:
        q = etree.QName(_urai(teks))
    except Exception:  # noqa: BLE001 - bukan XML / rusak: bukan ISO
        return False
    return (q.namespace, q.localname) in AKAR_ISO


def _teks(el):
    """Isi teks elemen properti (gco:CharacterString / gmx:Anchor / teks langsung), baris dipertahankan."""
    if el is None:
        return ""
    baris = (" ".join(b.split()) for b in "".join(el.itertext()).splitlines())
    return "\n".join(b for b in baris if b)


def _polos(teks):
    """Teks tanpa tag HTML (abstrak GeoNode bisa berisi HTML)."""
    return html.unescape(_TAG.sub("", teks or "")).strip()


def _sisipkan(induk, el):
    """Sisipkan el ke induk mengikuti urutan skema ISO: setelah saudara terakhir yang boleh mendahuluinya."""
    urutan = URUTAN.get(_lokal(induk))
    nama = _lokal(el)
    if not urutan or nama not in urutan:
        induk.append(el)
        return el
    batas = urutan.index(nama)
    posisi = 0
    for i, anak in enumerate(induk):
        if isinstance(anak.tag, str) and _lokal(anak) in urutan and urutan.index(_lokal(anak)) <= batas:
            posisi = i + 1
    induk.insert(posisi, el)
    return el


def _anak(induk, nama):
    """Anak langsung bernama `nama` (mis. 'gmd:title'); dibuat di posisi yang sah bila belum ada."""
    el = induk.find(nama, NS)
    if el is None:
        el = _sisipkan(induk, etree.Element(_q(nama)))
    return el


def _kosongkan(el):
    for anak in list(el):
        el.remove(anak)
    el.text = None
    for atribut in [a for a in el.attrib if etree.QName(a).localname == "nilReason"]:
        del el.attrib[atribut]


def _isi_teks(el, nilai):
    """Isi elemen properti ISO dengan satu gco:CharacterString."""
    _kosongkan(el)
    etree.SubElement(el, _q("gco:CharacterString")).text = nilai


def _kode(el):
    return ((el.get("codeListValue") or el.text or "") if el is not None else "").strip()


def _iso_waktu(nilai):
    if isinstance(nilai, datetime):
        return nilai.replace(microsecond=0).isoformat()
    if isinstance(nilai, date):
        return nilai.isoformat() + "T00:00:00"
    return str(nilai)


def _iso_tanggal(nilai):
    if isinstance(nilai, (datetime, date)):
        return nilai.strftime("%Y-%m-%d")
    return str(nilai)[:10]


def _isi_tanggal(el, nilai):
    """Isi gmd:date/gmd:dateStamp; jenis isi lama (gco:Date atau gco:DateTime) dipertahankan."""
    hanya_tanggal = el.find("gco:Date", NS) is not None
    _kosongkan(el)
    if hanya_tanggal:
        etree.SubElement(el, _q("gco:Date")).text = _iso_tanggal(nilai)
    else:
        etree.SubElement(el, _q("gco:DateTime")).text = _iso_waktu(nilai)


def _identifikasi(akar):
    info = akar.find("gmd:identificationInfo", NS)
    if info is None:
        return None
    return next((a for a in info if isinstance(a.tag, str)), None)


# ── Rapikan XML yang dipertahankan ───────────────────────────────────────────────────────────────────────────────

def _tautan_ada(akar):
    ada = set()
    for sumber in akar.iter(_q("gmd:CI_OnlineResource")):
        url = (sumber.findtext("gmd:linkage/gmd:URL", default="", namespaces=NS) or "").strip()
        protokol = _teks(sumber.find("gmd:protocol", NS)).lower()
        ada.add((url, protokol))
    return ada


def _tambah_tautan(akar, tautan):
    """Tambahkan tautan (url, protokol, nama, keterangan) yang pasangan url+protokolnya belum ada di XML."""
    ada = _tautan_ada(akar)
    baru = []
    for url, protokol, nama, keterangan in tautan:
        kunci = ((url or "").strip(), (protokol or "").lower())
        if kunci[0] and kunci not in ada:
            ada.add(kunci)
            baru.append((kunci[0], protokol, nama, keterangan))
    if not baru:
        return False
    distribusi = akar.find("gmd:distributionInfo/gmd:MD_Distribution", NS)
    if distribusi is None:
        info = _sisipkan(akar, etree.Element(_q("gmd:distributionInfo")))
        distribusi = etree.SubElement(info, _q("gmd:MD_Distribution"))
    transfer = distribusi.find("gmd:transferOptions/gmd:MD_DigitalTransferOptions", NS)
    if transfer is None:
        opsi = _sisipkan(distribusi, etree.Element(_q("gmd:transferOptions")))
        transfer = etree.SubElement(opsi, _q("gmd:MD_DigitalTransferOptions"))
    for url, protokol, nama, keterangan in baru:
        daring = _sisipkan(transfer, etree.Element(_q("gmd:onLine")))
        sumber = etree.SubElement(daring, _q("gmd:CI_OnlineResource"))
        etree.SubElement(etree.SubElement(sumber, _q("gmd:linkage")), _q("gmd:URL")).text = url
        for properti, nilai in (("gmd:protocol", protokol), ("gmd:name", nama), ("gmd:description", keterangan)):
            if nilai:
                _isi_teks(etree.SubElement(sumber, _q(properti)), nilai)
    return True


def _lingkup(dq):
    lingkup = dq.find("gmd:scope", NS)
    return re.sub(r">\s+<", "><", etree.tostring(lingkup, encoding="unicode")) if lingkup is not None else ""


def _gabung_kualitas(akar):
    """Pindahkan lineage ke blok dataQualityInfo PERTAMA bila blok itu belum punya lineage dan cakupannya (scope)
    sama. Banyak pembaca (XSL metadata GeoNode, OWSLib, harvester) hanya membaca blok pertama, padahal plugin
    GeoMDB 1.0.5 menaruh laporan kualitas dan lineage di blok terpisah. Isi tidak berubah, hanya letaknya."""
    blok = [b for b in akar.findall("gmd:dataQualityInfo", NS) if b.find("gmd:DQ_DataQuality", NS) is not None]
    if len(blok) < 2:
        return False
    pertama = blok[0].find("gmd:DQ_DataQuality", NS)
    if pertama.find("gmd:lineage", NS) is not None:
        return False
    for info in blok[1:]:
        dq = info.find("gmd:DQ_DataQuality", NS)
        lineage = dq.find("gmd:lineage", NS)
        if lineage is None or _lingkup(dq) != _lingkup(pertama):
            continue
        pertama.append(lineage)  # urutan DQ_DataQuality: scope, report*, lineage
        if not [a for a in dq if isinstance(a.tag, str) and _lokal(a) != "scope"]:
            akar.remove(info)  # tinggal scope saja: blok kosong
        return True
    return False


def rapikan(teks, uuid, tautan=()):
    """XML yang dipertahankan, siap disajikan CSW: fileIdentifier = uuid, lineage disatukan ke blok kualitas
    pertama, tautan yang belum ada ditambahkan."""
    akar = _urai(teks)
    if uuid:
        _isi_teks(_anak(akar, "gmd:fileIdentifier"), str(uuid))
    _gabung_kualitas(akar)
    _tambah_tautan(akar, tautan)
    return _serial(akar)


def tautan_geonode(instance):
    """Tautan yang ditulis template ISO GeoNode (catalogue/full_metadata.xml) untuk sumber daya ini."""
    from django.conf import settings
    from django.urls import reverse

    situs = (getattr(settings, "SITEURL", "") or "").rstrip("/")
    judul = getattr(instance, "title", "") or ""
    hasil = []
    try:
        halaman = situs + reverse("resolve_uuid", kwargs={"uuid": instance.uuid})
        hasil.append((halaman, "WWW:LINK-1.0-http--link", None, "Online link to the '%s' description on GeoNode" % judul))
    except Exception:  # noqa: BLE001 - tautan halaman hanya pelengkap
        LOGGER.debug("GeoMDB: tautan halaman %s tidak dibuat", instance.uuid, exc_info=True)
    tautan = getattr(instance, "link_set", None)
    if tautan is not None:
        nama = getattr(instance, "name", "") or ""
        for link in tautan.download():
            hasil.append((link.url, "WWW:DOWNLOAD-1.0-http--download", "%s.%s" % (nama, link.extension),
                          "%s (%s Format)" % (judul, link.name)))
        layer = getattr(instance, "alternate", None) or nama
        ruang = getattr(instance, "workspace", "") or ""
        for link in tautan.ows():
            hasil.append((link.url, link.link_type, layer, "%s Service - Provides Layer: %s" % (ruang, judul)))
    return hasil


def xml_preserve(instance):
    """Pengganti `etree.tostring(dlxml.fromstring(instance.metadata_xml))` di cabang preserve pembuat record CSW."""
    try:
        tautan = tautan_geonode(instance)
    except Exception:  # noqa: BLE001
        LOGGER.exception("GeoMDB: tautan GeoNode untuk %s tidak terbaca", getattr(instance, "uuid", "?"))
        tautan = []
    try:
        return rapikan(instance.metadata_xml, getattr(instance, "uuid", None), tautan)
    except Exception:  # noqa: BLE001 - XML tetap disajikan apa adanya (setara tambalan preserve biasa)
        LOGGER.exception("GeoMDB: XML %s gagal dirapikan, disajikan apa adanya", getattr(instance, "uuid", "?"))
        return teks_xml(instance.metadata_xml)


def xml_tersimpan(resource):
    """Pengganti `etree.tostring(dlxml.fromstring(resource.metadata_xml))` di tampilan XSL (hasilnya harus str)."""
    return teks_xml(resource.metadata_xml)


# ── Saat XML diunggah ────────────────────────────────────────────────────────────────────────────────────────────

def saat_unggah(resource, teks):
    """Dipanggil ResourceManager.update() tepat setelah XML unggahan dibaca: XML ISO dipertahankan apa adanya,
    format lain (FGDC, Dublin Core) mengikuti perilaku GeoNode biasa."""
    try:
        iso = apakah_iso(teks)
        resource.metadata_uploaded_preserve = iso
        if iso:
            resource.metadata_xml = teks_xml(teks)
    except Exception:  # noqa: BLE001
        LOGGER.exception("GeoMDB: pemeriksaan XML unggahan %s gagal", getattr(resource, "uuid", "?"))


def _satuan(el):
    if el is None:
        return ""
    for anak in el.iter():
        if isinstance(anak.tag, str) and _lokal(anak) in ("name", "catalogSymbol", "identifier") and _teks(anak):
            return _teks(anak)
    href = el.get("{%s}href" % XLINK) or ""
    return href.rsplit("#", 1)[-1].rsplit("/", 1)[-1]


def _ringkas_laporan(el):
    jenis = LABEL_LAPORAN.get(_lokal(el), _lokal(el).replace("DQ_", ""))
    nama = next((_teks(n) for n in el.iter(_q("gmd:nameOfMeasure")) if _teks(n)), "")
    hasil = []
    for kesesuaian in el.iter(_q("gmd:DQ_ConformanceResult")):
        lulus = (kesesuaian.findtext("gmd:pass/gco:Boolean", default="", namespaces=NS) or "").strip().lower()
        status = {"true": "lulus", "1": "lulus", "false": "tidak lulus", "0": "tidak lulus"}.get(lulus, "")
        penjelasan = _teks(kesesuaian.find("gmd:explanation", NS))
        if status or penjelasan:
            hasil.append(status + (" (%s)" % penjelasan if status and penjelasan else penjelasan))
    for kuantitatif in el.iter(_q("gmd:DQ_QuantitativeResult")):
        nilai = ", ".join(t for t in (_teks(v) for v in kuantitatif.findall("gmd:value", NS)) if t)
        if nilai:
            satuan = _satuan(kuantitatif.find("gmd:valueUnit", NS))
            hasil.append(nilai + (" " + satuan if satuan else ""))
    return "%s%s: %s" % (jenis, " – " + nama if nama else "", "; ".join(hasil) or "hasil tidak dicantumkan")


def pernyataan_kualitas(exml, lineage=None):
    """Isi data_quality_statement GeoNode: lineage dari blok dataQualityInfo mana pun (GeoNode/OWSLib hanya
    membaca blok pertama) ditambah ringkasan laporan kualitas, maksimal 2000 karakter."""
    try:
        akar = _urai(exml) if isinstance(exml, (str, bytes)) else exml
        blok = akar.findall("gmd:dataQualityInfo/gmd:DQ_DataQuality", NS)
        riwayat = next((t for t in (_teks(b.find("gmd:lineage/gmd:LI_Lineage/gmd:statement", NS))
                                    for b in blok) if t), "") or (lineage or "").strip()
        laporan = [_ringkas_laporan(el) for b in blok for r in b.findall("gmd:report", NS)
                   for el in r if isinstance(el.tag, str)]
        bagian = [_polos(riwayat)] if riwayat else []
        if laporan:
            # bernomor: tetap terbaca walau baris baru dilebur (View Metadata GeoNode menampilkannya sebagai HTML)
            bagian.append("Laporan kualitas data:\n" + "\n".join("%d. %s" % (i, _polos(t)) for i, t in enumerate(laporan, 1)))
        teks = "\n\n".join(bagian)
        if not teks:
            return lineage
        return teks if len(teks) <= BATAS_KUALITAS else teks[:BATAS_KUALITAS - 1] + "…"
    except Exception:  # noqa: BLE001
        LOGGER.exception("GeoMDB: ringkasan kualitas data gagal dibuat")
        return lineage


# ── Form metadata GeoNode -> XML yang dipertahankan ──────────────────────────────────────────────────────────────

def potret(resource):
    """Nilai field yang disinkronkan, diambil sebelum dan sesudah form metadata disimpan."""
    try:
        kategori = resource.category if resource.category_id else None
        return {
            "title": resource.title or "",
            "abstract": resource.abstract or "",
            "category": getattr(kategori, "identifier", None),
            "keywords": sorted({k.name for k in resource.keywords.all()}),
            "date": resource.date,
            "date_type": resource.date_type,
        }
    except Exception:  # noqa: BLE001
        LOGGER.exception("GeoMDB: nilai metadata %s tidak terbaca", getattr(resource, "uuid", "?"))
        return None


def _sama(a, b):
    return " ".join((a or "").split()) == " ".join((b or "").split())


def selisih(sebelum, sesudah):
    """Perubahan dari form: {title, abstract, category(+category_lama), kata_kunci_hapus/tambah, date+date_type}."""
    ubah = {}
    for kunci in ("title", "abstract"):
        if not _sama(sebelum.get(kunci), sesudah.get(kunci)) and sesudah.get(kunci):
            ubah[kunci] = sesudah[kunci]
    if sebelum.get("category") != sesudah.get("category"):
        ubah["category"] = sesudah.get("category")
        ubah["category_lama"] = sebelum.get("category")
    lama, baru = set(sebelum.get("keywords") or ()), set(sesudah.get("keywords") or ())
    if lama != baru:
        ubah["kata_kunci_hapus"] = sorted(lama - baru)
        ubah["kata_kunci_tambah"] = sorted(baru - lama)
    if (sebelum.get("date"), sebelum.get("date_type")) != (sesudah.get("date"), sesudah.get("date_type")):
        if sesudah.get("date"):
            ubah["date"] = sesudah["date"]
            ubah["date_type"] = sesudah.get("date_type") or "publication"
    return ubah


def _ubah_kategori(ident, lama, baru):
    def kode(el):
        return _kode(el.find("gmd:MD_TopicCategoryCode", NS))

    if lama and lama != baru:
        for el in ident.findall("gmd:topicCategory", NS):
            if kode(el) == lama:
                ident.remove(el)
    if not baru:
        return
    semua = ident.findall("gmd:topicCategory", NS)
    ada = [el for el in semua if kode(el) == baru]
    if ada:  # GeoNode memakai kategori PERTAMA: pindahkan ke depan
        if semua[0] is not ada[0]:
            ident.remove(ada[0])
            semua[0].addprevious(ada[0])
        return
    el = etree.Element(_q("gmd:topicCategory"))
    etree.SubElement(el, _q("gmd:MD_TopicCategoryCode")).text = baru
    if semua:
        semua[0].addprevious(el)
    else:
        _sisipkan(ident, el)


def _ubah_kata_kunci(ident, hapus, tambah):
    hapus = {h.casefold() for h in hapus}
    for blok in ident.findall("gmd:descriptiveKeywords", NS):
        daftar = blok.find("gmd:MD_Keywords", NS)
        if daftar is None:
            continue
        for kata in daftar.findall("gmd:keyword", NS):
            if " ".join(_teks(kata).split()).casefold() in hapus:
                daftar.remove(kata)
        if daftar.find("gmd:keyword", NS) is None:
            ident.remove(blok)
    ada = {" ".join(_teks(k).split()).casefold()
           for k in ident.iterfind("gmd:descriptiveKeywords/gmd:MD_Keywords/gmd:keyword", NS)}
    tambah = [t for t in tambah if t.casefold() not in ada]
    if not tambah:
        return
    tujuan = None
    for daftar in ident.findall("gmd:descriptiveKeywords/gmd:MD_Keywords", NS):
        if daftar.find("gmd:thesaurusName", NS) is None and \
                _kode(daftar.find("gmd:type/gmd:MD_KeywordTypeCode", NS)) in ("", "theme"):
            tujuan = daftar
            break
    if tujuan is None:
        blok = _sisipkan(ident, etree.Element(_q("gmd:descriptiveKeywords")))
        tujuan = etree.SubElement(blok, _q("gmd:MD_Keywords"))
        jenis = etree.SubElement(etree.SubElement(tujuan, _q("gmd:type")), _q("gmd:MD_KeywordTypeCode"),
                                 codeList=KODE_KATA_KUNCI, codeListValue="theme")
        jenis.text = "theme"
    for t in tambah:
        kata = etree.Element(_q("gmd:keyword"))
        _isi_teks(kata, t)
        _sisipkan(tujuan, kata)


def _ubah_tanggal(sitasi, nilai, jenis):
    """Isi tanggal sitasi berjenis `jenis` (publication/revision/creation); dibuat bila belum ada."""
    for tanggal in sitasi.findall("gmd:date/gmd:CI_Date", NS):
        if _kode(tanggal.find("gmd:dateType/gmd:CI_DateTypeCode", NS)) == jenis:
            _isi_tanggal(_anak(tanggal, "gmd:date"), nilai)
            return
    contoh = sitasi.find("gmd:date/gmd:CI_Date/gmd:dateType/gmd:CI_DateTypeCode", NS)
    daftar_kode = contoh.get("codeList") if contoh is not None and contoh.get("codeList") else KODE_TANGGAL
    tanggal = etree.SubElement(_sisipkan(sitasi, etree.Element(_q("gmd:date"))), _q("gmd:CI_Date"))
    _isi_tanggal(etree.SubElement(tanggal, _q("gmd:date")), nilai)
    kode = etree.SubElement(etree.SubElement(tanggal, _q("gmd:dateType")), _q("gmd:CI_DateTypeCode"),
                            codeList=daftar_kode, codeListValue=jenis)
    kode.text = jenis


def terapkan(teks, ubah):
    """Tulis perubahan dari selisih() ke XML; `datestamp` (opsional) menjadi tanggal metadata baru."""
    akar = _urai(teks)
    ident = _identifikasi(akar)
    if ident is None:
        raise ValueError("XML tidak memiliki identificationInfo")
    sitasi = ident.find("gmd:citation/gmd:CI_Citation", NS)
    if sitasi is None:
        sitasi = etree.SubElement(_anak(ident, "gmd:citation"), _q("gmd:CI_Citation"))
    if "title" in ubah:
        _isi_teks(_anak(sitasi, "gmd:title"), _polos(ubah["title"]))
    if "abstract" in ubah:
        _isi_teks(_anak(ident, "gmd:abstract"), _polos(ubah["abstract"]))
    if "category" in ubah:
        _ubah_kategori(ident, ubah.get("category_lama"), ubah["category"])
    if ubah.get("kata_kunci_hapus") or ubah.get("kata_kunci_tambah"):
        _ubah_kata_kunci(ident, ubah.get("kata_kunci_hapus") or (), ubah.get("kata_kunci_tambah") or ())
    if ubah.get("date"):
        _ubah_tanggal(sitasi, ubah["date"], ubah.get("date_type") or "publication")
    if ubah.get("datestamp"):
        _isi_tanggal(_anak(akar, "gmd:dateStamp"), ubah["datestamp"])
    return _serial(akar)


def _bisa_csw(instance):
    return type(instance).__name__ in ("Dataset", "Document")  # yang didaftarkan GeoNode ke katalog CSW


def _perbarui_csw(instance):
    from geonode.catalogue import models as katalog

    if hasattr(katalog, "update_csw_metadata"):  # GeoNode >= 5.1.1
        katalog.update_csw_metadata(instance)
    else:
        katalog.catalogue_post_save(instance=instance, sender=type(instance))


def setelah_form(resource, sebelum):
    """Dipanggil setelah form metadata GeoNode disimpan. Sumber daya ber-preserve: field yang berubah ditulis ke XML.
    GeoNode 5.0.x-5.1.0: record CSW diperbarui (bawaannya tidak, karena yang disimpan objek ResourceBase)."""
    try:
        from geonode.catalogue import models as katalog

        nyata = resource.get_real_instance()
        if not _bisa_csw(nyata):
            return
        if nyata.metadata_uploaded and nyata.metadata_uploaded_preserve:
            sesudah = potret(nyata)
            ubah = selisih(sebelum, sesudah) if sebelum and sesudah else {}
            if not ubah:
                return
            from django.utils import timezone
            from geonode.base.models import ResourceBase

            if isinstance(ubah.get("date"), datetime) and timezone.is_aware(ubah["date"]):
                ubah["date"] = timezone.localtime(ubah["date"])
            ubah["datestamp"] = timezone.localtime(timezone.now())
            teks = terapkan(nyata.metadata_xml, ubah)
            ResourceBase.objects.filter(pk=nyata.pk).update(metadata_xml=teks)
            nyata.metadata_xml = teks
            _perbarui_csw(nyata)
        elif not hasattr(katalog, "update_csw_metadata"):  # GeoNode >= 5.1.1 sudah memperbaruinya sendiri
            _perbarui_csw(nyata)
    except Exception:  # noqa: BLE001
        LOGGER.exception("GeoMDB: sinkronisasi form ke XML %s gagal", getattr(resource, "uuid", "?"))
