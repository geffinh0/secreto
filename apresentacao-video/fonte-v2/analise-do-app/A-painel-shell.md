# A: Painel, shell, avisos, instalação e motion (Super Moderator / Atila's Client)

Base: `/home/user/secreto`. Todas as citações são `arquivo:linha` lidas nesta sessão. Textos entre aspas estão literais no código (acentos e pontuação preservados).

---

## 1. Estados visuais do Painel

Arquivo: `lib/screens/dashboard/dashboard_screen.dart`.

Cabeçalho (linha 55): `PageHeader(title: 'Painel', subtitle: '${_greeting()}, $name')`.
- `_greeting()` (linhas 36-41): hora < 12 → `Bom dia`; < 18 → `Boa tarde`; senão → `Boa noite`.
- `name` = `user?.shownName ?? 'Usuário'` (linha 49).

O bloco de robô (`_RobotStatus`, linhas 104-190) tem três estados, decididos por duas variáveis:
- `connected = bot.isConnected` (`robot != null`, `lib/core/models/models.dart:556`)
- `live = connected && bot.isRunning` (`session.running`, `lib/core/models/models.dart:522`)

| Estado | Condição (código) | Título (headline) | Detalhe (detail) | Chip | Pose da raposa | Botão |
|---|---|---|---|---|---|---|
| **Moderando a live** | `live` (linhas 116-120) | `Moderando a live` | `'${bot.session.messagesSent} mensagens enviadas nesta live.'` | `Ao vivo` (ícone `sensors`, tom success) | `FoxPose.headLaugh` (altura 190) | `Abrir o robô` |
| **Aguardando a live** | `connected && !running` (linhas 121-125) | `Aguardando a live` | `O robô está conectado e não há live no momento.` | `Conectado` (ícone `pause_circle_outline`, neutro) | `FoxPose.headCalm` | `Abrir o robô` |
| **Robô desligado / desconectado** | `!connected` (linhas 126-131) | `Robô desligado` | `bot.error ?? 'Conecte o robô para começar a moderar.'` | `Desconectado` (ícone `link_off`, tom warning) | `FoxPose.sleeping` | `Conectar robô` |

Botão: `AppButton.inverse` com `onPressed: () => context.go('/bot')` (linhas 154-158). Ícone `smart_toy_outlined` quando conectado, `link` quando não.

Observações importantes:
- **Não existe estado "erro" próprio no Painel.** O `session.status` do backend (`idle | starting | running | waiting_for_live | stopping | stopped | error`, comentário em `lib/core/models/models.dart:474`) não é lido na tela; só o booleano `running`. Assim, `waiting_for_live`, `starting`, `stopping` e `error` caem em "Aguardando a live" (se `running == false`) ou em "Moderando a live" (se `running == true`). O `lastError` da sessão (`models.dart:529`) não aparece no Painel.
- O erro aparece apenas como texto em "Robô desligado" (`bot.error`) e na linha de última ação (abaixo).
- Textos de erro possíveis em `bot.error` (`lib/providers/bot_provider.dart`):
  - Falha ao carregar estado na primeira leitura (linha 62): `Não foi possível carregar o estado do robô. Tente de novo.` (ou o `detail` do servidor, se houver).
  - Falha de conexão do robô (linha 184-186): `Falha ao conectar o robô. Verifique as credenciais.`, ou o `detail` do servidor.
  - Falha de rede (`lib/core/services/portal_api_service.dart:117-125`, `statusCode == 0`): `Não foi possível conectar ao servidor. Verifique sua conexão.` (em build local, com URL entre parênteses).
  - Proxy fora (502/503/504, linha 128-129): `Servidor indisponível, tente novamente em instantes.`
  - Ao desconectar falhar (linha 201): `Não foi possível desconectar o robô. Tente de novo.`
- `bot.error` é limpo em `refresh()` com sucesso quando o estado não é `error` (linha 58).

**Última ação** (`_LastAction`, linhas 193-235): aparece dentro do bloco do robô quando `bot.recentActions` não está vazio (linhas 133, 149-152). Pega a última da lista.
- Sucesso e mute: `Silenciou <nome>`; sucesso e kick: `Baniu <nome>` (linha 200-201, `action.action == 'mute'`).
- Falha: `Falhou ao silenciar <nome>` ou `Falhou ao banir <nome>` (linha 202). Ícone `error_outline` em `AppColors.danger`.
- Sucesso: ícone `check_circle_outline` em `AppColors.success`.
- Linha de meta: `Palavra "<keyword>"` + ` às HH:mm` (linhas 203-205, 224), horário no fuso local.
- Ícone 20px, título `AppType.bodyStrong`, meta `AppType.meta`, cartão `raised: true`.

**Layout do bloco do robô** (linhas 162-189): `AppSurface(feature: true, color: forest)`, padding 24. Abaixo de 520px de largura: texto em coluna, raposa à direita com altura 120. Acima: texto à esquerda, raposa com altura 190.

**Números** (`_Numbers`, linhas 237-280): três entradas, rótulo em minúsculas.
- `${bot.totalActionsOk}` + `ações realizadas` (linha 256)
- `${mod.rules.length}` + `regras ativas` (linha 257). Conta todas as regras, inclusive desativadas.
- `${msg.messages.length}` + `mensagens na fila` (linha 258). Conta todas as mensagens.
- Valor em `AppType.numeral` (Fraunces 36), rótulo em `AppType.meta`. Em tela compacta (<600), linha horizontal de três colunas; senão coluna com divisores de 16px.

**Listas** (linhas 282-334):
- Regras (`_RulesList`, título `Regras de moderação`):
  - Vazio: `AppStateView` com `Nenhuma regra cadastrada` / `Adicione palavras em Moderação.` (linhas 292-294)
  - Com dados: até 4 linhas (`rules.take(4)`). Título = palavra. Subtítulo `Desativada` se inativa. Chip `Silenciar` (ícone `volume_off`, warning) ou `Banir` (ícone `block`, danger) (linhas 300-304).
- Fila (`_MessagesList`, título `Fila de mensagens`):
  - Vazio: `Nenhuma mensagem na fila` / `Adicione mensagens automáticas em Mensagens.` (linhas 321-323)
  - Com dados: até 4 linhas (`messages.take(4)`), título = conteúdo, subtítulo `Desativada` se inativa, chip `#<sortOrder + 1>` (linha 329).

Botão de rodapé da página: `Ver estatísticas` com seta `arrow_forward`, `AppButton.text`, `context.go('/stats')` (linhas 89-95).

Carregamento: `initState` dispara `_loadData()` após o primeiro frame (linha 23), que chama `bot.refresh()`, `mod.loadRules`, `msg.load` (linhas 31-33). Pull-to-refresh via `AppPage(onRefresh: _loadData)` (linha 52, `lib/widgets/ui/app_layout.dart:57-63`).

Polling: `BotProvider` consulta `/robot/status` a cada 3 s **somente** enquanto `isRunning` ou `watch.active` (`lib/providers/bot_provider.dart:12`, `:333-337`).

Estado de "carregando" do Painel: não há `AppStateView.loading` no Painel. A tela renderiza direto com valores vazios/padrão. Só o `AppSplash` (seção 3) aparece na inicialização.

### Estado vazio geral
Não existe tela vazia própria no Painel. Os vazios são as duas listas (acima).

---

## 2. Barras, menu Mais, aviso de nova versão, instalação como app

### 2a. Barra superior (`_TopBar`, `lib/widgets/shell/main_shell.dart:178-197`)
Só no celular (`!wide`, linha 57). Altura mínima 64, padding horizontal 16/24/32 conforme a largura.
- Largura < 400: só o medalhão `FoxIcon(size: 36)` (linha 190).
- Largura >= 400: `_Brand` = medalhão 36 + texto `Super Moderator` (`AppType.heading`, linha 154). Texto de marca: `Super Moderator` (não `Atila's Client`, que é o título da aba e do manifest).
- Direita: chip de status `_BotStatus` (linhas 169-174):
  - `Robô online` (ícone `check_circle_outline`, tom success)
  - `Robô offline` (ícone `remove_circle_outline`, tom danger)

### 2b. Barra inferior (`_BottomBar`, linhas 199-241)
Só no celular (linha 75). Altura fixa 64 (linha 216). Quatro abas de largura igual:
- `Painel` (`grid_view_outlined`), `Moderação` (`shield_outlined`), `Robô` (`smart_toy_outlined`), `Mais` (`more_horiz`).
- Texto de escala limitado a 1.3 (linha 207). Fita de cima com hairline `AppColors.rule`.
- Aba ativa: pílula 56x28 com fundo `AppColors.raised` (linha 317) e ícone e texto `AppColors.ink`; inativa: fundo transparente, cor `muted`. Peso do texto 700 ativo / 600 inativo (linha 327).
- Semântica: `Semantics(button, selected, label)` (linhas 298-302).

### 2c. Menu "Mais" (`_openMore`, linhas 243-279)
`showModalBottomSheet` com fundo `surface`, `isScrollControlled`.
- Título: `Mais` (`AppType.title`, linha 255).
- Itens (`AppRowList`, linhas 257-271): `Mensagens automáticas` (`/messages`), `Estatísticas` (`/stats`), `Configurações` (`/settings`). Cada um com ícone, chevron `chevron_right` e item selecionado destacado (`raised`).
- Rodapé: `_UserBlock(labeled: true)` (linha 273): avatar circular com inicial, nome, `@usuario`, e o botão de texto `Sair` (linha 462).
- Fechar o sheet antes de navegar (`Navigator.pop`, linha 267).

### 2d. Desktop, >= 900 px (`_Sidebar`, linhas 339-376)
Sem barra inferior nem barra superior. Coluna fixa à esquerda com fundo `forest`:
- Marca (`Super Moderator` em `onForest`) + chip de robô (linhas 352-354).
- Linha dourada `goldLight` (linha 357).
- Todos os destinos (inclui os três do Mais), item ativo com barra lateral dourada de 3 px (linha 403).
- Rodapé: `_UserBlock` com botão de ícone `logout` e tooltip `Sair` (linhas 467-471).
- Largura: `248` (linha 346). **Divergência**: o comentário em `main_shell.dart:35` diz "fixed 240px". O código tem 248.

### 2e. Aviso de nova versão (`_UpdateNotice`, `main_shell.dart:80-139`)
Fica entre a barra superior e o conteúdo, em todas as larguras (linha 58).
- Texto exato: `Há uma nova versão do app.` (`AppType.bodyStrong`, linha 127).
- Botão: `Atualizar agora`, ícone `refresh`, `AppButton` primário (terracota) (linhas 128-132), `onPressed: AppUpdateService.apply`.
- Cartão `AppSurface(raised: true)`, padding 16, quebra em linha (`Wrap`).
- Quando aparece: a cada 15 s (`Timer.periodic`, linha 96) consulta `AppUpdateService.available` e chama `setState` se mudou.
- Por trás (`web/index.html:108-206`):
  - O `BUILD_ID` é substituído no deploy (`@@BUILD_ID@@`; `deploy/deploy.sh:28`).
  - A página consulta `build.json?t=…` com `no-store` a cada 5 min (`web/index.html:198`) e ao voltar o foco da aba (linhas 199-201).
  - Se `build.json.build` for diferente do `BUILD` carregado, marca `__updateAvailable = true` (linhas 191-194).
  - Em build de desenvolvimento (`BUILD` não carimbado), nada é verificado (linhas 116, 188).
- "Atualizar agora": limpa service worker e caches e recarrega (`web/index.html:203-205`). `localStorage` (login) não é tocado (linha 121).

### 2f. Instalação como app (PWA)
Textos na tela de Configurações, não em `dashboard`/`main_shell`: `lib/screens/settings/settings_screen.dart:168-222` (`_PwaInstallSection`), inserido na coluna secundária na linha 120.

Condições de exibição (linhas 189-194):
- Oculto se `PwaInstallService.isStandalone` (já instalado; linha 190).
- Oculto se não é iOS e `canPromptInstall` é falso (linhas 193-194).

Texto da seção (linha 197): título **`Instalar como app`**.

Corpo do texto (linhas 202-206), dois casos:
- iOS (`isIos`): `No Safari, toque em compartilhar e depois em "Adicionar à Tela de Início".`
- Demais (Chrome/Android com evento de instalação): `Instale o Atila's Client como app: abre em tela cheia, com ícone próprio e sem a barra de endereço.`

Botão (somente fora do iOS, linhas 209-215): `Instalar app`, ícone `install_mobile`, estilo secundário, `key: install_pwa_button`.
- Ao tocar: `_installing = true` (rótulo continua `Instalar app`, mas aparece o spinner, `loading`), chama `triggerInstall()`, espera 2 s e volta (linhas 184-186). A própria prompt do navegador não é controlada pelo app.

Ponte JS (`web/index.html:73-96`):
- Guarda o evento `beforeinstallprompt` (com `preventDefault`), limpa em `appinstalled`.
- `pwaIsStandalone`: `display-mode: standalone` ou `navigator.standalone`.
- `pwaIsIos`: regex de iPhone/iPad/iPod no user agent.

Manifest (`web/manifest.json`): `name` = `Atila's Client`, `short_name` = `Atila`, `display` = `standalone`, `theme_color` = `#F4ECDC`, `background_color` = `#F4ECDC`, `orientation` = `portrait-primary`. Ícones 192/512 e maskable 192/512.

Título da aba (`web/index.html:21`): `Atila's Client`. Meta description (linha 9): `Atila's Client — Painel de Controle e Moderação Automática para SuperLive`.

**Divergência de nomes**: o app se chama `Super Moderator` na barra e na lateral, mas `Atila's Client` no manifest, na aba e na instalação. Vale mostrar nos vídeos sabendo disso.

---

## 3. Animações e transições

Tokens (`lib/core/theme/app_motion.dart:4-15`):
- `fast` 90 ms, `base` 160 ms, `slow` 240 ms, `stagger` 60 ms, `curve` = `Curves.easeOutCubic`.
- Comentário diz "Only transform and opacity ever animate" (linha 3). **Divergência**: a pílula da barra inferior anima `color` com `AnimatedContainer` (`main_shell.dart:310-318`).
- Movimento reduzido (`MediaQuery.disableAnimations`) é respeitado em `Reveal`, nas transições de rota e (por `AppMotion.reduced`) no próprio `Reveal`.

**Splash inicial** (`lib/widgets/common/app_splash.dart`, rota `/splash` em `lib/router/app_router.dart:69-71`):
- Aparece enquanto `authProvider.isInitialized` é falso (`app_router.dart:37-41`). Redireciona para `/splash?from=<destino>` e depois para o destino (linhas 50-54, padrão `/dashboard`).
- Conteúdo: raposa de costas `FoxPose.back` altura 132 (linha 19), espaço 24, anel de progresso 28x28, `strokeWidth` 2.5, cor `accent` (linhas 21-26), espaço 16, texto `Abrindo o painel` (`AppType.meta`, linha 28).
- Antes do Flutter subir, a mesma tela existe em HTML e CSS no `web/index.html:35-65`:
  - Anel: borda 2.5 px `#E3E8D6` com topo `#A8461F`, giro de 0.9 s linear infinito (linhas 45-53, 56). Com movimento reduzido, o anel fica parado (linha 57).
  - Texto `Abrindo o painel`, fundo `#F4ECDC`.
  - Ao primeiro frame do Flutter (`flutter-first-frame`), o indicador perde opacidade em 0.24 s e é removido após 240 ms (linhas 98-106). Transição de opacidade de 0.24 s (linha 42).
- O splash é o único "carregamento" de tela cheia. Dentro das telas, `AppStateView.loading` mostra um spinner 20 px com `Carregando` ou mensagem própria (`app_state_view.dart:120-135`).

**Transição entre rotas** (`lib/router/app_router.dart:121-141`):
- Entrada: `FadeTransition` + `SlideTransition` (12 px de subida, comentário na linha 121-123). Duração 240 + 40 = 280 ms, curva `easeOutCubic`.
- Saída: a página anterior faz fade-out (`Curves.easeIn`) em 160 ms (`reverseTransitionDuration`).

**Reveal** (`lib/widgets/ui/app_layout.dart:241-267`): entrada em fade + subida de 16 px, escalonada por `index` (máximo 5 degraus, `clamp(0, 5)`, linha 252). Atraso = `index * 60 ms`, duração total = `160 ms + atraso`. Toca uma vez por montagem. Usado no Painel nos índices 0, 1, 2, 2, 3 (`dashboard_screen.dart:54-86`); o divisor de ornamento tem índice 2 (linha 71-73).

**Micro-interações**:
- Botões (`app_button.dart:204-215`): fundo anima em 90 ms (`AppMotion.fast`). Primário muda para `accentHover` (`#8F3A18`) ao passar o mouse e `accentPressed` (`#7A3114`) ao pressionar (linhas 90-92).
- Foco de teclado: borda `ink` 2 px (`app_button.dart:126`).
- Linhas de lista com `hoverColor: raisedHover`, sem animação própria.
- Pull-to-refresh com `RefreshIndicator` em `accent` (`app_layout.dart:58-63`).
- Aviso de atualização aparece sem animação (`setState` puro).

---

## 4. Como reproduzir / capturar cada estado

Pré-requisitos gerais: login de um usuário do portal. Dependências de backend em `lib/providers/bot_provider.dart` (`GET /robot/status`, `POST /robot/connect`, linha 176 e 53) e nos endpoints de regras e mensagens de `ModerationProvider` e `AutoMessageProvider` (não lidos nesta análise).

| Estado | Backend necessário | Passos |
|---|---|---|
| Robô desligado (sem erro) | `/robot/status` retorna `robot: null`, `session.running: false` | Usuário sem robô conectado. Painel mostra `Robô desligado` + `Conecte o robô para começar a moderar.` |
| Robô desligado com erro de conexão | Conexão rejeitada pelo servidor | Em `/bot`, tentar conectar com senha errada. Voltar ao Painel: detalhe vira `Falha ao conectar o robô. Verifique as credenciais.` (ou o `detail` do servidor). |
| Erro de carregamento inicial | `/robot/status` falha antes de carregar | Derrubar a API ou usar proxy que responda 502/503/504 na primeira abertura. Texto: `Servidor indisponível, tente novamente em instantes.` ou `Não foi possível conectar ao servidor. Verifique sua conexão.` (rede). |
| Aguardando a live | `robot` preenchido, `session.running: false` | Robô conectado sem sessão iniciada. Painel mostra `Aguardando a live`. |
| Moderando a live | `robot` preenchido, `session.running: true`; `counters.messages_sent` e `recent_actions` com dados | Iniciar o robô pela tela `/bot` com uma live ativa. Painel mostra `Moderando a live`, o contador e `Ao vivo`. Atualiza a cada 3 s. |
| Última ação ok | `recent_actions` com `ok: true` | Gerada por moderação real. Texto `Silenciou <nome>` ou `Baniu <nome>`. |
| Última ação com falha | `recent_actions` com `ok: false` | Ação que o robô não conseguiu executar. Texto `Falhou ao silenciar <nome>` / `Falhou ao banir <nome>`. |
| Regras vazias | `mod.rules` vazio | Conta sem palavras cadastradas. Mostra `Nenhuma regra cadastrada`. |
| Fila vazia | `msg.messages` vazio | Conta sem mensagens automáticas. Mostra `Nenhuma mensagem na fila`. |
| Regra desativada | `is_active: false` | Mostra `Desativada` sob a palavra. |
| Aviso de nova versão | Build no servidor diferente do carregado | Local: `flutter build web`, trocar `@@BUILD_ID@@` em `build/web/index.html` por um valor, criar `build/web/build.json` com `{"build":"<mesmo valor>"}`; depois alterar o `build.json`. Em até 5 min, ou ao trocar o foco da aba, o banner aparece em até 15 s (`DEPLOY.md:144-146`). |
| Instalar como app (Chrome/Android) | Navegador com `beforeinstallprompt` (site instalável, não instalado) | Abrir o site em Chrome/Android, ir a Configurações: aparece `Instalar como app` e `Instalar app`. |
| Instalar como app (iOS) | Safari iOS, não instalado | Mesma tela: aparece só o texto do Safari, sem botão. |
| Já instalado | Modo standalone | A seção some. |
| Splash | Primeira carga, sessão em verificação | Recarregar o app; `Abrindo o painel` com a raposa de costas. |
| Mais (celular) | Largura < 900 | Tocar em `Mais` na barra inferior. |
| Lateral (desktop) | Largura >= 900 | Todos os destinos visíveis; chip `Robô online/offline` na lateral. |

Nota: o estado "erro" de sessão do backend (`session.status == error`, `lastError`) não tem tela própria. Para capturar, o efeito visível é só o `running` virar `false`, que cai em `Aguardando a live`.

---

## 5. Dez detalhes de design para close-up em vídeo

1. **Medalhão da raposa na barra superior** (`main_shell.dart:150`, `:190`): `FoxIcon` 36 px, ao lado de `Super Moderator` em Fraunces 20 (`app_type.dart:46`). Assinatura da marca.
2. **Forma "folha" (leaf) no botão principal e no painel de destaque** (`app_shape.dart:18-23`): raio 18 nos cantos superior-esquerdo e inferior-direito; 4 px nos outros. Usada no botão terracota (`app_button.dart:211-214`) e no bloco do robô (`dashboard_screen.dart:163`).
3. **Divisor de videira dourada** (`app_ornament.dart:8-79`): linha de 1 px dourada com uma videira em S e duas folhas no meio, 72 px de largura. Usado no Painel entre o bloco do robô e as listas (`dashboard_screen.dart:71-74`).
4. **Título "Painel" em Fraunces 28 com saudação em Source Sans** (`app_layout.dart:131-140`, `app_type.dart:41-43`): `Painel` + `Boa tarde, <nome>` em linha menor.
5. **Frase principal do robô em Fraunces 44** (`app_type.dart:37-39`, `dashboard_screen.dart:142-143`): `Moderando a live` / `Aguardando a live` / `Robô desligado`, com tracking -0.8 e altura 1.05. Vídeo: destaque do tipo.
6. **Números em Fraunces 36 com figuras tabulares** (`app_type.dart:48-50`, `:33` `FontFeature.tabularFigures`): as três contagens alinhadas em coluna, com divisores hairline entre elas (`dashboard_screen.dart:269-277`).
7. **Pílula ativa na barra inferior** (`main_shell.dart:310-322`): fundo `raised` (sálvia pálido) de 56x28 atrás do ícone, peso do rótulo 700 no ativo. Transição de 160 ms.
8. **Barra dourada de item ativo na lateral** (`main_shell.dart:400-404`): faixa de 3 px `goldLight` sobre fundo `forestSoft`, no tema verde-floresta.
9. **Chips de status com ícone + palavra** (`app_chip.dart:249-283`, `:287-289`): `Ao vivo`, `Conectado`, `Desconectado`, `Robô online`. A cor fica no ícone e o fundo é sálvia, nunca só cor.
10. **Listas em painel único com divisores hairline** (`app_list_row.dart:298-324`): todas as linhas de regras e mensagens ficam em um painel de `surface`, com borda 1 px `rule`, e uma `Divider` entre elas. Sem sombras no app inteiro (comentário em `app_surface.dart:199-202`).

Extras que valem plano curto: o `AppStateView` com raposa à direita e `sleeping` (`app_state_view.dart:166-191`, usado no Painel só como texto); e a raposa `headLaugh` no bloco "Moderando a live" (`dashboard_screen.dart:135-137`), 190 px de altura.

---

## Divergências e pontos a conferir
- `main_shell.dart:35` diz sidebar de 240 px; o código usa 248 (`main_shell.dart:346`).
- `app_motion.dart:3` diz que só transform e opacidade animam; a pílula anima `color` (`main_shell.dart:310-318`).
- `dashboard_screen.dart:257`: "regras ativas" conta todas as regras, inclusive desativadas (`mod.rules.length`).
- Nome do app: `Super Moderator` (barra/lateral) x `Atila's Client` (aba, manifest, texto de instalação).
- Painel não distingue `waiting_for_live`/`starting`/`stopping`/`error` do backend; só `running` booleano.
- Não lidos: `lib/providers/auth_provider.dart`, `moderation_provider.dart`, `auto_message_provider.dart`, `lib/router` (completo), `app_text_field.dart`, `app_dialogs.dart`, `app_data_table.dart`, `app_switch.dart`. Os endpoints de regras e mensagens não foram verificados.
