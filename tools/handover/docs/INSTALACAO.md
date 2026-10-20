# Instalação

## O que você precisa
- **Um servidor Linux** (VPS) com 2 vCPU, 4 GB de RAM (8 GB é mais folgado), Docker e Docker Compose v2.
  Portas **80 e 443** liberadas.
- **Um domínio** apontando (registro A) para o IP do servidor.
- **Um ou mais proxies fixos brasileiros** (ISP/residencial estático, cobrança por IP, tráfego
  ilimitado, SOCKS5 ou HTTP com usuário e senha). IP rotativo ou de datacenter não serve: o token do
  robô fica preso ao IP em que foi criado, e o SuperLive pode estranhar IP de datacenter.
- Cada IP atende **7 criadoras**. Comece com o número de IPs que cubra suas primeiras agências.

## Passo a passo
```bash
# 1. no servidor, dentro da pasta do projeto
./install.sh            # na primeira vez cria o .env e pede para você preencher

# 2. preencha o .env (nano .env):
#    DOMAIN, ADMIN_BOOTSTRAP_PASSWORD (8+ caracteres, uma maiúscula, um especial)
#    SUPERLIVE_PROXY_URLS  (ex.: socks5h://usuario:senha@host:porta)

# 3. rode de novo
./install.sh
```
Ao terminar, ele mostra os endereços. O HTTPS é emitido sozinho (1 a 2 minutos na primeira vez).

- **Portal das criadoras:** `https://seu-dominio`
- **Painel administrativo:** `https://seu-dominio/admin` (usuário e senha do `.env`)

## Depois de instalar (faça hoje)
1. **Guarde uma cópia de `secrets/sm_token_key` fora do servidor** (gerenciador de senhas). Ela cifra os
   tokens dos robôs e os proxies adicionados pelo painel. Sem ela, todos precisam reconectar.
2. Entre no `/admin`, crie a primeira **agência** e anote o código.
3. Teste: cadastre uma conta de teste com o código, conecte um robô e confira que ele entra numa live.
4. Apague `ADMIN_BOOTSTRAP_USERNAME/PASSWORD` do `.env` se quiser (a conta admin já foi criada).
5. Agende `./backup.sh` (por exemplo, todo dia às 4h no `crontab -e`:
   `0 4 * * * cd /caminho/do/projeto && ./backup.sh`) e copie a pasta `backups/` para fora do servidor.

## Sobre os IPs
- IPs ficam em `SUPERLIVE_PROXY_URLS` (no `.env`) **ou** são adicionados pelo painel. Pode misturar,
  mas os do `.env` vêm primeiro e a ordem nunca pode mudar depois que há criadoras.
- Sem proxy (`ALLOW_DIRECT=1 ./install.sh`) o sistema roda só para teste.
