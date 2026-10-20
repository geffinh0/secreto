# Atila's Client

Moderação automática de lives do SuperLive. Cada criadora (streamer) tem um **robô** que entra na live
dela, silencia ou expulsa quem usar palavras proibidas e envia mensagens recorrentes. Há um portal
para as criadoras (rotas do app) e um **painel administrativo** (`/admin`) para quem opera o serviço
(agências, usuárias, capacidade, IPs).

## O que vem neste pacote
| Pasta/arquivo | Para que serve |
|---|---|
| `backend/` | Servidor (Python, FastAPI, SQLite) |
| `lib/`, `web/`, `assets/`, `pubspec.yaml` | Aplicativo web/PWA (Flutter) |
| `docker-compose.yml`, `Caddyfile`, `deploy/` | Instalação em contêineres, com HTTPS automático |
| `install.sh` · `update.sh` · `backup.sh` · `restore.sh` | Instalar, atualizar, copiar e restaurar |
| `.env.example` | Configuração (copie para `.env`) |
| `docs/` | Guias (abaixo) |
| `SUPER_MODERATOR.md`, `docs/api/API_CATALOG.md` | Referência técnica do sistema e da API do SuperLive |

## Guias, na ordem em que você vai precisar
1. [Instalação](docs/INSTALACAO.md): do servidor zerado ao painel no ar.
2. [Operação do dia a dia](docs/OPERACAO.md): agências, usuárias, **adicionar IP**, backup, atualizar.
3. [Problemas comuns](docs/PROBLEMAS.md): o que olhar quando algo para.
4. [Como o sistema funciona](docs/ARQUITETURA.md): para quem for dar manutenção.
5. [Manutenção do SuperLive](docs/MANUTENCAO_SUPERLIVE.md): o risco principal e como reagir.

## Resumo em 5 linhas
- Cada IP de saída (proxy fixo brasileiro) atende **até 7 criadoras**. Mais criadoras = mais IPs.
- Um IP novo se adiciona pelo painel (Agências → Capacidade → **Adicionar IP**), sem reiniciar.
- As agências recebem um **código**; só quem tem o código consegue se cadastrar.
- Quando todos os IPs estão cheios, o cadastro mostra "estamos sem vagas".
- Faça `./backup.sh` com frequência e guarde `secrets/sm_token_key` fora do servidor.

## Testes
```bash
cd backend && pip install -r requirements.txt && python -m unittest discover -s tests -t .
flutter test
```
