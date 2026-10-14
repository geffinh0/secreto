# Deploy do Atila's Client numa VPS (Docker, isolado do cata-pobre)

Domínio: **atilaclient.tech** (Hostinger, separado do catapobre.com.br).

Levantamento feito na VPS (187.77.235.245): o que já roda lá é o **cata-pobre**
(`/root/cade_o_cata_pobre/`) — nginx, app Node e um servidor de IA, todos em
Docker, nginx ocupando as portas 80/443. Nada disso é tocado por este deploy:
o Atila's Client sobe em containers **próprios**, numa rede interna **própria**,
e se conecta ao nginx do cata-pobre só através de uma rede Docker
**compartilhada** (`proxy_shared`) — já criada, sem host port juggling nem
`host.docker.internal`.

Tudo que precisa de acesso a `/root/cade_o_cata_pobre/` (que o usuário
`deploy` não tem, de propósito) fica marcado abaixo como **"rodar como
root"**. O resto eu já rodo/testei direto com o acesso que tenho.

## 1. DNS (Hostinger)

Registro **A** pra `atilaclient.tech` e outro pra `www.atilaclient.tech`,
ambos apontando pra `187.77.235.245`. Pode levar alguns minutos pra propagar
— o passo 3 (certbot) só funciona depois que isso já resolver.

## 2. Subir o Atila's Client (não depende do passo 3/DNS pra funcionar localmente)

Como `deploy` (`ssh -i ~/.ssh/atila_deploy deploy@187.77.235.245`):

```bash
cd /home/deploy
git clone https://github.com/geffinh0/secreto.git atilas-client
cd atilas-client
docker compose up -d --build
docker compose ps                     # os dois serviços "running"
curl -s localhost:8088 | head -5      # devolve o HTML do portal
```

A rede `proxy_shared` já existe (`docker network create proxy_shared`, já
rodei). O `docker-compose.yml` já está configurado pra usá-la.

## 3. Encaixar no nginx do cata-pobre (rodar como root)

Isso adiciona um arquivo **novo** (`nginx/atila.conf`, copiado do repo que
você acabou de clonar) e **uma linha** no Dockerfile deles — não edita
`app.conf`, `common.conf` nem nenhum dos outros. `docker compose up -d nginx`
só recria o container `nginx`; `app` e `ia` continuam rodando do jeito que
estão, sem interrupção.

```bash
# 3a. copiar o bloco de servidor (já com o domínio certo)
cp /home/deploy/atilas-client/deploy/nginx-cata-pobre-snippet.conf \
   /root/cade_o_cata_pobre/nginx/atila.conf

# 3b. uma linha a mais no Dockerfile, logo depois das outras COPY do nginx
#     (dentro do estágio "nginx_final")
sed -i '/COPY nginx\/security_headers.conf/a COPY nginx/atila.conf /etc/nginx/conf.d/atila.conf' \
    /root/cade_o_cata_pobre/Dockerfile
grep -B1 -A1 "atila.conf" /root/cade_o_cata_pobre/Dockerfile   # confirma a linha certa

# 3c. certificado (mesmo método webroot que o catapobre.com.br já usa)
certbot certonly --webroot -w /var/www/certbot -d atilaclient.tech -d www.atilaclient.tech --key-type ecdsa

# 3d. rebuild só do nginx e troca sem derrubar app/ia
cd /root/cade_o_cata_pobre
docker compose build nginx
docker compose up -d nginx
docker compose ps          # confirma: app e ia com o mesmo "CREATED" de antes
```

O certbot já tem um timer systemd cuidando da renovação de tudo que está em
`/etc/letsencrypt/renewal/` — o certificado novo entra nesse mesmo ciclo
automaticamente, nada a mais pra configurar.

## 4. Conferir

```bash
curl -sI https://atilaclient.tech | head -5
```

Deve devolver `HTTP/2 200` e vir do nginx deles (não do meu `:8088` direto).

## 5. PWA (instalar como app)

Já está tudo pronto no código: `web/manifest.json` com nome, cores e a
raposinha como ícone (normal e "maskable"), e o Flutter gera o service worker
sozinho no build de produção. A única coisa que faltava era servir via
HTTPS — e isso o passo 3 resolve.

Depois do HTTPS no ar: abrir `https://atilaclient.tech` no Chrome/Edge mostra
um ícone de instalação na barra de endereço; no Android o navegador também
costuma sugerir "Adicionar à tela inicial" sozinho.

## 6. Atualizando depois de um novo push

```bash
# como deploy
cd /home/deploy/atilas-client
git pull
docker compose up -d --build

# o container web (ou o backend) troca de IP na rede proxy_shared a cada
# rebuild - o nginx do cata-pobre guarda o IP antigo em cache até recarregar,
# e devolve 502 até isso acontecer. deploy já está no grupo docker, então dá
# pra recarregar sem precisar de root:
docker exec cata_pobre_nginx nginx -s reload
```

Isso reconstrói e troca só os containers do Atila's Client — não toca no
cata-pobre (o `nginx -s reload` acima só recarrega a config, não derruba
nada). O banco (`backend_data`) é um volume nomeado: sobrevive ao rebuild.
Só `docker volume rm atilas-client_backend_data` apaga de verdade.

Se um dia o `nginx/atila.conf` precisar mudar, é só repetir o passo 3a (copiar
de novo) + 3d (rebuild só do nginx) — não precisa mexer no certbot de novo a
menos que o domínio mude.

## 6b. Atualização para todos (cache dos navegadores)

Antes, o nginx deixava **todos** os arquivos do app em cache por 7 dias (só
`index.html`, service worker e manifest eram revalidados), então quem já tinha
o site aberto ou instalado podia ficar até uma semana na versão velha. Agora
cada deploy tem um **`BUILD_ID`** (`<git sha>-<data-hora>`, definido por
`deploy/deploy.sh`) e a atualização chega por quatro caminhos:

1. **nginx** (`deploy/nginx.conf`): tudo é `no-cache`, isto é, o navegador
   guarda mas pergunta ao servidor a cada uso (ETag, resposta 304 barata).
   `build.json` é `no-store`.
2. **URLs com versão:** `index.html` carrega `flutter_bootstrap.js?v=<BUILD_ID>`
   e esse arquivo carrega `main.dart.js?v=<BUILD_ID>`. URL nova = o navegador
   busca o arquivo novo, mesmo com cópia velha no cache.
3. **Limpeza única por versão:** o `index.html` guarda o build em
   `localStorage` (`app_build`). Se for diferente, desregistra o service worker
   e apaga o Cache Storage antigo e recarrega uma vez (trava anti-loop em
   `sessionStorage`). O login (`localStorage` do Flutter) **não** é tocado. O
   nginx também manda `Clear-Site-Data: "cache"` até o navegador ter o cookie
   `app_build` igual ao build atual (limpa o cache HTTP velho uma vez; Safari
   ignora o cabeçalho e depende das URLs com versão).
4. **Aviso com o app aberto:** a página consulta `/build.json` a cada 5 min e
   quando a aba volta ao foco. Se o build do servidor for outro, o app mostra
   "Há uma nova versão do app" com o botão **Atualizar agora** (limpa o
   service worker/caches e recarrega).

Quem estiver no app antigo (sem esse esquema) recebe o `index.html` novo na
próxima abertura (ele já era `no-cache`) e entra no caminho 3.

Para testar localmente sem Docker: `flutter build web`, troque `@@BUILD_ID@@`
em `build/web/index.html` por um valor qualquer e crie `build/web/build.json`
com `{"build":"mesmo-valor"}`; mudar o `build.json` simula um deploy novo.
Em `flutter run` o token não é trocado e o esquema fica desligado.

## 7. Backup do banco

O banco roda em modo WAL (`journal_mode=WAL`, ver `backend/db.py`), então um
`cat` direto no arquivo pode sair sem as transações mais recentes (que ainda
estão só no `-wal`) ou corrompido. Uso o backup via API do próprio SQLite
(`sqlite3.Connection.backup`), que é seguro mesmo com o banco em uso - a
imagem `python:3.12-slim` já traz o módulo `sqlite3` do Python, mas não o CLI
`sqlite3`, por isso o comando é via `python -c` em vez de `sqlite3 .backup`:

```bash
# como deploy
docker exec atilas_client_backend python -c "
import sqlite3
src = sqlite3.connect('/data/super_moderator.db')
dst = sqlite3.connect('/tmp/backup.db')
src.backup(dst)
dst.close()
src.close()
"
docker cp atilas_client_backend:/tmp/backup.db backup-$(date +%F).db
docker exec atilas_client_backend rm /tmp/backup.db
```

Teste a restauração de vez em quando (`docker cp` o arquivo pra um container
novo e confirme que abre) - um backup nunca testado não é um backup.

## 8. Proxy residencial (notebook) para o SuperLive

O SuperLive marca o IP desta VPS como "VPN" em alguns endpoints (ex: a busca
por ID público da streamer), porque é um IP de datacenter. A correção é
rotear as chamadas ao SuperLive por um túnel SSH reverso até o notebook do
Gefferson, que sai pela internet residencial dele — ver scripts em
`deploy/notebook-proxy/`.

Como funciona (duas pernas de SSH):

1. **Notebook → VPS**: o notebook abre `ssh -R 2222:127.0.0.1:22 deploy@VPS`
   (script `tunnel.ps1`, rodando em segundo plano via Tarefa Agendada do
   Windows, reconecta sozinho se cair). Isso faz a porta 2222 da VPS "ecoar"
   pro sshd do notebook.
2. **VPS → notebook**: um serviço systemd (`atila-notebook-proxy.service`) na
   VPS roda `ssh -D 172.28.0.1:1080 -p 2222 deploy@localhost`, abrindo um
   proxy SOCKS5 que sai pela internet do notebook. `172.28.0.1` é o gateway
   fixo da rede `internal` deste compose (ver `docker-compose.yml`) — só os
   containers desta stack alcançam, nunca a internet.
3. O backend lê `SUPERLIVE_PROXY_URL=socks5h://172.28.0.1:1080` e passa TODAS
   as chamadas HTTP e o WebSocket do SuperLive por ele (`backend/superlive.py`,
   `backend/engine.py`).

Cada ponta usa uma chave SSH dedicada, sem shell, só com permissão de abrir
túnel (`restrict,permitlisten`/`restrict,port-forwarding`) — nenhuma delas dá
acesso a mais nada além disso.

**Importante**: com isso, o robô passa a depender do notebook estar ligado,
conectado e logado. Se o notebook desligar, dormir ou perder internet, a
moderação para até ele voltar. Vale desativar o modo de suspensão (pelo menos
na tomada) pra não derrubar isso à toa:

```powershell
powercfg /change standby-timeout-ac 0
```

Instalação (uma vez só):

```bash
# no notebook, como Administrador (botão direito > Executar como administrador)
# cole o conteudo de deploy/notebook-proxy/setup_elevated.ps1

# na VPS, como root
# Libera o gateway da rede Docker interna pra acessar a porta do proxy SOCKS5
ufw allow from 172.28.0.0/24 to 172.28.0.1 port 1080 proto tcp comment 'Atila notebook SOCKS5 proxy from Docker'
cp deploy/notebook-proxy/atila-notebook-proxy.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now atila-notebook-proxy
systemctl status atila-notebook-proxy
```

## 9. Bot do Telegram com o status de tudo

Fica de olho nos containers, no túnel do notebook, no proxy SOCKS5 e nos dois
domínios — avisa sozinho quando algo muda de estado (só quando muda, pra não
virar spam) e responde a comandos na hora: `/status` (infra), `/live`
(status da transmissão agora) e `/resumo` (última live encerrada). Script em
`deploy/healthbot/healthbot.py`.

Token, chat_id e a chave do `/live`/`/resumo` ficam só em arquivos de
ambiente na VPS, fora do git - nenhum dos três precisa (nem deve) ser colado
no chat.

```bash
# 1. no Telegram: fala com @BotFather, /newbot, guarda o token
# 2. manda qualquer mensagem pro bot que acabou de criar

# 3. como deploy, na VPS - cria o venv e instala a única dependência
python3 -m venv ~/healthbot-venv
~/healthbot-venv/bin/pip install --quiet requests

# 4. gera a chave que protege /robot/live_status (esse endpoint não tem
#    login de portal, então usa um segredo compartilhado em vez disso)
HEALTHBOT_KEY=$(openssl rand -hex 32)

# 5. cola o token recebido do BotFather e a chave gerada acima
cat > ~/.healthbot.env <<EOF
TELEGRAM_BOT_TOKEN=COLE_O_TOKEN_AQUI
TELEGRAM_CHAT_ID=
HEALTHBOT_API_KEY=$HEALTHBOT_KEY
EOF

# 6. a MESMA chave precisa estar no .env do docker-compose (raiz do repo,
#    fora do git), pro backend aceitar - sem isso /live e /resumo voltam
#    "não foi possível obter o status"
echo "HEALTHBOT_API_KEY=$HEALTHBOT_KEY" >> ~/atilas-client/.env
# 6b. Só necessário quando houver MAIS DE UMA usuária com robô ativo ao mesmo
#     tempo: fixa de qual delas é o status que o bot reporta. Com uma única
#     usuária ativa (caso comum hoje) pode deixar de fora - o endpoint se
#     resolve sozinho; com mais de uma e isso vazio, ele recusa (503) em vez
#     de adivinhar. O ID é o `id` da conta de portal (tabela users).
# echo "HEALTHBOT_TARGET_USER_ID=1" >> ~/atilas-client/.env
cd ~/atilas-client && docker compose up -d --build backend

# 7. descobre o chat_id a partir da mensagem que você mandou no passo 2
set -a; source ~/.healthbot.env; set +a
curl -s "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/getUpdates" | python3 -m json.tool
# procura "chat": {"id": ...} no resultado e completa TELEGRAM_CHAT_ID em ~/.healthbot.env
```

Depois, como root, instala o serviço:

```bash
cp /home/deploy/atilas-client/deploy/healthbot/atila-healthbot.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now atila-healthbot
systemctl status atila-healthbot
```

Manda `/status` pro bot no Telegram pra testar - deve responder na hora com
a lista de tudo. `/live` e `/resumo` só têm o que mostrar depois da próxima
live. Se algo cair depois, o bot avisa sozinho.

## Painel administrativo (`/admin`)

Login próprio, separado das contas de portal - sem is_admin, sem cadastro
público. A primeira (e única, por enquanto) conta é criada automaticamente
no startup do backend a partir de duas variáveis de ambiente; depois disso
vira um no-op permanente (não sobrescreve a conta existente a cada restart).

```bash
# gera uma senha forte e cola no .env do docker-compose (raiz do repo, fora do git)
ADMIN_PASS=$(openssl rand -base64 18)
cat >> ~/atilas-client/.env <<EOF
ADMIN_BOOTSTRAP_USERNAME=geffinho
ADMIN_BOOTSTRAP_PASSWORD=$ADMIN_PASS
EOF
echo "Senha do painel admin: $ADMIN_PASS"   # guarda em algum lugar seguro - só aparece aqui

cd ~/atilas-client && docker compose up -d --build backend
```

Acessa em `https://SEU_DOMINIO/#/admin` com esse usuário/senha. As duas
variáveis podem continuar no `.env` depois disso sem problema - só criam a
conta na primeira vez que `admin_accounts` estiver vazia.

## 10. Deploy seguro, rollback, IP real e SOCKS restrito

- **Deploy**: `git pull && deploy/deploy.sh`. Cria `secrets/sm_token_key` (guarde cópia fora da VPS), faz backup do SQLite com `integrity_check`, etiqueta as imagens atuais, builda, recusa trocar se houver live sendo moderada (`FORCE=1` ignora), troca só backend e web, recarrega o nginx do cata-pobre e roda teste de fumaça. Nunca use `docker compose down`.
- **Rollback**: `deploy/rollback.sh [carimbo]`. Volta imagens E banco (a versão nova guarda token do robô cifrado e sessões em hash; a imagem antiga não entende). O banco atual é salvo antes.
- **IP real no login**: adicione ao `.env` `FORWARDED_ALLOW_IPS=172.28.0.10,<IP do nginx do cata em proxy_shared>` (`docker network inspect proxy_shared`; fixe esse IP no compose do cata, senão ele muda ao recriar). Sem o IP do cata tudo continua como antes (um único balde), nunca pior. Nunca use `*` nem sub-rede.
- **SOCKS**: troque a regra do ufw da sub-rede inteira por `ufw allow from 172.28.0.11 to 172.28.0.1 port 1080 proto tcp`. No notebook, rode `setup_elevated.ps1 -PermitOpen "host:443,..."` depois de levantar os hosts reais nos logs (`superlive websocket host`).
- **Limites de login**: usuário = 8 falhas/5 min; IP = 50 (`SM_LOGIN_IP_MAX`). Sem o IP do cata em `FORWARDED_ALLOW_IPS` o balde de IP é um só para todos, então 50 falhas de qualquer origem travam o login de todos por 5 min; com ele configurado, pode baixar `SM_LOGIN_IP_MAX` para 10-15.
- **Backups antigos**: os feitos antes desta versão ainda contêm tokens de sessão em claro (e o token do robô). Apague-os depois de validar o primeiro deploy.
- **Ler a chave depois do 1o deploy**: `secrets/sm_token_key` passa a pertencer ao uid do container (modo 400). Para copiá-la: `docker run --rm -v "$PWD/secrets:/s:ro" --entrypoint cat nginx:alpine /s/sm_token_key` (ou `sudo cat`).

## 11. Agências, cadastro por código e capacidade (10 agências / 500 criadoras)

**Cadastro.** `SM_ALLOW_REGISTRATION` agora vem ligado (`1`), mas ninguém se cadastra sem um
**código de agência**. No painel admin, aba **Agências → Nova agência**: o servidor gera o código
(8 caracteres, ex. `AB3K-9XQ2`); você manda para a agência e cada criadora digita no cadastro.
Por agência o painel mostra: cadastradas, com robô conectado, com a "favorita" ligada e
**moderando agora**. Pausar uma agência (chave) só bloqueia cadastros novos; as já cadastradas
seguem. "Gerar novo código" invalida o antigo se ele vazar. Quem se cadastrou antes aparece em
"Sem agência". Chutar códigos é limitado (`SM_REGISTER_IP_MAX`, 20 erros/10 min por IP) e o erro é o
mesmo para código inexistente e agência pausada. Fechar de vez: `SM_ALLOW_REGISTRATION=0` no `.env`.

**Uma conta SuperLive = uma criadora do portal.** Conectar uma conta que já está ligada a outra
criadora devolve 409 (`SM_ALLOW_SHARED_ROBOT=1` desliga a regra, só para testes).

**Códigos por SMS/e-mail.** Mínimo de 60 s entre envios e 10 por dia por criadora
(`SM_CODE_SEND_MIN_GAP`, `SM_CODE_SEND_DAILY_MAX`).

**Capacidade: o limite é o IP de saída, não o servidor.** Cada IP de saída (hoje só o do
notebook) aguenta, medido, ~1,7 requisições/s (1/(L + 0,35 s), com L ≈ 0,24 s por chamada) e
~18 mensagens de chat/min (3 s + L entre mensagens; a SuperLive recusa duas ações no mesmo
instante vindas do mesmo IP, por isso a fila é serial por IP). O que isso permite:

| IPs de saída | Lives moderadas ao mesmo tempo | Quanto o robô demora para perceber que uma criadora entrou ao vivo (500 criadoras) |
|---|---|---|
| 1 (hoje) | ~15 (ver medição abaixo) | quente ~2 min · normal ~4 min · fria ~15 min (ou na hora, com o botão) |
| 3 | ~45 | quente ~40 s · normal ~1,3 min · fria ~5 min |
| 5 | ~75 | quente ~25 s · normal ~45 s · fria ~3 min |

"Quente" = costuma entrar ao vivo nesta hora do dia (3 dos últimos 21 dias, ±1 h) ou acabou de
encerrar uma live; "fria" = nenhuma live nos últimos 14 dias; o resto é "normal". O robô aprende
isso sozinho pelo histórico de atividade. Em qualquer caso a criadora pode apertar **"Entrei ao
vivo"** no app: o robô entra em instantes (1 aperto a cada 30 s). Enquanto a criadora está ao vivo
ou aguardando a próxima live, só o vigia pergunta se ela está no ar (antes eram três laços
perguntando a mesma coisa). Valores calculados pela mesma fórmula do código (orçamento
`SM_POLL_BUDGET_RPS`, 2 req/s por IP), com 15% quentes, 55% normais e 30% frias.

**Medição (coleta de 17 h com 1 live, `tools/pacing_sim.py`).** Cerca de 96% das chamadas eram
consultas de perfil de uma sessão ociosa, em par, a cada ~20,6 s (0,096/s por sessão): com 25
sessões isso já passa da capacidade serial, e as mensagens esperam sem limite (mute/kick não: eles
furam a fila, p95 ≈ 1 s). Na simulação o IP sustenta ~12 lives sem folga e satura perto de 16;
por isso o painel sugere 15 por IP (`SM_SUGGESTED_SESSIONS_PER_EGRESS`) até a coleta mostrar mais.
O trace (`SUPERLIVE_PACING_LOG_FILE`, `/data/pacing.jsonl`) e o resumo no log (a cada 60 s) mostram
espera na fila por prioridade, tempo de chamada (L), erros e 429; `/admin/capacity` traz `pacing` e
`lookup`. Chaves de ajuste (todas no `docker-compose.yml`): `SUPERLIVE_DEDUPE_LOOKUP` (1 = pula a
2ª consulta de perfil quando é a mesma conta), `SUPERLIVE_NETWORK_COOLDOWN` (pausa as consultas de
fundo após 3 falhas de rede seguidas; mute/kick e mensagens nunca são puladas),
`SUPERLIVE_SESSION_POLL_S` (intervalo do "já entrou ao vivo?" por sessão; é também o maior atraso
para notar uma live nova), `SUPERLIVE_MESSAGE_FROM_START` e `SUPERLIVE_PACING_FROM_START` (contam o
espaçamento do início da chamada anterior; aumentam a taxa de requisições, ficam desligadas até
o trace mostrar folga).

Como crescer: some proxies à lista `SUPERLIVE_PROXY_URLS` no `.env` (o **primeiro** tem de ser o
atual, `socks5h://172.28.0.1:1080`; quem já tem robô continua nele) e suba `SM_MAX_SESSIONS`
(15 por IP até medir mais). Cada criadora é fixada num IP quando conecta o robô (o menos carregado) e nunca é
trocada, porque a SuperLive amarra o token ao IP. A aba Agências mostra IPs, lives agora,
fila mais longa e o tempo de detecção. Fila longa ou "lives agora" colado no máximo = hora de
pôr outro IP. Sem pool nada muda: tudo sai pelo proxy único, e o intervalo de verificação
das favoritas passa a crescer sozinho (`SM_POLL_BUDGET_RPS`, 2 req/s por IP) em vez de a fila
explodir.

**nginx do web.** Lê o IP real do visitante (`X-Forwarded-For` só da rede docker) e limita
`/api/auth/*` e `/api/admin/login` (5 req/s por IP, rajada 20) e `/api/robot/connect*` (1 req/s,
rajada 10), com resposta 429. Antes todo mundo parecia vir do proxy e dividia um único balde de
falhas de login.

**Healthbot.** Além de "porta 1080 aberta", testa uma requisição HTTPS de verdade pela saída
(`HEALTHBOT_SOCKS_PROXIES`, lista `host:porta`; `HEALTHBOT_EGRESS_URL`). Se o notebook cair, o
robô não encerra a sessão em 3 min: fica tentando por ~1 h mostrando "saída de rede (proxy)
indisponível".
