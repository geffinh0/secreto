# Robô (moderação) — análise de produto

Escopo lido: `lib/screens/bot/bot_control_screen.dart` (1470 linhas, inteiro), `lib/providers/bot_provider.dart` (347 linhas, inteiro), rotas `/robot/*` de `backend/main.py`, além dos módulos que elas chamam (`backend/engine.py`, `backend/superlive.py`, `backend/db.py`, `backend/security.py`, `backend/tests/mock_superlive.py`) e os modelos em `lib/core/models/models.dart`.

Convenção: `arquivo:linha`. Textos entre aspas são exatos, como estão no código. Quando algo não foi verificado, está marcado como "não verificado".

---

## Achados principais (leia primeiro)

1. **Alertas e resumo da live NÃO aparecem na tela do Robô.** O backend monta `alerts` (`backend/engine.py:315`, `:438-443`, `:559-564`) e `last_live_summary` (`engine.py:316`, `:437`) e os envia no snapshot (`engine.py:1220-1221`). O modelo Dart `RobotSession` (`lib/core/models/models.dart:471-538`) não lê esses campos, e não há nenhuma referência a `alerts` ou `live_summary` em `lib/` fora do rótulo em `models.dart:616`. Na prática, o alerta e o resumo só chegam ao usuário pelo log de atividade (`db.log_activity`, `engine.py:447` e `:556`), com rótulos em `models.dart:600-620`.
2. **Texto de ajuda aponta para uma opção que não existe.** `backend/main.py:1072-1073` diz: `use a opção "Colar token"`. Nenhuma tela do Flutter tem essa opção (busca em `lib/` sem resultado). O backend aceita `token` (`main.py:1183-1191`), mas a UI só oferece os três modos de login.
3. **Dois rótulos "Ações de moderação" com números diferentes na mesma tela.** O cabeçalho da seção mostra `totalActionsOk` (histórico total, `bot_control_screen.dart:1267-1268`), e o cartão "Sessão" mostra `actionsOk` da sessão (`bot_control_screen.dart:1286`). Não há rótulo que diferencie os dois.
4. **Estado `error` não tem texto próprio.** O `_StateHero` só trata `running`, `waiting_for_live` e "watch ativo"; qualquer outro estado cai no ramo "Parado" (`bot_control_screen.dart:931-959`). Se a sessão falhar com a sentinela armada, o título vira "Em espera / Sentinela armada", e a causa aparece só no aviso amarelo (`bot_control_screen.dart:802-808`).
5. **Regra oculta de expulsão.** Qualquer usuário cujo nome seja exatamente `w` é expulso automaticamente, com o motivo `Nome de usuário proibido ('w')` (`backend/engine.py:1033-1044` para chat e `:986-1003` para quem entra na live). Isso aparece no feed como "banido". Não é uma regra configurada pelo usuário, e um vídeo de produto deve dizer isso.

---

## (1) Estados do robô

### 1a. Estado do painel (`_StateHero`, `bot_control_screen.dart:915-986`)

Ordem de avaliação, na mesma sequência do código (`:931-959`):

| Condição | Título | Texto de detalhe | Chip (texto / tom) | Ação principal |
|---|---|---|---|---|
| `session.running` (`is_active`: `starting`, `running` ou `waiting_for_live` no backend, `engine.py:341-342`) e `wsState == 'connected'` | "Moderando" | "O robô está na live e aplica as regras de moderação em tempo real." | "Chat conectado" / sucesso | "Parar moderação" (`:777-781`, id `stop_robot_button`) |
| `running` e `wsState != 'connected'` | "Moderando" | igual | "Reconectando" / aviso | "Parar moderação" |
| `state == 'waiting_for_live'` | "Aguardando live" | "A live anterior terminou. O robô volta a moderar quando o streamer abrir uma nova." | "Aguardando nova live" / aviso | "Iniciar moderação" (`:786-790`, id `start_robot_button`) |
| `watch.hasTarget && watch.active` (e não rodando) | "Em espera" | "O robô entra sozinho assim que o streamer iniciar a live." | "Sentinela armada" / acento | "Iniciar moderação" |
| qualquer outro caso (inclui `idle`, `starting`, `stopping`, `stopped`, `error`) | "Parado" | "Informe o ID da live para iniciar a moderação." | "Robô parado" / neutro | "Iniciar moderação" |

Observações:
- Quando a sentinela está armada, o `hint` substitui o detalhe, mas só se o campo de ID estiver vazio e a sessão não estiver rodando nem esperando (`bot_control_screen.dart:794-796`): "A moderação automática está armada. Para iniciar agora, informe o ID da live."
- O botão "Iniciar moderação" aparece mesmo com a sentinela armada (`:786-790`).
- Estados transitórios (`starting`, `stopping`) são mostrados como "Parado". O botão mostra `loading` só quando `bot.isBusy` (`:790`).

### 1b. Avisos (faixas) abaixo do cartão principal (`bot_control_screen.dart:798-814`)

- Erro do provedor (`bot.error`), tom perigo: texto vindo de `bot_provider.dart`. Exemplos: "Não foi possível iniciar o robô. Tente de novo.", "Não foi possível parar o robô. Tente de novo.", "Não foi possível desconectar o robô. Tente de novo.", "Não foi possível carregar o estado do robô. Tente de novo." (`bot_provider.dart:62`, `:201`, `:222`, `:240`).
- `session.lastError`, tom aviso, mostrado quando `state != 'idle'` (`:802-808`).
- `Sessão encerrada: <stopReason>`, quando `!running && state != 'idle' && stopReason != null` (`:809-814`).

### 1c. Textos de erro e de parada originados no backend

| Origem | Texto exato | Onde |
|---|---|---|
| Parada manual (padrão) | `Parado pelo usuário` | `backend/engine.py:453` |
| Live encerrada sem favorita | `A live foi encerrada` | `engine.py:927` (vira `Sessão encerrada: A live foi encerrada`) |
| Desligamento do servidor | `Servidor encerrado` | `engine.py:1305` |
| Token expirou (ação, mensagem, WS, espera) | `O token do robô expirou. Reconecte o robô na aba Robô.` | `engine.py:830`, `:1139`, `:1184` |
| WS recusado com 401/403 | `O SuperLive recusou a conexão em tempo real (HTTP {status}): o token do robô é inválido ou expirou. Reconecte o robô.` | `engine.py:584-587` (estado `error`) |
| Proxy de saída indisponível (aviso, reconecta sozinho) | `Saída de rede (proxy) indisponível; reconectando automaticamente.` | `engine.py:578` |
| Proxy indisponível por muito tempo (erro) | `A saída de rede (proxy) ficou indisponível por muito tempo.` | `engine.py:608` |
| WS recusado (outro código) | `WebSocket recusado (HTTP {status})` | `engine.py:589` |
| Falha de rede no WS | `WebSocket: {exc}` | `engine.py:592` |
| Queda sem recuperação (12 falhas seguidas) | `Não foi possível manter a conexão em tempo real com o SuperLive.` | `engine.py:633`, `MAX_WS_FAILURES=12` em `:96` |
| Ação recusada por falta de moderador (403) | `O SuperLive recusou a ação (403). O robô precisa ser moderador desta live.` | `engine.py:1142-1144` |
| Mensagem automática falhou | `Mensagem automática não enviada: {exc.message}` | `engine.py:1186` |
| Já existe sessão | `Já existe uma sessão do robô em andamento` (HTTP 409) | `engine.py:1262`; `main.py:1537-1538` |
| Capacidade atingida | `Capacidade de robôs simultâneos atingida; tente mais tarde.` (HTTP 409) | `engine.py:1269` |
| Sem conta conectada | `Conecte a conta do robô primeiro.` | `main.py:1389`, `:1518`, `:1532` |
| Trocar conta com sessão ativa | `Pare a sessão do robô antes de trocar a conta.` | `main.py:1143` |
| Erro genérico do SuperLive (HTTP) | `O SuperLive recusou {ação} (HTTP {status}): {mensagem}.` | `main.py:1065-1074` |
| SuperLive inalcançável | `Não foi possível falar com o SuperLive ({mensagem}).` (HTTP 502) | `main.py:1066-1067` |

Observação: o texto do 403 de moderador está no backend, mas a exigência também aparece na tela, na legenda da seção "Live": `Para silenciar e banir, o robô precisa ser moderador da live. Peça ao streamer para adicioná-lo antes de começar.` (`bot_control_screen.dart:818-819`).

### 1d. Estado de espera e campo de ID (`bot_control_screen.dart:822-843`)

- Com `waiting`: aviso `A live anterior terminou. O robô acompanha o perfil do streamer e volta a moderar quando ele abrir uma nova live.` (`:827-828`).
- Rótulo do campo: `Aguardando próxima live` (espera) ou `ID da live` (demais). Texto de apoio: `O ID aparece aqui quando o streamer abrir uma nova transmissão.` ou `Opcional se o streamer estiver favoritado. Necessário para iniciar manualmente.` (`:839-842`). O campo fica desabilitado quando `locked || waiting` (`:838`), e `locked = running || bot.isBusy` (`:764`).
- `didUpdateWidget` limpa o campo durante a espera (`:621-625`) e preenche com o ID da live que o robô está moderando (`:626-631`).

### 1e. Estado "preso" (aguardando nova transmissão)

Cartão do streamer favorito, quando a sessão foi parada na mesma live que o vigia ainda enxerga (`bot_control_screen.dart:1162-1173`):
- Badge: `Aguardando nova transmissão` (tom accent, ícone `sync_problem_rounded`).
- Texto: `O robô foi parado numa transmissão que ainda não mudou de ID no SuperLive. Espera há {tempo}. Ele não reinicia sozinho na mesma transmissão. Se já for uma live nova, informe o ID da live manualmente.`
- `{tempo}` vem de `_roundedDuration` (`:1135-1139`): `Ns` abaixo de 60 s, `1 minuto`, ou `N minutos`.
- Backend: `engine.py:1576-1592`, que registra a atividade `watch_stuck` com o texto `aguardando novo livestream_id (live anterior: {id})`. Rótulo na atividade: `Aguardando nova transmissão` (`models.dart:619`).

### 1f. Badges do cartão do streamer favorito (`bot_control_screen.dart:1151-1186`)

Ordem: inativo, aguardando live, preso, rodando, sentinela.
- `Desativado` / "A moderação automática está pausada para este streamer."
- `Aguardando live` / "A transmissão anterior terminou. O robô continua de olho na próxima live."
- `Moderando ao vivo` / "Conectado à transmissão agora, aplicando as regras em tempo real."
- `Sentinela armada` / "O robô monitora o perfil e começa a moderar sozinho quando o streamer iniciar a live."

### 1g. Pré-ativação (`bot_control_screen.dart:988-1016`)

Aparece só com `watch.hasTarget && watch.active && !running` (`:832-835`).
- Título: `Moderação pré-ativada`.
- Texto: `Você não precisa apertar nada. O robô entra na live e aplica as regras de silenciar e banir assim que ela iniciar.`
- Botão: `Avisar que entrei ao vivo`.

---

## (2) Os três modos de login

Seletor (`bot_control_screen.dart:484-503`): chips `E-mail e senha`, `Celular`, `Código por e-mail`. Modo padrão: e-mail e senha (`:118`). Título do cartão: `Conta do robô no SuperLive` (`:478`). Subtítulo da página quando desconectado: `Conecte a conta do robô para começar a moderar.` (`:75-77`).

Modo restaurado da última vez, sem guardar senha ou token (`:146-163`, `:165-177`). Só o modo e o e-mail/telefone são lembrados, e só após login bem-sucedido. A senha é apagada do campo após sucesso (`:204`).

Mensagem durante a conexão: `Conectando ao SuperLive. Isso pode levar alguns segundos.` (`:526-527`).

### 2a. E-mail e senha

- Texto de apoio: `Use o e-mail e a senha da conta do robô no SuperLive. A senha serve só para entrar e não fica guardada.` (`:338-340`)
- Campos: `E-mail da conta do robô` (`:358`), `Senha` (`:364`), com ícone de mostrar/ocultar (tooltips `Mostrar senha` / `Ocultar senha`, `:368`). Enter na senha dispara a conexão (`:366`).
- Botão: `Conectar robô` (`:328`).
- Validação local: `Informe o e-mail e a senha do robô.` (`:197`).
- Falha genérica: `Falha ao conectar o robô. Verifique as credenciais.` (`bot_provider.dart:184-185`).
- Backend: `POST /robot/connect` (`main.py:1174-1201`). Sem e-mail/senha nem token: `Informe e-mail e senha do robô ou cole o token da sessão.` (`:1186`).

### 2b. Celular por SMS (duas etapas)

- Texto antes do envio: `Informe o número da conta do robô no SuperLive, com o código do país.` (`:343`)
- Texto depois do envio: `Digite o código recebido por SMS em {telefone}.` (`:342`)
- Campo do número: `Telefone com código do país`, dica `+5511999999999` (`:384-385`). Enquanto o código não foi enviado o campo fica habilitado, e depois fica bloqueado (`:386`).
- Campo do código: `Código recebido por SMS` (`:394`).
- Botões: `Enviar código por SMS` (`:325`), depois `Confirmar código` (`:325`).
- Após o envio: `Usar outro número` (`:403`), e `Reenviar código (Ns)` com contagem regressiva, ou `Reenviar código` quando liberado (`:407-409`). A contagem vem do backend (`retry_timeout_seconds`); se ausente, usa 60 s (`bot_provider.dart:89`).
- Validações locais: `Informe o telefone com o código do país, ex: +5511999999999.` (`bot_control_screen.dart:213-214`) e `Informe o código recebido por SMS.` (`:245`).
- Falhas: `Não foi possível enviar o código por SMS. Tente de novo.` (`bot_provider.dart:91`); `Código inválido ou expirado.` (`bot_provider.dart:115`).
- Backend: `main.py:1204-1275`.
  - Formato: `use o formato internacional, ex: +5511999999999` (`main.py:463`).
  - Código expirado ou não pedido: `O código expirou ou não foi solicitado. Peça um novo código.` (`:1255`). TTL de 600 s (`:74`).
  - Número diferente: `Esse número não é o que recebeu o código. Peça um novo código.` (`:1257`).
  - Limite de tentativas: 5 (`MAX_OTP_ATTEMPTS`, `:81`). Mensagem: `Número de tentativas excedido. Peça um novo código.` (`:1260`).
  - Intervalo mínimo entre envios: 60 s, `SM_CODE_SEND_MIN_GAP` (`:62`). Mensagem: `Aguarde {N}s para pedir um novo código.` (`:1165`).
  - Limite diário: 10, `SM_CODE_SEND_DAILY_MAX` (`:63`). Mensagem: `Limite diário de códigos atingido. Tente amanhã.` (`:1167`).

### 2c. Código por e-mail (duas etapas)

- Texto antes do envio: `Para contas sem senha no e-mail, criadas por celular ou login social. O SuperLive envia um código por e-mail.` (`:346-347`)
- Texto depois: `Digite o código recebido por e-mail em {e-mail}.` (`:345`)
- Campos: `E-mail da conta do robô` (`:425`), depois `Código recebido por e-mail` (`:434`).
- Botões: `Enviar código por e-mail` (`:327`), `Confirmar código`, `Usar outro e-mail` (`:443`), `Reenviar código` (`:447`). Sem contagem regressiva (`bot_provider.dart:121-124` e `bot_control_screen.dart:272`).
- Validações: `Informe o e-mail da conta do robô.` (`:278`) e `Informe o código recebido por e-mail.` (`:293`).
- Falhas: `Não foi possível enviar o código por e-mail. Tente de novo.` (`bot_provider.dart:141`).
- Backend: `main.py:1278-1340`. Código só numérico: `informe o código recebido por e-mail (só números)` (`:518`). E-mail inválido: `e-mail inválido` (`:497`, `:510`). Mesmas regras de expiração, tentativas e intervalo do SMS (`:1288`, `:1296`, `:1322-1327`).

### 2d. Após conectar (`bot_control_screen.dart:1018-1068`)

- Nome: nickname do perfil, ou `Atila's Client` se vazio (`:1045`; também em `models.dart:348` e `main.py:1132`).
- Modo: `Conectado com token de sessão` (`token`), `Conectado com celular` (`phone`), `Conectado com código por e-mail` (`email_code`), ou `Conectado com e-mail e senha` (demais) (`:1026-1031`).
- Botão: `Desconectar robô` (`:1059`). Se houver sessão rodando, pede confirmação: título `Desconectar robô?`, texto `A moderação desta live será interrompida.`, botão de confirmação `Desconectar robô` (`:746-752`). Backend: `main.py:1343-1367`, que para o vigia e a sessão, faz logout no SuperLive quando o robô foi criado pelo portal, e apaga a conta.

---

## (3) ID da live x ID público do streamer

### 3a. Dois IDs diferentes

- **ID da live** (`livestream_id`): é o ID da transmissão em andamento. Campo `ID da live` (`bot_control_screen.dart:839`). Validação do backend: letras, números, hífen e underline, até 64 caracteres (`main.py:525-531`, mensagem em `:530`).
- **ID público do streamer** (`shared_id`): é o número exibido no perfil dela no SuperLive. Campo `ID público do streamer`, exemplo `69622983` (`bot_control_screen.dart:856-857`). Só dígitos: `use o ID numérico público do perfil dela no SuperLive` (`main.py:539-547`, `:559-562`).
- O código documenta que os dois não são o mesmo campo (`main.py:535-537`, `superlive.py:726-734`).

### 3b. Buscar streamer

Seção `Streamer`, subtítulo `Não sabe o ID da live? Busque pelo ID público do perfil.` (`bot_control_screen.dart:848-849`). Botão `Buscar streamer` (`:865`). Desabilitado com `locked` ou durante a busca (`:868`).

- Campo vazio: `Informe o ID público do streamer.` (`:659`).
- Ao encontrar uma live: o campo `ID da live` é preenchido e aparece o aviso `{apelido} está ao vivo agora. ID da live preenchido.` (`:681-684`).
- Ao não encontrar live: não há aviso de sucesso. O cartão mostra o chip `não está ao vivo` (`:1100`). Nenhum ID é preenchido.
- Falha da busca: mostra `bot.error`, que vem de `Não foi possível buscar essa conta. Tente de novo.` (`bot_provider.dart:262`), ou o texto de reserva `Não foi possível buscar essa conta. Confira o ID e tente de novo.` (`bot_control_screen.dart:676`).
- O cartão de resultado mostra avatar, apelido e o chip `ao vivo agora` ou `não está ao vivo` (`bot_control_screen.dart:1070-1111`).
- Backend: `POST /robot/lookup_streamer` (`main.py:1508-1523`) chama `find_live_by_shared_id` (`superlive.py:726-760`). Ele pesquisa o ID em `users/search` (mock em `mock_superlive.py:238`), confere o `shared_id` exato e lê a live pelo `user_id` interno. Se não achar conta: `Não encontramos nenhuma conta com esse ID.` (`superlive.py:747-748`). Há cache de `shared_id` para `user_id` (`superlive.py:733-744`, `:757`).

### 3c. Streamer favorito (vigia em segundo plano)

Botão `Favoritar e moderar automaticamente` (`bot_control_screen.dart:880`). Aparece depois de uma busca quando o ID buscado é diferente do favorito atual, ou quando o favorito está inativo (`:874-875`).

Ao favoritar: `setWatch(id, true)` (`bot_provider.dart:270-285`), que chama `PUT /robot/watch`.
- Sucesso: `Moderação automática ativada. O robô entra e modera a live assim que ela começar.` (`bot_control_screen.dart:705`).
- Falha: `Não foi possível salvar o streamer favorito. Tente de novo.` (`bot_provider.dart:281`) ou `Não foi possível salvar. Tente de novo.` (`bot_control_screen.dart:712`).
- Desativar pelo interruptor: `Streamer favorito desativado.` (`:706`). O interruptor tem o rótulo semântico `Moderação automática` (`:1222`). Não pede confirmação.

Cartão do favorito: título é o apelido, ou `Streamer favorito` se não houver apelido (`:1210`). Linha `ID público: {shared_id}` (`:1214`).

**O que o backend faz (`PUT /robot/watch`, `main.py:1376-1425`):**
1. Exige conta conectada (`main.py:1389`).
2. Valida o ID com uma busca imediata (`main.py:1393`). Grava nome e avatar (`:1397`).
3. Se já estiver ao vivo e não houver sessão ativa, inicia a moderação na hora (`:1406-1416`). Se a sessão estiver em outra live, troca de live (`:1417-1421`).
4. Liga a tarefa de fundo (`watchers.start`, `:1404`). Se `active=false`, para a tarefa (`:1422-1423`).
5. Ao reiniciar o backend, todas as vigias ativas são religadas com jitter (`main.py:166-168`).

**Como a tarefa de fundo vigia o perfil (`WatchManager`, `engine.py:1370-1648`):**
- Intervalo mínimo de 30 s (`engine.py:1311`), teto de 300 s (`:1321`), e teto de 900 s para criadoras sem live há 14 dias (`:1322`, `:1351-1357`).
- Multiplicador por criadora (`watch_multiplier`, `:1327-1357`): 2 se a sessão está rodando; 0,5 se a sessão espera a próxima live; 0,5 se a última live terminou há menos de 20 min; 0,5 se ela costuma começar a live na mesma hora em pelo menos 3 dos últimos 21 dias; 4 se não tem live há 14 dias (conta com mais de 14 dias); 1 nos demais casos.
- Orçamento por IP de saída: `SM_POLL_BUDGET_RPS`, padrão 2,0 req/s (`engine.py:1314-1318`, `:1360-1367`). Cada criadora tem uma saída fixa (`main.py` via `_client`, `engine.py:1436`). Intervalo com variação de ±10% (`:1474`).
- Botão `Avisar que entrei ao vivo` (`POST /robot/watch/ping`, `main.py:1432-1446`) acorda a tarefa na hora (`engine.py:1396-1402`). Intervalo mínimo de 30 s entre pings (`main.py:1429`). Erros: `Ligue a streamer favorita primeiro para o robô poder entrar sozinho.` (`:1444`) e `Aguarde {N}s para chamar de novo.` (`:1441-1442`). Na tela, o sucesso mostra `Aviso enviado. O robô entra na sua live em instantes.` (`bot_control_screen.dart:647-650`), e o estado é atualizado 3 s depois (`bot_provider.dart:295-297`).
- Decisão a cada ciclo (`engine.py:1562-1637`):
  - Ao vivo e sem sessão ativa: inicia a moderação e grava a atividade `session_auto_started`, rótulo `Moderação iniciada automaticamente` (`:1594-1618`; `models.dart:614`). Se a sessão parou nessa mesma live, espera uma live nova (`:1576-1592`).
  - Ao vivo com sessão em espera: troca para a nova live (`:1621-1626`).
  - Ao vivo com sessão rodando em outra live: troca (`:1627-1633`).
  - Offline com sessão rodando: encerra a live (`on_live_ended`, `:1634-1637`).
- Na sessão, a live de um favorito gera o alerta `A streamer favorita {nome} entrou ao vivo e o robô conectou com sucesso na live {id}!` (`engine.py:550-552`), gravado como atividade `favorite_live_connected` (rótulo `Streamer ao vivo & Robô conectado`, `models.dart:615`).
- Na tela, enquanto o favorito está ativo, o provedor consulta o backend a cada 3 s (`bot_provider.dart:12`, `:332-339`). Sem favorito ativo e sem sessão, não há consulta periódica.

---

## (4) Feed de atividade, chat, ações, alertas e resumo

### 4a. Coluna direita (`bot_control_screen.dart:1242-1275`)

Três seções: `Sessão`, `Chat ao vivo`, `Ações de moderação`.

**Sessão** (`_SessionStats`, `:1277-1327`). Três contadores, com estes rótulos:
- `Mensagens vistas`: todas as mensagens de chat recebidas (`engine.py:1023`).
- `Mensagens enviadas`: só mensagens automáticas (`engine.py:1177`). Não inclui respostas.
- `Ações de moderação`: ações da sessão, com sucesso (`engine.py:1130`).
- Em telas com largura menor que 420 px, os contadores vão em coluna (`:1292-1307`).

**Chat ao vivo** (`_ChatList`, `:1331-1362`).
- Chip `Ao vivo` (sucesso, ícone de sensor) aparece no cabeçalho quando `isRunning` (`:1257-1263`).
- Vazio com sessão rodando: título `Aguardando mensagens`, texto `As mensagens do chat aparecem aqui assim que chegarem.` (`:1342-1344`).
- Vazio sem sessão: título `Nenhuma mensagem ainda`, texto `O chat aparece aqui quando o robô estiver em uma live.` (`:1345-1346`).
- Lista com altura fixa de 360 px, mais recente no topo (`:1337`, `:1352`). O backend guarda as últimas 60 (`engine.py:313`).
- Linha (`_ChatRow`, `:1364-1403`): hora `HH:mm:ss` (`:16`), chip `banido` (ícone de bloqueio, perigo) ou `silenciado` (ícone de volume mudo, aviso) quando há ação, e em seguida `usuário: texto`. O texto fica na cor do chip quando a mensagem foi moderada.

**Ações de moderação** (`_ActionList`, `:1405-1470`).
- Cabeçalho: `{totalActionsOk} no total` (`:1268`). Total histórico do usuário (`main.py:1098`, `db.action_totals`).
- Vazio: título `Nenhuma ação nesta sessão`, texto `Silenciamentos e banimentos aparecem aqui.` (`:1415-1416`).
- Linha (`_ActionRow`, `:1426-1470`):
  - Título: `Silenciou {nome}` ou `Baniu {nome}`.
  - Se falhou: `Falhou ao silenciar {nome}` ou `Falhou ao banir {nome}` (`:1435-1437`).
  - Linha de apoio: `palavra "{palavra}" · "{texto da mensagem}"` (`:1454`).
  - Se falhou e houver detalhe: o texto do SuperLive (`:1459-1460`).
  - Hora no canto direito.
- Até 30 ações (`:1421`). O backend guarda 60 (`engine.py:314`).
- Dados: `ActionEntry` com `ts`, `action` (`mute` ou `kick`), `target_name`, `keyword`, `message_text` (até 300 caracteres), `ok`, `detail` (`engine.py:1157-1161`). Gravado também no log persistente (`db.log_action`, `engine.py:1152-1154`; `GET /robot/log`, `main.py:1558-1566`).

### 4b. Regras de ação (o que vira "silenciado" ou "banido")

- Níveis: silenciar = 1, banir = 2 (`engine.py:100`). Banir vence silenciar quando ambos batem (docstring de `RuleMatcher`, `engine.py:180-190`).
- Conteúdo: o `RuleMatcher` faz correspondência por palavra inteira, com proteção contra disfarces, por exemplo `passazap` ou `z.a.p` (`engine.py:180-190`). As palavras são configuradas pelo usuário em outra tela (não inspecionada).
- Imunidade por presentes: se ativada, quem enviou presentes acima de um limite na live não é moderado (`engine.py:1046-1047`, `:1062-1064`, `:1067-1087`).
- Execução: `mute` ou `kick` (com `kick_permanent`) (`engine.py:1124-1128`). Se a ação falhar por 403, a sessão grava o aviso de moderador (`:1140-1144`).
- Ação de 'w' (regra fixa): ver Achado 5.
- Fila: ritmo mínimo entre ações (`ACTION_SPACING_SECONDS`, `engine.py:1096`). Ações de uma live que já mudou são descartadas (`:1098-1121`, `:1118-1121`).

### 4c. Alertas (`session.alerts`) e resumo da live (`last_live_summary`)

**Não são exibidos na tela do Robô.** Ver Achado 1. O que o usuário vê:

- Alerta de favorita ao vivo: texto `A streamer favorita {nome} entrou ao vivo e o robô conectou com sucesso na live {id}!` (`engine.py:550-552`). Chega ao usuário como atividade `Streamer ao vivo & Robô conectado` (`models.dart:615`), com o texto em `detail`.
- Resumo: é gravado como atividade `live_summary` com o rótulo `Resumo da Transmissão` (`models.dart:616`) e o texto:
  `Resumo da Live {id}: Duração: {dur} | Chat monitorado: {N} msgs | Moderações: {N} ({N} silenciamentos, {N} expulsões) | Mensagens automáticas: {N} | Diamantes arrecadados: {N}` (`engine.py:414-419`, gravado em `:447`).
  - `{dur}` é `Ns`, `Nm SSs` ou `Nh MMm SSs` (`engine.py:397-405`).
  - Emitido quando a sessão para em uma live (`engine.py:458-459`), troca de live (`:862-863`) ou a live termina (`:931-932`).
  - O snapshot também traz `last_live_summary` com os mesmos números em campos (`engine.py:422-435`), mas a UI não os lê.
  - Não verificado: se a tela de atividade mostra o campo `detail` do rótulo `Resumo da Transmissão`.
- Demais rótulos de atividade relevantes para a sessão (`models.dart:600-620`): `Moderação iniciada`, `Moderação parada`, `Moderação iniciada automaticamente`, `Live encerrada`, `Live alterada`, `Aguardando nova transmissão`, `Robô conectado`, `Robô desconectado`.

---

## (5) Exigência de o robô ser moderador

Textos onde a exigência aparece:
- Legenda da seção Live (`bot_control_screen.dart:818-819`): `Para silenciar e banir, o robô precisa ser moderador da live. Peça ao streamer para adicioná-lo antes de começar.`
- Aviso de erro 403 na sessão (`engine.py:1142-1144`): `O SuperLive recusou a ação (403). O robô precisa ser moderador desta live.`
- Aviso amarelo na tela, que vem de `session.lastError` (`bot_control_screen.dart:802-808`).

Limites da exigência:
- O backend não verifica se o robô é moderador antes de começar. A checagem é feita só quando o SuperLive recusa uma ação com 403 (`engine.py:1140`). A sessão continua rodando e apenas registra o aviso e a ação falha.
- Não há texto específico para mensagem automática recusada por falta de moderador, além de `Mensagem automática não enviada: {mensagem}` (`engine.py:1186`).
- O mock sempre aceita silenciar e banir (`backend/tests/mock_superlive.py:261-263`). A recusa 403 só aparece se o teste injetar a falha (`mock.fail`, `mock_superlive.py:37`, `:133-134`; uso em `backend/tests/test_integration.py:941-949`).

---

## (6) Passo a passo para gravar o vídeo

### 6a. Pré-requisitos (não verificados como um roteiro pronto)

O repositório não tem um script de demonstração pronto. Os pontos abaixo são o que o código exige.

1. **Chave de cifra do token**: `SM_TOKEN_KEY_FILE` deve apontar para um arquivo de chave válido (`backend/security.py:134-147`). Sem ela, a conexão do robô é recusada e a falha é fechada (`backend/main.py:189-192`). O token nunca fica em variável de ambiente.
2. **Apontar o backend para o mock**: `superlive.py:26` lê `SUPERLIVE_BASE_URL` no import, então a variável precisa estar definida antes de importar o módulo. O valor é `mock.base_url` depois de `mock.start(porta)` (`mock_superlive.py:60`, `:98-107`). O WebSocket é informado pelo próprio mock em `mock_superlive.py:254`. `SUPERLIVE_WS_URL` só é necessário se quiser sobrescrever (`main.py:1411`, `:1536`).
3. **Subir o backend**: `main:app` com `SM_HOST` (padrão `127.0.0.1`) e `SM_PORT` (padrão `8000`) (`main.py:1953-1954`).
4. **Ajustes para não esperar**: `SM_CODE_SEND_MIN_GAP=0` (padrão 60 s, `main.py:62`), `SM_CODE_SEND_DAILY_MAX` (padrão 10, `:63`) e `SM_WATCH_PING_MIN_GAP` (padrão 30 s, `:1429`).
5. **Apontar o app Flutter para o backend local**: não inspecionado nesta análise. Verificar antes de gravar.
6. **Script do mock**: escrever um pequeno processo que cria `MockSuperLive()`, chama `start(porta)` e expõe o objeto para acionar os eventos (ver 6c). `test_integration.py:59-63` mostra o padrão de uso.

### 6b. Estado do mock necessário

Constantes (`backend/tests/mock_superlive.py:14-30`):
- Robô: e-mail `robot@x.com`, senha `good` (`:153`, verificar a linha exata no arquivo antes de usar).
- Robô alternativo com senha: `existing@x.com` / `good` (`:150-163`).
- SMS: telefone `+5511999999999`, código `123456` (`:26-27`, `:166-171`).
- E-mail com código: `nopassword@x.com`, código `654321` (`:28-29`, `:192-197`).
- Streamer com live: ID interno `100`, ID público `555100`, apelido `Streamer` (`:21-22`, `:243-244`).
- Streamer offline: ID interno `200`, ID público `555200`, apelido `Offline` (`:23-24`, `:249-250`).

Para a streamer 555100 estar ao vivo na sala de demonstração, o script precisa chamar `mock.start_new_live(STREAMER_ID, "live1")` (`mock_superlive.py:88-91`). Para o streamer offline voltar a ficar ao vivo, `start_new_live(OFFLINE_STREAMER_ID, "live3")`.

### 6c. Passo a passo na tela

Pré-condição: backend e mock no ar, `start_new_live` feito para a streamer 555100 ao vivo como `live1`.

1. **Login**: abrir `Robô`. Escolher o chip `E-mail e senha`. Digitar `robot@x.com` e a senha `good`. Clicar em `Conectar robô`. Esperar a troca para o painel.
   - Alternativa SMS: chip `Celular`, digitar `+5511999999999`, clicar em `Enviar código por SMS`, digitar `123456`, clicar em `Confirmar código`.
   - Alternativa e-mail: chip `Código por e-mail`, digitar `nopassword@x.com`, clicar em `Enviar código por e-mail`, digitar `654321`, clicar em `Confirmar código`.
2. **Estado inicial**: cartão `Parado`, chip `Robô parado`, texto `Informe o ID da live para iniciar a moderação.`
3. **Iniciar manualmente**: digitar `live1` no campo `ID da live` e clicar em `Iniciar moderação`. Aparece o aviso `Robô entrou na live e está moderando.` e o cartão vira `Moderando` com `Chat conectado`.
4. **Feed**: pelo script, chamar `mock.chat(user_id, nome, texto, "live1")` (`mock_superlive.py:70-74`). A mensagem aparece em `Chat ao vivo`, com o chip `Ao vivo`. Para ver um silenciamento, a palavra precisa estar em uma regra de silenciar configurada (tela de regras, não inspecionada). Para ver um banimento automático, use um nome exatamente `w` (Achado 5).
5. **Falha simulada de moderador (opcional, deve ser identificada como simulada)**: pelo script, `mock.fail["livestream/chat/mute"] = (403, {"message": "not a moderator"})` (padrão de `test_integration.py:941`). A próxima ação falha com o aviso amarelo `O SuperLive recusou a ação (403). O robô precisa ser moderador desta live.` e a linha `Falhou ao silenciar {nome}` aparece em `Ações de moderação`.
6. **Sentinela**: parar a moderação (`Parar moderação`, aparece `Sessão encerrada: Parado pelo usuário`). Digitar `555100` em `ID público do streamer` e clicar em `Buscar streamer`. O cartão mostra `Streamer` e `ao vivo agora`, e o campo `ID da live` é preenchido com `live1`. Clicar em `Favoritar e moderar automaticamente`. Aparece `Moderação automática ativada. O robô entra e modera a live assim que ela começar.` A página passa a mostrar `Sentinela armada`, o cartão do favorito e a faixa `Moderação pré-ativada`. Como a live já está em andamento, o backend inicia a moderação na hora (`main.py:1406-1416`).
   - Para mostrar a entrada automática com a live começando depois: antes de favoritar, usar a streamer offline `555200` e depois chamar `mock.start_new_live(OFFLINE_STREAMER_ID, "live3")`. Clicar em `Avisar que entrei ao vivo` para não esperar o intervalo de 30 s (Achado: `main.py:1432-1446`). Após cerca de 3 s, o cartão vira `Moderando` e o log ganha `Moderação iniciada automaticamente`.
7. **Espera pela próxima live**: pelo script, `mock.end_live(STREAMER_ID, "live1")` (`mock_superlive.py:82-86`). A página passa para `Aguardando live`, com a faixa `A live anterior terminou...`, o campo `Aguardando próxima live` bloqueado e o cartão do favorito em `Aguardando live`. Depois, `mock.start_new_live(STREAMER_ID, "live2")` e `Avisar que entrei ao vivo`. A página volta a `Moderando` com `live2` no campo.
8. **Resumo**: parar a moderação. A atividade ganha `Resumo da Transmissão` (ver 4c). Não verificado se a tela de atividade mostra o texto.
9. **Desconectar**: `Desconectar robô`. Com sessão rodando, aparece a confirmação `Desconectar robô?`.

### 6d. Limites do mock para o roteiro

- `mute` e `kick` sempre retornam sucesso, a menos que `mock.fail` seja usado (`mock_superlive.py:261-263`).
- Nome fixo da streamer (`Streamer`) e do robô, sem foto real.
- Mensagens só entram pelo script (`mock.chat`).
- O intervalo de 30 s do vigia só é encurtado pelo botão de aviso, e ele só funciona se o vigia já estiver ativo.
- Não há reCAPTCHA, a menos que `mock.require_captcha` seja ligado (`mock_superlive.py:148`, `:165`, `:191`).

---

## (7) O que NÃO dá para mostrar de forma honesta

1. **Moderação real no SuperLive.** Todo o roteiro acima roda contra um mock que aceita silenciar e banir sem verificar nada. Nenhum vídeo deve sugerir que o robô silenciou ou baniu alguém numa live real.
2. **A exigência de moderador como comportamento real.** O mock não recusa ações por falta de moderador. Só a falha injetada (passo 5) mostra o aviso, e isso precisa ser dito no vídeo.
3. **Alertas e resumo na tela do Robô.** O código gera `alerts` e `last_live_summary`, mas a UI não os mostra (Achado 1). Não é honesto mostrar um alerta ou resumo como parte do painel do Robô. Só dá para mostrar o que chega na atividade, e isso precisa ser verificado na tela de atividade.
4. **Tempo real de entrada.** Com o intervalo normal, o vigia pode levar de 30 s a 15 min para perceber uma live (`engine.py:1311-1322`). O vídeo só pode mostrar uma entrada quase imediata com o botão de aviso, e deve dizer isso.
5. **Login real e códigos reais.** O mock aceita códigos fixos. Não dá para mostrar um código real de SMS ou e-mail como se fosse o fluxo do SuperLive. O próprio backend avisa que o SuperLive pode exigir verificação anti-robô (`main.py:1072-1073`).
6. **Token colado.** O backend aceita `token` (`main.py:1183-1191`), mas a tela não oferece essa opção, e a mensagem que menciona "Colar token" aponta para algo que não existe (Achado 2). Não mostrar.
7. **Contas, IDs e avatares reais.** A análise não usou nenhum. Um vídeo de produto não deve mostrar IDs públicos, avatares ou nomes de streamers reais, nem o e-mail de uma conta de robô real. Usar os dados fictícios do mock.
8. **Números de diamantes e imunidade por presentes.** Dependem de eventos de presente do SuperLive que o mock não emite (o mock só tem chat, entradas e fim de live). Não dá para mostrar a imunidade por presentes com o mock.
9. **Robustez em produção.** Reconexão, falha de proxy, limite de capacidade (`SM_MAX_SESSIONS`, `engine.py:1236-1239`) e divergência entre duas contas vendo a mesma streamer (`engine.py:1483-1502`) não estão cobertos pelo roteiro. Mostrar esses casos exige forçar falhas no mock, o que deve ser dito no vídeo.
10. **Texto de "Atila's Client".** Aparece como nome padrão quando o perfil não tem apelido (`bot_control_screen.dart:1045`). Se o vídeo mostrar esse nome, é preciso avisar que é o padrão do app, não um streamer real.
