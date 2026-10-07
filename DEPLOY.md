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

## 7. Backup do banco

```bash
# como deploy
docker exec atilas_client_backend sh -c 'cat /data/super_moderator.db' > backup-$(date +%F).db
```

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
virar spam) e responde `/status` na hora quando perguntado. Script em
`deploy/healthbot/healthbot.py`.

Token e chat_id ficam só num arquivo de ambiente na VPS, fora do git -
nenhum dos dois precisa (nem deve) ser colado no chat.

```bash
# 1. no Telegram: fala com @BotFather, /newbot, guarda o token
# 2. manda qualquer mensagem pro bot que acabou de criar

# 3. como deploy, na VPS - cria o venv e instala a única dependência
python3 -m venv ~/healthbot-venv
~/healthbot-venv/bin/pip install --quiet requests

# 4. cola o token recebido do BotFather (só ele por enquanto)
cat > ~/.healthbot.env <<'EOF'
TELEGRAM_BOT_TOKEN=COLE_O_TOKEN_AQUI
TELEGRAM_CHAT_ID=
EOF

# 5. descobre o chat_id a partir da mensagem que você mandou no passo 2
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
a lista de tudo. Se algo cair depois, ele avisa sozinho.
