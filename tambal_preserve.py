#!/usr/bin/env python3
"""Tambal bug preserve GeoNode — dijalankan DI DALAM lingkungan Python GeoNode (kontainer django/celery, atau
virtualenv GeoNode tanpa Docker). Skrip pendamping tambal-geonode-preserve.sh menjalankannya di semua kontainer.

    python tambal_preserve.py cek        # lihat status, tidak mengubah apa pun
    python tambal_preserve.py tambal     # pasang tambalan (berkas asli dicadangkan)
    python tambal_preserve.py pulihkan   # kembalikan kode asli GeoNode

Bug (GeoNode 4.2.5 s.d. master): geonode/catalogue/models.py, update_csw_metadata() menyimpan hasil
etree.tostring() — bytes — ke kolom teks metadata_xml untuk record ber-preserve, sehingga isinya menjadi
"b'<gmd:...'": record CSW-nya tak terbaca (HTTP 500) dan setiap penyimpanan berikutnya gagal dengan
"Start tag expected, '<' not found". Tambalannya satu baris: encoding="unicode" (seperti jalur non-preserve).

Kode keluar: 0 berhasil / sudah sesuai · 1 galat · 2 kode tidak dikenali, tidak diubah · 3 belum ditambal (cek)
"""
import importlib.util
import os
import py_compile
import re
import shutil
import sys
import tempfile

LAMA = "md_doc = etree.tostring(dlxml.fromstring(instance.metadata_xml))"
BARU = 'md_doc = etree.tostring(dlxml.fromstring(instance.metadata_xml), encoding="unicode")'
CADANGAN = ".geomdb-asli"
# Fungsinya catalogue_post_save() (4.2 – 5.1) atau update_csw_metadata() (master); keduanya memeriksa preserve
# lalu menyimpan md_doc ke metadata_xml — itu yang dijadikan pengaman, bukan nama fungsinya.
CIRI = ("metadata_uploaded_preserve", "metadata_xml=md_doc")


def lokasi():
    """geonode/catalogue/models.py milik GeoNode yang terpasang — tanpa mengimpor Django."""
    spec = importlib.util.find_spec("geonode")
    if spec is None or not spec.submodule_search_locations:
        raise RuntimeError("paket 'geonode' tidak ditemukan di Python ini")
    return os.path.join(list(spec.submodule_search_locations)[0], "catalogue", "models.py")


def versi_geonode():
    try:
        import geonode  # ringan: hanya informasi versi
        return getattr(geonode, "__version__", None) or geonode.get_version()
    except Exception:  # noqa: BLE001 — versi hanya informasi
        return "?"


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
    if _cocok_di_fungsi(teks, LAMA) and BARU not in teks:
        return "belum"
    if _cocok_di_fungsi(teks, BARU) and LAMA not in teks:
        return "sudah"
    return "tidak-dikenali"


def _ganti(teks, dari, ke):
    m = _cocok_di_fungsi(teks, dari)
    return teks[:m.start()] + m.group(0).replace(dari, ke) + teks[m.end():]


def _baca(jalur):
    with open(jalur, encoding="utf-8", newline="") as fh:
        return fh.read()


def _tulis(jalur, teks):
    """Tulis atomik, izin berkas tetap, lalu pastikan Python bisa mengompilasinya."""
    fd, sementara = tempfile.mkstemp(dir=os.path.dirname(jalur), prefix=".tambal-", suffix=".py")
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as fh:
        fh.write(teks)
    shutil.copymode(jalur, sementara)
    try:
        py_compile.compile(sementara, doraise=True)
    except py_compile.PyCompileError:
        os.remove(sementara)
        raise
    os.replace(sementara, jalur)


def main(aksi):
    jalur = lokasi()
    teks = _baca(jalur)
    st = status(teks)
    print("GeoNode %s | %s" % (versi_geonode(), jalur))
    if aksi == "cek":
        print({"belum": "BELUM ditambal - preserve akan merusak record CSW.",
               "sudah": "SUDAH ditambal.",
               "tidak-dikenali": "Kode tidak dikenali (mungkin GeoNode sudah memperbaikinya) - tidak perlu/tidak bisa "
                                 "ditambal otomatis."}[st])
        return {"belum": 3, "sudah": 0, "tidak-dikenali": 2}[st]
    if st == "tidak-dikenali":
        print("Kode tidak dikenali - tidak diubah.")
        return 2
    if aksi == "tambal":
        if st == "sudah":
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
        if st == "belum":
            print("Belum ditambal - tidak ada yang dikembalikan.")
            return 0
        # Balikkan baris yang diubah (bukan menyalin cadangan: cadangan bisa berasal dari versi GeoNode lama)
        _tulis(jalur, _ganti(teks, BARU, LAMA))
        print("Kode asli GeoNode dikembalikan." if status(_baca(jalur)) == "belum" else "Verifikasi gagal.")
        return 0 if status(_baca(jalur)) == "belum" else 1
    print("pemakaian: python tambal_preserve.py cek|tambal|pulihkan")
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "cek"))
    except (OSError, RuntimeError, py_compile.PyCompileError) as e:
        print("GALAT: %s" % e)
        sys.exit(1)
