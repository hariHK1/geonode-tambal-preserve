# Tambal GeoNode untuk GeoMDB

*Patches for GeoNode used with the GeoMDB metadata tools: a one-line fix for a GeoNode bug (4.2.5 → master) where
`metadata_uploaded_preserve` stores `metadata_xml` as a Python bytes repr, an optional GeoNode 5.x patch that
makes ISO 19139 XML uploaded through the GeoNode UI be served complete by CSW, and an optional GeoNode 5.x patch that
makes CSW serve ISO 19115-3:2018 (MDB) like GeoNetwork, converted with GeoNetwork's XSLT on Saxon-HE. Instructions
below are in Indonesian.*

Alat untuk **admin server GeoNode**. Ada tiga tambalan:

| Tambalan | Untuk apa | GeoNode |
|---|---|---|
| **GeoMDB (preserve)** | Memperbaiki bug mode *preserve*: mode yang membuat CSW GeoNode menyajikan metadata lengkap apa adanya. Wajib untuk *Kirim ke GeoNode* di plugin QGIS **GeoMDB – Metadata Editor**. | 4.2.5 – master |
| **Unggah metadata UI** | XML ISO 19139 yang diunggah lewat UI GeoNode (*Edit → Upload Metadata*) tersaji **lengkap** di CSW dan unduhan ISO, tanpa API. Sudah termasuk tambalan GeoMDB. | 5.x |
| **CSW ISO 19115-3 (MDB)** | CSW GeoNode juga menyajikan **ISO 19115-3:2018** (`outputSchema=http://standards.iso.org/iso/19115/-3/mdb/2.0`), hasil konversi XSLT seperti GeoNetwork, lolos XSD + Schematron resmi. Berdiri sendiri, bisa dipasang bersama dua tambalan lainnya. | 5.x |

## Unduh

```bash
git clone https://github.com/hariHK1/geonode-tambal-preserve.git
cd geonode-tambal-preserve
```

atau tanpa git:

```bash
curl -fsSL https://github.com/hariHK1/geonode-tambal-preserve/archive/refs/heads/main.tar.gz | tar xz
cd geonode-tambal-preserve-main
```

| Berkas | Fungsi |
|---|---|
| `tambal-geonode-preserve.sh` | Dijalankan di **server Docker**. Menu pilihan; mencari semua kontainer GeoNode (django, celery, …) lalu menjalankan penambal di masing-masing. |
| `tambal_preserve.py` | Penambal. Dijalankan di dalam lingkungan Python GeoNode, otomatis lewat skrip di atas, atau langsung untuk GeoNode tanpa Docker. |
| `geomdb_unggah.py` | Modul tambalan unggah metadata. Dipasang penambal ke `geonode/catalogue/geomdb_unggah.py`. |
| `geomdb_mdb.py` | Modul tambalan CSW ISO 19115-3. Dipasang ke `geonode/catalogue/geomdb_mdb.py`. |
| `xslt-mdb/` | XSLT konversi ISO 19139 → ISO 19115-3 (GeoNetwork + perbaikan GeoMDB, lihat `xslt-mdb/SUMBER.md`). Dipasang ke `geonode/catalogue/geomdb_xslt/`. |

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
  6) Tambalan CSW ISO 19115-3 / MDB (butuh GeoNode 5.x dan internet untuk memasang saxonche)
  7) Lepas tambalan CSW ISO 19115-3
```

atau langsung dengan perintahnya:

```bash
./tambal-geonode-preserve.sh cek              # status semua kontainer GeoNode, tidak mengubah apa pun
./tambal-geonode-preserve.sh tambal           # tambalan GeoMDB (preserve)
./tambal-geonode-preserve.sh tambal-unggah    # tambalan unggah metadata UI (termasuk tambalan GeoMDB)
./tambal-geonode-preserve.sh pulihkan-unggah  # lepas tambalan unggah metadata; tambalan GeoMDB tetap
./tambal-geonode-preserve.sh tambal-mdb       # tambalan CSW ISO 19115-3 (MDB)
./tambal-geonode-preserve.sh pulihkan-mdb     # lepas tambalan CSW ISO 19115-3
./tambal-geonode-preserve.sh pulihkan         # kembalikan kode asli GeoNode (lepas semua tambalan)
```

- Setelah ada perubahan, skrip menanyakan dulu sebelum memulai ulang kontainer. Tambahkan `-y` untuk langsung
  memulai ulang (django & celery berhenti beberapa detik).
- Pilih kontainer sendiri bila perlu: `KONTAINER="django4geonode celery4geonode" ./tambal-geonode-preserve.sh cek`.
- **django dan celery wajib ditambal semua.** Pemrosesan unggah metadata berjalan di celery.

## Pemakaian (GeoNode tanpa Docker)

```bash
source /path/ke/virtualenv-geonode/bin/activate
python tambal_preserve.py cek | tambal | tambal-unggah | tambal-mdb | pulihkan-unggah | pulihkan-mdb | pulihkan
```

`geomdb_unggah.py`, `geomdb_mdb.py`, dan folder `xslt-mdb/` harus berada di folder yang sama dengan
`tambal_preserve.py` (atau isi jalurnya di variabel `GEOMDB_MODUL`, `GEOMDB_MDB_MODUL`, `GEOMDB_XSLT`). Lalu mulai ulang layanan GeoNode dan celery (mis. `systemctl restart uwsgi celery`, sesuaikan
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

## Tambalan CSW ISO 19115-3 / MDB (GeoNode 5.x)

pycsw di GeoNode 5.x sudah punya profil ISO 19115-3 (`iso19115p3`), tetapi GeoNode tidak mengaktifkannya. Kalaupun
diaktifkan, isinya dibuat dari kolom database sehingga kualitas data, lineage, dan banyak elemen lain hilang.
Tambalan ini:

- **mengaktifkan profil itu**: `GetCapabilities` mengiklankan outputSchema
  `http://standards.iso.org/iso/19115/-3/mdb/2.0` dan typeName `mdb:MD_Metadata`;
- **mengonversi XML ISO 19139 dataset** (yang dipertahankan / preserve maupun buatan GeoNode) **dengan XSLT**, seperti
  GeoNetwork: XSLT konversi GeoNetwork dijalankan Saxon-HE (XSLT 2.0). `elementSetName` brief/summary dipotong dari
  hasil lengkapnya dengan XSLT CSW GeoNetwork.

Contoh permintaan:

```
/catalogue/csw?service=CSW&version=2.0.2&request=GetRecordById&id=<UUID>&elementSetName=full&outputSchema=http://standards.iso.org/iso/19115/-3/mdb/2.0
/catalogue/csw?service=CSW&version=2.0.2&request=GetRecords&typeNames=mdb:MD_Metadata&resultType=results&outputSchema=http://standards.iso.org/iso/19115/-3/mdb/2.0
```

**Penyempurnaan atas XSLT GeoNetwork** (`xslt-mdb/geomdb-ke-mdb.xsl`; berkas GeoNetwork tidak disunting):

- *Sebelum konversi*, gmd dirapikan: urutan elemen disusun ulang menurut XSD ISO 19139, dan properti laporan
  kualitas yang dibungkus berlapis diratakan. XML ekspor plugin GeoMDB 1.0.5 yang tidak valid pun menjadi
  ISO 19115-3 yang valid.
- *Bug / celah GeoNetwork*: setiap hasil kualitas data tertulis **dua kali** (`DQ.xsl` menerapkan `gmd:result` dua
  kali); template `updateScope` yang tidak pernah terpanggil (nama mode salah); `associatedResource` kehilangan
  judul; bahasa sumber daya ditulis sebagai `otherLocale`; `dataSetURI` hilang bila sitasi tanpa
  `citedResponsibleParty`; elemen ekstensi codelist tanpa `code`/`conceptName`; `gco:LocalName` (tidak ada di
  ISO 19115-3) → `gco:ScopedName`; aturan ganda untuk `gmd:locale`; deklarasi `mda/1.0`.
- *Kelengkapan ISO 19115-1*: tanggal `creation` metadata (dari tanggal dataset dibuat di GeoNode), `gco:DateTime`
  untuk tanggal sitasi, `MD_Scope` untuk scope lineage, `characterEncoding` locale, dan elemen wajib
  `DQ_ConformanceResult` yang kosong ditandai `gco:nilReason`. Data yang tidak ada **tidak dikarang**.
- *Bug GeoNode*: kode peran berupa label ("Metadata Author", "Point of Contact") → kode ISO (`author`,
  `pointOfContact`); organisasi tanpa nama yang hanya membungkus satu orang → `CI_Individual`.
- Namespace mengikuti set ISO 19115-3:2018 yang diimpor XSD resmi `mds/2.0` (mdb, mds, cit, mrl, mrc, mac, mda, msr,
  srv = 2.0; lainnya 1.0); `xsi:schemaLocation` menunjuk `mdb/2.0/mdb.xsd` resmi.

Diuji pada XML buatan GeoNode 5.1.1, XML ber-preserve, ekspor lengkap & minimal geomdb-hub, dan ekspor plugin GeoMDB
1.0.5 (asli maupun setelah tambalan unggah) dan 1.1.0: semuanya **valid XSD + Schematron ISO 19115-3:2018**, setiap
nilai sumber terbawa, dan jumlah elemen kunci (laporan & hasil kualitas, tahap proses, sumber, tautan, kata kunci,
format, ekstensi) sama dengan sumbernya. Pengecualiannya disengaja: label peran diganti kode ISO, nama standar menjadi "ISO 19115-3:2018", dan
pihak tanpa nama dibuang.

Catatan:

- **Butuh paket `saxonche`** (Saxon-HE 13.1.1, sekitar 40 MB unduhan / 110 MB terpasang per kontainer). `tambal-mdb`
  memasangnya lewat pip bila belum ada, **perlu internet**. Saxon diuji dulu di proses terpisah; bila tidak berfungsi
  di CPU/OS server itu, tidak ada kode GeoNode yang diubah. `pulihkan-mdb` melepas saxonche lagi bila dulu dipasang
  oleh penambal ini. Server tanpa internet: unduh wheel `saxonche` (manylinux, versi Python GeoNode) di komputer
  lain, `pip install` di kontainer, lalu jalankan `tambal-mdb`.
- **Memori**: Saxon dimuat per proses worker uwsgi saat rekaman ISO 19115-3 pertama diminta, sekitar **+120 MB per
  worker** yang pernah melayaninya. Worker didaur ulang uwsgi GeoNode (`max-requests`, `max-worker-lifetime`).
  Perhatikan batas memori kontainer django bila ada.
- Keluaran gmd (ISO 19139) dan format lain **tidak berubah**. Rekaman yang XML-nya rusak atau gagal dikonversi
  dibuat pycsw dari kolom database seperti biasa, dan sebabnya dicatat di log.
- brief/summary tidak lolos XSD karena elemen wajib (contact, dateInfo) memang tidak disertakan. Ini sama dengan
  GeoNetwork dan himpunan brief/summary CSW ISO AP.
- **Pihak tanpa nama dibuang.** Kontak yang nama individu, organisasi, dan jabatannya kosong (GeoNode menulisnya
  untuk akun yang profilnya belum diisi) tidak bisa dijadikan pihak ISO 19115-3. Lengkapi nama dan organisasi di
  profil akun GeoNode.
- Bagian yang diubah di kode GeoNode bertanda `# geomdb-mdb` (satu baris di `catalogue/views.py` + modul + folder
  XSLT).

## Pengaman

- **Hanya mengubah bila kodenya persis dikenali.** Setiap baris yang dimaksud harus muncul tepat sekali dan utuh
  (untuk tambalan GeoMDB: di fungsi pembuat record CSW). Kalau GeoNode sudah memperbaikinya sendiri atau kodenya
  berbeda, tidak ada yang diubah (kode keluar 2). Tambalan unggah dipasang semua atau tidak sama sekali.
- **Berkas asli dicadangkan** sebagai `*.geomdb-asli` (tambalan GeoMDB), `*.geomdb-unggah-asli` (tambalan
  unggah), dan `*.geomdb-mdb-asli` (tambalan CSW ISO 19115-3) di sebelah berkas aslinya.
- **Hasil tambalan diperiksa** dengan kompilasi Python sebelum menggantikan berkas asli.
- **Aman dijalankan berulang.** Yang sudah ditambal tidak diubah lagi. Bila modul (`geomdb_unggah.py`,
  `geomdb_mdb.py`) atau XSLT di repo lebih baru, `cek` melaporkannya dan `tambal-unggah` / `tambal-mdb`
  memperbaruinya.
- Diuji pada kode asli GeoNode 4.2.5, 4.4.5, 5.0.0, 5.0.3, 5.1.0, 5.1.1 dan `master`: `pulihkan` mengembalikan berkas
  identik dengan aslinya. Tambalan unggah dan CSW ISO 19115-3 ditolak di 4.x (kode keluar 2, tidak ada yang diubah).

Kode keluar: `0` berhasil/sudah sesuai · `1` galat · `2` kode tidak dikenali (tidak diubah) · `3` tambalan GeoMDB
belum terpasang (hanya pada `cek`).

## Penting setelah upgrade

Tambalan tersimpan di berkas kode yang dipakai kontainer:

- **Kode ada di dalam image** (umum): tambalan **hilang bila kontainer dibuat ulang** (upgrade image,
  `docker compose up` dengan image baru). Paket `saxonche` selalu terpasang di dalam kontainer, jadi ikut hilang.
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
# tambalan CSW ISO 19115-3 (GeoNode 5.x); memasang saxonche saat build
COPY geomdb_mdb.py /tmp/
COPY xslt-mdb /tmp/xslt-mdb
RUN cd /tmp && python tambal_preserve.py tambal-mdb
```

Setelah GeoNode merilis perbaikan bug preserve, tambalan GeoMDB tidak diperlukan lagi: `cek` akan melaporkan
"kode tidak dikenali".

## Lisensi

GPL-3.0, sama dengan GeoNode. XSLT GeoNetwork di `xslt-mdb/ISO19139/` dan `xslt-mdb/present/` berlisensi
GPL-2.0-or-later (lihat `xslt-mdb/SUMBER.md`).
