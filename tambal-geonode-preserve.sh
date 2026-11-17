#!/usr/bin/env bash
# Tambal GeoNode untuk GeoMDB di SEMUA kontainer GeoNode pada server Docker (django, celery, ...).
#
#   ./tambal-geonode-preserve.sh                  # menu (pilih versi GeoNode dulu, lalu alat yang kompatibel)
#   ./tambal-geonode-preserve.sh cek              # status tiap kontainer, tidak mengubah apa pun
#   ./tambal-geonode-preserve.sh tambal           # tambalan GeoMDB (preserve)
#   ./tambal-geonode-preserve.sh tambal-unggah    # tambalan unggah metadata UI (termasuk tambalan GeoMDB; GeoNode 5.x)
#   ./tambal-geonode-preserve.sh pulihkan-unggah  # lepas tambalan unggah metadata; tambalan GeoMDB tetap
#   ./tambal-geonode-preserve.sh tambal-mdb       # tambalan CSW ISO 19115-3 / MDB (GeoNode 5.x; pip saxonche, perlu internet)
#   ./tambal-geonode-preserve.sh pulihkan-mdb     # lepas tambalan CSW ISO 19115-3
#   ./tambal-geonode-preserve.sh cek-aman         # celah keamanan: kode GeoNode (K1..K4) + versi/konfigurasi GeoServer & PostgreSQL
#   ./tambal-geonode-preserve.sh tambal-aman      # tambalan keamanan kode GeoNode 4.x – 5.1.x (hanya kode yang rentan)
#   ./tambal-geonode-preserve.sh pulihkan-aman    # lepas tambalan keamanan
#   ./tambal-geonode-preserve.sh perketat         # perketat konfigurasi Docker (image GeoServer/PostgreSQL, port, CSRF, pendaftaran)
#   ./tambal-geonode-preserve.sh kembalikan       # batalkan "perketat" (image PostgreSQL pengganti tetap dipakai)
#   PERKETAT_HANYA=image-db ./tambal-geonode-preserve.sh perketat -y   # hanya pilihan tertentu (lihat fungsi pilih)
#   ./tambal-geonode-preserve.sh uji-aman         # uji keamanan: simulasi serangan K1..K4 ke server ini (lalu dibersihkan)
#   ./tambal-geonode-preserve.sh pulihkan         # kembalikan kode asli GeoNode (lepas semua tambalan)
#   tambahkan -y untuk melewati konfirmasi mulai ulang
#   KONTAINER="django4geonode celery4geonode" ./tambal-geonode-preserve.sh cek   # pilih kontainer sendiri
#
# Tambalan tersimpan di dalam kontainer: hilang bila kontainer DIBUAT ULANG (upgrade image, "docker compose
# up" dengan image baru). Jalankan "cek" setelah setiap upgrade dan pasang lagi bila perlu.
set -uo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
PENAMBAL="$DIR/tambal_preserve.py"
MODUL="$DIR/geomdb_unggah.py"
MODUL_KONTAINER=/tmp/geomdb_unggah.py
MODUL_MDB="$DIR/geomdb_mdb.py"
XSLT_MDB="$DIR/xslt-mdb"
MODUL_MDB_KONTAINER=/tmp/geomdb_mdb.py
XSLT_KONTAINER=/tmp/geomdb_xslt
MODUL_AMAN="$DIR/geomdb_aman.py"
MODUL_AMAN_KONTAINER=/tmp/geomdb_aman.py
AKSI=${1:-}
YA=${2:-}

deteksi_versi_major() {  # cetak angka mayor GeoNode (4/5) dari kontainer django yang berjalan, atau kosong
  command -v docker >/dev/null 2>&1 || return 0
  local n v
  for n in $(docker ps --format '{{.Names}}' 2>/dev/null); do
    case "$n" in *django*) ;; *) continue ;; esac
    v=$(docker exec "$n" sh -c 'python3 -c "import geonode;print(geonode.__version__[0])" 2>/dev/null || python -c "import geonode;print(geonode.__version__[0])" 2>/dev/null' 2>/dev/null | tr -dc '0-9' | head -c1)
    [ -n "$v" ] && { echo "$v"; return 0; }
  done
}

menu_5x() {  # tambalan & alat yang kompatibel dengan GeoNode 5.x
  local pilih
  cat <<'TEKS'

GeoNode 5.x — tambalan & alat yang kompatibel:
  1) Cek status (tidak mengubah apa pun)
  — Metadata —
  2) Tambalan GeoMDB (preserve)  — wajib untuk "Kirim ke GeoNode" plugin QGIS GeoMDB
  3) Tambalan unggah metadata UI  — Edit > Upload Metadata tersaji LENGKAP di CSW (termasuk preserve)
  4) Lepas tambalan unggah metadata (tambalan GeoMDB tetap)
  5) Tambalan CSW ISO 19115-3 / MDB  — perlu internet untuk saxonche (lolos XSD+Schematron)
  6) Lepas tambalan CSW ISO 19115-3
  — Keamanan —
  7) Cek celah  — K1..K4 + versi/konfigurasi GeoServer & PostgreSQL
  8) Pasang tambalan keamanan  — hanya kode yang masih rentan
  9) Lepas tambalan keamanan
 10) Uji keamanan  — simulasi serangan K1..K4, lalu dibersihkan
 11) Perketat konfigurasi Docker  — image/port GeoServer, image/port PostgreSQL, CSRF/JSONP/CORS, pendaftaran
 12) Kembalikan konfigurasi Docker (batalkan no. 11; image PostgreSQL pengganti tetap)
  — Lainnya —
 13) Pulihkan kode asli GeoNode (lepas semua tambalan kode)
  0) Keluar
TEKS
  read -r -p "Pilih [1]: " pilih
  case "${pilih:-1}" in
    1) AKSI=cek ;;
    2) AKSI=tambal ;;
    3) AKSI=tambal-unggah ;;
    4) AKSI=pulihkan-unggah ;;
    5) AKSI=tambal-mdb ;;
    6) AKSI=pulihkan-mdb ;;
    7) AKSI=cek-aman ;;
    8) AKSI=tambal-aman ;;
    9) AKSI=pulihkan-aman ;;
    10) AKSI=uji-aman ;;
    11) AKSI=perketat ;;
    12) AKSI=kembalikan ;;
    13) AKSI=pulihkan ;;
    0) exit 0 ;;
    *) echo "Pilihan tidak dikenal: $pilih"; exit 1 ;;
  esac
}

menu_4x() {  # tambalan & alat yang kompatibel dengan GeoNode 4.x
  local pilih
  cat <<'TEKS'

GeoNode 4.x — tambalan & alat yang kompatibel:
  (tambalan unggah metadata UI & CSW ISO 19115-3/MDB hanya untuk GeoNode 5.x — tidak ditampilkan di sini)
  1) Cek status (tidak mengubah apa pun)
  — Metadata —
  2) Tambalan GeoMDB (preserve)  — wajib untuk "Kirim ke GeoNode" plugin QGIS GeoMDB
  — Keamanan —
  3) Cek celah  — K1..K4 + versi/konfigurasi GeoServer & PostgreSQL
  4) Pasang tambalan keamanan  — hanya kode yang masih rentan
  5) Lepas tambalan keamanan
  6) Uji keamanan  — simulasi serangan K1..K4, lalu dibersihkan
  7) Perketat konfigurasi Docker  — image/port GeoServer, image/port PostgreSQL, CSRF/JSONP/CORS, pendaftaran
  8) Kembalikan konfigurasi Docker (batalkan no. 7; image PostgreSQL pengganti tetap)
  — Lainnya —
  9) Panduan upgrade GeoNode 4.x -> 5.x
 10) Pulihkan kode asli GeoNode (lepas semua tambalan kode)
  0) Keluar
TEKS
  read -r -p "Pilih [1]: " pilih
  case "${pilih:-1}" in
    1) AKSI=cek ;;
    2) AKSI=tambal ;;
    3) AKSI=cek-aman ;;
    4) AKSI=tambal-aman ;;
    5) AKSI=pulihkan-aman ;;
    6) AKSI=uji-aman ;;
    7) AKSI=perketat ;;
    8) AKSI=kembalikan ;;
    9) AKSI=panduan-upgrade ;;
    10) AKSI=pulihkan ;;
    0) exit 0 ;;
    *) echo "Pilihan tidak dikenal: $pilih"; exit 1 ;;
  esac
}

panduan_upgrade() {
  cat <<'TEKS'
Upgrade GeoNode 4.4.x -> 5.1.x (ringkas; langkah lengkap di README bagian "Upgrade GeoNode 4.x ke 5.x")

  1. Cadangkan: pg_dumpall + volume data GeoServer (<proyek>-gsdatadir), statics, data, serta .env & berkas compose.
  2. docker compose down   (TANPA -v; volume tetap dipakai ulang)
  3. Ambil sumber GeoNode 5.1.1 di folder baru. Buat .env baru (create-envfile.py) dengan RAHASIA YANG SAMA:
     ADMIN_PASSWORD, GEOSERVER_ADMIN_PASSWORD, POSTGRES_PASSWORD, GEONODE_DATABASE_PASSWORD,
     GEONODE_GEODATABASE_PASSWORD, SECRET_KEY, OAUTH2_CLIENT_ID/SECRET. Samakan COMPOSE_PROJECT_NAME & SITEURL.
     RabbitMQ -> Redis:  BROKER_URL=redis://redis:6379/0   CELERY_RESULT_BACKEND=redis://redis:6379/1
  4. docker compose up -d   (migrasi basis data berjalan otomatis; pantau: docker logs -f django<...>)
  5. Tambah aturan /rest/crs di <data dir GeoServer>/security/rest.properties (sebelum baris ROLE_ADMINISTRATOR):
       /rest/crs;GET=IS_AUTHENTICATED_FULLY
       /rest/crs/**;GET=IS_AUTHENTICATED_FULLY
     lalu restart kontainer geoserver. Tanpa ini pengguna non-admin bisa 403 saat memilih CRS.
  6. Pasang lagi tambalan GeoMDB (menu Metadata & Keamanan) — kontainer baru tidak membawa tambalan lama.
     GeoNode 4.0-4.3: naik dulu ke 4.4.4 sebelum ke 5.x.

Teruji: 4.4.4 -> 5.1.1 di tempat, 90 migrasi OK, seluruh dataset/gaya/kata kunci/pengguna terbawa, WMS/WFS/CSW jalan.
Selalu cadangkan basis data & folder data GeoServer sebelum upgrade.
TEKS
}

menu() {  # dua tingkat: pilih versi GeoNode dulu, lalu alat yang kompatibel dengan versi itu
  local vmaj vdef vpil
  vmaj=$(deteksi_versi_major)
  case "$vmaj" in 4) vdef=1 ;; *) vdef=2 ;; esac
  echo "Tambal GeoNode untuk GeoMDB"
  [ -n "$vmaj" ] && echo "(terdeteksi kontainer GeoNode ${vmaj}.x sedang berjalan)"
  echo
  echo "Pilih versi GeoNode server:"
  echo "  1) GeoNode 4.x"
  echo "  2) GeoNode 5.x"
  echo "  0) Keluar"
  read -r -p "Versi [$vdef]: " vpil
  case "${vpil:-$vdef}" in
    1) menu_4x ;;
    2) menu_5x ;;
    0) exit 0 ;;
    *) echo "Pilihan tidak dikenal: $vpil"; exit 1 ;;
  esac
  echo
}

if [ -z "$AKSI" ]; then
  if [ -t 0 ]; then menu; else AKSI=cek; fi
fi
case "$AKSI" in
  cek|tambal|tambal-unggah|pulihkan-unggah|tambal-mdb|pulihkan-mdb|cek-aman|tambal-aman|pulihkan-aman|uji-aman|perketat|kembalikan|pulihkan|panduan-upgrade) ;;
  *) echo "pemakaian: $0 [cek|tambal|tambal-unggah|tambal-mdb|pulihkan-unggah|pulihkan-mdb|cek-aman|tambal-aman|pulihkan-aman|uji-aman|perketat|kembalikan|pulihkan] [-y]"; exit 1 ;;
esac
if [ "$AKSI" = panduan-upgrade ]; then panduan_upgrade; exit 0; fi
command -v docker >/dev/null 2>&1 || { echo "GALAT: perintah docker tidak ditemukan. Untuk GeoNode tanpa Docker:"
                                       echo "       python $PENAMBAL $AKSI   (di virtualenv GeoNode)"; exit 1; }
[ -f "$PENAMBAL" ] || { echo "GALAT: $PENAMBAL tidak ditemukan (letakkan di folder yang sama)."; exit 1; }
if [ ! -f "$MODUL" ]; then
  if [ "$AKSI" = tambal-unggah ]; then
    echo "GALAT: $MODUL tidak ditemukan (letakkan di folder yang sama)."; exit 1
  fi
  MODUL=""
fi
if [ ! -f "$MODUL_MDB" ] || [ ! -d "$XSLT_MDB" ]; then
  if [ "$AKSI" = tambal-mdb ]; then
    echo "GALAT: $MODUL_MDB atau folder $XSLT_MDB tidak ditemukan (letakkan di folder yang sama)."; exit 1
  fi
  MODUL_MDB=""
fi
if [ ! -f "$MODUL_AMAN" ]; then
  if [ "$AKSI" = tambal-aman ]; then
    echo "GALAT: $MODUL_AMAN tidak ditemukan (letakkan di folder yang sama)."; exit 1
  fi
  MODUL_AMAN=""
fi

python_kontainer() {  # jalur python di kontainer, kosong bila tidak ada
  docker exec "$1" sh -c 'command -v python3 || command -v python' 2>/dev/null | head -n1
}

memuat_geonode() {  # kontainer punya paket geonode?
  local py
  py=$(python_kontainer "$1")
  [ -n "$py" ] && docker exec "$1" "$py" -c \
    'import importlib.util, sys; sys.exit(0 if importlib.util.find_spec("geonode") else 1)' >/dev/null 2>&1
}

if [ -n "${KONTAINER:-}" ]; then
  read -r -a DAFTAR <<< "$KONTAINER"
else
  DAFTAR=()
  while read -r nama; do
    [ -n "$nama" ] && memuat_geonode "$nama" && DAFTAR+=("$nama")
  done < <(docker ps --format '{{.Names}}')
fi
if [ ${#DAFTAR[@]} -eq 0 ]; then
  echo "Tidak ada kontainer GeoNode yang sedang berjalan. Pilih manual dengan KONTAINER=\"nama1 nama2\"."
  exit 1
fi

kode_lebih_baru() {  # berkas kode di kontainer diubah SETELAH kontainer dimulai → proses masih memakai kode lama
  local mulai ubah
  mulai=$(date -d "$(docker inspect -f '{{.State.StartedAt}}' "$1" 2>/dev/null)" +%s 2>/dev/null) || return 1
  ubah=$(docker exec "$1" stat -c %Y "$2" 2>/dev/null) || return 1
  [ -n "$mulai" ] && [ -n "$ubah" ] && [ "$ubah" -gt "$mulai" ]
}

versi_lt() {  # $1 < $2 (urutan versi)
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ]
}

# Celah GeoServer yang sudah dieksploitasi di internet (advisory GeoServer / katalog KEV CISA).
celah_geoserver() {  # $1 = versi x.y.z → daftar celah, satu per baris
  local v=$1
  if versi_lt "$v" 2.23.6 || { ! versi_lt "$v" 2.24.0 && versi_lt "$v" 2.24.4; } \
     || { ! versi_lt "$v" 2.25.0 && versi_lt "$v" 2.25.2; }; then
    echo "CVE-2024-36401 - eksekusi kode jarak jauh tanpa login (KEV)"
  fi
  if versi_lt "$v" 2.25.6 || { ! versi_lt "$v" 2.26.0 && versi_lt "$v" 2.26.2; }; then
    echo "CVE-2025-58360 - XXE tanpa login lewat WMS GetMap (KEV)"
  fi
  if versi_lt "$v" 2.27.6 || { ! versi_lt "$v" 2.28.0 && versi_lt "$v" 2.28.5; } \
     || { ! versi_lt "$v" 3.0.0 && versi_lt "$v" 3.0.1; }; then
    echo "GHSA-mqjf-5f49-2fjh - injeksi SQL jsonArrayContains, bisa berujung RCE (Agustus 2026, dieksploitasi)"
  fi
}

java_geoserver() {  # argumen proses Java GeoServer yang sedang berjalan (lebih pasti daripada variabel lingkungan)
  docker exec "$1" sh -c 'for p in /proc/[0-9]*/cmdline; do tr "\0" " " < "$p" 2>/dev/null; echo; done | grep -m1 -E "(^| )[^ ]*java "' 2>/dev/null
}

# Minor PostgreSQL terbaru per seri utama (rilis keamanan 2026-11-12: 52 CVE, a.l. CVE-2026-6460 RCE terautentikasi
# CVSS 8.8, PostGREShell CVE-2026-6471). Seri <= 14 sudah END-OF-LIFE. PERBARUI daftar ini saat ada rilis baru.
pg_terbaru() { case "$1" in 15) echo 15.20 ;; 16) echo 16.16 ;; 17) echo 17.12 ;; 18) echo 18.7 ;; *) echo "" ;; esac; }

pg_q() {  # $1 = kontainer db, $2 = database, $3 = SQL -> hasil (-tA), sebagai POSTGRES_USER kontainer
  docker exec "$1" sh -c 'psql -U "${POSTGRES_USER:-postgres}" -d "$0" -tAc "$1"' "$2" "$3" </dev/null 2>/dev/null
}

pg_versi() { docker exec "$1" postgres --version </dev/null 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -n1; }

pg_siap() { local i; for i in $(seq 90); do docker exec "$1" pg_isready -q </dev/null >/dev/null 2>&1 && return 0; sleep 2; done; return 1; }

# Image resmi pengganti kontainer db: postgis/postgis dengan seri PostgreSQL dan minor PostGIS yang sama, varian Alpine.
# Hanya bila image sekarang juga Alpine (musl): pindah musl <-> glibc mengubah urutan collation sehingga indeks teks bisa
# rusak tanpa peringatan. Mencetak "image versi" bila kandidat lebih baru, kosong bila tidak ada.
pg_image_pengganti() {  # $1 = kontainer db
  local db=$1 img v pgis cand cv
  img=$(docker inspect -f '{{.Config.Image}}' "$db")
  [ "$(docker exec "$db" sh -c '. /etc/os-release 2>/dev/null; echo "$ID"' </dev/null 2>/dev/null)" = alpine ] || return 0
  v=$(pg_versi "$db")
  pgis=$(pg_q "$db" postgres "SELECT default_version FROM pg_available_extensions WHERE name = 'postgis'" | grep -oE '^[0-9]+\.[0-9]+')
  [ -n "$v" ] && [ -n "$pgis" ] || return 0
  cand="postgis/postgis:${v%%.*}-$pgis-alpine"
  [ "$img" = "$cand" ] && return 0
  docker pull -q "$cand" >/dev/null 2>&1 || return 0
  cv=$(docker run --rm --entrypoint postgres "$cand" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -n1)
  [ -n "$cv" ] && versi_lt "$v" "$cv" && echo "$cand $cv"
  return 0
}

# Versi ekstensi PostGIS di katalog vs versi bawaan image: "lebih-baru" (katalog lebih baru = image DB kembali ke versi
# lama, mis. sesudah upgrade GeoNode mengganti compose), "tertinggal" (belum di-UPDATE), atau kosong (cocok).
pg_status_ekstensi() {  # $1 = kontainer db
  local c=$1 dbn r st=""
  for dbn in $(pg_q "$c" postgres "SELECT datname FROM pg_database WHERE datallowconn AND datname <> 'template0'"); do
    for r in $(pg_q "$c" "$dbn" "SELECT e.extversion || '|' || a.default_version FROM pg_extension e JOIN pg_available_extensions a ON a.name = e.extname WHERE e.extname LIKE 'postgis%' AND e.extversion <> a.default_version"); do
      if versi_lt "${r#*|}" "${r%%|*}"; then st=lebih-baru; elif [ "$st" != lebih-baru ]; then st=tertinggal; fi
    done
  done
  echo "$st"
}

pg_perbarui_ekstensi() {  # $1 = kontainer db: ALTER EXTENSION ... UPDATE untuk ekstensi postgis* yang tertinggal dari image
  local c=$1 dbn e n=0 g=0
  for dbn in $(pg_q "$c" postgres "SELECT datname FROM pg_database WHERE datallowconn AND datname <> 'template0'"); do
    for e in $(pg_q "$c" "$dbn" "SELECT e.extname FROM pg_extension e JOIN pg_available_extensions a ON a.name = e.extname WHERE e.extname LIKE 'postgis%' AND e.extversion <> a.default_version ORDER BY (e.extname <> 'postgis'), e.extname"); do
      if docker exec "$c" sh -c 'psql -U "${POSTGRES_USER:-postgres}" -d "$0" -v ON_ERROR_STOP=1 -qtAc "ALTER EXTENSION $1 UPDATE"' "$dbn" "$e" </dev/null >/dev/null 2>&1; then
        n=$((n + 1))
      else
        g=$((g + 1)); echo "  GAGAL: ekstensi $e di database $dbn - jalankan manual: ALTER EXTENSION $e UPDATE;"
      fi
    done
  done
  echo "  Ekstensi PostGIS diperbarui: $n$([ $g -gt 0 ] && echo ", gagal $g")."
  [ $g -eq 0 ]
}

pg_cadangkan() {  # $1 = kontainer db, $2 = folder, $3 = cap waktu: pg_dumpall + salinan volume data (db berhenti sebentar)
  local c=$1 dir=$2 tgl=$3 sumber perlu sisa
  sumber=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{if .Name}}{{.Name}}{{else}}{{.Source}}{{end}}{{end}}{{end}}' "$c")
  [ -n "$sumber" ] || { echo "GALAT: volume data PostgreSQL tidak ditemukan."; return 1; }
  mkdir -p "$dir"
  perlu=$(docker run --rm -v "$sumber":/d:ro alpine du -sk /d 2>/dev/null | cut -f1)
  sisa=$(df -Pk "$dir" | awk 'NR==2 {print $4}')
  if [ -z "$perlu" ] || [ "${sisa:-0}" -le $((perlu * 2)) ]; then
    echo "GALAT: ruang disk di $dir kurang (perlu sekitar $((${perlu:-0} * 2 / 1024)) MB)."; return 1
  fi
  echo "Mencadangkan PostgreSQL ($c): pg_dumpall ..."
  docker exec "$c" sh -c 'pg_dumpall -U "${POSTGRES_USER:-postgres}"' </dev/null 2>/dev/null | gzip > "$dir/postgres-dumpall-$tgl.sql.gz"
  [ "$(gzip -dc "$dir/postgres-dumpall-$tgl.sql.gz" 2>/dev/null | head -c 200 | wc -c)" -ge 50 ] || { echo "GALAT: pg_dumpall gagal."; return 1; }
  echo "  -> $dir/postgres-dumpall-$tgl.sql.gz"
  echo "Menghentikan PostgreSQL sebentar untuk menyalin volume datanya ..."
  docker stop "$c" >/dev/null
  if ! docker run --rm -v "$sumber":/d:ro -v "$dir":/c alpine tar czf "/c/postgres-volume-$tgl.tgz" -C /d .; then
    docker start "$c" >/dev/null; echo "GALAT: salinan volume gagal - PostgreSQL dinyalakan lagi."; return 1
  fi
  echo "  -> $dir/postgres-volume-$tgl.tgz (titik pemulihan persis)"
}

cek_konfigurasi_geoserver() {
  local proyek p gs dj v celah port opsi
  proyek=$(for n in "${DAFTAR[@]}"; do docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$n" 2>/dev/null; done | sort -u)
  for p in $proyek; do
    echo
    echo "== Konfigurasi proyek Docker \"$p\""
    gs=$(docker ps --filter "label=com.docker.compose.project=$p" --filter "label=com.docker.compose.service=geoserver" --format '{{.Names}}' | head -n1)
    dj=$(docker ps --filter "label=com.docker.compose.project=$p" --filter "label=com.docker.compose.service=django" --format '{{.Names}}' | head -n1)
    if [ -n "$gs" ]; then
      v=$(docker exec "$gs" sh -c 'ls /usr/local/tomcat/webapps/geoserver/WEB-INF/lib 2>/dev/null' | sed -n 's/^gs-main-\([0-9][0-9.]*[0-9]\)\.jar$/\1/p' | head -n1)
      if [ -z "$v" ]; then
        echo "   GeoServer ($gs): versi tidak terbaca"
      else
        celah=$(celah_geoserver "$v")
        if [ -n "$celah" ]; then
          echo "   RENTAN  GeoServer $v ($gs):"
          sed 's/^/             - /' <<< "$celah"
          if versi_lt "$v" 2.28.0; then
            echo "           Ganti image GeoServer ke geonode/geoserver:2.27.6-latest (jalur GeoNode 4.4.x / 5.0.x)"
            echo "           atau 2.28.6-latest (GeoNode 5.x), lalu: docker compose up -d geoserver"
          else
            echo "           Ganti image GeoServer ke geonode/geoserver:2.28.6-latest, lalu: docker compose up -d geoserver"
          fi
        else
          echo "   OK      GeoServer $v ($gs): tidak terdampak celah GeoServer yang dieksploitasi aktif"
        fi
      fi
      port=$(docker port "$gs" 2>/dev/null | grep -vE '127\.0\.0\.1|\[::1\]' | sed 's/^/ /' | tr '\n' ' ')
      [ -n "$port" ] && echo "   PERINGATAN port GeoServer terbuka ke semua antarmuka:$port- ikat ke 127.0.0.1 (nginx sudah meneruskan /geoserver/)"
      grep -q 'GEOSERVER_CSRF_DISABLED=true' <<< "$(java_geoserver "$gs")" \
        && echo "   PERINGATAN proteksi CSRF admin GeoServer dimatikan (-DGEOSERVER_CSRF_DISABLED=true)"
      opsi=$(docker exec "$gs" env 2>/dev/null)
      if grep -q '^GEOSERVER_CORS_ALLOWED_ORIGINS=\*$' <<< "$opsi" && grep -qE '^GEOSERVER_CORS_ALLOWED_METHODS=.*(PUT|DELETE)' <<< "$opsi"; then
        echo "   PERINGATAN CORS GeoServer: semua origin (*) termasuk metode PUT/DELETE"
      fi
      grep -qi '^ENABLE_JSONP=true$' <<< "$opsi" && echo "   PERINGATAN JSONP GeoServer aktif (data terbatas bisa dibaca situs lain lewat sesi pengguna)"
    else
      echo "   (kontainer GeoServer proyek ini tidak ditemukan)"
    fi
    if [ -n "$dj" ]; then
      opsi=$(docker exec "$dj" env 2>/dev/null)
      grep -qiE '^ACCOUNT_OPEN_SIGNUP=(true|1)$' <<< "$opsi" && echo "   PERINGATAN pendaftaran akun mandiri TERBUKA (ACCOUNT_OPEN_SIGNUP=True) - celah yang butuh login bisa dipakai siapa saja"
      grep -qiE '^DEBUG=(true|1)$' <<< "$opsi" && echo "   PERINGATAN DEBUG=True"
      grep -qE '^SECRET_KEY=.+' <<< "$opsi" || echo "   PERINGATAN SECRET_KEY tidak diset - GeoNode memakai kunci bawaan yang publik"
    fi
    db=$(docker ps --filter "label=com.docker.compose.project=$p" --filter "label=com.docker.compose.service=db" --format '{{.Names}}' | head -n1)
    if [ -n "$db" ]; then
      v=$(docker exec "$db" postgres --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -n1)
      if [ -z "$v" ]; then
        echo "   PostgreSQL ($db): versi tidak terbaca"
      else
        maj=${v%%.*}; latest=$(pg_terbaru "$maj")
        if [ "${maj:-99}" -le 14 ] 2>/dev/null; then
          echo "   PERINGATAN PostgreSQL $v ($db): seri $maj sudah END-OF-LIFE - tidak ada lagi patch keamanan; rencanakan upgrade ke 15+"
        elif [ -n "$latest" ] && versi_lt "$v" "$latest"; then
          echo "   RENTAN  PostgreSQL $v ($db): usang - minor terbaru $latest (rilis 2026-11-12: CVE-2026-6460 RCE terautentikasi 8.8, PostGREShell CVE-2026-6471)"
          echo "           Perbarui (cadangkan dulu): docker compose pull db && docker compose up -d db. Bila image belum"
          echo "           dirilis ulang, menu 11 menawarkan image resmi postgis/postgis (seri & minor PostGIS sama, Alpine)."
        else
          echo "   OK      PostgreSQL $v ($db): minor terbaru untuk seri $maj"
        fi
      fi
      case "$(pg_status_ekstensi "$db")" in
        lebih-baru) echo "   PERINGATAN katalog PostGIS $db lebih baru dari image ($(docker inspect -f '{{.Config.Image}}' "$db")) - image DB kembali ke versi lama (mis. sesudah upgrade GeoNode); jalankan menu 11" ;;
        tertinggal) echo "   PERINGATAN ekstensi PostGIS $db belum diperbarui mengikuti image - jalankan menu 11 (ALTER EXTENSION ... UPDATE)" ;;
      esac
      port=$(docker port "$db" 5432/tcp 2>/dev/null | grep -vE '127\.0\.0\.1|\[::1\]' | sed 's/^/ /' | tr '\n' ' ')
      [ -n "$port" ] && echo "   PERINGATAN port PostgreSQL terbuka ke semua antarmuka:$port- ikat ke 127.0.0.1 (DB hanya diakses antar-kontainer)"
    fi
  done
}

TANDA_KONF="# geomdb-aman"
BERKAS_KONF=docker-compose.geomdb-aman.yml
BERKAS_PG=docker-compose.geomdb-pg.yml  # image PostgreSQL pengganti; sengaja tidak dilepas menu 12

tanya() {  # $1 = pertanyaan, $2 = bawaan y/n → 0 bila ya; dengan -y semua dijawab ya
  local j
  if [ "$YA" = "-y" ]; then echo "$1 [ya, -y]"; return 0; fi
  read -r -p "$1 [$([ "$2" = y ] && echo Y/n || echo y/N)] " j
  [[ "${j:-$2}" =~ ^[yY]$ ]]
}

# Pertanyaan menu 11 bisa dibatasi untuk pemakaian terskrip, mis. PERKETAT_HANYA=image-db ... perketat -y.
# Kunci: image-geoserver port-geoserver csrf-geoserver port-db image-db ekstensi-db signup; yang tidak disebut = tidak.
pilih() {  # $1 = kunci, $2 = pertanyaan, $3 = bawaan y/n → 0 bila ya
  if [ -n "${PERKETAT_HANYA:-}" ] && [[ ",${PERKETAT_HANYA// /}," != *",$1,"* ]]; then
    echo "$2 [dilewati: bukan bagian PERKETAT_HANYA]"; return 1
  fi
  tanya "$2" "$3"
}

proyek_tunggal() {  # proyek compose kontainer GeoNode terpilih; galat bila lebih dari satu
  local p
  p=$(for n in "${DAFTAR[@]}"; do docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$n" 2>/dev/null; done | sort -u)
  if [ "$(wc -l <<< "$p")" -ne 1 ] || [ -z "$p" ]; then
    echo "GALAT: kontainer GeoNode berasal dari lebih dari satu proyek Docker ($(tr '\n' ' ' <<< "$p"))."
    echo "       Pilih satu dengan KONTAINER=\"django4<proyek> celery4<proyek>\" $0 $AKSI"
    return 1
  fi
  echo "$p"
}

kontainer_layanan() { docker ps --filter "label=com.docker.compose.project=$1" --filter "label=com.docker.compose.service=$2" --format '{{.Names}}' | head -n1; }

tambalan_terpasang() {  # aksi tambal yang sedang terpasang di kontainer django (untuk dipasang lagi bila dibuat ulang)
  local dj=$1 py k
  py=$(python_kontainer "$dj"); [ -n "$py" ] || return 0
  [ -n "$MODUL_AMAN" ] && docker cp "$MODUL_AMAN" "$dj:$MODUL_AMAN_KONTAINER" >/dev/null 2>&1
  k=$(docker exec -i -u root -e "GEOMDB_AMAN_MODUL=$MODUL_AMAN_KONTAINER" "$dj" "$py" - cek < "$PENAMBAL" 2>/dev/null)
  docker exec -u root "$dj" rm -f "$MODUL_AMAN_KONTAINER" >/dev/null 2>&1
  grep -q 'Tambalan CSW ISO 19115-3 (MDB): SUDAH' <<< "$k" && echo tambal-mdb
  if grep -q 'Tambalan unggah metadata: SUDAH' <<< "$k"; then echo tambal-unggah
  elif grep -q 'Tambalan GeoMDB (preserve): SUDAH' <<< "$k"; then echo tambal; fi
  grep -q 'DITAMBAL GeoMDB' <<< "$k" && echo tambal-aman
}

pasang_lagi() {  # $1 = id kontainer django sebelum; $2.. = aksi tambal yang dulu terpasang
  local p=$3 dj_lama=$1 dj aksi; shift 3
  dj=$(kontainer_layanan "$p" django)
  if [ -n "$dj" ] && [ "$(docker inspect -f '{{.Id}}' "$dj")" != "$dj_lama" ] && [ $# -gt 0 ]; then
    echo "Kontainer GeoNode dibuat ulang: tambalan kode dipasang lagi ($*)."
    for i in $(seq 60); do [ "$(docker inspect -f '{{.State.Health.Status}}' "$dj" 2>/dev/null)" = healthy ] && break; sleep 3; done
    for aksi in "$@"; do KONTAINER="$dj $(kontainer_layanan "$p" celery)" "$0" "$aksi" -y | sed 's/^/   /'; done
  fi
}

# COMPOSE_FILE = berkas compose asli proyek + berkas tambahan alat ini yang ada ($BERKAS_KONF, $BERKAS_PG). Nilai
# asli disimpan di baris penanda agar bisa dikembalikan persis; tanpa berkas tambahan, nilai asli dipulihkan.
compose_file_alat() {  # $1 = folder proyek, $2 = kontainer django (daftar berkas compose bila COMPOSE_FILE asli kosong)
  local wd=$1 dj=$2 asli dasar tambahan="" f
  if grep -q "$TANDA_KONF COMPOSE_FILE asli: " "$wd/.env"; then
    asli=$(grep -m1 -o "$TANDA_KONF COMPOSE_FILE asli: .*" "$wd/.env" | sed "s/^$TANDA_KONF COMPOSE_FILE asli: //")
  else
    asli=$(grep -m1 '^COMPOSE_FILE=' "$wd/.env" | cut -d= -f2-); asli=${asli:-"(tidak ada)"}
  fi
  for f in "$BERKAS_KONF" "$BERKAS_PG"; do [ -f "$wd/$f" ] && tambahan+=":$f"; done
  # penanda bisa di baris sendiri atau (versi awal alat ini) menempel di akhir baris lain
  sed -i "/^$TANDA_KONF COMPOSE_FILE asli: /d; s/$TANDA_KONF COMPOSE_FILE asli: .*\$//; /^COMPOSE_FILE=/d" "$wd/.env"
  if [ -z "$tambahan" ]; then
    [ "$asli" != "(tidak ada)" ] && echo "COMPOSE_FILE=$asli" >> "$wd/.env"
    return 0
  fi
  if [ "$asli" = "(tidak ada)" ]; then
    dasar=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.config_files"}}' "$dj" | tr ',' '\n' \
      | sed "s#^$wd/##" | grep -vE "^($BERKAS_KONF|$BERKAS_PG)\$" | paste -sd: -)
  else
    dasar=$asli
  fi
  [ -n "$(tail -c1 "$wd/.env")" ] && echo >> "$wd/.env"  # .env tanpa baris baru di akhir: penanda jangan menempel
  printf '%s COMPOSE_FILE asli: %s\nCOMPOSE_FILE=%s%s\n' "$TANDA_KONF" "$asli" "$dasar" "$tambahan" >> "$wd/.env"
}

perketat() {
  local p wd dj gs db dbport v tgl isi port jopts origin lama_dj sebelum simpan f
  local gsisi="" target="" dbisi="" dbimg="" dbver="" dbstatus="" ext_saja=0 aman=() aktif=()
  p=$(proyek_tunggal) || exit 1
  dj=$(kontainer_layanan "$p" django); gs=$(kontainer_layanan "$p" geoserver); db=$(kontainer_layanan "$p" db)
  wd=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "$dj")
  [ -d "$wd" ] && [ -f "$wd/.env" ] || { echo "GALAT: folder proyek Docker ($wd) atau .env-nya tidak ditemukan."; exit 1; }
  echo "Proyek Docker \"$p\" di $wd"
  isi="services:"
  if [ -n "$gs" ]; then
    v=$(docker exec "$gs" sh -c 'ls /usr/local/tomcat/webapps/geoserver/WEB-INF/lib' | sed -n 's/^gs-main-\([0-9][0-9.]*[0-9]\)\.jar$/\1/p' | head -n1)
    if [ -n "$v" ] && [ -n "$(celah_geoserver "$v")" ]; then
      versi_lt "$v" 2.28.0 && target=2.27.6-latest || target=2.28.6-latest
      echo; echo "GeoServer $v rentan:"; celah_geoserver "$v" | sed 's/^/  - /'
      versi_lt "$v" 2.27.0 && echo "  Catatan: lompatan dari $v ke ${target%-latest} - folder data GeoServer dicadangkan dulu."
      if pilih image-geoserver "Ganti image GeoServer ke geonode/geoserver:$target?" y; then
        gsisi+=$'\n'"    image: geonode/geoserver:$target"; aman+=("image GeoServer $target")
      fi
    fi
    port=$(docker port "$gs" 8080/tcp 2>/dev/null | grep -vE '127\.0\.0\.1|\[::1\]' | head -n1 | sed 's/.*://')
    if [ -n "$port" ] && pilih port-geoserver "Port GeoServer $port terbuka ke semua antarmuka. Ikat ke 127.0.0.1 saja?" y; then
      gsisi+=$'\n'"    ports: !override"$'\n'"      - \"127.0.0.1:$port:8080\""; aman+=("port GeoServer $port hanya localhost")
    fi
    jopts=$(docker exec "$gs" sh -c 'echo "$GEOSERVER_JAVA_OPTS"')
    if grep -q 'GEOSERVER_CSRF_DISABLED=true' <<< "$(java_geoserver "$gs")" || docker exec "$gs" env | grep -qi '^ENABLE_JSONP=true$'; then
      if pilih csrf-geoserver "Aktifkan proteksi CSRF admin GeoServer, matikan JSONP, CORS tanpa PUT/DELETE?" y; then
        origin=$(docker exec "$dj" sh -c 'echo "$SITEURL"' | sed -E 's#^https?://([^/:]+).*#\1#')
        jopts=$(sed -E 's/ ?-DGEOSERVER_CSRF_DISABLED=true//; s/ ?-DGEOSERVER_CSRF_WHITELIST=[^ ]*//' <<< "$jopts")
        jopts="$jopts -DGEOSERVER_CSRF_WHITELIST=$origin"
        jopts=${jopts//\$/\$\$}; jopts=${jopts//\"/\\\"}
        gsisi+=$'\n'"    environment:"$'\n'"      GEOSERVER_JAVA_OPTS: \"$jopts\""$'\n'"      ENABLE_JSONP: \"false\""
        gsisi+=$'\n'"      GEOSERVER_CORS_ALLOWED_METHODS: \"GET,POST,HEAD,OPTIONS\""
        aman+=("CSRF GeoServer aktif (whitelist $origin), JSONP mati, CORS GET/POST")
      fi
    fi
    [ -n "$gsisi" ] && isi+=$'\n'"  geoserver:$gsisi"
  fi
  if [ -n "$db" ]; then
    dbport=$(docker port "$db" 5432/tcp 2>/dev/null | grep -vE '127\.0\.0\.1|\[::1\]' | head -n1 | sed 's/.*://')
    if [ -n "$dbport" ] && pilih port-db "Port PostgreSQL $dbport terbuka ke semua antarmuka. Ikat ke 127.0.0.1 saja?" y; then
      dbisi+=$'\n'"    ports: !override"$'\n'"      - \"127.0.0.1:$dbport:5432\""; aman+=("port PostgreSQL $dbport hanya localhost")
    fi
    [ -n "$dbisi" ] && isi+=$'\n'"  db:$dbisi"
    dbstatus=$(pg_status_ekstensi "$db")
    if [ "$dbstatus" = lebih-baru ]; then
      echo; echo "PERINGATAN: katalog PostGIS di $db lebih baru dari image $(docker inspect -f '{{.Config.Image}}' "$db") - image DB sempat kembali ke versi lama."
    fi
    read -r dbimg dbver <<< "$(pg_image_pengganti "$db")"
    if [ -n "$dbimg" ]; then
      echo
      echo "PostgreSQL $(pg_versi "$db") ($(docker inspect -f '{{.Config.Image}}' "$db")) bisa naik ke $dbver dengan image resmi $dbimg"
      echo "  (seri PostgreSQL & minor PostGIS sama, sama-sama Alpine). Sebelum diganti: pg_dumpall + salinan volume data"
      echo "  (PostgreSQL berhenti sebentar); sesudahnya ekstensi PostGIS diperbarui otomatis. Image pengganti disimpan di"
      echo "  $BERKAS_PG dan TIDAK dilepas menu 12 (kembali ke PostGIS lama tidak didukung). Hanya untuk instalasi yang"
      echo "  sudah berjalan: image resmi tidak membawa skrip pembuat database GeoNode untuk instalasi baru."
      pilih image-db "Ganti image PostgreSQL ke $dbimg ($dbver)?" y || dbimg=""
    elif [ "$dbstatus" = tertinggal ] && pilih ekstensi-db "Ekstensi PostGIS di $db tertinggal dari image. Perbarui sekarang (ALTER EXTENSION ... UPDATE)?" y; then
      ext_saja=1
    fi
  fi
  if docker exec "$dj" env | grep -qiE '^ACCOUNT_OPEN_SIGNUP=(true|1)$' \
     && pilih signup "Pendaftaran akun mandiri terbuka. Tutup (akun dibuat Walidata/admin)?" y; then
    isi+=$'\n'"  django:"$'\n'"    environment:"$'\n'"      ACCOUNT_OPEN_SIGNUP: \"False\""
    isi+=$'\n'"  celery:"$'\n'"    environment:"$'\n'"      ACCOUNT_OPEN_SIGNUP: \"False\""
    aman+=("pendaftaran mandiri ditutup")
  fi
  if [ ${#aman[@]} -gt 0 ] && [ -f "$wd/$BERKAS_KONF" ]; then
    echo; echo "Berkas $BERKAS_KONF sudah ada dari pengetatan sebelumnya. Pilihan berikut TIDAK diterapkan agar pengaturan"
    echo "lama tidak tertimpa: $(IFS=';'; echo "${aman[*]}" | sed 's/;/; /g')."
    echo "Untuk menilai ulang semuanya: jalankan menu 12 lalu menu 11 lagi."
    aman=()
  fi
  tgl=$(date +%Y%m%d-%H%M%S)
  if [ ${#aman[@]} -eq 0 ] && [ -z "$dbimg" ]; then
    if [ $ext_saja = 1 ]; then
      mkdir -p "$wd/cadangan-geomdb-aman"
      echo "Mencadangkan PostgreSQL (pg_dumpall) ..."
      docker exec "$db" sh -c 'pg_dumpall -U "${POSTGRES_USER:-postgres}"' </dev/null 2>/dev/null | gzip > "$wd/cadangan-geomdb-aman/postgres-dumpall-$tgl.sql.gz"
      echo "  -> $wd/cadangan-geomdb-aman/postgres-dumpall-$tgl.sql.gz"
      pg_perbarui_ekstensi "$db"; return
    fi
    echo "Tidak ada pengetatan yang dipilih/diperlukan - tidak ada yang diubah."; return 0
  fi
  aktif=(${aman[@]+"${aman[@]}"}); [ -n "$dbimg" ] && aktif+=("image PostgreSQL $dbimg ($dbver)")
  cp -p "$wd/.env" "$wd/.env.geomdb-aman-$tgl"
  simpan="$wd/.geomdb-sebelum-$tgl"; mkdir -p "$simpan"
  for f in "$BERKAS_KONF" "$BERKAS_PG"; do [ -f "$wd/$f" ] && cp -p "$wd/$f" "$simpan/"; done
  batal() {  # .env & berkas alat kembali seperti sebelum menu 11 dijalankan
    cp -p "$wd/.env.geomdb-aman-$tgl" "$wd/.env"; rm -f "$wd/$BERKAS_KONF" "$wd/$BERKAS_PG"
    for f in "$BERKAS_KONF" "$BERKAS_PG"; do [ -f "$simpan/$f" ] && cp -p "$simpan/$f" "$wd/"; done
    rm -rf "$simpan"
  }
  if [ ${#aman[@]} -gt 0 ]; then
    printf '%s\n# Dibuat %s oleh tambal-geonode-preserve.sh (menu 11); dilepas lewat menu 12.\n%s\n' \
      "$TANDA_KONF" "$tgl" "$isi" > "$wd/$BERKAS_KONF"
  fi
  if [ -n "$dbimg" ]; then
    printf '%s\n# Dibuat %s oleh tambal-geonode-preserve.sh (menu 11): image PostgreSQL pengganti. Tidak dilepas menu 12\n# karena katalog PostGIS sudah diperbarui. Cadangan sebelum penggantian: cadangan-geomdb-aman/postgres-*-%s.*\nservices:\n  db:\n    image: %s\n' \
      "$TANDA_KONF" "$tgl" "$tgl" "$dbimg" > "$wd/$BERKAS_PG"
  fi
  compose_file_alat "$wd" "$dj"
  echo "Menerapkan: $(IFS=';'; echo "${aktif[*]}" | sed 's/;/; /g')"
  (cd "$wd" && docker compose config -q) || { echo "GALAT: konfigurasi compose tidak sah - dikembalikan."; batal; exit 1; }
  if [[ " ${aman[*]-} " == *"image GeoServer"* ]]; then
    local vol
    vol=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/geoserver_data/data"}}{{.Name}}{{end}}{{end}}' "$gs")
    if [ -n "$vol" ]; then
      mkdir -p "$wd/cadangan-geomdb-aman"
      echo "Mencadangkan folder data GeoServer (volume $vol) ..."
      docker run --rm -v "$vol":/d:ro -v "$wd/cadangan-geomdb-aman":/c alpine tar czf "/c/geoserver-data-dir-$tgl.tgz" -C /d . \
        || { echo "GALAT: cadangan folder data GeoServer gagal - tidak ada yang diubah."; batal; exit 1; }
      echo "  -> $wd/cadangan-geomdb-aman/geoserver-data-dir-$tgl.tgz"
    fi
  fi
  if [ -n "$dbimg" ]; then
    pg_cadangkan "$db" "$wd/cadangan-geomdb-aman" "$tgl" || { echo "Tidak ada yang diubah."; batal; exit 1; }
  fi
  sebelum=$(tambalan_terpasang "$dj"); lama_dj=$(docker inspect -f '{{.Id}}' "$dj")
  if [ ${#aman[@]} -gt 0 ]; then
    (cd "$wd" && docker compose pull -q geoserver >/dev/null 2>&1; docker compose up -d 2>&1 | grep -vE 'Running|Waiting' | sed 's/^/  /')
  else  # hanya image PostgreSQL: layanan lain tetap berjalan dan tersambung ulang sendiri
    (cd "$wd" && docker compose up -d --no-deps db 2>&1 | grep -vE 'Running|Waiting' | sed 's/^/  /')
  fi
  if [ ${#aman[@]} -gt 0 ] && [ -n "$gs" ]; then
    for i in $(seq 80); do [ "$(docker inspect -f '{{.State.Health.Status}}' "$(kontainer_layanan "$p" geoserver)" 2>/dev/null)" = healthy ] && break; sleep 3; done
  fi
  if [ -n "$dbimg" ]; then
    db=$(kontainer_layanan "$p" db)
    if [ -n "$db" ] && [ "$(docker inspect -f '{{.Config.Image}}' "$db")" = "$dbimg" ] && pg_siap "$db"; then
      echo "PostgreSQL $(pg_versi "$db") siap dengan $dbimg. Memperbarui ekstensi PostGIS ..."
      pg_perbarui_ekstensi "$db" || echo "  Periksa pesan di atas; cadangan ada di $wd/cadangan-geomdb-aman/."
    else
      echo "GALAT: PostgreSQL tidak siap dengan $dbimg - image dikembalikan (katalog PostGIS belum diubah)."
      rm -f "$wd/$BERKAS_PG"; [ -f "$simpan/$BERKAS_PG" ] && cp -p "$simpan/$BERKAS_PG" "$wd/"
      compose_file_alat "$wd" "$dj"
      (cd "$wd" && docker compose up -d --no-deps db 2>&1 | grep -vE 'Running|Waiting' | sed 's/^/  /')
    fi
  fi
  rm -rf "$simpan"
  read -r -a sebelum_arr <<< "$(tr '\n' ' ' <<< "$sebelum")"
  pasang_lagi "$lama_dj" "" "$p" ${sebelum_arr[@]+"${sebelum_arr[@]}"}
  echo "Selesai. Cadangan .env: $wd/.env.geomdb-aman-$tgl ."
  [ ${#aman[@]} -gt 0 ] && echo "Pengetatan dilepas lewat menu 12."
  [ -n "$dbimg" ] && echo "Image PostgreSQL pengganti ($BERKAS_PG) tetap dipakai walau menu 12 dijalankan."
  return 0
}

kembalikan_konf() {  # $1 = folder proyek, $2 = kontainer django: lepas $BERKAS_KONF (image PostgreSQL pengganti tetap)
  rm -f "$1/$BERKAS_KONF"
  compose_file_alat "$1" "$2"
}

kembalikan() {
  local p wd dj sebelum lama_dj ganti_image
  p=$(proyek_tunggal) || exit 1
  dj=$(kontainer_layanan "$p" django)
  wd=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "$dj")
  if [ ! -f "$wd/$BERKAS_KONF" ]; then
    echo "Konfigurasi belum diperketat oleh alat ini ($wd/$BERKAS_KONF tidak ada) - tidak ada yang dikembalikan."
    [ -f "$wd/$BERKAS_PG" ] && echo "Image PostgreSQL pengganti ($BERKAS_PG) sengaja tidak dilepas menu 12: katalog PostGIS sudah diperbarui."
    return 0
  fi
  echo "Proyek Docker \"$p\" di $wd. Berkas $BERKAS_KONF:"; sed 's/^/  /' "$wd/$BERKAS_KONF"
  tanya "Kembalikan konfigurasi Docker seperti sebelum menu 11?" n || { echo "Dibatalkan."; return 0; }
  sebelum=$(tambalan_terpasang "$dj"); lama_dj=$(docker inspect -f '{{.Id}}' "$dj")
  ganti_image=$(grep -cE '^[[:space:]]*image:' "$wd/$BERKAS_KONF" || true)
  kembalikan_konf "$wd" "$dj"
  (cd "$wd" && docker compose up -d 2>&1 | grep -vE 'Running|Waiting' | sed 's/^/  /')
  read -r -a sebelum_arr <<< "$(tr '\n' ' ' <<< "$sebelum")"
  pasang_lagi "$lama_dj" "" "$p" ${sebelum_arr[@]+"${sebelum_arr[@]}"}
  echo "Konfigurasi dikembalikan."
  if [ "${ganti_image:-0}" -gt 0 ]; then
    echo "Image GeoServer kembali ke versi lama. Bila GeoServer bermasalah, pulihkan folder datanya dari"
    echo "$wd/cadangan-geomdb-aman/ (cadangan sebelum menu 11)."
  fi
  if [ -f "$wd/$BERKAS_PG" ]; then
    echo "Image PostgreSQL pengganti ($BERKAS_PG) TETAP dipakai: katalog PostGIS sudah diperbarui dan kembali ke image"
    echo "lama tidak didukung. Cadangan sebelum penggantian: $wd/cadangan-geomdb-aman/postgres-*."
  fi
  return 0
}

uji_aman() {  # menu 13: simulasikan serangan K1..K4 ke GeoNode LOKAL ini, lalu bersihkan jejaknya
  local p dj ce py wd sandi marker lulus=0 gagal=0 nama out
  marker=/tmp/geomdb_uji_$$
  p=$(proyek_tunggal) || exit 1
  dj=$(kontainer_layanan "$p" django); ce=$(kontainer_layanan "$p" celery)
  [ -n "$dj" ] || { echo "GALAT: kontainer django tidak ditemukan."; return 1; }
  py=$(python_kontainer "$dj"); [ -n "$py" ] || { echo "GALAT: python tidak ada di $dj."; return 1; }
  wd=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "$dj")
  sandi=$(grep -m1 '^ADMIN_PASSWORD=' "$wd/.env" 2>/dev/null | cut -d= -f2-)
  [ -n "$sandi" ] || { echo "GALAT: ADMIN_PASSWORD tidak ditemukan di $wd/.env."; return 1; }

  echo "Uji keamanan proyek Docker \"$p\" (django=$dj)"
  echo "Uji ini MENSIMULASIKAN serangan sungguhan ke GeoNode LOKAL ini: nama layer berisi perintah,"
  echo "XML ber-DOCTYPE/XSLT, dan skrip di abstrak. Jejaknya (dataset uji, abstrak) dibersihkan sesudahnya."
  echo "Jalankan HANYA pada server yang Anda kelola sendiri atau dengan izin tertulis pengelolanya."
  tanya "Lanjutkan uji keamanan?" n || { echo "Dibatalkan."; return 0; }
  echo

  # ── K1 injeksi perintah lewat nama layer (unggahan nyata, diproses celery) ──
  echo "== K1 injeksi perintah lewat nama layer unggahan"
  [ -n "$ce" ] && docker exec "$ce" rm -f "$marker" >/dev/null 2>&1
  out=$(docker exec -i -e GEOMDB_SANDI="$sandi" -e GEOMDB_MARKER="$marker" "$dj" "$py" - <<'PY'
import os, re, time, tempfile, json
import requests
B = "http://localhost:8000"; A = ("admin", os.environ["GEOMDB_SANDI"]); M = os.environ["GEOMDB_MARKER"]
def unggah(isi):
    fh = tempfile.NamedTemporaryFile("w", suffix=".geojson", delete=False); fh.write(isi); fh.close()
    with open(fh.name, "rb") as f:
        r = requests.post(B + "/api/v2/uploads/upload", files={"base_file": f},
                          data={"store_spatial_files": "false", "action": "upload"}, auth=A, timeout=90)
    m = re.search(r'"execution_id":\s*"([^"]+)"', r.text); return m.group(1) if m else None
def tunggu(eid):
    for _ in range(80):
        if not eid: return "?"
        t = requests.get(B + "/api/v2/executionrequest/" + eid, auth=A, timeout=30).text
        m = re.search(r'"status":\s*"([a-z_]+)"', t); s = m.group(1) if m else ""
        if s in ("finished", "failed"): return s
        time.sleep(3)
    return "timeout"
jahat = '{"type":"FeatureCollection","name":"uji\\"; touch %s; echo \\"","features":[{"type":"Feature","properties":{"n":1},"geometry":{"type":"Point","coordinates":[107.6,-2.8]}}]}' % M
st = tunggu(unggah(jahat))
print("STATUS_JAHAT", st)
nama = "geomdb_uji_normal_%d" % int(time.time())
biasa = '{"type":"FeatureCollection","name":"%s","features":[{"type":"Feature","properties":{"nama":"A"},"geometry":{"type":"Polygon","coordinates":[[[107.6,-2.8],[107.7,-2.8],[107.7,-2.7],[107.6,-2.8]]]}}]}' % nama
stb = tunggu(unggah(biasa))
n = re.search(r'"total":\s*(\d+)', requests.get(B + "/api/v2/datasets?search=" + nama, auth=A, timeout=30).text)
print("STATUS_BIASA", stb, "TOTAL", (n.group(1) if n else "0"), "NAMA", nama)
PY
)
  nama=$(sed -n 's/.*NAMA \([^ ]*\).*/\1/p' <<< "$out")
  if [ -n "$ce" ] && docker exec "$ce" test -f "$marker" 2>/dev/null; then
    echo "  GAGAL  perintah sisipan TERJALANKAN di server (RENTAN) — tambal dengan menu 9"; gagal=$((gagal+1))
    docker exec "$ce" rm -f "$marker" >/dev/null 2>&1
  else
    echo "  OK     perintah sisipan tidak dijalankan ($(sed -n 's/.*STATUS_JAHAT \([^ ]*\).*/status unggah: \1/p' <<< "$out"))"; lulus=$((lulus+1))
  fi
  if grep -q 'STATUS_BIASA finished' <<< "$out" && ! grep -q 'TOTAL 0' <<< "$out"; then
    echo "  OK     unggahan GeoJSON biasa tetap berhasil"; lulus=$((lulus+1))
  else
    echo "  (catatan) unggahan GeoJSON biasa tidak selesai — $(grep -o 'STATUS_BIASA [^ ]* TOTAL [0-9]*' <<< "$out")"
  fi

  # ── K2 /proxy, K2 pendaftaran layanan, K3 XML, K4 XSS (di dalam Django) ──
  echo "== K2 SSRF /proxy · K2 layanan · K3 XML/SLD · K4 XSS"
  out=$(docker exec -i -e GEOMDB_SANDI="$sandi" "$dj" "$py" manage.py shell 2>/dev/null <<'PY'
import os, re, tempfile
import requests
L = {"lulus": 0, "gagal": 0}
def hasil(ok, teks):
    L["lulus" if ok else "gagal"] += 1
    print(("  OK     " if ok else "  GAGAL  ") + teks)

B = "http://localhost:8000"; A = ("admin", os.environ["GEOMDB_SANDI"])
for u in ("http://db:5432/", "http://169.254.169.254/latest/meta-data/", "http://localhost:8080/geoserver/ows"):
    try:
        k = requests.get(B + "/proxy/", params={"url": u}, auth=A, timeout=20, allow_redirects=False).status_code
    except Exception as e:
        k = "err"
    hasil(k == 403, "/proxy ke %s ditolak (HTTP %s; diharapkan 403)" % (u, k))

try:
    from geonode.services.forms import CreateServiceForm
    for url in ("http://127.0.0.1:8080/geoserver/ows", "http://169.254.169.254/", "http://db:5432/"):
        f = CreateServiceForm(data={"url": url, "type": "WMS"})
        hasil(not f.is_valid() and "url" in f.errors, "pendaftaran layanan ke %s ditolak" % url)
except Exception as e:
    print("  (lewati) uji pendaftaran layanan:", e)

try:
    try:
        from importer.handlers.xml.handler import XMLFileHandler
    except Exception:
        from geonode.upload.handlers.xml.handler import XMLFileHandler
    def xml_lolos(isi):
        fh = tempfile.NamedTemporaryFile("w", suffix=".xml", delete=False); fh.write(isi); fh.close()
        try:
            XMLFileHandler.is_valid({"base_file": fh.name}); return True
        except Exception:
            return False
    hasil(not xml_lolos('<!DOCTYPE a [<!ENTITY e SYSTEM "file:///etc/passwd">]><a>&e;</a>'), "XML ber-DOCTYPE/entitas ditolak")
    hasil(not xml_lolos('<a xmlns:xsl="http://www.w3.org/1999/XSL/Transform"><xsl:value-of select="1"/></a>'), "XML berisi XSLT ditolak")
    hasil(xml_lolos('<?xml version="1.0"?><gmd:MD_Metadata xmlns:gmd="http://www.isotc211.org/2005/gmd"/>'), "XML metadata biasa diterima")
except Exception as e:
    print("  (lewati) uji XML:", e)

PAY = '<p>Uji <b>tebal</b></p><script>alert(1)</script><img src=x onerror=alert(1)><a href="javascript:alert(2)">x</a>'
def berbahaya(teks):
    t = (teks or "").lower()
    return any(x in t for x in ("<script", "onerror", "javascript:", "<img"))
aman_k4 = False; cara = []
# jalur 1: editor metadata (perbaikan resmi GeoNode 5.0.3+ di metadata/handlers/meta.py)
try:
    from geonode.metadata.handlers import meta as _meta
    _cls = next((getattr(_meta, n) for n in dir(_meta)
                 if isinstance(getattr(_meta, n), type) and hasattr(getattr(_meta, n), "_sanitize_string")), None)
    if _cls is not None:
        r = _cls._sanitize_string(PAY); r = r[0] if isinstance(r, tuple) else r
        if not berbahaya(r):
            aman_k4 = True; cara.append("editor metadata membersihkan")
except Exception:
    pass
# jalur 2: pembersihan saat disimpan (tambalan GeoMDB di base.save)
try:
    from geonode.layers.models import Dataset
    d = Dataset.objects.order_by("-pk").first()
    if d is not None:
        asli = d.abstract
        d.abstract = PAY; d.save(); d.refresh_from_db()
        if not berbahaya(d.abstract):
            aman_k4 = True; cara.append("dibersihkan saat disimpan")
        d.abstract = "Data < 2020 & tahun 2019"; d.save(); d.refresh_from_db()
        hasil(d.abstract == "Data < 2020 & tahun 2019", "abstrak teks biasa tidak diubah")
        d.abstract = asli; d.save()
    else:
        print("  (catatan) uji simpan abstrak dilewati: belum ada dataset")
except Exception as e:
    print("  (lewati) uji simpan abstrak:", e)
hasil(aman_k4, "skrip di abstrak dinetralkan" + (" (%s)" % "; ".join(cara) if cara else " — TIDAK: abstrak rentan XSS"))

print("RINGKAS", L["lulus"], L["gagal"])
PY
)
  echo "$out" | grep -E '^  (OK|GAGAL|\(lewati\)|\(catatan\))'
  lulus=$((lulus + $(sed -n 's/^RINGKAS \([0-9]*\) .*/\1/p' <<< "$out")))
  gagal=$((gagal + $(sed -n 's/^RINGKAS [0-9]* \([0-9]*\)/\1/p' <<< "$out")))

  # ── bersihkan dataset uji ──
  if [ -n "$nama" ]; then
    docker exec -i -e GEOMDB_SANDI="$sandi" -e GEOMDB_NAMA="$nama" "$dj" "$py" - <<'PY' >/dev/null 2>&1
import os, re, requests
B = "http://localhost:8000"; A = ("admin", os.environ["GEOMDB_SANDI"])
t = requests.get(B + "/api/v2/datasets?search=" + os.environ["GEOMDB_NAMA"], auth=A, timeout=30).text
for pk in re.findall(r'"pk":\s*(\d+)', t):
    requests.delete(B + "/api/v2/datasets/" + pk, auth=A, timeout=30)
PY
  fi

  echo
  echo "Hasil uji keamanan: LULUS $lulus, GAGAL $gagal."
  if [ "$gagal" -gt 0 ]; then
    echo "Ada celah yang masih terbuka. Tambal kode dengan menu 9 (tambal-aman) dan perketat dengan menu 11."
    return 3
  fi
  echo "Semua uji lulus: celah K1..K4 tertutup pada server ini."
}

if [ "$AKSI" = perketat ]; then perketat; exit $?; fi
if [ "$AKSI" = kembalikan ]; then kembalikan; exit $?; fi
if [ "$AKSI" = uji-aman ]; then uji_aman; exit $?; fi

echo "Kontainer GeoNode: ${DAFTAR[*]}"
BERUBAH=()
BASI=()
GAGAL=0
for nama in "${DAFTAR[@]}"; do
  echo "== $nama"
  py=$(python_kontainer "$nama")
  if [ -z "$py" ]; then echo "   GALAT: python tidak ditemukan"; GAGAL=1; continue; fi
  ENV_MODUL=()
  if [ -n "$MODUL" ]; then  # modul tambalan unggah disalin ke kontainer; penambal memasangnya ke paket geonode
    if docker cp "$MODUL" "$nama:$MODUL_KONTAINER" >/dev/null 2>&1; then
      ENV_MODUL=(-e "GEOMDB_MODUL=$MODUL_KONTAINER")
    elif [ "$AKSI" = tambal-unggah ]; then
      echo "   GALAT: $MODUL gagal disalin ke kontainer"; GAGAL=1; continue
    fi
  fi
  if [ -n "$MODUL_MDB" ]; then  # modul + XSLT tambalan CSW ISO 19115-3, dengan cara yang sama
    docker exec -u root "$nama" rm -rf "$XSLT_KONTAINER" >/dev/null 2>&1  # docker cp ke folder yang ada = subfolder
    if docker cp "$MODUL_MDB" "$nama:$MODUL_MDB_KONTAINER" >/dev/null 2>&1        && docker cp "$XSLT_MDB" "$nama:$XSLT_KONTAINER" >/dev/null 2>&1; then
      ENV_MODUL+=(-e "GEOMDB_MDB_MODUL=$MODUL_MDB_KONTAINER" -e "GEOMDB_XSLT=$XSLT_KONTAINER")
    elif [ "$AKSI" = tambal-mdb ]; then
      echo "   GALAT: $MODUL_MDB / $XSLT_MDB gagal disalin ke kontainer"; GAGAL=1; continue
    fi
  fi
  if [ -n "$MODUL_AMAN" ]; then  # modul tambalan keamanan, dengan cara yang sama
    if docker cp "$MODUL_AMAN" "$nama:$MODUL_AMAN_KONTAINER" >/dev/null 2>&1; then
      ENV_MODUL+=(-e "GEOMDB_AMAN_MODUL=$MODUL_AMAN_KONTAINER")
    elif [ "$AKSI" = tambal-aman ]; then
      echo "   GALAT: $MODUL_AMAN gagal disalin ke kontainer"; GAGAL=1; continue
    fi
  fi
  keluaran=$(docker exec -i -u root ${ENV_MODUL[@]+"${ENV_MODUL[@]}"} "$nama" "$py" - "$AKSI" < "$PENAMBAL" 2>&1)
  kode=$?
  [ ${#ENV_MODUL[@]} -gt 0 ] && docker exec -u root "$nama" rm -rf "$MODUL_KONTAINER" "$MODUL_MDB_KONTAINER" "$XSLT_KONTAINER" "$MODUL_AMAN_KONTAINER" >/dev/null 2>&1
  echo "$keluaran" | sed 's/^/   /'
  case "$kode" in
    0) grep -qE '^(Ditambal|Diperbarui|Dilepas|Kode asli GeoNode dikembalikan)' <<< "$keluaran" && BERUBAH+=("$nama") ;;
    2|3) [ "$AKSI" = cek ] || [ "$AKSI" = cek-aman ] || GAGAL=1 ;;  # pada cek/cek-aman, 2/3 hanyalah status
    *) GAGAL=1 ;;
  esac
  berkas=$(head -n1 <<< "$keluaran" | sed -n 's/^GeoNode .* | //p')
  modul_aman=${berkas%/catalogue/models.py}/security/geomdb_aman.py  # dipasang/diperbarui oleh tambalan keamanan
  if [ -n "$berkas" ] && { kode_lebih_baru "$nama" "$berkas" || kode_lebih_baru "$nama" "$modul_aman"; }; then
    BASI+=("$nama")
    echo "   Berkas kode diubah setelah kontainer ini dimulai - prosesnya masih memakai kode LAMA."
  fi
done

# Kontainer GeoNode sering berbagi berkas kode (volume /usr/src/geonode): kontainer yang tidak "diubah" bisa ikut
# berubah karena berkasnya sama. Proses baru memakai kode baru setelah dimulai ulang, jadi setelah ada perubahan
# SEMUA kontainer GeoNode dimulai ulang; tanpa perubahan, yang dimulai ulang hanya kontainer yang prosesnya basi.
ULANG=()
if [ ${#BERUBAH[@]} -gt 0 ]; then
  ULANG=("${DAFTAR[@]}")
  echo
  echo "Kode berubah (lewat: ${BERUBAH[*]}). SEMUA kontainer GeoNode perlu DIMULAI ULANG agar perubahan dipakai,"
  echo "karena kontainer bisa berbagi berkas kode yang sama: ${ULANG[*]}"
elif [ ${#BASI[@]} -gt 0 ]; then
  ULANG=("${BASI[@]}")
  echo
  echo "Kontainer berikut masih menjalankan kode lama dan perlu DIMULAI ULANG: ${ULANG[*]}"
fi
if [ "$AKSI" = cek-aman ]; then
  cek_konfigurasi_geoserver
fi
if [ ${#ULANG[@]} -gt 0 ] && { [ "$AKSI" = cek ] || [ "$AKSI" = cek-aman ]; }; then  # cek tidak pernah mengubah apa pun
  echo "Jalankan: docker restart ${ULANG[*]}   (atau pasang lewat $0, yang menawarkan mulai ulang)"
elif [ ${#ULANG[@]} -gt 0 ]; then
  echo "(django & celery berhenti sebentar, beberapa detik)."
  jawab=y
  if [ "$YA" != "-y" ]; then read -r -p "Mulai ulang sekarang? [y/N] " jawab; fi
  if [[ "$jawab" =~ ^[yY]$ ]]; then
    docker restart "${ULANG[@]}" >/dev/null && echo "Dimulai ulang: ${ULANG[*]}"
  else
    echo "Belum dimulai ulang. Jalankan sendiri: docker restart ${ULANG[*]}"
  fi
fi
exit $GAGAL
