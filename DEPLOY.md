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
```

Isso reconstrói e troca só os containers do Atila's Client — não toca no
cata-pobre. O banco (`backend_data`) é um volume nomeado: sobrevive ao
rebuild. Só `docker volume rm atilas-client_backend_data` apaga de verdade.

Se um dia o `nginx/atila.conf` precisar mudar, é só repetir o passo 3a (copiar
de novo) + 3d (rebuild só do nginx) — não precisa mexer no certbot de novo a
menos que o domínio mude.

## 7. Backup do banco

```bash
# como deploy
docker exec atilas_client_backend sh -c 'cat /data/super_moderator.db' > backup-$(date +%F).db
```
