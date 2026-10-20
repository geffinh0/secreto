#!/usr/bin/env bash
# Atualiza para uma versão nova (depois de substituir os arquivos do projeto, mantendo .env e secrets/):
#   ./update.sh            recusa se houver live sendo moderada
#   FORCE=1 ./update.sh    atualiza mesmo assim (derruba as sessões ativas; as criadoras precisam religar o robô)
set -euo pipefail
cd "$(dirname "$0")"
umask 077
BACKEND=atilas_client_backend
STAMP=$(date +%Y%m%d-%H%M%S)
BUILD_ID="v1-$STAMP"; export BUILD_ID
val() { grep -E "^$1=" .env | head -n1 | cut -d= -f2- | tr -d '\r'; }

if [ "$(docker inspect -f '{{.State.Running}}' "$BACKEND" 2>/dev/null || echo false)" = true ]; then
  ./backup.sh
  active=$(docker exec "$BACKEND" python -c "
import json, os, urllib.request
req = urllib.request.Request('http://127.0.0.1:8000/ops/active_sessions', headers={'X-Healthbot-Key': os.environ.get('HEALTHBOT_API_KEY','')})
print(json.load(urllib.request.urlopen(req, timeout=5))['active'])" 2>/dev/null || echo erro)
  if [ "$active" != 0 ] && [ "${FORCE:-0}" != 1 ]; then
    echo "ABORTADO: sessões de moderação ativas ($active). Espere acabarem as lives ou use FORCE=1."
    exit 2
  fi
fi

docker compose build
IMG=$(docker compose config --images | grep -- '-backend$' | head -n1)
UID_APP=$(docker run --rm --no-healthcheck --entrypoint id "$IMG" -u | tr -d '\r')
docker run --rm -v "$PWD/secrets:/s" --entrypoint chown alpine:3 "$UID_APP" /s/sm_token_key
docker compose up -d
for _ in $(seq 1 45); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' "$BACKEND" 2>/dev/null || echo none)" = healthy ] && ok=1 && break
  sleep 2
done
[ "${ok:-0}" = 1 ] || { echo "O backend novo não ficou saudável (docker compose logs backend). O backup está em backups/."; exit 1; }
echo "Atualizado ($BUILD_ID). Quem está com o app aberto vê um aviso 'nova versão' e atualiza com um toque."
