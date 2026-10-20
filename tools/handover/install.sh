#!/usr/bin/env bash
# Primeira instalação. Rode na pasta do projeto, num servidor com Docker e Docker Compose:
#   ./install.sh
set -euo pipefail
cd "$(dirname "$0")"
umask 077

command -v docker >/dev/null || { echo "Instale o Docker antes (https://docs.docker.com/engine/install/)."; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "Falta o Docker Compose v2 (comando 'docker compose')."; exit 1; }

if [ ! -f .env ]; then
  cp .env.example .env
  echo "Criei o arquivo .env. Preencha DOMAIN, ADMIN_BOOTSTRAP_PASSWORD e SUPERLIVE_PROXY_URLS"
  echo "(nano .env) e rode ./install.sh de novo."
  exit 0
fi

# lê só as chaves de que o script precisa (sem executar o conteúdo do .env)
val() { grep -E "^$1=" .env | head -n1 | cut -d= -f2- | tr -d '\r'; }
[ -n "$(val DOMAIN)" ] || { echo "Preencha DOMAIN no .env."; exit 1; }
[ -n "$(val ADMIN_BOOTSTRAP_PASSWORD)" ] || { echo "Preencha ADMIN_BOOTSTRAP_PASSWORD no .env."; exit 1; }
if [ -z "$(val SUPERLIVE_PROXY_URLS)" ] && [ "${ALLOW_DIRECT:-0}" != 1 ]; then
  echo "SUPERLIVE_PROXY_URLS está vazio. Sem proxy, o SuperLive enxerga o IP do servidor (de datacenter),"
  echo "que costuma ser tratado como VPN. Contrate um IP fixo brasileiro e preencha, ou rode"
  echo "ALLOW_DIRECT=1 ./install.sh apenas para testar."
  exit 1
fi

# chave que cifra o token do robô de cada criadora. GUARDE UMA CÓPIA FORA DO SERVIDOR.
if [ ! -s secrets/sm_token_key ]; then
  mkdir -p secrets && chmod 700 secrets
  openssl rand -base64 32 | tr '+/' '-_' | tr -d '\r\n' > secrets/sm_token_key
  chmod 400 secrets/sm_token_key
  echo "Chave criada em secrets/sm_token_key. GUARDE UMA COPIA FORA DESTE SERVIDOR: sem ela os"
  echo "robôs conectados precisam ser reconectados pelas criadoras."
fi

# chave interna usada pelo update.sh
if [ -z "$(val HEALTHBOT_API_KEY)" ]; then
  key=$(openssl rand -hex 24)
  if grep -qE '^HEALTHBOT_API_KEY=' .env; then
    sed -i "s/^HEALTHBOT_API_KEY=.*/HEALTHBOT_API_KEY=$key/" .env
  else
    printf '\nHEALTHBOT_API_KEY=%s\n' "$key" >> .env
  fi
fi

BUILD_ID="v1-$(date +%Y%m%d-%H%M%S)"; export BUILD_ID
docker compose build
# o container roda como usuário sem privilégio: a chave precisa pertencer a ele
IMG=$(docker compose config --images | grep -- '-backend$' | head -n1)
UID_APP=$(docker run --rm --no-healthcheck --entrypoint id "$IMG" -u | tr -d '\r')
docker run --rm -v "$PWD/secrets:/s" --entrypoint chown alpine:3 "$UID_APP" /s/sm_token_key
docker compose up -d

echo "Esperando o sistema subir..."
for _ in $(seq 1 45); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' atilas_client_backend 2>/dev/null || echo none)" = healthy ] && ok=1 && break
  sleep 2
done
[ "${ok:-0}" = 1 ] || { echo "O backend não ficou saudável. Veja: docker compose logs backend"; exit 1; }
echo
echo "Pronto. Painel das criadoras: https://$(val DOMAIN)   Painel administrativo: https://$(val DOMAIN)/admin"
echo "(o certificado HTTPS pode levar 1-2 min na primeira vez; o DNS do domínio precisa apontar para este servidor)"
