#!/usr/bin/env bash
# Volta o Atila's Client ao estado anterior a um deploy feito com deploy/deploy.sh:
# imagens (etiquetadas atila-rollback/...) E banco (backup de antes do deploy).
#
#   deploy/rollback.sh              # usa o ultimo deploy
#   deploy/rollback.sh 20261013-1405
#   KEEP_DB=1 deploy/rollback.sh    # volta so as imagens, mantem o banco atual
#
# POR QUE o banco volta junto: a versao nova guarda o token do robo cifrado
# ("enc:v1:...") e os tokens de sessao como hash. A imagem antiga nao entende
# nenhum dos dois - com o banco novo, os robos mandariam lixo ao SuperLive. Voltar
# o banco perde o que foi gravado DEPOIS do deploy (contas novas, regras editadas);
# por isso o banco atual e salvo em atila-before-rollback-<stamp>.db antes de trocar.
# (KEEP_DB=1 so serve se voce aceita reconectar todos os robos.)
#
# Nao toca no cata-pobre alem de `nginx -s reload`. Nunca usa `docker compose down`.
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077

BACKUP_DIR=${BACKUP_DIR:-$HOME/atila-backups}
BACKEND=atilas_client_backend
WEB=atilas_client_web
CATA_NGINX=${CATA_NGINX:-cata_pobre_nginx}
VOLUME=${VOLUME:-atilas-client_backend_data}
STAMP=${1:-$(cat "$BACKUP_DIR/last-deploy" 2>/dev/null || true)}

[ -n "$STAMP" ] || { echo "Informe o carimbo do deploy (ver $BACKUP_DIR)."; exit 1; }
for c in "$BACKEND" "$WEB"; do
  docker image inspect "atila-rollback/$c:$STAMP" >/dev/null 2>&1 \
    || { echo "Imagem atila-rollback/$c:$STAMP nao existe."; exit 1; }
done
if [ "${KEEP_DB:-0}" != 1 ]; then
  [ -s "$BACKUP_DIR/atila-$STAMP.db" ] || { echo "Backup $BACKUP_DIR/atila-$STAMP.db nao existe."; exit 1; }
fi

say() { printf '\n==> %s\n' "$*"; }

# um nome de volume errado faria o `docker run -v` criar um volume vazio e "restaurar" nele
if [ "${KEEP_DB:-0}" != 1 ]; then
  docker volume inspect "$VOLUME" >/dev/null 2>&1 || { echo "Volume $VOLUME nao existe (ajuste VOLUME=...)."; exit 1; }
fi

say "1/4 salvando o banco atual antes de qualquer troca"
NOW=$(date +%Y%m%d-%H%M%S)
if docker inspect -f '{{.State.Running}}' "$BACKEND" 2>/dev/null | grep -q true; then
  docker exec "$BACKEND" python -c "
import os, sqlite3
src = sqlite3.connect(os.environ.get('SM_DB_PATH', '/data/super_moderator.db'))
src.backup(sqlite3.connect('/tmp/before-rollback.db'))
"
  docker cp "$BACKEND:/tmp/before-rollback.db" "$BACKUP_DIR/atila-before-rollback-$NOW.db"
  docker exec "$BACKEND" rm -f /tmp/before-rollback.db
  chmod 600 "$BACKUP_DIR/atila-before-rollback-$NOW.db"
  echo "salvo: $BACKUP_DIR/atila-before-rollback-$NOW.db"
fi

say "2/4 parando so o backend e voltando o banco"
docker compose stop backend
if [ "${KEEP_DB:-0}" != 1 ]; then
  # roda como appuser (dono do /data), com a imagem antiga; apaga WAL/SHM do banco novo
  docker run --rm -v "$VOLUME:/data" -v "$BACKUP_DIR:/b:ro" --entrypoint sh \
    "atila-rollback/$BACKEND:$STAMP" -c \
    "cp /b/atila-$STAMP.db /data/super_moderator.db && rm -f /data/super_moderator.db-wal /data/super_moderator.db-shm"
  echo "banco restaurado de atila-$STAMP.db"
fi

say "3/4 voltando as imagens"
for svc_c in "backend:$BACKEND" "web:$WEB"; do
  svc=${svc_c%%:*}; c=${svc_c##*:}
  image=$(docker compose config --images | grep -- "-$svc\$" | head -n1)
  docker tag "atila-rollback/$c:$STAMP" "$image"
done
docker compose up -d --no-deps --no-build backend
for _ in $(seq 1 45); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' "$BACKEND" 2>/dev/null || echo none)" = healthy ] && break
  sleep 2
done
docker compose up -d --no-deps --no-build web
docker exec "$CATA_NGINX" nginx -s reload 2>/dev/null || echo "AVISO: recarregue o nginx do cata-pobre manualmente (docker exec $CATA_NGINX nginx -s reload)."

say "4/4 conferindo"
sleep 3
code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8088/api/health || echo 000)
if [ "$code" = 200 ]; then echo "ok: /api/health = 200. Rollback concluido."; else echo "ATENCAO: /api/health = $code"; exit 1; fi
