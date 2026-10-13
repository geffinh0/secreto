#!/usr/bin/env bash
# Redeploy seguro do Atila's Client. Rode NA VPS, a partir da raiz do repo, como o
# usuario `deploy` (o que ja esta no grupo docker):
#
#   git pull && deploy/deploy.sh
#   FORCE=1 deploy/deploy.sh     # faz o deploy mesmo com lives sendo moderadas
#                                # (derruba essas sessoes; a fila em memoria se perde)
#
# O que faz, em ordem (para na primeira falha):
#   1. garante a chave que cifra o token do robo (secrets/sm_token_key)
#   2. backup consistente do SQLite (API de backup + integrity_check)
#   3. etiqueta as imagens em uso (atila-rollback/...) para o rollback
#   4. builda as imagens novas (nada e derrubado ainda)
#   5. GATE: recusa trocar o backend se houver sessao de moderacao ativa
#   6. troca so backend e web (--no-deps) e recarrega a config do nginx do cata-pobre
#   7. teste de fumaca; se falhar, diz como voltar (deploy/rollback.sh)
#
# NUNCA roda `docker compose down` (remove a rede `internal`; o proxy SOCKS5 preso
# ao gateway 172.28.0.1 entra em loop) e NUNCA recria containers do cata-pobre -
# so um `nginx -s reload`, que valida a config antes de aplicar e, se ela estiver
# invalida, mantem a antiga rodando.
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077

STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=${BACKUP_DIR:-$HOME/atila-backups}
BACKEND=atilas_client_backend
WEB=atilas_client_web
CATA_NGINX=${CATA_NGINX:-cata_pobre_nginx}
FORCE=${FORCE:-0}

say() { printf '\n==> %s\n' "$*"; }
running() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null || echo false)" = true ]; }

mkdir -p "$BACKUP_DIR"

say "1/7 chave de cifra do token do robo"
if [ ! -s secrets/sm_token_key ]; then
  mkdir -p secrets
  chmod 700 secrets
  # 32 bytes aleatorios em base64 url-safe = formato de chave Fernet
  openssl rand -base64 32 | tr '+/' '-_' | tr -d '\n' > secrets/sm_token_key
  chmod 400 secrets/sm_token_key
  echo "Chave criada em secrets/sm_token_key."
  echo "GUARDE UMA COPIA FORA DESTA VPS (cofre de senhas). Sem ela, os tokens"
  echo "cifrados dos robos nao abrem e cada robo precisa ser reconectado."
fi

if running "$BACKEND"; then
  say "2/7 backup do banco (consistente, com integrity_check)"
  docker exec "$BACKEND" python -c "
import os, sqlite3
src = sqlite3.connect(os.environ.get('SM_DB_PATH', '/data/super_moderator.db'))
dst = sqlite3.connect('/tmp/backup.db')
src.backup(dst)
result = dst.execute('PRAGMA integrity_check').fetchone()[0]
assert result == 'ok', result
print('integrity_check:', result)
"
  docker cp "$BACKEND:/tmp/backup.db" "$BACKUP_DIR/atila-$STAMP.db"
  docker exec "$BACKEND" rm -f /tmp/backup.db
  chmod 600 "$BACKUP_DIR/atila-$STAMP.db"
  echo "backup: $BACKUP_DIR/atila-$STAMP.db  (contem dados de contas: mantenha 600, apague quando nao precisar)"

  say "3/7 etiquetando as imagens atuais para rollback"
  for c in "$BACKEND" "$WEB"; do
    docker tag "$(docker inspect -f '{{.Image}}' "$c")" "atila-rollback/$c:$STAMP"
  done
  echo "$STAMP" > "$BACKUP_DIR/last-deploy"
else
  say "2-3/7 backend nao esta rodando: sem backup/etiqueta (primeiro deploy?)"
  # um last-deploy antigo faria o rollback restaurar um banco de dias atras
  rm -f "$BACKUP_DIR/last-deploy"
fi

say "4/7 build das imagens novas (nada e derrubado ainda)"
docker compose build

# o container roda como `appuser`; a chave (modo 400) precisa pertencer a esse uid
# (docker run direto na imagem: `compose run` tentaria pegar o IP fixo do backend, que ja esta em uso)
BACKEND_IMAGE=$(docker compose config --images | grep -- '-backend$' | head -n1)
BACKEND_UID=$(docker run --rm --no-healthcheck --entrypoint id "$BACKEND_IMAGE" -u | tr -d '\r')
docker run --rm -v "$PWD/secrets:/s" --entrypoint chown nginx:alpine "$BACKEND_UID" /s/sm_token_key

if running "$BACKEND"; then
  say "5/7 gate: ha moderacao em andamento?"
  active=$(docker exec "$BACKEND" python -c "
import json, os, sys, urllib.request
key = os.environ.get('HEALTHBOT_API_KEY', '')
if not key:
    print('sem-chave'); sys.exit(0)
req = urllib.request.Request('http://127.0.0.1:8000/ops/active_sessions', headers={'X-Healthbot-Key': key})
print(json.load(urllib.request.urlopen(req, timeout=5))['active'])
" 2>/dev/null || echo erro)
  if [ "$active" = 0 ]; then
    echo "nenhuma sessao ativa."
  elif [ "$FORCE" = 1 ]; then
    echo "AVISO: sessoes ativas ($active) - FORCE=1, seguindo."
  else
    echo "ABORTADO: nao foi possivel confirmar que nao ha live sendo moderada (resposta: $active)."
    echo "Se a resposta e 'erro'/'sem-chave', o backend em execucao ainda nao tem o gate"
    echo "(primeiro deploy desta versao) ou HEALTHBOT_API_KEY nao esta no .env."
    echo "Confira o painel e rode de novo com FORCE=1 se puder derrubar as sessoes."
    exit 2
  fi
fi

say "6/7 trocando backend e web (so eles)"
docker compose up -d --no-deps backend
healthy=0
for _ in $(seq 1 45); do
  if [ "$(docker inspect -f '{{.State.Health.Status}}' "$BACKEND" 2>/dev/null || echo none)" = healthy ]; then
    healthy=1; break
  fi
  sleep 2
done
if [ "$healthy" != 1 ]; then
  echo "FALHOU: o backend novo nao ficou saudavel em 90s (docker logs $BACKEND)."
  echo "O web antigo continua no ar. Para voltar: deploy/rollback.sh $STAMP"
  exit 1
fi
docker compose up -d --no-deps web
# o web ganha outro IP em proxy_shared a cada recriacao; o nginx do cata-pobre
# guarda o antigo ate recarregar. Recarregar so releia a config (sem derrubar nada).
if docker exec "$CATA_NGINX" nginx -t >/dev/null 2>&1 && docker exec "$CATA_NGINX" nginx -s reload 2>/dev/null; then
  echo "nginx do cata-pobre recarregado."
else
  echo "AVISO: nao consegui recarregar $CATA_NGINX; rode 'docker exec $CATA_NGINX nginx -s reload' como root se o site der 502."
fi

say "7/7 teste de fumaca"
sleep 3
fail=0
check() { # descricao, esperado, obtido
  if [ "$2" = "$3" ]; then echo "ok   $1 ($3)"; else echo "FALHOU $1: esperado $2, veio $3"; fail=1; fi
}
check "GET /api/health" 200 "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8088/api/health || echo 000)"
check "login invalido nao e 5xx" 401 "$(curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
  -d '{"username":"smoke-test-inexistente","password":"x"}' http://127.0.0.1:8088/api/auth/login || echo 000)"
check "live_status sem chave" 403 "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8088/api/robot/live_status || echo 000)"
logs=$(docker logs --since 2m "$BACKEND" 2>&1 || true)   # sem pipe: grep -q + pipefail da falso negativo
case "$logs" in *Traceback*) echo "FALHOU: ha Traceback nos logs recentes do backend"; fail=1 ;; esac
if ! grep -qE '^FORWARDED_ALLOW_IPS=.*,' .env 2>/dev/null; then
  echo "AVISO: FORWARDED_ALLOW_IPS no .env nao lista o IP do nginx do cata-pobre; o limite de login por IP"
  echo "       continua sendo um balde unico para todos (ver DEPLOY.md, secao 10)."
fi

if [ "$fail" != 0 ]; then
  echo
  echo "DEPLOY COM PROBLEMAS. Para voltar ao estado anterior (imagens + banco): deploy/rollback.sh $STAMP"
  exit 1
fi
echo
echo "Deploy concluido ($STAMP). Rollback, se precisar: deploy/rollback.sh $STAMP"
