# Tambal bug "preserve" GeoNode

*One-line patch for a GeoNode bug (4.2.5 → master) where `metadata_uploaded_preserve` stores `metadata_xml` as a
Python bytes repr (`b'<gmd:…'`), breaking the CSW record of that dataset. Instructions below are in Indonesian.*

Alat untuk **admin server GeoNode**. Perlu dijalankan agar mode *preserve* bisa dipakai, yaitu mode yang membuat
CSW GeoNode menyajikan metadata lengkap apa adanya, misalnya dari plugin QGIS **GeoMDB – Metadata Editor**.

## Masalah yang ditambal

Di GeoNode 4.2.5 sampai versi terbaru (`master`), fungsi pembuat record CSW (`geonode/catalogue/models.py`)
menyimpan XML ber-preserve sebagai *bytes* ke kolom teks. Isinya menjadi `b'<gmd:MD_Metadata …'`, sehingga:

- record CSW dataset itu tidak bisa dibaca (`GetRecordById` format ISO → HTTP 500);
- setiap penyimpanan dataset berikutnya gagal (`Start tag expected, '<' not found`) dan dataset bisa berstatus
  `INVALID`.

Data spasial (layer, WMS/WFS) **tidak** terpengaruh, hanya metadata.

Tambalannya **satu baris**:

```python
md_doc = etree.tostring(dlxml.fromstring(instance.metadata_xml))                       # sebelum
md_doc = etree.tostring(dlxml.fromstring(instance.metadata_xml), encoding="unicode")   # sesudah
```

## Unduh

```bash
git clone https://github.com/hariHK1/geonode-tambal-preserve.git
cd geonode-tambal-preserve
```

atau cukup dua berkasnya:

```bash
curl -fsSLO https://raw.githubusercontent.com/hariHK1/geonode-tambal-preserve/main/tambal_preserve.py
curl -fsSLO https://raw.githubusercontent.com/hariHK1/geonode-tambal-preserve/main/tambal-geonode-preserve.sh
chmod +x tambal-geonode-preserve.sh
```

| Berkas | Fungsi |
|---|---|
| `tambal-geonode-preserve.sh` | Dijalankan di **server Docker**. Mencari semua kontainer GeoNode (django, celery, …) lalu menjalankan penambal di masing-masing. |
| `tambal_preserve.py` | Penambal. Dijalankan di dalam lingkungan Python GeoNode, otomatis lewat skrip di atas, atau langsung untuk GeoNode tanpa Docker. |

## Pemakaian (GeoNode dengan Docker)

```bash
./tambal-geonode-preserve.sh cek        # lihat status semua kontainer GeoNode, tidak mengubah apa pun
./tambal-geonode-preserve.sh tambal     # tambal; ditanya dulu sebelum kontainer dimulai ulang
./tambal-geonode-preserve.sh pulihkan   # kembalikan kode asli GeoNode
```

- Tambahkan `-y` untuk langsung memulai ulang kontainer tanpa ditanya (django & celery berhenti beberapa detik).
- Pilih kontainer sendiri bila perlu: `KONTAINER="django4geonode celery4geonode" ./tambal-geonode-preserve.sh tambal`.
- **django dan celery wajib ditambal semua.** Pemrosesan unggah metadata berjalan di celery.

## Pemakaian (GeoNode tanpa Docker)

```bash
source /path/ke/virtualenv-geonode/bin/activate
python tambal_preserve.py cek | tambal | pulihkan
```

Lalu mulai ulang layanan GeoNode dan celery (mis. `systemctl restart uwsgi celery`, sesuaikan dengan server).

## Pengaman

- **Hanya mengubah bila kodenya persis dikenali.** Baris yang dimaksud harus muncul tepat sekali, utuh, di fungsi
  pembuat record CSW. Kalau GeoNode sudah memperbaikinya sendiri atau kodenya berbeda, tidak ada yang diubah
  (kode keluar 2).
- **Berkas asli dicadangkan** sebagai `models.py.geomdb-asli` di sebelah berkas aslinya.
- **Hasil tambalan diperiksa** dengan `py_compile` sebelum menggantikan berkas asli.
- **Aman dijalankan berulang.** Yang sudah ditambal tidak diubah lagi.
- Diuji pada kode asli GeoNode 4.2.5, 4.4.5, 5.0.0, 5.0.3, 5.1.0 dan `master`: tepat satu baris berubah, dan
  `pulihkan` mengembalikan berkas identik dengan aslinya.

Kode keluar: `0` berhasil/sudah sesuai · `1` galat · `2` kode tidak dikenali (tidak diubah) · `3` belum ditambal
(hanya pada `cek`).

## Setelah ditambal

Uji preserve pada **satu dataset** dulu. Di plugin GeoMDB: buka *Kirim ke GeoNode*, centang **"Server GeoNode ini
sudah ditambal"**, lalu Perbarui. Bila ternyata belum berhasil, plugin otomatis kembali ke mode biasa dan
memulihkan record CSW-nya.

## Penting setelah upgrade

Tambalan tersimpan di berkas kode yang dipakai kontainer:

- **Kode ada di dalam image** (umum): tambalan **hilang bila kontainer dibuat ulang** (upgrade image,
  `docker compose up` dengan image baru).
- **Kode dipasang dari folder server** (mis. `~/geonode` → `/usr/src/geonode`, sering dipakai bersama oleh django
  & celery): tambalan bertahan walau kontainer dibuat ulang, tetapi terlihat sebagai perubahan oleh git di folder
  itu dan bisa tertimpa saat folder itu diperbarui (`git pull`). Cek dengan
  `docker inspect django4geonode --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}'`.

Karena itu, setelah setiap upgrade atau pembaruan kode GeoNode, jalankan `cek`, lalu `tambal` bila perlu. Skrip
selalu memulai ulang **semua** kontainer GeoNode setelah ada perubahan, karena kontainer yang berbagi berkas ikut
berubah walau tidak dilaporkan "Ditambal".

Supaya permanen, masukkan ke Dockerfile image GeoNode (mis. proyek *geonode-project*), setelah GeoNode terpasang:

```dockerfile
COPY tambal_preserve.py /tmp/tambal_preserve.py
RUN python /tmp/tambal_preserve.py tambal || [ $? -eq 2 ]   # 2 = GeoNode sudah memperbaikinya sendiri
```

Setelah GeoNode merilis perbaikannya, alat ini tidak diperlukan lagi: `cek` akan melaporkan "kode tidak dikenali".

## Lisensi

GPL-3.0, sama dengan GeoNode.
