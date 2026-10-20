#!/usr/bin/env bash
# Gera a versão para entregar ao comprador, numa pasta nova, SEM o histórico do git e sem nada da
# sua infraestrutura (VPS, túnel do notebook, cata-pobre, domínio, bot de monitoramento).
#
#   tools/make_handover.sh [pasta-destino]      (padrão: ../atilas-client-entrega)
#
# Copia os arquivos do projeto como estão agora (inclui o que ainda não foi commitado, exclui o
# que o .gitignore exclui), troca a instalação pela versão independente (tools/handover/),
# remove o que é só seu e troca nomes pessoais nos testes. Depois rode os testes dentro da pasta.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-../atilas-client-entrega}
[ ! -e "$OUT" ] || { echo "$OUT já existe: apague ou escolha outro destino."; exit 1; }
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

git ls-files -co --exclude-standard -z | grep -zv '^tools/handover/' | tar --null -T - -cf - | tar -xf - -C "$OUT"

cd "$OUT"
# só seu / específico da sua infraestrutura
rm -rf deploy/notebook-proxy deploy/healthbot deploy/nginx-cata-pobre-snippet.conf deploy/deploy.sh \
       deploy/rollback.sh DEPLOY.md PROJECT_STATUS.md FEATURE_COVERAGE.md README.md start.bat \
       start_local_test.bat .github docs/reverse-engineering tools/make_handover.sh .tribunal
# instalação independente + guias
SRC="$(cd - >/dev/null && pwd)/tools/handover"
cp "$SRC/docker-compose.yml" "$SRC/Caddyfile" "$SRC/.env.example" "$SRC/install.sh" "$SRC/update.sh" \
   "$SRC/backup.sh" "$SRC/restore.sh" "$SRC/LEIA-ME.md" .
mkdir -p docs && cp "$SRC"/docs/*.md docs/
chmod +x install.sh update.sh backup.sh restore.sh
# nomes pessoais em fixtures de teste e comentários
for f in test/widget_test.dart backend/tests/test_unit.py backend/tests/test_integration.py backend/engine.py backend/db.py; do
  [ -f "$f" ] || continue
  sed -i -e 's/geffinho/ana/g; s/Geffinho/Ana/g; s/Nyx/Bia/g; s/nyx/bia/g' \
         -e 's/cata-pobre nginx/front nginx/g; s#deploy/notebook-proxy/#o proxy#g' "$f"
done

# varredura final: nada pessoal pode ter ficado
if grep -rnIE "187\.77\.|atilaclient|cata[-_]pobre|geffinh|atila_deploy|notebook-proxy|hostinger" \
     --exclude-dir=.git --exclude-dir=build --exclude-dir=.dart_tool . ; then
  echo "ATENÇÃO: as linhas acima ainda citam algo pessoal; revise antes de entregar." >&2
  exit 1
fi
echo "Pronto: $OUT"
echo "Confira: (cd $OUT/backend && python -m unittest discover -s tests -t .) && (cd $OUT && flutter test)"
