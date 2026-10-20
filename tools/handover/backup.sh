#!/usr/bin/env bash
# Backup consistente do banco (contas, regras, mensagens). Rode quando quiser; o update.sh já roda antes de atualizar.
# Guarde cópias fora do servidor: o arquivo tem dados de contas.
set -euo pipefail
cd "$(dirname "$0")"
umask 077
mkdir -p backups
F="backups/atila-$(date +%Y%m%d-%H%M%S).db"
docker exec atilas_client_backend python -c "
import os, sqlite3
src = sqlite3.connect(os.environ.get('SM_DB_PATH', '/data/super_moderator.db'))
dst = sqlite3.connect('/tmp/backup.db'); src.backup(dst)
assert dst.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'"
docker cp atilas_client_backend:/tmp/backup.db "$F"
docker exec atilas_client_backend rm -f /tmp/backup.db
echo "Backup salvo em $F"
# mantém só os 30 mais recentes
ls -1t backups/atila-*.db | tail -n +31 | xargs -r rm -f
