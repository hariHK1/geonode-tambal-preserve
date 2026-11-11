"""GeoMDB: CSW GeoNode menyajikan ISO 19115-3:2018 (MDB 2.0), seperti GeoNetwork.

Dipasang oleh tambal_preserve.py (perintah tambal-mdb) sebagai geonode/catalogue/geomdb_mdb.py, bersama folder
geonode/catalogue/geomdb_xslt/. Satu baris di catalogue/views.py (csw_global_dispatch) memanggil atur(mdict):

- profil pycsw iso19115p3 diaktifkan, sehingga GetCapabilities mengiklankan outputSchema
  http://standards.iso.org/iso/19115/-3/mdb/2.0 dan typeName mdb:MD_Metadata;
- write_record profil itu diganti: rekaman gmd GeoNode (preserve maupun buatan GeoNode) dikonversi dengan XSLT
  geomdb_xslt/geomdb-ke-mdb.xsl (XSLT GeoNetwork + perbaikan GeoMDB) memakai Saxon-HE (paket saxonche, XSLT 2.0);
  elementSetName brief/summary dipotong dari hasil lengkapnya dengan XSLT CSW GeoNetwork.

Bila saxonche tidak bisa dimuat atau konversi satu rekaman gagal, rekaman itu dibuat pycsw sendiri dari kolom
basis data (isinya terbatas) dan sebabnya dicatat di log. Saxon dimuat sekali per proses worker, saat rekaman
ISO 19115-3 pertama diminta (sekitar 80 MB RAM per worker), bukan saat GeoNode mulai.
"""
import logging
import os
import re
import threading

from lxml import etree

VERSI = "1"
LOGGER = logging.getLogger(__name__)

PROFIL = "iso19115p3"
FOLDER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "geomdb_xslt")
XSLT = {"full": "geomdb-ke-mdb.xsl", "summary": "present/mdb-summary.xsl", "brief": "present/mdb-brief.xsl"}
DEKLARASI = re.compile(r"^\s*<\?xml[^>]*\?>")

_kunci = threading.Lock()  # memuat Saxon & menjalankan transformasi (parameter XSLT melekat pada executable)
_saxon = {"pid": None, "mesin": None}


def _mesin():
    """(processor, {elementSetName: executable}) untuk proses ini; None bila Saxon tidak bisa dimuat.
    Dipanggil dengan _kunci terpegang."""
    if _saxon["pid"] != os.getpid():  # proses baru (fork worker): muat sendiri
        _saxon["pid"], _saxon["mesin"] = os.getpid(), None
        try:
            from saxonche import PySaxonProcessor

            proc = PySaxonProcessor(license=False)
            xslt = proc.new_xslt30_processor()
            exe = {esn: xslt.compile_stylesheet(stylesheet_file=os.path.join(FOLDER, *f.split("/")))
                   for esn, f in XSLT.items()}
            _saxon["mesin"] = (proc, exe)
        except Exception:  # noqa: BLE001 — jatuh ke pembuat MDB bawaan pycsw
            LOGGER.exception("geomdb-mdb: Saxon/XSLT tidak bisa dimuat; ISO 19115-3 dibuat pycsw dari kolom basis data")
    return _saxon["mesin"]


def ke_mdb(xml, esn="full", tanggal_dibuat=None):
    """XML ISO 19139 (str/bytes) -> teks ISO 19115-3 (mdb 2.0) untuk elementSetName esn; None bila gagal."""
    teks = DEKLARASI.sub("", xml.decode("utf-8") if isinstance(xml, bytes) else xml, count=1)
    with _kunci:
        mesin = _mesin()
        if mesin is None:
            return None
        proc, exe = mesin
        penuh = exe["full"]
        penuh.clear_parameters()
        if tanggal_dibuat:
            penuh.set_parameter("tanggal-dibuat", proc.make_string_value(tanggal_dibuat))
        hasil = penuh.transform_to_string(xdm_node=proc.parse_xml(xml_text=teks))
        if hasil and esn in ("brief", "summary"):
            hasil = exe[esn].transform_to_string(xdm_node=proc.parse_xml(xml_text=hasil))
    return hasil if hasil and "MD_Metadata" in hasil else None


def _tanggal_dibuat(result):
    dibuat = getattr(result, "created", None)
    return dibuat.isoformat(timespec="seconds") if hasattr(dibuat, "isoformat") else None


def _pasang_write_record():
    from pycsw.core import util
    from pycsw.plugins.profiles.iso19115p3 import iso19115p3 as modul

    kelas = modul.ISO19115p3
    if getattr(kelas.write_record, "geomdb", False):
        return
    asli = kelas.write_record

    def write_record(self, result, esn, outputschema, queryables, caps=None):
        peta = self.context.md_core_model["mappings"]
        if util.getqattr(result, peta["pycsw:Typename"]) == "gmd:MD_Metadata":
            xml = util.getqattr(result, peta["pycsw:XML"])
            try:
                hasil = ke_mdb(xml, esn, _tanggal_dibuat(result)) if xml else None
                if hasil:
                    return etree.fromstring(hasil.encode("utf-8"), self.context.parser)
            except Exception:  # noqa: BLE001 — satu rekaman rusak tidak boleh menggagalkan seluruh respons
                LOGGER.warning("geomdb-mdb: rekaman %s gagal dikonversi ke ISO 19115-3",
                               util.getqattr(result, peta["pycsw:Identifier"]), exc_info=True)
        return asli(self, result, esn, outputschema, queryables, caps)

    write_record.geomdb = True
    kelas.write_record = write_record


def atur(mdict):
    """Konfigurasi pycsw GeoNode + profil iso19115p3 (dipanggil csw_global_dispatch untuk setiap permintaan CSW)."""
    try:
        _pasang_write_record()
    except Exception:  # noqa: BLE001 — pycsw tanpa profil iso19115p3: CSW tetap jalan seperti biasa
        LOGGER.exception("geomdb-mdb: profil pycsw iso19115p3 tidak tersedia; CSW tanpa ISO 19115-3")
        return mdict
    profil = mdict.get("profiles") or ()
    if isinstance(profil, str):
        profil = profil.split(",")
    mdict = dict(mdict)
    mdict["profiles"] = list(dict.fromkeys([p.strip() for p in profil if p.strip()] + [PROFIL]))
    return mdict
