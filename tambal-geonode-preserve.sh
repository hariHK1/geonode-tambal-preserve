#!/usr/bin/env bash
# Tambal GeoNode untuk GeoMDB di SEMUA kontainer GeoNode pada server Docker (django, celery, ...).
#
#   ./tambal-geonode-preserve.sh                  # menu
#   ./tambal-geonode-preserve.sh cek              # status tiap kontainer, tidak mengubah apa pun
#   ./tambal-geonode-preserve.sh tambal           # tambalan GeoMDB (preserve)
#   ./tambal-geonode-preserve.sh tambal-unggah    # tambalan unggah metadata UI (termasuk tambalan GeoMDB; GeoNode 5.x)
#   ./tambal-geonode-preserve.sh pulihkan-unggah  # lepas tambalan unggah metadata; tambalan GeoMDB tetap
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
AKSI=${1:-}
YA=${2:-}

menu() {
  cat <<'TEKS'
Tambal GeoNode untuk GeoMDB
  1) Cek status
  2) Tambalan GeoMDB (preserve)
       memperbaiki bug preserve GeoNode; wajib untuk "Kirim ke GeoNode" di plugin QGIS GeoMDB
  3) Tambalan unggah metadata UI GeoNode (butuh GeoNode 5.x, sudah termasuk tambalan GeoMDB)
       XML ISO 19139 yang diunggah lewat UI (Edit > Upload Metadata) tersaji LENGKAP di CSW/unduhan ISO:
       otomatis preserve, fileIdentifier = UUID, tautan GeoNode ditambahkan, Data Quality terisi,
       perubahan form metadata ikut ditulis ke XML
  4) Lepas tambalan unggah metadata (tambalan GeoMDB tetap terpasang)
  5) Pulihkan kode asli GeoNode (lepas semua tambalan)
  0) Keluar
TEKS
  local pilih
  read -r -p "Pilih [1]: " pilih
  case "${pilih:-1}" in
    1) AKSI=cek ;;
    2) AKSI=tambal ;;
    3) AKSI=tambal-unggah ;;
    4) AKSI=pulihkan-unggah ;;
    5) AKSI=pulihkan ;;
    0) exit 0 ;;
    *) echo "Pilihan tidak dikenal: $pilih"; exit 1 ;;
  esac
  echo
}

if [ -z "$AKSI" ]; then
  if [ -t 0 ]; then menu; else AKSI=cek; fi
fi
case "$AKSI" in
  cek|tambal|tambal-unggah|pulihkan-unggah|pulihkan) ;;
  *) echo "pemakaian: $0 [cek|tambal|tambal-unggah|pulihkan-unggah|pulihkan] [-y]"; exit 1 ;;
esac
command -v docker >/dev/null 2>&1 || { echo "GALAT: perintah docker tidak ditemukan. Untuk GeoNode tanpa Docker:"
                                       echo "       python $PENAMBAL $AKSI   (di virtualenv GeoNode)"; exit 1; }
[ -f "$PENAMBAL" ] || { echo "GALAT: $PENAMBAL tidak ditemukan (letakkan di folder yang sama)."; exit 1; }
if [ ! -f "$MODUL" ]; then
  if [ "$AKSI" = tambal-unggah ]; then
    echo "GALAT: $MODUL tidak ditemukan (letakkan di folder yang sama)."; exit 1
  fi
  MODUL=""
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
  keluaran=$(docker exec -i -u root ${ENV_MODUL[@]+"${ENV_MODUL[@]}"} "$nama" "$py" - "$AKSI" < "$PENAMBAL" 2>&1)
  kode=$?
  [ ${#ENV_MODUL[@]} -gt 0 ] && docker exec -u root "$nama" rm -f "$MODUL_KONTAINER" >/dev/null 2>&1
  echo "$keluaran" | sed 's/^/   /'
  case "$kode" in
    0) grep -qE '^(Ditambal|Diperbarui|Dilepas|Kode asli GeoNode dikembalikan)' <<< "$keluaran" && BERUBAH+=("$nama") ;;
    2|3) [ "$AKSI" = cek ] || GAGAL=1 ;;  # pada "cek", 2/3 hanyalah status
    *) GAGAL=1 ;;
  esac
  berkas=$(head -n1 <<< "$keluaran" | sed -n 's/^GeoNode .* | //p')
  if [ -n "$berkas" ] && kode_lebih_baru "$nama" "$berkas"; then
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
if [ ${#ULANG[@]} -gt 0 ] && [ "$AKSI" = cek ]; then  # "cek" tidak pernah mengubah apa pun
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
