# Asal berkas XSLT

Dipasang oleh `tambal_preserve.py tambal-mdb` ke `geonode/catalogue/geomdb_xslt/` dan dijalankan dengan Saxon-HE
(paket `saxonche`, XSLT 2.0).

| Berkas | Asal | Diubah? |
|---|---|---|
| `ISO19139/` (fromISO19139.xsl, mapping/, utility/) | GeoNetwork [`core-geonetwork`](https://github.com/geonetwork/core-geonetwork), `schemas/iso19115-3.2018/src/main/plugin/iso19115-3.2018/convert/ISO19139/`, commit `fae908fdde1188255c5fae60fbf60162cfcdb3c5` (2026-10-14) | tidak |
| `present/mdb-brief.xsl`, `present/mdb-summary.xsl` | GeoNetwork, `.../iso19115-3.2018/present/csw/`, commit `3fbac20a845b61763c007f2855641fd5e03ea7cf` (2025-10-02) | tidak |
| `geomdb-ke-mdb.xsl` | GeoMDB: membungkus XSLT GeoNetwork (merapikan gmd sebelum konversi, memperbaiki hasilnya). Rinciannya di komentar kepala berkas. | — |
| `urutan-gmd.xsl` | GeoMDB: dibangkitkan `buat_urutan_gmd.py` dari XSD resmi ISO 19139 (`schemas.isotc211.org/19139/-/gmd/1.0`) | dibangkitkan |

XSLT GeoNetwork berlisensi GPL-2.0-or-later (lisensi repositori GeoNetwork), sehingga dapat disertakan dalam repo
GPL-3.0 ini. Berkas GeoNetwork tidak disunting. Perbaikan dilakukan di `geomdb-ke-mdb.xsl` dengan menimpa template
dan variabel lewat presedensi impor XSLT, supaya pembaruan dari GeoNetwork tinggal disalin ulang.

Konversi lain di folder GeoNetwork tidak disertakan, misalnya `toISO19139.xsl` (ISO 19115-3 → 19139).
