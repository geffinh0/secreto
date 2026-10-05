# Super Moderator — Documentação Técnica

## Visão geral

Portal Flutter Web + backend FastAPI/SQLite que **modera lives do SuperLive automaticamente**.
Uma conta "robô" do SuperLive entra na live, lê o chat em tempo real e aplica as regras da
criadora: silencia (mute) ou bane (kick) quem usar palavras proibidas e envia mensagens
recorrentes.

**O robô roda no backend, não no navegador.** O portal só configura e acompanha. Fechar a
aba não interrompe a moderação; o que importa é o servidor (`python main.py`) estar ligado.

```
 Flutter Web (portal)  ──HTTP──►  FastAPI (backend/main.py)  ──HTTP + WebSocket──►  SuperLive
   regras, mensagens,              contas, regras, robô,                            (conta do robô)
   controle e status               motor de moderação (engine.py)
```

## Estrutura

```
backend/
├── main.py            # API: auth, regras, mensagens, configurações, /robot/*
├── engine.py          # motor: sessão da live, WebSocket, regras, mensagens recorrentes
├── superlive.py       # cliente do SuperLive (HTTP + frames do WebSocket)
├── db.py              # SQLite, schema e migrações aditivas
├── security.py        # hash de senha (PBKDF2), limite de tentativas de login
├── requirements.txt
└── tests/             # unitários + integração com um SuperLive simulado
lib/                   # Flutter (providers, telas, modelos)
test/widget_test.dart  # testes do Flutter
start_server.bat       # sobe backend + Flutter Web
```

## Como iniciar

**Tudo de uma vez:** duplo clique em `start_server.bat`.

**Manual:**
```bash
cd backend
pip install -r requirements.txt
python main.py                      # http://localhost:8000  (docs em /docs)
```
```bash
flutter run -d web-server --web-port 3000 --web-hostname localhost
```
Abra http://localhost:3000.

Variáveis de ambiente do backend (todas opcionais):

| Variável | Padrão | Para quê |
|---|---|---|
| `SM_HOST` / `SM_PORT` | `127.0.0.1` / `8000` | onde a API escuta (só localhost por padrão) |
| `SM_DB_PATH` | `backend/super_moderator.db` | outro arquivo de banco |
| `SM_CORS_ORIGINS` | — | origens extras permitidas (localhost já é aceito) |
| `SM_RELOAD` | — | `1` liga o auto-reload (reinicia o robô a cada save de arquivo) |
| `SUPERLIVE_BASE_URL` | `https://api.sprlv-api.com/api/v1/` | API do SuperLive (**o `/api/v1/` é obrigatório**) |
| `SUPERLIVE_WS_URL` | vem de `user/settings` | força a URL do WebSocket |
| `SUPERLIVE_USER_AGENT` | `SuperLive/2.31.0 (...)` | User-Agent enviado |

O front usa `http://localhost:8000`; para outro endereço:
`flutter run ... --dart-define=API_URL=http://host:8000`.

## Usando

1. **Criar conta** no portal e entrar.
2. **Moderação:** cadastre palavras em *Silenciar* e *Banir*.
3. **Mensagens:** monte a fila, escolha o intervalo (mínimo 10 s) e ligue o envio automático.
4. **Robô:** conecte a conta do robô no SuperLive — e-mail/senha, **celular** (SMS) ou
   token da sessão —, informe o **ID da live** e clique em *Iniciar moderação*. Se só
   tiver o **ID público do perfil** dela (ex.: `69622983`), use a busca "ID público da
   streamer": se ela estiver ao vivo, o ID da live é preenchido sozinho.
5. **A streamer precisa adicionar o robô como moderador da live**; sem isso o SuperLive
   recusa mute/kick (o portal mostra o erro e continua registrando as tentativas).

### Como as palavras são comparadas
- Comparação por **palavra inteira** (ou frase inteira), sem diferenciar maiúsculas, acentos
  nem espaços repetidos: `passa zap` pega "Me PASSA   ZÁP?", mas não "passa o zap";
  `ass` não pega "passar".
- `*` no fim vira prefixo: `puta*` pega "putaria" mas não "computador".
- Se uma mensagem casa com regras de silenciar e de banir, vale **banir**.
- Nunca são moderados: o próprio robô e a streamer da live.
- Cada usuário é punido uma vez por sessão (silenciar → banir é permitido, repetir não).
- *Banimento permanente* (opção na tela de Moderação) usa `permanent: true` no kick.
- Mudar regras/opções durante a live vale em poucos segundos.

## API do portal

Autenticação: `Authorization: Bearer <token>` (sessões expiram em 30 dias).
Cada usuário só acessa os próprios dados (`403`/`404` caso contrário).
Erros de validação sempre voltam como `{"detail": "texto legível"}`.

| Método | Endpoint | Descrição |
|---|---|---|
| POST | `/auth/register`, `/auth/login` | criar conta / entrar |
| GET | `/auth/me` | dados da sessão |
| POST | `/auth/logout` | encerra a sessão no servidor |
| GET/POST | `/moderation/rules` | listar (`?user_id=`) / criar |
| PUT/DELETE | `/moderation/rules/{id}` | atualizar / remover |
| GET/POST | `/messages` | listar (`?user_id=`) / criar |
| PUT/DELETE | `/messages/{id}` | atualizar / remover |
| GET | `/settings?user_id=` | configurações |
| PUT | `/settings/{user_id}` | atualização **parcial** das configurações |
| POST | `/robot/connect` | conecta o robô: `{email,password}` **ou** `{token}` |
| POST | `/robot/connect/phone/send_code` | `{phone_number,resend}` — envia o código por SMS |
| POST | `/robot/connect/phone/verify` | `{phone_number,code}` — confirma o código e conecta |
| POST | `/robot/disconnect` | para a sessão e esquece o robô |
| GET | `/robot/status` | robô, sessão atual (chat/ações recentes, contadores) e totais |
| POST | `/robot/lookup_streamer` | `{shared_id}` — acha o `livestream_id` atual pelo ID público do perfil (se ela estiver ao vivo) |
| POST | `/robot/start` | `{livestream_id}` — entra na live e começa a moderar |
| POST | `/robot/stop` | para a sessão e sai da live |
| GET | `/robot/log?limit=` | histórico de ações de moderação |

## Integração com o SuperLive

Descoberta na decompilação do app 2.31.0 (ver `docs/`). Todos os caminhos abaixo ficam sob
`https://api.sprlv-api.com/api/v1/`; sem o prefixo `/api/v1/` o servidor responde
`HTTP 400 {"error":{"code":77,"message":"unknown urd"}}` a qualquer chamada.
Já confirmado contra o serviço real: `device/register` (devolve o `guid`) e a resposta de erro de
`user/signup/email_signin` (`{"error":{"code":36,"message":"..."}}`). O resto segue sem confirmação.

| Uso | Endpoint / canal |
|---|---|
| Registrar o aparelho | `POST device/register` (sem `Device-ID`) → `guid` |
| Login do robô (e-mail) | `POST user/signup/email_signin` `{email,password}` → `token` |
| Login do robô (celular, passo 1) | `POST user/signup/send_phone_verification_code` `{phone_number,is_retry}` → `phone_verification_id` |
| Login do robô (celular, passo 2) | `POST user/signup/auth_phone` `{phone_verification_id,phone_number,code}` → `token` |
| Perfil (robô) | `POST users/own_profile` |
| Achar conta pelo ID público | `POST users/search` `{search_query}` → `items[].user_id` (ver nota abaixo) |
| Perfil público (pelo `user_id` interno) | `POST users/profile` `{user_id}` → `user.livestream_id` (só vem preenchido se ela estiver ao vivo) |
| URL do chat em tempo real | `POST user/settings` → `websocket.url` + `heartbeat` |
| Validar a live | `POST livestream/retrieve` `{livestream_id}` |
| Mensagem | `POST livestream/chat/send_text_message` `{livestream_id,text,guid}` |
| Silenciar | `POST livestream/chat/mute` `{livestream_id,user_id}` |
| Banir | `POST livestream/kick` `{livestream_id,user_id,permanent}` |
| Chat ao vivo | WebSocket `url?device=<Device-ID>&auth=<token>` |

Headers: `Authorization: Token <token>`, `Device-ID: <guid>`, `User-Agent`.

**O `Device-ID` precisa ser o `guid` que o SuperLive devolve em `device/register`** (é o que o
app faz na primeira abertura). Um UUID inventado é recusado com HTTP 400 `unknown urd`. O
backend registra o aparelho na primeira conexão do robô e reaproveita o mesmo `guid` depois.

WebSocket: o servidor envia `{"id","type","data"}` (`livestream_message_sent` traz
`user_id`, `name`, `text`, `livestream_id`; `livestream_ended` encerra a sessão). O robô envia
`{"id","action","data"}`: `enter_livestream`, `heartbeat` (`"state":"livestream:<id>"`) e
`leave_livestream`. Reconecta sozinho com backoff.

### Confirmado contra o SuperLive real
- **Login por e-mail/senha e por celular** (`device/register` → `email_signin`/
  `send_phone_verification_code`+`auth_phone`) **funcionam de verdade**, sem forjar
  `app_check_token`/`re_token`/`recaptcha_token` — apesar de o app cliente chamar
  `AuthPreCheckManager.execute("auth", ...)` antes dos dois (mesmo gate pros dois fluxos;
  `auth_pre_check` do serviço real confirma `{"app_check":true,"ac_fallback":true,"re":true}`),
  na prática o servidor aceitou a requisição simples. Não há garantia de que isso continue
  assim (pode variar por conta, por IP, ou o SuperLive pode passar a exigir de verdade); se
  algum dia recusar, a alternativa é **"Colar token"** (token obtido ao entrar no app).
- **A resposta do login pode trazer `"logged_in": false` com um `token` válido mesmo
  assim** — confirmado com uma conta real (`existed: true, logged_in: false, token: "..."`).
  O código do app (`UserSignUpRepositoryImpl.emailLogin`/`verifyPhoneWithSmsCode`) salva o
  `token` sem checar `logged_in`; o backend faz o mesmo agora (corrigido — a versão anterior
  rejeitava esse caso achando que era falha de login).
- **O "ID" que aparece na tela de perfil do SuperLive (`ID: 12345678`) NÃO é o `user_id`
  interno** — é um campo diferente, `shared_id` (confirmado: `getString(R.string.user_id,
  sharedId)` no app, e na prática: um `/robot/lookup_streamer` com esse ID direto em
  `users/profile` devolveu **uma conta completamente diferente e desconectada**, sem erro
  nenhum). Corrigido: agora `shared_id` é resolvido antes via `users/search`
  (`{search_query}`), e só o `user_id` real encontrado ali vai pro `users/profile`.

### O que NÃO foi verificado contra o SuperLive real
O resto foi implementado a partir do código decompilado e testado contra um SuperLive
simulado (`backend/tests/mock_superlive.py`), não contra o serviço de verdade:

- O app real envia `client_params` (dados do aparelho) em cada requisição; se a API exigir,
  será preciso adicioná-los em `superlive.py`.
- O WebSocket pode recusar clientes que não sejam o app; nesse caso a sessão para com a
  mensagem "recusou a conexão em tempo real".
- O robô precisa ser **moderador** da live.
- A API é privada/não documentada e pode mudar sem aviso; o uso por robôs pode ir contra os
  termos do SuperLive. Use apenas em lives suas, com a conta do robô.

## Segurança

- Senhas do portal: PBKDF2-SHA256 com salt (hashes antigos em SHA-256 são aceitos e
  atualizados no primeiro login). Limite de tentativas de login.
- Sessões com validade de 30 dias; `POST /auth/logout` as revoga no servidor.
- O backend escuta só em `127.0.0.1`; CORS aceita apenas origens `localhost`.
- A senha do robô **não é guardada**. Fica salvo só o **token da sessão** dele, em texto
  puro no SQLite local, e nunca é devolvido pela API. Proteja o arquivo `.db`.
- O histórico de ações (`moderation_log`) guarda o texto das mensagens moderadas (até 300
  caracteres, no máximo 2000 registros por usuária).

## Testes

```bash
cd backend
python -m unittest discover -s tests -t . -v      # 72 testes (unitários + integração)
cd ..
flutter analyze
flutter test                                       # 27 testes
```
Os testes de integração sobem a API de verdade, um SuperLive simulado (HTTP + WebSocket) e
usam um banco temporário; o `super_moderator.db` não é tocado (a migração é testada numa
cópia).
