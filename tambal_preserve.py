#!/usr/bin/env python3
"""Tambal GeoNode untuk GeoMDB — dijalankan DI DALAM lingkungan Python GeoNode (kontainer django/celery, atau
virtualenv GeoNode tanpa Docker). Skrip pendamping tambal-geonode-preserve.sh menjalankannya di semua kontainer.

    python tambal_preserve.py cek              # status kedua tambalan, tidak mengubah apa pun
    python tambal_preserve.py tambal           # pasang tambalan GeoMDB (preserve)
    python tambal_preserve.py tambal-unggah    # pasang tambalan unggah metadata (beserta tambalan GeoMDB)
    python tambal_preserve.py pulihkan-unggah  # lepas tambalan unggah metadata; tambalan GeoMDB tetap
    python tambal_preserve.py pulihkan         # kembalikan kode asli GeoNode (lepas keduanya)

1. Tambalan GeoMDB (preserve), GeoNode 4.2.5 s.d. master: geonode/catalogue/models.py menyimpan hasil
   etree.tostring() — bytes — ke kolom teks metadata_xml untuk record ber-preserve, sehingga isinya menjadi
   "b'<gmd:...'": record CSW-nya tak terbaca (HTTP 500) dan setiap penyimpanan berikutnya gagal dengan
   "Start tag expected, '<' not found". Tambalannya satu baris: encoding="unicode" (seperti jalur non-preserve).

2. Tambalan unggah metadata, GeoNode 5.x: memasang geonode/catalogue/geomdb_unggah.py (dari berkas geomdb_unggah.py
   di sebelah skrip ini, atau jalur di variabel GEOMDB_MODUL) beserta baris pemanggilnya, bertanda "# geomdb-unggah".
   XML ISO yang diunggah lewat UI GeoNode otomatis dipertahankan (preserve) dan dirapikan; lihat docstring modul itu.

Kode keluar: 0 berhasil / sudah sesuai · 1 galat · 2 kode tidak dikenali, tidak diubah · 3 tambalan GeoMDB belum
terpasang (hanya pada cek)
"""
import importlib.util
import os
import re
import shutil
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

    def __init__(self, berkas, cara, jangkar, baris, pulih=None, ciri=False):
        self.berkas, self.cara, self.jangkar, self.baris = berkas, cara, jangkar, baris
        self.pulih = pulih or (jangkar[0] if cara == "ganti" else None)
        self.ciri = ciri  # jangkar wajib berada di fungsi pembuat record CSW (lihat CIRI)

    def blok(self):
        return [b + "  " + TANDA for b in self.baris]

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


def _sumber_modul():
    kandidat = [os.environ.get("GEOMDB_MODUL")]
    if globals().get("__file__"):
        kandidat.append(os.path.join(os.path.dirname(os.path.abspath(__file__)), MODUL))
    kandidat.append(os.path.join(os.getcwd(), MODUL))
    return next((k for k in kandidat if k and os.path.isfile(k)), None)


def _berkas_unggah():
    """{jalur: daftar baris} untuk semua berkas yang disentuh tambalan unggah (berkas yang tidak ada: None)."""
    akar = paket()
    hasil = {}
    for b in BAGIAN_UNGGAH:
        jalur = os.path.join(akar, *b.berkas.split("/"))
        if jalur not in hasil:
            hasil[jalur] = _baca(jalur).splitlines(True) if os.path.isfile(jalur) else None
    return hasil


def _jalur(b):
    return os.path.join(paket(), *b.berkas.split("/"))


def keadaan_unggah():
    """([(bagian, keadaan)], keadaan modul: belum|sudah|beda)."""
    berkas = _berkas_unggah()
    bagian = [(b, "tidak-ada" if berkas[_jalur(b)] is None else b.keadaan(berkas[_jalur(b)])) for b in BAGIAN_UNGGAH]
    tujuan = os.path.join(paket(), "catalogue", MODUL)
    sumber = _sumber_modul()
    if not os.path.isfile(tujuan):
        modul = "belum"
    elif sumber and _baca(sumber) != _baca(tujuan):
        modul = "beda"
    else:
        modul = "sudah"
    return bagian, modul


def ringkasan_unggah(bagian, modul):
    nilai = {k for _, k in bagian}
    if nilai == {"sudah"}:
        return "SUDAH ditambal" + (" (modul geomdb_unggah.py perlu diperbarui)" if modul != "sudah" else "") + "."
    if nilai == {"belum"}:
        return "BELUM ditambal."
    if "tidak-ada" in nilai and nilai <= {"tidak-ada", "belum"}:
        return "tidak bisa dipasang: butuh GeoNode 5.x (berkas tidak ada: %s)." % ", ".join(
            sorted({b.berkas for b, k in bagian if k == "tidak-ada"}))
    rinci = ", ".join("%s=%s" % (b.berkas, k) for b, k in bagian)
    return "SEBAGIAN / tidak dikenali (%s)." % rinci


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


def tambal_unggah():
    sumber = _sumber_modul()
    if not sumber:
        print("GALAT: %s tidak ditemukan (letakkan di sebelah skrip ini atau isi variabel GEOMDB_MODUL)." % MODUL)
        return 1
    bagian, modul = keadaan_unggah()
    asing = [(b, k) for b, k in bagian if k not in ("sudah", "belum")]
    if asing:
        print("Tambalan unggah %s Tidak ada yang diubah." % ringkasan_unggah(bagian, modul))
        return 2
    tujuan = os.path.join(paket(), "catalogue", MODUL)
    if modul != "sudah":  # modul dulu: baris yang dipasang sesudahnya mengimpornya
        baru_dibuat = not os.path.isfile(tujuan)
        _tulis(tujuan, _baca(sumber))
        if all(k == "sudah" for _, k in bagian):
            print("Diperbarui: %s" % tujuan)
            return 0
    elif all(k == "sudah" for _, k in bagian):
        print("Tambalan unggah sudah terpasang - tidak ada yang diubah.")
        return 0
    else:
        baru_dibuat = False
    berkas = _berkas_unggah()
    perubahan = {}
    for b, k in bagian:
        if k == "belum":
            jalur = _jalur(b)
            berkas[jalur] = b.pasang(berkas[jalur])
            perubahan[jalur] = (_baca(jalur), "".join(berkas[jalur]))
    try:
        _simpan_semua(perubahan, CADANGAN_UNGGAH)
    except Exception:
        if baru_dibuat:
            os.remove(tujuan)
        raise
    bagian, modul = keadaan_unggah()
    if any(k != "sudah" for _, k in bagian) or modul != "sudah":
        print("Verifikasi gagal: %s" % ringkasan_unggah(bagian, modul))
        return 1
    print("Ditambal (unggah metadata): %s" % ", ".join(sorted(os.path.relpath(j, paket()) for j in perubahan)))
    print("Modul: %s. Asli dicadangkan sebagai *%s" % (tujuan, CADANGAN_UNGGAH))
    return 0


def lepas_unggah(pulih_katalog=BARU):
    """Lepas bagian yang terpasang. Kembalian: (kode keluar, ada perubahan)."""
    bagian, _ = keadaan_unggah()
    berkas = _berkas_unggah()
    perubahan = {}
    for b, k in bagian:
        if k == "sudah":
            jalur = _jalur(b)
            berkas[jalur] = b.lepas(berkas[jalur], pulih_katalog if b is BAGIAN_UNGGAH[0] else None)
            perubahan.setdefault(jalur, [_baca(jalur), None])[1] = "".join(berkas[jalur])
    _simpan_semua({j: tuple(v) for j, v in perubahan.items()}, None)
    sisa, _ = keadaan_unggah()
    tujuan = os.path.join(paket(), "catalogue", MODUL)
    if os.path.isfile(tujuan) and not any(k == "sudah" for _, k in sisa):  # tak ada lagi yang mengimpornya
        os.remove(tujuan)
        perubahan.setdefault(tujuan, None)
        cache = os.path.join(os.path.dirname(tujuan), "__pycache__")
        for nama in os.listdir(cache) if os.path.isdir(cache) else ():
            if nama.startswith(MODUL[:-3] + "."):  # geomdb_unggah.cpython-312.pyc dst.
                os.remove(os.path.join(cache, nama))
    if perubahan:
        print("Dilepas (unggah metadata): %s" % ", ".join(sorted(os.path.relpath(j, paket()) for j in perubahan)))
    asing = [(b, k) for b, k in sisa if k == "tidak-dikenali"]
    if asing:
        print("Tidak dikenali, dibiarkan: %s" % ", ".join(b.berkas for b, _ in asing))
        return 2, bool(perubahan)
    return 0, bool(perubahan)


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
        print("Tambalan unggah metadata: " + ringkasan_unggah(*keadaan_unggah()))
        return {"belum": 3, "sudah": 0, "sudah-unggah": 0, "tidak-dikenali": 2}[st]
    if aksi == "tambal-unggah":
        return tambal_unggah()
    if aksi == "pulihkan-unggah":
        return lepas_unggah()[0]
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
        kode, berubah = lepas_unggah(pulih_katalog=LAMA) if st == "sudah-unggah" else (0, False)
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
        if any(k == "sudah" for _, k in keadaan_unggah()[0]):
            kode, _ = lepas_unggah()
        return kode
    print("pemakaian: python tambal_preserve.py cek|tambal|tambal-unggah|pulihkan-unggah|pulihkan")
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "cek"))
    except (OSError, RuntimeError, SyntaxError) as e:
        print("GALAT: %s" % e)
        sys.exit(1)
