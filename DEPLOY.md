# Deploy do Atila's Client numa VPS (Docker, isolado)

Isso sobe o portal + backend inteiros dentro de **dois containers Docker**, numa
rede interna própria, sem tocar em nada que já esteja rodando na VPS. O único
ponto exposto é `127.0.0.1:8088` (só acessível de dentro da própria VPS) - quem
expõe isso pro mundo é o reverse proxy que já existe aí, apontando um subdomínio
seu pra essa porta.

Eu não tenho como rodar isso por você: só recebi a chave **pública** SSH (a
privada, que autentica de verdade, nunca deve sair da sua máquina/VPS). Os
comandos abaixo são pra você rodar via `ssh root@187.77.235.245`. Se algo der
erro, cola a saída aqui que eu te ajudo a resolver.

## 1. Pré-requisitos na VPS

```bash
# Docker + Compose plugin, se ainda não tiver
curl -fsSL https://get.docker.com | sh
docker compose version   # confirma que o plugin "compose" está presente
```

## 2. Clonar e subir

```bash
cd /opt   # ou onde preferir manter os serviços
git clone https://github.com/geffinh0/secreto.git atilas-client
cd atilas-client
docker compose up -d --build
```

A primeira build demora alguns minutos (baixa a imagem do Flutter pra compilar
o portal). Depois disso:

```bash
docker compose ps                 # os dois serviços devem estar "running"
curl -s localhost:8088 | head -5  # deve devolver o HTML do portal
```

O banco (`backend_data`) é um volume Docker nomeado: sobrevive a
`docker compose down` e a rebuilds. Só `docker volume rm atilas-client_backend_data`
apaga de verdade (cuidado).

## 3. Apontar seu domínio

Na Hostinger, crie um registro **A** pro subdomínio que você quiser usar (ex.:
`atila.seudominio.com`) apontando pro IP da VPS: `187.77.235.245`.

Na VPS, o que já está rodando (nginx, Caddy, outro container, etc.) precisa
**encaminhar esse subdomínio pra `127.0.0.1:8088`**. Se for nginx "normal" no
host, um bloco assim resolve (ajuste o domínio):

```nginx
server {
    listen 80;
    server_name atila.seudominio.com;

    location / {
        proxy_pass http://127.0.0.1:8088;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

```bash
# depois de criar o arquivo acima em /etc/nginx/sites-available/atila.conf
ln -s /etc/nginx/sites-available/atila.conf /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

# HTTPS (obrigatório pro PWA instalar) via Let's Encrypt
certbot --nginx -d atila.seudominio.com
```

Se o que já roda na VPS for Caddy ou outro proxy (Traefik, etc.), me avisa qual
é que eu monto a config certa pra ele - a ideia é sempre a mesma: esse
subdomínio → `127.0.0.1:8088`, com HTTPS.

## 4. PWA (instalar como app)

Já está tudo pronto no código pra isso: `web/manifest.json` com nome, cores e
ícones (a raposinha, em `web/icons/Icon-*` e `web/icons/Icon-maskable-*`), e o
Flutter gera o service worker (`flutter_service_worker.js`) sozinho no build de
produção. A única coisa que falta pra funcionar é **servir via HTTPS** (passo
3 acima) - sem isso o navegador recusa o "Instalar app".

Depois do HTTPS no ar: abrir `https://atila.seudominio.com` no Chrome/Edge
(desktop ou Android) deve mostrar um ícone de instalação na barra de endereço;
no Android, o próprio navegador também costuma sugerir "Adicionar à tela
inicial" sozinho.

## 5. Atualizando depois de um novo push

```bash
cd /opt/atilas-client
git pull
docker compose up -d --build
```

Isso reconstrói as imagens e troca os containers sem perder o banco (que fica
no volume, fora dos containers).

## 6. Backup do banco

```bash
docker compose exec backend sh -c 'cat /data/super_moderator.db' > backup-$(date +%F).db
```
