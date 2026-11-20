# Tambal GeoNode untuk GeoMDB

*Patches for GeoNode used with the GeoMDB metadata tools: a one-line fix for a GeoNode bug (4.2.5 → master) where
`metadata_uploaded_preserve` stores `metadata_xml` as a Python bytes repr, an optional GeoNode 5.x patch that
makes ISO 19139 XML uploaded through the GeoNode UI be served complete by CSW, and an optional GeoNode 5.x patch that
makes CSW serve ISO 19115-3:2018 (MDB) like GeoNetwork, converted with GeoNetwork's XSLT on Saxon-HE, plus security
patches for GeoNode 4.x – 5.1.x (command injection, SSRF, unsafe XML, stored XSS) and Docker hardening for GeoServer,
PostgreSQL and nginx (security headers, hidden server versions).
Instructions below are in Indonesian.*

Alat untuk **admin server GeoNode**. Ada tiga tambalan metadata dan satu paket [keamanan](#keamanan-menu-712):

| Tambalan | Untuk apa | GeoNode |
|---|---|---|
| **GeoMDB (preserve)** | Memperbaiki bug mode *preserve*: mode yang membuat CSW GeoNode menyajikan metadata lengkap apa adanya. Wajib untuk *Kirim ke GeoNode* di plugin QGIS **GeoMDB – Metadata Editor**. | 4.2.5 – master |
| **Unggah metadata UI** | XML ISO 19139 yang diunggah lewat UI GeoNode (*Edit → Upload Metadata*) tersaji **lengkap** di CSW dan unduhan ISO, tanpa API. Sudah termasuk tambalan GeoMDB. | 5.x |
| **CSW ISO 19115-3 (MDB)** | CSW GeoNode juga menyajikan **ISO 19115-3:2018** (`outputSchema=http://standards.iso.org/iso/19115/-3/mdb/2.0`), hasil konversi XSLT seperti GeoNetwork, lolos XSD + Schematron resmi. Berdiri sendiri, bisa dipasang bersama dua tambalan lainnya. | 5.x |

**Panduan bergambar** (PowerPoint, 39 slide): langkah demi langkah dengan screenshot GeoNode 5.1.1 asli dan kotak
perintah yang bisa disalin, termasuk keamanan, perketat Docker, temuan pemindai VA, dan upgrade 4.x → 5.x —
[`docs/Panduan-Penambalan-GeoNode-GeoMDB.pptx`](docs/Panduan-Penambalan-GeoNode-GeoMDB.pptx).

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
| `geomdb_aman.py` | Modul tambalan keamanan. Dipasang ke `geonode/security/geomdb_aman.py`. |
| `xslt-mdb/` | XSLT konversi ISO 19139 → ISO 19115-3 (GeoNetwork + perbaikan GeoMDB, lihat `xslt-mdb/SUMBER.md`). Dipasang ke `geonode/catalogue/geomdb_xslt/`. |

## Pemakaian (GeoNode dengan Docker)

Jalankan tanpa argumen. Menunya **dua tingkat**: pilih **versi GeoNode** dulu (versi yang sedang berjalan
terdeteksi otomatis sebagai bawaan), lalu muncul hanya tambalan/alat yang **kompatibel** dengan versi itu.

```bash
./tambal-geonode-preserve.sh
```

```
Pilih versi GeoNode server:
  1) GeoNode 4.x
  2) GeoNode 5.x
```

```
GeoNode 5.x — tambalan & alat yang kompatibel:      GeoNode 4.x — tambalan & alat yang kompatibel:
  1) Cek status                                        1) Cek status
  — Metadata —                                         — Metadata —
  2) Tambalan GeoMDB (preserve)                        2) Tambalan GeoMDB (preserve)
  3) Tambalan unggah metadata UI                       — Keamanan —
  4) Lepas tambalan unggah metadata                    3) Cek celah
  5) Tambalan CSW ISO 19115-3 / MDB                    4) Pasang tambalan keamanan
  6) Lepas tambalan CSW ISO 19115-3                    5) Lepas tambalan keamanan
  — Keamanan —                                         6) Uji keamanan (simulasi serangan)
  7) Cek celah                                         7) Perketat konfigurasi Docker
  8) Pasang tambalan keamanan                          8) Kembalikan konfigurasi Docker
  9) Lepas tambalan keamanan                           — Lainnya —
 10) Uji keamanan (simulasi serangan)                  9) Panduan upgrade 4.x -> 5.x
 11) Perketat konfigurasi Docker                      10) Pulihkan kode asli GeoNode
 12) Kembalikan konfigurasi Docker
  — Lainnya —          (unggah metadata UI & CSW ISO 19115-3/MDB hanya untuk 5.x,
 13) Pulihkan kode asli GeoNode        maka tidak muncul di menu 4.x)
```

atau langsung dengan perintahnya (sama untuk versi apa pun; perintah 5.x ditolak di 4.x dengan kode 2):

```bash
./tambal-geonode-preserve.sh cek              # status semua kontainer GeoNode, tidak mengubah apa pun
./tambal-geonode-preserve.sh tambal           # tambalan GeoMDB (preserve)
./tambal-geonode-preserve.sh tambal-unggah    # tambalan unggah metadata UI (termasuk tambalan GeoMDB)
./tambal-geonode-preserve.sh pulihkan-unggah  # lepas tambalan unggah metadata; tambalan GeoMDB tetap
./tambal-geonode-preserve.sh tambal-mdb       # tambalan CSW ISO 19115-3 (MDB)
./tambal-geonode-preserve.sh pulihkan-mdb     # lepas tambalan CSW ISO 19115-3
./tambal-geonode-preserve.sh cek-aman         # celah kode K1..K4 + konfigurasi GeoServer, PostgreSQL & header web
./tambal-geonode-preserve.sh tambal-aman      # tambalan keamanan pada kode yang masih rentan
./tambal-geonode-preserve.sh pulihkan-aman    # lepas tambalan keamanan
./tambal-geonode-preserve.sh perketat         # perketat konfigurasi Docker (GeoServer, PostgreSQL, nginx, Tomcat, pendaftaran)
./tambal-geonode-preserve.sh kembalikan       # batalkan perketat
./tambal-geonode-preserve.sh uji-aman         # simulasi serangan K1..K4 + cek header/versi web, lalu dibersihkan
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
python tambal_preserve.py cek-aman | tambal-aman | pulihkan-aman
```

`geomdb_unggah.py`, `geomdb_mdb.py`, `geomdb_aman.py`, dan folder `xslt-mdb/` harus berada di folder yang sama dengan
`tambal_preserve.py` (atau isi jalurnya di variabel `GEOMDB_MODUL`, `GEOMDB_MDB_MODUL`, `GEOMDB_AMAN_MODUL`,
`GEOMDB_XSLT`). Menu 11–12 (konfigurasi Docker) hanya untuk GeoNode dengan Docker. Lalu mulai ulang layanan GeoNode dan celery (mis. `systemctl restart uwsgi celery`, sesuaikan
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

## Keamanan (menu 7–12)

Nomor menu di bagian ini mengikuti submenu GeoNode 5.x. Di submenu 4.x: 3 cek, 4 tambal, 5 lepas, 6 uji,
7 perketat, 8 kembalikan.

### Celah kode GeoNode (menu 7 cek, 8 tambal, 9 lepas)

| | Celah | Rentan | Tambalan GeoMDB (setara perbaikan resmi) |
|---|---|---|---|
| **K1** | Injeksi perintah lewat nama layer unggahan (CVE-2026-33050): nama layer di GeoJSON/KML disisipkan ke perintah `ogr2ogr` yang dijalankan shell, sehingga pengguna yang boleh mengunggah bisa menjalankan perintah di server | semua 4.x, 5.0.0 – 5.0.2 (advisory resmi: < 5.1.0) | argumen dikutip (`shlex.quote`) dan `ogr2ogr` dijalankan tanpa shell. Di 4.x yang ditambal paket `importer` |
| **K2** | SSRF lewat pendaftaran *Remote Service* dan `/proxy` (CVE-2026-39922): server GeoNode bisa disuruh mengambil URL jaringan dalam (database, metadata cloud `169.254.169.254`, layanan internal) | 4.0 – 4.4.x, 5.0.0 – 5.0.2 | URL ditolak bila bukan http(s), memuat userinfo, atau salah satu alamat IP-nya bukan alamat publik. Host GeoServer/GeoNode sendiri tetap boleh lewat `/proxy` |
| **K3** | XML/SLD unggahan berisi DTD, entitas, XSLT, atau skrip | 4.x – 5.1.0 | XML ditolak bila memuat DOCTYPE, *processing instruction*, XSLT, elemen skrip/iframe/objek, atribut `on*`, atau URL `javascript:` |
| **K4** | XSS tersimpan di abstrak & isian HTML metadata (CVE-2026-55649): skrip di abstrak dijalankan di peramban pengunjung halaman dataset | 4.x, 5.0.0 – 5.0.2 | abstrak, tujuan, batasan, informasi tambahan, dan pernyataan kualitas data dibersihkan saat disimpan (daftar tag aman; skrip dan atribut berbahaya dibuang). Teks biasa tidak diubah |

- **Hanya kode yang masih rentan yang ditambal.** Bagian yang sudah diperbaiki GeoNode sendiri dilaporkan
  "aman (sudah diperbaiki di GeoNode versi ini)" dan tidak diubah. Di GeoNode 5.1.1 keempatnya sudah diperbaiki.
- Bagian yang diubah bertanda `# geomdb-aman`, berkas asli dicadangkan sebagai `*.geomdb-aman-asli`. Bila
  pemeriksaan setelah menambal gagal, semua berkas dikembalikan.
- Tambalan ini **bukan pengganti upgrade**. GeoNode 4.x tidak lagi mendapat perbaikan keamanan, dan K1 tidak pernah
  diperbaiki untuk 4.x. Rencanakan [upgrade ke 5.x](#upgrade-geonode-4x-ke-5x).

### Konfigurasi Docker (menu 11 perketat, 12 kembalikan)

Menu 7 juga memeriksa konfigurasi yang tidak bisa diperbaiki dengan menambal kode. Menu 11 memperbaikinya, dengan
pertanyaan satu per satu. Sebelum tiap pertanyaan tampil penjelasan singkat bertanda kuncinya:

```
[header-nginx]
  Masalah  : halaman GeoNode bisa dibingkai (iframe) situs lain (temuan VA 'Clickjacking') ...
  Perubahan: Content-Security-Policy frame-ancestors 'self' (+ domain yang Anda izinkan), X-Frame-Options ...
  Dampak   : peta/GeoStory GeoNode yang DISEMATKAN (iframe) di situs LAIN berhenti tampil, kecuali ...
Tambahkan header keamanan di nginx GeoNode? [Y/n]
```

Yang diperiksa dan ditawarkan:

- **Image GeoServer** diganti versi bertambal bila versinya terdampak celah GeoServer yang sudah dieksploitasi
  aktif: RCE CVE-2024-36401 (< 2.23.6, 2.24.0 – 2.24.3, 2.25.0 – 2.25.1), XXE CVE-2025-58360 (≤ 2.25.5,
  2.26.0 – 2.26.1), dan SQL injection GHSA-mqjf-5f49-2fjh (< 2.27.6, 2.28.0 – 2.28.4, 3.0.0). Target: `2.27.6-latest`
  (GeoServer < 2.28) atau `2.28.6-latest`. **Folder data GeoServer dicadangkan dulu** ke
  `<folder compose>/cadangan-geomdb-aman/`. Celah ini hanya tertutup dengan mengganti image: K3 menambal XML
  unggahan di kode GeoNode, bukan GeoServer, dan port `127.0.0.1` tidak menolong karena `/geoserver/` tetap
  dilayani nginx. Kunci `PERKETAT_HANYA=image-geoserver` mengganti image GeoServer saja.
- **Port GeoServer hanya `127.0.0.1`.** Port yang dibuka Docker melewati ufw, jadi GeoServer bisa diakses langsung
  dari luar tanpa lewat nginx/GeoNode. **Port PostgreSQL** (service `db`) juga diikat ke `127.0.0.1` bila terbuka —
  basis data cukup diakses antar-kontainer.
- **CSRF admin GeoServer aktif** (whitelist = host `SITEURL`), **JSONP mati**, **CORS tanpa PUT/DELETE**.
- **Pendaftaran akun mandiri ditutup** (`ACCOUNT_OPEN_SIGNUP=False`): akun dibuat Walidata/admin. Celah yang butuh
  login (K1, K3) tidak bisa dipakai orang luar yang mendaftar sendiri.
- **Image PostgreSQL** (service `db`) diganti image resmi `postgis/postgis:<seri>-<minor PostGIS>-alpine` bila lebih
  baru — lihat di bawah.
- **Versi Tomcat disembunyikan** (`tomcat-info`): halaman galat GeoServer menampilkan versi Tomcat, juga lewat alamat
  publik `https://domain/geoserver/…`. `server.xml` dari image yang dipakai disalin, ditambah
  `ErrorReportValve showReport="false" showServerInfo="false"`, lalu dipasang hanya-baca. Berkas di image tidak diubah.
- **Header keamanan nginx** (`header-nginx`): template nginx GeoNode sengaja membuang `X-Frame-Options` dari Django,
  sehingga halaman GeoNode bisa dibingkai situs lain (*clickjacking*). Ditambahkan `Content-Security-Policy:
  frame-ancestors 'self'`, `X-Frame-Options: SAMEORIGIN`, `X-Content-Type-Options: nosniff`, `Referrer-Policy`, dan
  `server_tokens off` (versi nginx tidak ditampilkan). **Peta/GeoStory GeoNode yang disematkan lewat iframe di situs
  lain berhenti tampil** kecuali domain situs itu diizinkan. Menu 11 menanyakannya (contoh
  `https://peta.pemda.go.id`, pisahkan spasi). Pada mode `-y`, isi variabel `GEOMDB_FRAME_ANCESTORS`. Bila ada
  domain yang diizinkan, `X-Frame-Options` tidak dikirim karena header itu tidak bisa memuat daftar domain. Template
  nginx bertambahan dipasang hanya-baca; volume konfigurasi nginx tidak diubah.
- **Port nginx hanya `127.0.0.1`** (`port-nginx`): hanya ditawarkan bila server memakai tunnel (`cloudflared`) di host,
  dan bawaannya **tidak**. Tanpa ini login GeoNode bisa dilakukan lewat `http://IP-server` tanpa enkripsi dari jaringan
  lokal. Syaratnya, tunnel mengarah ke `http://localhost` atau `http://127.0.0.1` (lihat dasbor Cloudflare Zero Trust
  → Networks → Tunnels → Public Hostname). Sesudah diterapkan, alat ini membuka `SITEURL`. Bila tidak lagi
  terjangkau, perubahan dibatalkan otomatis. Pemindai VA di jaringan lokal juga tidak bisa lagi memindai lewat IP,
  jadi pasang setelah pemindaian ulang selesai. Pada mode `-y` kunci ini hanya diterapkan bila disebut di
  `PERKETAT_HANYA`.

Menu 11 dan 12 menulis ke folder proyek Docker GeoNode. Bila folder itu milik root (misalnya dibuat dengan
`sudo`), jalankan alat dengan `sudo bash tambal-geonode-preserve.sh perketat`. Tanpa izin tulis, alat berhenti
sebelum pertanyaan pertama dan tidak mengubah apa pun.

Perubahan ditulis ke berkas tambahan `docker-compose.geomdb-aman.yml` dan baris `COMPOSE_FILE` di `.env`
(`docker-compose.yml` tidak disunting; `.env` dicadangkan sebagai `.env.geomdb-aman-<tanggal>`). Berkas pendukung
(`server.xml` Tomcat, template nginx) ada di folder `geomdb-aman/` di samping `docker-compose.yml`. Kontainer lalu
dibuat ulang, dan tambalan kode yang tadinya terpasang dipasang lagi otomatis. Hasilnya **diverifikasi** (nginx
menjawab, header terkirim, versi tersembunyi, `SITEURL` terjangkau). Bila ada yang gagal, semuanya dikembalikan
seperti semula. Menu 12 menghapus berkas tambahan, folder `geomdb-aman/`, dan baris itu lalu membuat ulang kontainer.
Bila `docker-compose.geomdb-aman.yml` sudah ada, menu 11 tidak menimpanya (pengaturan lama bisa hilang tanpa terasa):
jalankan menu 12 lalu menu 11 lagi untuk menilai ulang semuanya.

Pertanyaan menu 11 bisa dibatasi untuk pemakaian terskrip, misalnya hanya mengganti image PostgreSQL:

```bash
PERKETAT_HANYA=image-db ./tambal-geonode-preserve.sh perketat -y
```

Kunci: `image-geoserver`, `port-geoserver`, `csrf-geoserver`, `tomcat-info`, `header-nginx`, `port-nginx`, `port-db`,
`image-db`, `ekstensi-db`, `signup`; yang tidak disebut dijawab "tidak". Contoh header web saja, dengan satu situs
yang boleh menyematkan GeoNode:

```bash
PERKETAT_HANYA=header-nginx,tomcat-info GEOMDB_FRAME_ANCESTORS="https://peta.pemda.go.id" \
  ./tambal-geonode-preserve.sh perketat -y
```

#### Temuan pemindai kerentanan (Nessus dan sejenisnya)

Temuan umum laporan VA atas server GeoNode Docker dan kunci menu 11 yang menutupnya:

| Temuan VA | Penyebab | Kunci menu 11 |
|---|---|---|
| Apache Tomcat Default Files (Medium) | halaman galat GeoServer menampilkan versi Tomcat, di port 8080 maupun `/geoserver/` publik | `tomcat-info` + `port-geoserver` |
| Web Application Potentially Vulnerable to Clickjacking (Medium) | nginx GeoNode membuang `X-Frame-Options` | `header-nginx` |
| Web Server Transmits Cleartext Credentials (Low) | port 80 nginx terbuka ke jaringan lokal | `port-nginx` (server bertunnel) atau HTTPS di nginx |
| HTTP Server Type and Version (Info) | header `Server: nginx/1.x` | `header-nginx` |
| Web Server Allows Password Auto-Completion (Low) | kolom sandi login memakai `autocomplete="current-password"` (bawaan django-allauth). Peramban modern mengabaikan `autocomplete="off"` pada kolom sandi, dan NIST SP 800-63B serta OWASP ASVS menganjurkan pengelola sandi tetap diizinkan | — terima risiko; tandai di Nessus *Resources → Plugin Rules* (plugin 42057) |
| Cookie tanpa `HttpOnly` (`csrftoken`), robots.txt, sitemap, dsb. (Info) | perilaku bawaan Django/GeoNode, bukan celah | — |

Jalankan menu 7 untuk melihat temuan mana yang masih terbuka di server Anda, dan menu 10 untuk membuktikan hasilnya.
Saat memindai GeoNode di balik Cloudflare, isi target Nessus dengan `domain[IP-server]` (misalnya
`geonode.pemda.go.id[10.0.0.5]`) supaya yang dipindai server Anda, bukan *edge* Cloudflare. Jangan menyertakan `#/`
pada URL target.

#### PostgreSQL (menu 7 & 11)

Menu 7 **memeriksa versi PostgreSQL** (service `db`): membandingkan minor yang berjalan dengan rilis keamanan terakhir
(per 2026-11-12: seri 15 → **15.20**, 16 → 16.16, 17 → 17.12, 18 → 18.7; **seri ≤ 14 END-OF-LIFE**). Rilis itu menutup
52 CVE termasuk **CVE-2026-6460** (RCE terautentikasi, CVSS 8.8) dan **PostGREShell CVE-2026-6471**. Menu 7 juga
memperingatkan bila **versi ekstensi PostGIS tidak cocok dengan image**: tertinggal (belum di-`UPDATE`) atau justru
lebih baru (image DB kembali ke versi lama, misalnya sesudah upgrade GeoNode mengganti berkas compose).

Image `geonode/postgis` tidak selalu cepat dirilis ulang (per 15-11-2026: `15-3.5-latest` masih PostgreSQL 15.17).
Bila image resmi `postgis/postgis` dengan seri PostgreSQL dan minor PostGIS yang sama lebih baru, menu 11 menawarkannya:

- **Hanya bila image sekarang juga Alpine** (`geonode/postgis` berbasis Alpine). Pindah musl ↔ glibc mengubah urutan
  collation sehingga indeks teks bisa rusak tanpa peringatan; karena itu varian Debian tidak ditawarkan.
- **Cadangan dulu**: `pg_dumpall` dan salinan volume data (PostgreSQL berhenti sebentar) ke
  `<folder compose>/cadangan-geomdb-aman/postgres-*`; ruang disk diperiksa lebih dulu.
- Hanya kontainer `db` yang dibuat ulang (`--no-deps`); django/celery/GeoServer tetap berjalan dan tambalan kode di
  dalamnya tidak tersentuh. Bila PostgreSQL tidak siap dengan image baru, image dikembalikan otomatis.
- Sesudahnya **`ALTER EXTENSION … UPDATE`** dijalankan untuk ekstensi `postgis*` yang tertinggal (semua database).
- Image pengganti disimpan di **`docker-compose.geomdb-pg.yml`** dan **tidak dilepas menu 12**: setelah katalog PostGIS
  diperbarui, kembali ke image lama tidak didukung. Pemulihan penuh lewat salinan volume di atas.
- **Hanya untuk instalasi yang sudah berjalan.** Image resmi tidak membawa skrip pembuat database GeoNode
  (`geonode.sh`) yang dijalankan saat instalasi baru.
- Sesudah upgrade GeoNode, jalankan menu 7: bila image DB kembali ke versi lama, menu 11 memasangnya lagi.

Diuji di GeoNode 5.1.1 (dua stack): 15.17 → 15.19, PostGIS 3.5.3/3.5.5 → 3.5.7; jumlah baris semua tabel dan geometri
identik, WMS GetMap dari layer PostGIS menghasilkan gambar yang sama persis, tambalan GeoMDB tetap terpasang. Pada
salinan basis data, `amcheck` memeriksa 787 indeks B-tree tanpa galat. Skenario "image kembali ke versi lama"
terdeteksi menu 7 dan dipulihkan menu 11.

Diuji pada GeoNode 4.4.4 dan 5.1.1 (Docker). Di 4.4.4, nama layer berisi perintah benar-benar dijalankan sebelum
ditambal. Setelah menu 8 dan 11, ke-14 uji lulus: perintah sisipan tidak dijalankan, unggahan biasa tetap terbit,
`/proxy` dan pendaftaran layanan ke alamat dalam ditolak, WMS tetap jalan, XML ber-DOCTYPE/XSLT ditolak, XML metadata
biasa diterima, skrip di abstrak dibuang, teks biasa tidak berubah. Di 5.1.1 menu 11 menutup JSONP, preflight CORS
PUT, dan pendaftaran mandiri, sementara WMS dan unggahan tetap jalan. Menu 9 dan 12 mengembalikan berkas dan
konfigurasi persis seperti semula.

Pengamanan web diuji di GeoNode 5.1.1 di balik Cloudflare Tunnel (nginx 1.31.7, GeoServer 2.28.6, Tomcat 9.0.123),
berdasarkan hasil pemindaian Nessus pada server itu. Setelah `header-nginx`, `tomcat-info`, `port-geoserver`, dan
`port-nginx`, alamat publik mengirim `frame-ancestors 'self'` + `X-Frame-Options: SAMEORIGIN`, versi nginx dan Tomcat
tidak tampil, WMS tetap jalan, dan port nginx & GeoServer tidak lagi terbuka ke jaringan lokal. Domain yang diizinkan masuk ke
`frame-ancestors`; isian berformat salah diabaikan. Menu 12 mengembalikan semuanya, dan template di volume nginx
tetap utuh.

### Uji keamanan (menu 10)

Menu 7 menebak status celah dari **kode** (mencari penanda perbaikan resmi); menu 10 **membuktikannya dengan
simulasi serangan** ke GeoNode lokal, lalu membersihkan jejaknya:

- **K1**: mengunggah GeoJSON dengan nama layer berisi perintah shell (membuat berkas penanda di kontainer celery),
  lalu memastikan perintah itu **tidak** dijalankan; sekaligus memastikan unggahan biasa tetap berhasil.
- **K2**: `/proxy` dan pendaftaran *Remote Service* ke alamat dalam (`db:5432`, `169.254.169.254`, GeoServer internal)
  harus ditolak.
- **K3**: XML ber-DOCTYPE/entitas dan ber-XSLT ditolak, XML metadata biasa diterima.
- **K4**: skrip di abstrak dinetralkan, lewat editor metadata (perbaikan resmi 5.x) **atau** saat disimpan (tambalan
  GeoMDB); teks biasa tidak diubah.
- **Konfigurasi web** (tanpa serangan): halaman GeoNode mengirim header anti-clickjacking, versi nginx tidak
  ditampilkan, halaman galat GeoServer tanpa versi Tomcat. Baris GAGAL menyebut kunci menu 11 yang menutupnya.

Dataset uji (unggahan biasa dan unggahan berisi perintah, termasuk sisa uji sebelumnya) dihapus dan abstrak
dikembalikan sesudahnya. Sandi admin dibaca dari `.env` (tidak ditampilkan). Permintaan uji memakai nama host yang
diizinkan `ALLOWED_HOSTS`, jadi tetap jalan walau `localhost` tidak terdaftar di sana. Bila unggahan uji tidak
diproses, K1 dilaporkan "(lewati)", bukan OK. Kode keluar `3` bila masih ada celah terbuka. Teruji: 5.1.1 lulus
16/0 (setelah `header-nginx` dan `tomcat-info`); 4.4.4 tanpa tambalan mendeteksi K1 & K4 rentan.

> **Hanya untuk server yang Anda kelola sendiri atau dengan izin tertulis pengelolanya.** Uji ini mengunggah data
> uji dan mengubah abstrak untuk sementara. Untuk menilai server pihak lain, cukup baca versinya dari halaman
> publik (`view-source` → cari `geonode-mapstore-client-vX`): klien v4 = GeoNode 4.x (rentan K1..K4), v5 = 5.x.
> Jangan menjalankan simulasi serangan ke server yang bukan milik Anda.

## Upgrade GeoNode 4.x ke 5.x

Instansi dengan GeoNode **4.4.x** bisa langsung upgrade ke **5.1.1** (versi 4.0 – 4.3: naik dulu ke 4.4.4, sesuai
wiki resmi *Upgrade from GeoNode 4 to 5*). Diuji: GeoNode 4.4.4 berisi dataset bergaya, kata kunci, metadata, dan
pengguna Produsen, di-upgrade di tempat dengan volume Docker yang sama. Hasilnya: 90 migrasi database berjalan tanpa
galat, semua dataset/gaya/kata kunci/pengguna terbawa, WMS/WFS/CSW berjalan, record lama terbuka di editor metadata
baru, dan unggahan baru berhasil.

1. **Cadangkan**: `pg_dumpall`, volume data GeoServer (`<proyek>-gsdatadir`), `statics`, `data`, serta `.env` dan
   berkas compose.
2. `docker compose down` (**tanpa** `-v`, volume tetap).
3. Ambil sumber GeoNode 5.1.1 di folder baru. Buat `.env` dari `.env.sample` 5.1.1 (`create-envfile.py`) dengan
   **rahasia yang sama** dengan 4.x: `ADMIN_PASSWORD`, `GEOSERVER_ADMIN_PASSWORD`, `POSTGRES_PASSWORD`,
   `GEONODE_DATABASE_PASSWORD`, `GEONODE_GEODATABASE_PASSWORD`, `SECRET_KEY`, `OAUTH2_CLIENT_ID/SECRET`. Samakan
   `COMPOSE_PROJECT_NAME` (agar volume lama dipakai) dan `SITEURL`. RabbitMQ diganti Redis:
   `BROKER_URL=redis://redis:6379/0`, `CELERY_RESULT_BACKEND=redis://redis:6379/1`.
4. `docker compose up -d`. Migrasi berjalan otomatis; pantau `docker logs -f django4<proyek>`.
5. **Tambahkan aturan REST `/rest/crs` di GeoServer.** Folder data lama tidak punya aturan yang dibutuhkan 5.x;
   tanpa itu pengguna non-admin mendapat 403 saat klien mencari CRS. Di
   `<data dir>/security/rest.properties`, sebelum baris terakhir `/**;GET,POST,DELETE,PUT=ROLE_ADMINISTRATOR`:

   ```
   /rest/crs;GET=IS_AUTHENTICATED_FULLY
   /rest/crs/**;GET=IS_AUTHENTICATED_FULLY
   ```

   lalu `docker restart geoserver4<proyek>`.
6. **Pasang lagi tambalan GeoMDB** (menu 2/3/5). Kontainer baru tidak membawa tambalan dari 4.x. Jalankan menu 7: di
   5.1.1 K1–K4 sudah aman tanpa tambalan, tinggal konfigurasi Docker (menu 11).

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
belum terpasang (hanya pada `cek`) · pada `cek-aman`/`uji-aman` nilai `3` berarti masih ada celah terbuka.

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
# tambalan keamanan (hanya bagian yang masih rentan di versi itu)
COPY geomdb_aman.py /tmp/
RUN cd /tmp && python tambal_preserve.py tambal-aman
```

Setelah GeoNode merilis perbaikan bug preserve, tambalan GeoMDB tidak diperlukan lagi: `cek` akan melaporkan
"kode tidak dikenali".

## Lisensi

GPL-3.0, sama dengan GeoNode. XSLT GeoNetwork di `xslt-mdb/ISO19139/` dan `xslt-mdb/present/` berlisensi
GPL-2.0-or-later (lihat `xslt-mdb/SUMBER.md`).
