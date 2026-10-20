#!/usr/bin/env bash
# Restaura um backup:  ./restore.sh backups/atila-AAAAMMDD-HHMMSS.db
# Troca o banco atual pelo do arquivo (faz antes um backup do atual). Derruba as sessões ativas.
set -euo pipefail
cd "$(dirname "$0")"
[ -f "${1:-}" ] || { echo "uso: ./restore.sh backups/arquivo.db"; exit 1; }
./backup.sh
docker compose stop backend
VOL=$(docker volume ls -q | grep -E '(^|_)backend_data$' | head -n1)
docker run --rm -v "$VOL:/data" -v "$PWD/$1:/in.db:ro" alpine:3 sh -c \
  'cp /in.db /data/super_moderator.db && chown $(stat -c %u:%g /data) /data/super_moderator.db && rm -f /data/super_moderator.db-wal /data/super_moderator.db-shm'
docker compose start backend
echo "Restaurado. As criadoras podem precisar religar o robô."
