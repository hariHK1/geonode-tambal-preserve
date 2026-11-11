# Tambal GeoNode untuk GeoMDB

*Patches for GeoNode used with the GeoMDB metadata tools: a one-line fix for a GeoNode bug (4.2.5 → master) where
`metadata_uploaded_preserve` stores `metadata_xml` as a Python bytes repr, and an optional GeoNode 5.x patch that
makes ISO 19139 XML uploaded through the GeoNode UI be served complete by CSW. Instructions below are in Indonesian.*

Alat untuk **admin server GeoNode**. Ada dua tambalan:

| Tambalan | Untuk apa | GeoNode |
|---|---|---|
| **GeoMDB (preserve)** | Memperbaiki bug mode *preserve*: mode yang membuat CSW GeoNode menyajikan metadata lengkap apa adanya. Wajib untuk *Kirim ke GeoNode* di plugin QGIS **GeoMDB – Metadata Editor**. | 4.2.5 – master |
| **Unggah metadata UI** | XML ISO 19139 yang diunggah lewat UI GeoNode (*Edit → Upload Metadata*) tersaji **lengkap** di CSW dan unduhan ISO, tanpa API. Sudah termasuk tambalan GeoMDB. | 5.x |

## Unduh

```bash
git clone https://github.com/hariHK1/geonode-tambal-preserve.git
cd geonode-tambal-preserve
```

atau cukup tiga berkasnya:

```bash
for f in tambal_preserve.py geomdb_unggah.py tambal-geonode-preserve.sh; do
  curl -fsSLO https://raw.githubusercontent.com/hariHK1/geonode-tambal-preserve/main/$f
done
chmod +x tambal-geonode-preserve.sh
```

| Berkas | Fungsi |
|---|---|
| `tambal-geonode-preserve.sh` | Dijalankan di **server Docker**. Menu pilihan; mencari semua kontainer GeoNode (django, celery, …) lalu menjalankan penambal di masing-masing. |
| `tambal_preserve.py` | Penambal. Dijalankan di dalam lingkungan Python GeoNode, otomatis lewat skrip di atas, atau langsung untuk GeoNode tanpa Docker. |
| `geomdb_unggah.py` | Modul tambalan unggah metadata. Dipasang penambal ke `geonode/catalogue/geomdb_unggah.py`. |

## Pemakaian (GeoNode dengan Docker)

Jalankan tanpa argumen untuk memilih dari menu:

```bash
./tambal-geonode-preserve.sh
```

```
  1) Cek status
  2) Tambalan GeoMDB (preserve)
  3) Tambalan unggah metadata UI GeoNode (butuh GeoNode 5.x, sudah termasuk tambalan GeoMDB)
  4) Lepas tambalan unggah metadata (tambalan GeoMDB tetap terpasang)
  5) Pulihkan kode asli GeoNode (lepas semua tambalan)
```

atau langsung dengan perintahnya:

```bash
./tambal-geonode-preserve.sh cek              # status semua kontainer GeoNode, tidak mengubah apa pun
./tambal-geonode-preserve.sh tambal           # tambalan GeoMDB (preserve)
./tambal-geonode-preserve.sh tambal-unggah    # tambalan unggah metadata UI (termasuk tambalan GeoMDB)
./tambal-geonode-preserve.sh pulihkan-unggah  # lepas tambalan unggah metadata; tambalan GeoMDB tetap
./tambal-geonode-preserve.sh pulihkan         # kembalikan kode asli GeoNode
```

- Setelah ada perubahan, skrip menanyakan dulu sebelum memulai ulang kontainer. Tambahkan `-y` untuk langsung
  memulai ulang (django & celery berhenti beberapa detik).
- Pilih kontainer sendiri bila perlu: `KONTAINER="django4geonode celery4geonode" ./tambal-geonode-preserve.sh cek`.
- **django dan celery wajib ditambal semua.** Pemrosesan unggah metadata berjalan di celery.

## Pemakaian (GeoNode tanpa Docker)

```bash
source /path/ke/virtualenv-geonode/bin/activate
python tambal_preserve.py cek | tambal | tambal-unggah | pulihkan-unggah | pulihkan
```

`geomdb_unggah.py` harus berada di folder yang sama dengan `tambal_preserve.py` (atau isi jalurnya di variabel
`GEOMDB_MODUL`). Lalu mulai ulang layanan GeoNode dan celery (mis. `systemctl restart uwsgi celery`, sesuaikan
dengan server).

## Tambalan GeoMDB (preserve)

Di GeoNode 4.2.5 sampai versi terbaru (`master`), fungsi pembuat record CSW (`geonode/catalogue/models.py`)
menyimpan XML ber-preserve sebagai *bytes* ke kolom teks. Isinya menjadi `b'<gmd:MD_Metadata …'`, sehingga:

- record CSW dataset itu tidak bisa dibaca (`GetRecordById` format ISO → HTTP 500);
- setiap penyimpanan dataset berikutnya gagal (`Start tag expected, '<' not found`) dan dataset bisa berstatus
  `INVALID`.

Data spasial (layer, WMS/WFS) **tidak** terpengaruh, hanya metadata. Tambalannya **satu baris**:

```python
md_doc = etree.tostring(dlxml.fromstring(instance.metadata_xml))                       # sebelum
md_doc = etree.tostring(dlxml.fromstring(instance.metadata_xml), encoding="unicode")   # sesudah
```

Setelah ditambal, uji preserve pada **satu dataset** dulu. Di plugin GeoMDB: buka *Kirim ke GeoNode*, centang
**"Server GeoNode ini sudah ditambal"**, lalu Perbarui. Bila ternyata belum berhasil, plugin otomatis kembali ke mode
biasa dan memulihkan record CSW-nya.

## Tambalan unggah metadata UI (GeoNode 5.x)

Tanpa tambalan ini, XML yang diunggah lewat UI hanya dipakai GeoNode untuk mengisi beberapa field (judul, abstrak,
kata kunci, …); CSW dan unduhan ISO dibuat ulang dari database, sehingga kualitas data, lineage, tahap proses,
sumber, edisi, kredit, skala, kontak organisasi, dan lisensi hilang. Mode preserve hanya bisa dinyalakan lewat API.

Setelah ditambal:

- **XML ISO 19139 yang diunggah otomatis dipertahankan** (preserve), baik lewat *Edit → Upload Metadata* maupun
  `.xml` yang ikut diunggah bersama data. XML FGDC / Dublin Core tetap diperlakukan seperti biasa.
- **XML dirapikan sebelum disajikan CSW**:
  - `fileIdentifier` diganti UUID dataset di GeoNode;
  - deklarasi `<?xml … encoding="UTF-8"?>` aman (sebelumnya membuat unggahan ber-preserve gagal);
  - lineage yang ditaruh di blok `dataQualityInfo` terpisah (plugin GeoMDB 1.0.5) dipindah ke blok pertama bila
    cakupannya sama, karena tampilan XSL GeoNode, OWSLib, dan banyak harvester hanya membaca blok pertama;
  - tautan GeoNode ditambahkan bila pasangan URL + protokolnya belum ada di XML: halaman dataset, unduhan,
    WMS/WFS/WCS. Tautan yang sudah ditulis di XML tetap.
- **"Data Quality" di halaman GeoNode terisi**: lineage, dari blok `dataQualityInfo` mana pun (GeoNode hanya membaca
  blok pertama), ditambah ringkasan laporan kualitas, misalnya
  `1. Konsistensi domain – Kesesuaian format kode wilayah: lulus (49 dari 49 …)`.
- **Perubahan lewat form metadata GeoNode ikut ditulis ke XML.** Judul, abstrak, kata kunci, kategori, dan tanggal
  (beserta jenisnya) yang **diubah** di form ditulis ke XML yang dipertahankan, `dateStamp` diperbarui, lalu record
  CSW diperbarui. Field lain (kontak, wilayah, lisensi, …) tidak disinkronkan: ubah di GeoMDB lalu unggah ulang XML.
- **GeoNode 5.0.x – 5.1.0: record CSW diperbarui setelah form metadata disimpan.** Di versi itu form tidak memperbarui
  CSW sama sekali, juga untuk dataset biasa (GeoNode memperbaikinya di 5.1.1).
- Tampilan metadata XSL untuk dataset ber-preserve tidak lagi gagal ("Resource Metadata not available!").

Catatan:

- Dataset yang XML-nya diunggah **sebelum** ditambal: unggah ulang XML-nya agar dipertahankan.
- XML disajikan apa adanya, jadi isinya harus sudah bersih. Contohnya, hapus sisa template ekspor plugin GeoMDB
  1.0.5 sebelum diunggah.
- Bagian yang diubah di kode GeoNode bertanda `# geomdb-unggah` (5 berkas + modul `catalogue/geomdb_unggah.py`).
  Setiap fungsi modul menangkap galatnya sendiri: kegagalan tambalan tidak menggagalkan penyimpanan dataset.

## Pengaman

- **Hanya mengubah bila kodenya persis dikenali.** Setiap baris yang dimaksud harus muncul tepat sekali dan utuh
  (untuk tambalan GeoMDB: di fungsi pembuat record CSW). Kalau GeoNode sudah memperbaikinya sendiri atau kodenya
  berbeda, tidak ada yang diubah (kode keluar 2). Tambalan unggah dipasang semua atau tidak sama sekali.
- **Berkas asli dicadangkan** sebagai `*.geomdb-asli` (tambalan GeoMDB) dan `*.geomdb-unggah-asli` (tambalan
  unggah) di sebelah berkas aslinya.
- **Hasil tambalan diperiksa** dengan kompilasi Python sebelum menggantikan berkas asli.
- **Aman dijalankan berulang.** Yang sudah ditambal tidak diubah lagi. Bila modul `geomdb_unggah.py` di repo lebih
  baru, `cek` melaporkannya dan `tambal-unggah` memperbaruinya.
- Diuji pada kode asli GeoNode 4.2.5, 4.4.5, 5.0.0, 5.0.3, 5.1.0, 5.1.1 dan `master`: `pulihkan` mengembalikan berkas
  identik dengan aslinya. Tambalan unggah ditolak di 4.x (kode keluar 2, tidak ada yang diubah).

Kode keluar: `0` berhasil/sudah sesuai · `1` galat · `2` kode tidak dikenali (tidak diubah) · `3` tambalan GeoMDB
belum terpasang (hanya pada `cek`).

## Penting setelah upgrade

Tambalan tersimpan di berkas kode yang dipakai kontainer:

- **Kode ada di dalam image** (umum): tambalan **hilang bila kontainer dibuat ulang** (upgrade image,
  `docker compose up` dengan image baru).
- **Kode dipasang dari folder server** (mis. `~/geonode` → `/usr/src/geonode`, sering dipakai bersama oleh django
  & celery): tambalan bertahan walau kontainer dibuat ulang, tetapi terlihat sebagai perubahan oleh git di folder
  itu dan bisa tertimpa saat folder itu diperbarui (`git pull`). Cek dengan
  `docker inspect django4geonode --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}'`.

Karena itu, setelah setiap upgrade atau pembaruan kode GeoNode, jalankan `cek`, lalu pasang lagi bila perlu. Skrip
selalu memulai ulang **semua** kontainer GeoNode setelah ada perubahan, karena kontainer yang berbagi berkas ikut
berubah walau tidak dilaporkan "Ditambal".

Supaya permanen, masukkan ke Dockerfile image GeoNode (mis. proyek *geonode-project*), setelah GeoNode terpasang:

```dockerfile
COPY tambal_preserve.py geomdb_unggah.py /tmp/
# tambalan GeoMDB saja; 2 = GeoNode sudah memperbaikinya sendiri
RUN python /tmp/tambal_preserve.py tambal || [ $? -eq 2 ]
# atau tambalan unggah metadata (GeoNode 5.x); gagal bila kode GeoNode tidak dikenali
RUN cd /tmp && python tambal_preserve.py tambal-unggah
```

Setelah GeoNode merilis perbaikan bug preserve, tambalan GeoMDB tidak diperlukan lagi: `cek` akan melaporkan
"kode tidak dikenali".

## Lisensi

GPL-3.0, sama dengan GeoNode.
