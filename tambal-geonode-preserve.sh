#!/usr/bin/env bash
# Tambal bug preserve GeoNode di SEMUA kontainer GeoNode pada server Docker (django, celery, ...).
#
#   ./tambal-geonode-preserve.sh cek            # status tiap kontainer, tidak mengubah apa pun
#   ./tambal-geonode-preserve.sh tambal         # tambal, lalu (setelah konfirmasi) mulai ulang kontainer
#   ./tambal-geonode-preserve.sh pulihkan       # kembalikan kode asli GeoNode
#   tambahkan -y untuk melewati konfirmasi mulai ulang
#   KONTAINER="django4geonode celery4geonode" ./tambal-geonode-preserve.sh cek   # pilih kontainer sendiri
#
# Tambalan tersimpan di dalam kontainer: hilang bila kontainer DIBUAT ULANG (upgrade image, "docker compose
# up" dengan image baru). Jalankan "cek" setelah setiap upgrade dan "tambal" lagi bila perlu.
set -uo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
PENAMBAL="$DIR/tambal_preserve.py"
AKSI=${1:-cek}
YA=${2:-}

case "$AKSI" in
  cek|tambal|pulihkan) ;;
  *) echo "pemakaian: $0 cek|tambal|pulihkan [-y]"; exit 1 ;;
esac
command -v docker >/dev/null 2>&1 || { echo "GALAT: perintah docker tidak ditemukan. Untuk GeoNode tanpa Docker:"
                                       echo "       python $PENAMBAL $AKSI   (di virtualenv GeoNode)"; exit 1; }
[ -f "$PENAMBAL" ] || { echo "GALAT: $PENAMBAL tidak ditemukan (letakkan di folder yang sama)."; exit 1; }

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
  keluaran=$(docker exec -i -u root "$nama" "$py" - "$AKSI" < "$PENAMBAL" 2>&1)
  kode=$?
  echo "$keluaran" | sed 's/^/   /'
  case "$kode" in
    0) grep -qE '^(Ditambal\.|Kode asli GeoNode dikembalikan\.)' <<< "$keluaran" && BERUBAH+=("$nama") ;;
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
  echo "Jalankan: docker restart ${ULANG[*]}   (atau: $0 tambal, yang menawarkan mulai ulang)"
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
