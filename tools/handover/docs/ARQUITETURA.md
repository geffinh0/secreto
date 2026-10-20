# Como o sistema funciona

```
Criadora/Admin (navegador)
        │ HTTPS
      Caddy ──► web (nginx: app Flutter + /api) ──► backend (FastAPI + SQLite)
                                                        │
                                       fila serial por IP de saída (proxy)
                                                        │
                                                    SuperLive (HTTP + WebSocket)
```

## Backend (`backend/`)
| Arquivo | Conteúdo |
|---|---|
| `main.py` | Rotas da API (portal, robô, admin), cadastro, capacidade, adicionar IP |
| `engine.py` | Sessão de moderação por criadora: WebSocket do chat, regras, mensagens automáticas, vigia da próxima live, limite por IP |
| `superlive.py` | Cliente da API do SuperLive, **fila serial por IP** (mute/kick furam a fila), pausa em falha de rede/429, telemetria |
| `db.py` | SQLite, migrações, atribuição de IP (slot) e vagas |
| `security.py` | Senhas, cifra dos tokens (Fernet), limite de tentativas |
| `tests/` | Testes de unidade e integração (rodam sem internet, com um SuperLive simulado) |

## Ideias que explicam as decisões
- **Um IP por criadora, fixo.** O SuperLive amarra o token ao IP. Ao se cadastrar, a criadora recebe o IP
  com menos gente (`users.egress_slot`) e nunca muda. A lista de IPs só cresce, nunca é reordenada.
- **7 criadoras por IP.** O SuperLive recusa duas ações simultâneas do mesmo IP, então tudo de um IP passa
  por uma fila serial. Medido com regras reais: com 7, mute/kick ficam em ~0,6 s (p95) e mensagens em ~5 s.
- **Prioridades:** banir/silenciar (urgente) passa na frente de mensagens, que passam na frente de consultas de fundo.
- **Segredos:** tokens de robô e URLs dos proxies adicionados pelo painel ficam cifrados no banco com
  `secrets/sm_token_key`.
- **Painel:** `/admin` usa contas separadas (`admin_accounts`), sem relação com as usuárias.

## Aplicativo (`lib/`)
Flutter Web/PWA. Telas em `lib/screens/` (auth, bot, moderação, mensagens, estatísticas, configurações, admin);
estado em `lib/providers/`; modelos e serviços em `lib/core/`; tema em `lib/core/theme/`.
O build gera um identificador (`BUILD_ID`) para forçar os navegadores a atualizar a cada versão.

Mais detalhes (rotas, regras de palavras, limitações): [../SUPER_MODERATOR.md](../SUPER_MODERATOR.md).
