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

echo "Kontainer GeoNode: ${DAFTAR[*]}"
BERUBAH=()
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
done

if [ ${#BERUBAH[@]} -gt 0 ]; then
  # Kontainer GeoNode sering berbagi berkas kode (volume /usr/src/geonode): kontainer yang tidak "diubah" bisa
  # ikut berubah karena berkasnya sama. Proses yang sedang berjalan baru memakai kode baru setelah dimulai ulang,
  # jadi SEMUA kontainer GeoNode dimulai ulang, bukan hanya yang mengubah berkas.
  echo
  echo "Kode berubah (lewat: ${BERUBAH[*]}). SEMUA kontainer GeoNode perlu DIMULAI ULANG agar perubahan dipakai,"
  echo "karena kontainer bisa berbagi berkas kode yang sama: ${DAFTAR[*]}"
  echo "(django & celery berhenti sebentar, beberapa detik)."
  jawab=y
  if [ "$YA" != "-y" ]; then read -r -p "Mulai ulang sekarang? [y/N] " jawab; fi
  if [[ "$jawab" =~ ^[yY]$ ]]; then
    docker restart "${DAFTAR[@]}" >/dev/null && echo "Dimulai ulang: ${DAFTAR[*]}"
  else
    echo "Belum dimulai ulang. Jalankan sendiri: docker restart ${DAFTAR[*]}"
  fi
fi
exit $GAGAL
