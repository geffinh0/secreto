# Análise de produto: Mensagens automáticas, Estatísticas, Configurações e Login/Cadastro

Escopo lido integralmente: `lib/screens/messages/auto_messages_screen.dart`, `lib/screens/stats/stats_screen.dart`, `lib/screens/settings/settings_screen.dart`, `lib/screens/settings/import_config_card.dart`, `lib/screens/auth/login_screen.dart`, `register_screen.dart`, `change_password_screen.dart`, `lib/providers/auto_message_provider.dart`, `lib/providers/stats_provider.dart`, e as rotas `/messages`, `/settings`, `/stats`, `/activity`, mais `/config/import`, `/auth/*` e as funções de apoio de `backend/main.py`, `backend/db.py`, `backend/security.py`, `backend/engine.py` e `lib/core/models/models.dart`.

Caminhos abreviados: `APP/` = `/home/user/secreto/`.

---

## 1. Telas: funções e textos exatos

### 1.1 Mensagens automáticas (`APP/lib/screens/messages/auto_messages_screen.dart`)

Título da página (linhas 57-60):
- Título: `Mensagens automáticas`
- Subtítulo: `O robô envia as mensagens da fila em ordem, em repetição, durante a live.`

Layout: no desktop (`AppSpacing.isWide`, linhas 36-44) a fila fica à esquerda (flex 3) e as configurações à direita (flex 2). No celular (linhas 45-52) a ordem é configurações, depois fila.

Carregamento: `initState` dispara `_load()` após o primeiro frame (linhas 17-25), que chama `AutoMessageProvider.load(user.id)`.

**Bloco "Envio automático"** (`_SendSettings`, linhas 144-206)
- Seção: `Envio automático`
- Switch: `Enviar mensagens automáticas` / subtítulo `O robô envia a fila em repetição durante a live.` (linhas 153-154)
- Campo: label `Intervalo entre mensagens (mínimo 10 segundos)`, sufixo `s`, habilitado só com o switch ligado (linhas 165-166)
- Atalhos (chips, linhas 184-192): `30 s`, `1 min`, `2 min`, `5 min`. Valores 30, 60, 120, 300. Também só ativos com o switch ligado.
- Botão: `Salvar configurações` (chave `save_settings_button`, linha 198)
- Validação (linhas 110-121): valor fora de 10..3600 mostra `O intervalo deve ficar entre 10 e 3600 segundos.`
- Feedback (linhas 132-139): `Configurações salvas.` ou o erro do provider, senão `Não foi possível salvar as configurações. Tente de novo.`
- Ao salvar, envia só os dois campos (linhas 125-128): `auto_messages_enabled` e `message_interval_seconds`.

**Bloco "Fila de mensagens"** (`_Queue`, linhas 210-248)
- Seção: `Fila de mensagens`
- Subtítulo: `Arraste para reordenar. Toque numa mensagem para editar ou excluir.` (linhas 234-235)
- Contador (linha 236): `1 mensagem` ou `N mensagens`
- Carregando: `Carregando mensagens` (linha 221)
- Vazia (linhas 223-226): ilustração de raposa dormindo, título `Nenhuma mensagem na fila`, texto `Escreva a primeira mensagem acima para o robô enviar.`

**Formulário de adição** (`_AddMessageForm`, linhas 250-313)
- Campo: `Nova mensagem`, dica `Exemplo: Obrigada por acompanharem a live.`, 2 a 4 linhas, máximo 280 caracteres (linhas 293-300)
- Botão: `Adicionar à fila` (chave `add_message_button`, linha 304)
- Texto vazio: não faz nada (linha 270). Após sucesso, limpa o campo (linha 275).
- Erro: `provider.error` ou `Não foi possível adicionar a mensagem. Tente de novo.` (linhas 279-283)

**Lista reordenável** (`_MessageList`, linhas 315-372)
- `ReorderableListView` com `buildDefaultDragHandles: false`. Só a alça (`Icons.drag_indicator`, semântica `Reordenar`, linhas 339-347) inicia o arraste.
- Título da linha = texto da mensagem.
- Subtítulo: `Ativa` ou `Desativada: o robô pula esta mensagem` (linhas 349-351)
- Switch por linha, semântica `Mensagem ativa` (linhas 352-366). Chama `toggleMessage`, que faz um PUT completo do registro.
- Toque na linha abre o diálogo de edição (linha 367).

**Diálogo de edição** (`_EditMessageDialog`, linhas 424-494)
- Título: `Editar mensagem` (linha 455)
- Campo: `Mensagem`, 3 a 6 linhas, máximo 280, autofocus (linhas 457-464)
- Botões (linhas 471-486): `Excluir mensagem` (perigo), `Cancelar`, `Salvar mensagem`
- Confirmação de exclusão (linhas 382-390): título `Excluir mensagem`; texto `A mensagem sai da fila e o robô deixa de enviá-la. Essa ação não pode ser desfeita.`; botão de confirmação `Excluir mensagem`, destrutivo.
- Salvar com texto vazio não faz nada (linha 405).

### 1.2 Estatísticas (`APP/lib/screens/stats/stats_screen.dart`)

- Carregamento inicial: `_load(30)` (linha 20). Os períodos são `7`, `30` e `90` (linha 49).
- Cabeçalho: título `Estatísticas`, subtítulo `Moderação nos últimos ${days} dias` (linhas 38-39).
- Chips de período: `7 dias`, `30 dias`, `90 dias` (linhas 50-53). Ao trocar, recarrega.
- Carregando: `Carregando estatísticas` (linha 60).
- Erro sem dados (linhas 61-69): título `Não foi possível carregar as estatísticas`, mensagem do provider, botão `Tentar de novo`.
- Pull-to-refresh: `onRefresh` recarrega o período atual (linha 34).

Blocos (linhas 70-81), em ordem:
1. **Totais** (`_Totals`, linhas 87-118): número grande com `ações no total`. Três figuras: `silenciadas` (mutes), `banidas` (kicks), `taxa de sucesso`. Taxa mostra `—` quando não há ações, senão percentual arredondado (linhas 93-95).
2. **Palavras mais acionadas** (`_TopKeywords`, linhas 181-205): barras horizontais, uma por palavra, proporcionais ao máximo. Vazio: `Nenhuma ação registrada` / `Nenhuma palavra foi acionada nesse período.`
3. **Lives recentes** (`_RecentLives`, linhas 207-241): tabela com colunas `Live` e `Ações`. Data no formato `dd/MM 'às' HH:mm` (linha 230). Sem data: `ID da live ${livestreamId}`. Vazio: `Nenhuma live com ações` / `Nenhuma live teve ações nesse período.`
4. **Ações por dia** (`_ByDay`, linhas 243-270): barras por dia no formato `dd/MM`, em ordem invertida (`days.reversed`, linha 261). Vazio: `Nenhuma ação foi feita nesse período.`

Os blocos 2 e 3 ficam lado a lado (`AppSplit` ratio 0.5, linhas 74-79).

Não há gráfico de linha, pizza ou biblioteca de gráficos. Tudo são barras com `FractionallySizedBox` (linhas 166-174).

### 1.3 Configurações (`APP/lib/screens/settings/settings_screen.dart`)

Título da página: `Configurações` (linha 133).

Seções, em ordem (coluna principal à esquerda e secundária à direita no desktop, linhas 108-129):
- **Conta** (linhas 22-39): `Nome` (nome exibido, ou `—`), `Usuário` (`@username`), `Tipo` = `Administrador` ou `Streamer`.
- **Segurança** (linhas 41-51): botão `Alterar senha`, navega para `/change-password`.
- **Importar configurações** (`ImportConfigCard`, linha 113). Detalhado na seção 4.
- **Instalar como app** (`_PwaInstallSection`, linhas 168-223). Some se já está em modo standalone (linha 190) ou se o navegador não oferece instalação (linha 194). Texto no iOS (linha 204): `No Safari, toque em compartilhar e depois em "Adicionar à Tela de Início".` Texto em outros: `Instale o Atila's Client como app: abre em tela cheia, com ícone próprio e sem a barra de endereço.` Botão `Instalar app` (chave `install_pwa_button`).
- **Conta do robô** (linhas 53-75): subtítulo `Para conectar o robô, abra a página Robô e informe as credenciais da conta oficial.` Chip `Conectado` ou `Desconectado`. Se conectado, mostra o apelido, com fallback `Atila's Client`.
- **Atividade da conta** (`_ActivitySection`, linhas 227-322). Ver abaixo.
- **Sobre o Atila's Client** (linhas 77-90): `Versão` (`AppConstants.appVersion`) e `Plataforma` = `SuperLive v2.31.0`.
- **Sair** (linhas 92-106): subtítulo `Encerra a sessão neste dispositivo. O robô continua como está.` Botão `Sair da conta` (chave `logout_button`). No desktop fica na coluna principal; no celular, no fim da página (linhas 114, 124-127).

Atividade (`GET /activity?limit=20`, linha 246):
- Título: `Atividade da conta`
- Carregando: `Carregando atividade`
- Erro: título `Atividade indisponível`, botão `Tentar de novo`
- Vazio: `Nenhuma atividade ainda` / `As ações feitas nesta conta aparecem aqui.`
- Cada linha: rótulo em português (de `ActivityEntry.label`, `models.dart` linhas 585-605), detalhe e data `dd/MM HH:mm`.

Rótulos já mapeados em `models.dart`: `Login no portal`, `Conta criada`, `Palavra de moderação adicionada/alterada/removida`, `Mensagem automática adicionada/alterada/removida`, `Configurações alteradas`, `Robô conectado`, `Robô desconectado`, `Moderação iniciada`, `Moderação parada`, `Moderação iniciada automaticamente`, `Streamer ao vivo & Robô conectado`, `Resumo da Transmissão`, `Live encerrada`, `Live alterada`, `Aguardando nova transmissão`.

**Lacunas encontradas na atividade:**
- `config_imported` (gravado em `backend/main.py:890`) não tem rótulo em `models.dart` e cai no `_ => action` (linha 615). Na tela aparece o texto bruto `config_imported`.
- `password_changed` (gravado em `backend/main.py:680`) também não tem rótulo. Aparece como `password_changed`.
- `_iconFor` (`settings_screen.dart:262-276`) também não trata esses dois tipos. Caem no ícone `history`.

### 1.4 Login (`APP/lib/screens/auth/login_screen.dart`)

- Título: `Entre na sua conta`. Subtítulo: `Gerencie o robô que modera as suas lives.` (linhas 45-46)
- Rodapé: `Ainda não tem conta?` + botão `Criar conta` → `/register` (linhas 47-51)
- Campo `Usuário`, dica `Seu nome de usuário` (linhas 59-61)
- Campo `Senha`, dica `Sua senha`, com botão de mostrar/ocultar, tooltips `Mostrar senha` / `Ocultar senha` (linhas 70-86)
- Obrigatórios: `Preencha este campo` (linhas 65, 88)
- Botão `Entrar` (chave `login_submit_button`, linha 93). Sucesso → `/dashboard` (linha 36).
- Erro: banner `AuthErrorBanner` com `auth.error` (linha 57).
- Mensagens do backend (`main.py`): `Credenciais inválidas` (401, linha 622); `Muitas tentativas de login. Aguarde alguns minutos.` (429, linha 610); `Esta senha provisória já foi usada ou expirou. Peça uma nova ao administrador.` (401, linha 634).

### 1.5 Cadastro (`APP/lib/screens/auth/register_screen.dart`)

- Título: `Criar conta`. Subtítulo: `Use o código da sua agência para configurar o portal de moderação.` (linhas 65-67)
- Rodapé: `Já tem conta?` + `Entrar` → `/login` (linhas 68-72)

Campos, na ordem da tela:
1. `Código da agência`, dica `Peça o código à sua agência`. Converte para maiúsculas ao digitar (linhas 80-86). Vazio: `Informe o código da sua agência` (linha 89).
2. `Nome de exibição`, dica `Como você quer aparecer`. Vazio: `Preencha este campo` (linhas 94-99). Backend: máximo 60 caracteres (`main.py:342`).
3. `Usuário`, dica `Sem espaços ou caracteres especiais`. Vazio: `Preencha este campo`. Com espaço: `Sem espaços` (linhas 104-112).
4. `Senha`, ajuda `Mínimo de 8 caracteres, com uma letra maiúscula e um caractere especial`. Vazio: `Preencha este campo`. Depois: `passwordRuleError` (linhas 116-129).
5. `Confirmar senha`. Diferente: `As senhas não coincidem` (linhas 133-141).

Botão `Criar conta` (chave `register_submit_button`, linha 146). Sucesso → `/dashboard`.

Mensagens do backend (`main.py`):
- `Cadastro de novas contas está temporariamente desativado.` (403, linha 569, quando `SM_ALLOW_REGISTRATION` ≠ 1)
- `Muitas tentativas de cadastro. Aguarde alguns minutos.` (429, linha 572)
- `Código de agência inválido. Peça o código à sua agência.` (400, linha 578). Mesma resposta para código inexistente e agência desativada, de propósito.
- `Esse nome de usuário já está em uso. Escolha outro.` (400, linha 579)
- Usuário fora da regra: `use 3 a 32 caracteres: letras, números, ponto, hífen ou underline` (`main.py:350`, regex em `main.py:66`).

### 1.6 Alterar senha (`APP/lib/screens/auth/change_password_screen.dart`)

Dois modos, decididos por `auth.mustChangePassword`:
- **Forçado** (senha provisória): título `Escolha a sua senha`; subtítulo `Você entrou com uma senha provisória. Ela só vale uma vez: crie agora uma senha só sua para continuar.` (linhas 78-81). Sem seta de voltar (linha 83). Campo atual rotulado `Senha provisória` (linha 106). Botão `Sair` extra (linhas 161-168).
- **Voluntário** (a partir de Configurações): título `Alterar senha`; subtítulo `Por segurança, as suas outras sessões serão encerradas.` (linha 82). Seta de voltar, `Voltar` (linha 86). Campo atual rotulado `Senha atual`.

Campos: `Nova senha` com ajuda `Mínimo de 8 caracteres, com uma letra maiúscula e um caractere especial. Não use seu usuário, nome ou senhas comuns.` (linhas 127-129). `Confirmar nova senha`. Botão `Salvar nova senha` (chave `change_password_submit_button`). Sucesso: snackbar `Senha alterada` e vai para `/dashboard` (linha 60).

Mensagens locais:
- `Use uma senha diferente da atual` (linha 136)
- `As senhas não coincidem` (linha 149)

Mensagens do backend:
- `A senha atual está incorreta.` (400, `main.py:666`)
- `A nova senha precisa ser diferente da atual.` (400, `main.py:668`)
- `Muitas tentativas. Aguarde alguns minutos.` (429, `main.py:662`)
- Senha fraca: 422 com `Senha fraca: ` seguido da lista de problemas (`main.py:671`).

---

## 2. Estatísticas: o que mostra de fato e como gerar dados reais de teste

### 2.1 Fonte dos dados

`GET /stats?user_id=&days=` (`main.py:1577-1581`) chama `db.get_stats` (`backend/db.py`, função a partir de ~linha 614). Tudo sai da tabela `moderation_log` (schema em `db.py:169-184`), que tem uma linha por ação automática de mute ou kick. Colunas relevantes: `livestream_id`, `target_name`, `action` (`mute`/`kick`), `keyword`, `ok`, `created_at`.

Campos retornados e uso na tela:
- `days`: período.
- `total_actions`: `COUNT(*)` no período. Inclui ações falhas.
- `mutes` e `kicks`: contagens por `action`, também no período.
- `success_rate`: `ok=1 / total`, arredondado para 4 casas. `null` se não há ações.
- `top_keywords`: `keyword` agrupado, `ORDER BY n DESC LIMIT 8` (db.py ~linha 631).
- `by_day`: `date(created_at)`, `ORDER BY day` ASC.
- `recent_lives`: `livestream_id` agrupado, `LIMIT 10`, `ORDER BY first_at DESC`. Mostra data da primeira ação e contagem.

Pontos que o produto precisa saber:
- A tela não tem filtro por tipo de ação. Mute e kick aparecem só nas figuras de topo.
- `taxa de sucesso` conta ações com `ok=1`. Ações falhas (por exemplo, o robô não é moderador, `engine.py` ~linha 1140-1155) só aparecem no total.
- Palavras vêm de `keyword` gravada no log. Se a regra foi removida, a palavra ainda aparece no histórico.
- Em `by_day`, o `date()` do SQLite usa UTC (`datetime('now')` padrão). Um horário de Brasil após 21h cai no dia seguinte. Vale checar antes de gravar vídeo.
- `_load` no `StatsProvider` (linha 27-43) zera `stats` em caso de erro. Na troca de período com dados antigos, a tela mantém os dados antigos enquanto carrega.

### 2.2 Como gerar dados reais plausíveis

Não existe seed nem script de demo no repositório. Os testes em `backend/tests/` (`test_unit.py`, `test_integration.py`) usam banco próprio. Não li esses testes, então não sei se eles reaproveitam fixtures.

Caminho recomendado (banco de desenvolvimento isolado):

1. Backend com banco dedicado: `export SM_DB_PATH=/tmp/demo.db` (ou pasta de scratchpad). `DB_PATH` vem de `SM_DB_PATH` (`db.py:11-12`).
2. Criar agência: `db.create_agency(conn, "Agência Demo")` (`db.py`, `create_agency`), que devolve o código no formato `XXXX-XXXX`. Alternativa: `POST /admin/agencies` com login de admin, bootstrap por `ADMIN_BOOTSTRAP_USERNAME` e `ADMIN_BOOTSTRAP_PASSWORD` (`main.py:1591-1592`).
3. Cadastrar a streamer: `POST /auth/register` com `{"username":"lia.demo","password":"Senha@Forte1","display_name":"Lia Demo","agency_code":"XXXX-XXXX"}`. A senha precisa passar nas regras do servidor (seção 5).
4. Criar regras: `POST /moderation/rules` com `{"user_id":N,"keyword":"...","action":"mute"|"kick"}`, ou `POST /moderation/rules/bulk` com uma lista (`main.py:736`).
5. Gravar as ações. Não há rota pública para gravar `moderation_log`. Use `db.log_action(user_id, livestream_id, target_user_id, target_name, action, keyword, message_text, ok, detail)` (`db.py`, `log_action`, INSERT em ~linha 557). É a mesma função que o motor usa (`engine.py:1152-1154`). Ela já aplica o limite de 2000 linhas por usuário (`MAX_LOG_ROWS`, `db.py:16`).
6. Espalhar as datas. `log_action` grava `created_at = datetime('now')`. Para parecer histórico, rodar depois um UPDATE do tipo `UPDATE moderation_log SET created_at = datetime('now', '-' || ? || ' days') WHERE id = ?`, com `?` sorteado entre 0 e 29 (ou 0 e 89 para o período de 90 dias).
7. Gerar cerca de 60 a 150 linhas: 3 a 4 lives (`livestream_id` como `"7301844"`, `"7302310"` etc.), 8 a 12 palavras de regra com pesos desiguais, 85% de `ok=1`, mute em ~70% e kick em ~30%. Nomes de alvo fictícios, sem dados reais de terceiros.
8. Consultar com `GET /stats?user_id=N&days=30` para validar e abrir o app apontando para esse backend.

Limites: não é possível gerar `recent_lives` real sem uma live de verdade. O robô só grava ações reais de chat quando conectado a uma live do SuperLive (rotas `/robot/*`, `main.py:1174-1560`). Para vídeo, o dado sintético basta, mas o texto da live (`Live` com ID numérico) não é um nome de streamer.

---

## 3. Mensagens automáticas: ordem, repetição, reordenação, edição, exclusão e intervalo

### 3.1 Ordem

- Backend: `GET /messages` ordena por `sort_order ASC, id ASC` (`main.py:970`).
- Provider: `messages` reordena de novo no cliente (`auto_message_provider.dart:15-16`).
- Nova mensagem recebe `sort_order = maior + 1` (`auto_message_provider.dart:48-51`). Se a fila está vazia, recebe 0.
- Limite backend: `sort_order >= 0` (`main.py:408`, `422`).

### 3.2 Repetição (motor)

`_auto_message_loop` (`backend/engine.py:1164-1190`):
- Dorme `_interval` segundos, relê a configuração com `force=True` e só envia se: há live ativa (`livestream_id` não nulo), `auto_messages_enabled` é verdadeiro e há mensagens na lista.
- Escolhe `messages[index % len(messages)]`, com `index` incrementado a cada envio. Ou seja, percorre a lista em ordem e volta ao início, em loop.
- Quando não há live, o `continue` não avança o índice. O ciclo recomeça do ponto onde parou.
- Envio pelo SuperLive: `send_text` (`superlive.py:769`).
- Erro de autenticação do robô para o loop com `_fail`, com mensagem `O token do robô expirou. Reconecte o robô na aba Robô.`

Ponto a confirmar: a UI diz que mensagens desativadas são puladas (`auto_messages_screen.dart:351`). O loop lê `cfg["messages"]`. Não confirmei se `load_engine_config` filtra `is_active = 1` para as mensagens (confirmado apenas para as regras, `db.py`, `load_engine_config`, `WHERE user_id = ? AND is_active = 1`). Se não filtrar, a promessa da UI está errada.

### 3.3 Intervalo

- Padrão: 120 s (`db.py` schema, `bot_settings.message_interval_seconds DEFAULT 120`; `models.dart:246`).
- Mínimo: 10 s no motor (`engine.py:92`, `_interval` em `engine.py:1195-1198` aplica `max(10, valor)`).
- Mínimo e máximo na API: `ge=10`, `le=3600` (`main.py:440`).
- Mínimo e máximo na UI: 10 a 3600 (`auto_messages_screen.dart:112-113`, usando `BotSettings.minIntervalSeconds/maxIntervalSeconds`, `models.dart:189-190`).
- Os atalhos são 30 s, 1 min, 2 min e 5 min. O atalho de 30 s está válido para o backend.
- Inconsistência: a UI aceita 10 a 3600, mas o atalho de 30 s faz o chip ficar selecionado só se o texto for exatamente `30`. Edição manual de `30` e `030` tem resultado diferente. Detalhe pequeno.

### 3.4 Reordenar por arrastar

- Só pela alça `drag_indicator` (`auto_messages_screen.dart:339-347`).
- `AutoMessageProvider.reorderMessages` (`auto_message_provider.dart:97-113`):
  1. Move o item no cliente e reatribui `sort_order` = índice (0..n-1).
  2. Atualiza a tela na hora (otimista).
  3. Faz um `PUT /messages/{id}` com `{"sort_order": n}` para cada mensagem da fila, em sequência. Não confere o resultado de cada chamada.
- Achado: a reordenação envia N requisições para N mensagens, mesmo que só duas trocaram de lugar. Em fila longa, a janela de inconsistência é maior. Se uma chamada falhar no meio, o cliente fica com uma ordem e o servidor com outra, sem aviso ao usuário (o erro não é gravado em `_error`).
- Backend: `sort_order`-only não gera linha de atividade (`main.py:1009-1011`, comentário "too noisy").

### 3.5 Editar

- Toque na linha abre o diálogo (seção 1.1). `Salvar mensagem` faz `PUT /messages/{id}` com o `toJson()` completo, incluindo `user_id` e `sort_order` (`auto_message_provider.dart:66-79`). Backend ignora campos fora de `AutoMessageUpdate`.
- Limites: `content` entre 1 e 500 caracteres após `strip` (`main.py:420-433`). A tela limita a 280 (`auto_messages_screen.dart:299` e `463`). Achado: tela e API divergem em 280 versus 500. A importação aceita 500 (`main.py:820`). Mensagem importada com 300 a 500 caracteres não pode ser editada na tela sem ser cortada.
- Log: `message_updated` só quando muda `content` ou `is_active` (`main.py:1009-1011`).

### 3.6 Excluir

- Diálogo de confirmação (seção 1.1). `DELETE /messages/{id}` (`main.py:1016-1023`).
- Após sucesso, o cliente renumera a fila localmente (`_reorderAfterDelete`, `auto_message_provider.dart:137-143`). Achado: essa renumeração não é gravada no servidor. Os `sort_order` do banco ficam com buracos (por exemplo 0, 2, 3). Não afeta a ordem, porque o `ORDER BY` é relativo, mas cria divergência entre cliente e servidor até a próxima reordenação.
- Log: `message_deleted` com `mensagem #id` (`main.py:1022`). O texto da mensagem não é gravado.

### 3.7 Ativar e desativar (switch por linha)

- `PUT` completo com `is_active` invertido (`auto_message_provider.dart:81-82`).
- Desativada: subtítulo `Desativada: o robô pula esta mensagem`. Ver ponto a confirmar em 3.2.

### 3.8 Criação

- `POST /messages` (`main.py:975-986`). Sem checagem de duplicidade na rota. A importação faz essa checagem (seção 4), mas o formulário manual não.
- Log: `message_created` com os primeiros 80 caracteres (`main.py:984`).

---

## 4. Configurações e importação de configuração

### 4.1 O que o `ImportConfigCard` importa e de onde

Origem: o usuário cola o conteúdo de um arquivo `.json` de backup no campo `Conteúdo do backup` (`import_config_card.dart:196-213`). Não há seletor de arquivo. O conteúdo vem de um backup gerado fora deste app. Não encontrei nenhum botão de exportação nos arquivos lidos.

Formato aceito (`main.py:774-796`):
```json
{
  "format": "atilas-config",
  "version": 1,
  "rules":    [ { "keyword": "...", "action": "mute" | "kick", "is_active": true } ],
  "messages": [ { "content": "...", "sort_order": 0, "is_active": true } ]
}
```
- Só estas quatro chaves são lidas. Nada no arquivo pode trocar usuário, robô, token ou configuração (`main.py:782-784`).
- Limites: até 5000 palavras (`CONFIG_MAX_RULES`, `main.py:776`) e até 500 mensagens (`CONFIG_MAX_MESSAGES`, `main.py:777`).
- Mensagens de arquivo errado: `Arquivo inválido: não é um backup de configurações do Atila's Client.` (`main.py:793`) e `Versão N do arquivo não é suportada por este app.` (`main.py:795`).

Regras de aceitação por item (`main.py:799-825`):
- Palavra: texto obrigatório, normalizado (minúsculas, espaços colapsados), até 60 caracteres, `action` deve ser `mute` ou `kick`.
- Mensagem: texto obrigatório, após `strip`, até 500 caracteres. `sort_order` inválido vira "sem ordem" e usa a posição no arquivo.
- Itens inválidos são listados (`Palavra #N: motivo`, `Mensagem #N: motivo`), no máximo 20 (`CONFIG_INVALID_SHOWN`, `main.py:778`). A tela mostra no máximo 8 (`import_config_card.dart:153`).

Duplicatas (`main.py:839-860`, `869-873`):
- Palavra: duplicada se a mesma palavra normalizada já existe com a mesma `action`. Mute e kick podem coexistir.
- Mensagem: duplicada se o texto, em minúsculas e com espaços colapsados, já existe.

Efeito: mensagens novas entram depois da última existente (`next_order`, `main.py:845-846`), mantendo a ordem do arquivo (`main.py:874-878`).

### 4.2 Fluxo na tela

1. `Conferir arquivo` chama `POST /config/import?dry_run=true`. Não grava nada. Mostra `O que vai acontecer` (`import_config_card.dart:143`).
2. `Importar` só fica habilitado se a conferência mostrou pelo menos um item criado (`import_config_card.dart:180-184`, `257`). Chama `POST /config/import` sem `dry_run`.
3. Resultado: `Importação concluída`. Recarrega regras e mensagens (`_reloadLists`, linhas 96-102).
4. Linhas de resumo (chaves de teste `import_rules_line` e `import_messages_line`): `Palavras de moderação: N serão adicionadas · M já existiam · K inválidas`. Em mensagens: `Mensagens automáticas: ...`.

Textos fixos da seção:
- Título: `Importar configurações`
- Subtítulo: `Traga as palavras de moderação e as mensagens automáticas de um arquivo de backup para esta conta. Nada é apagado: o que já existe é mantido e repetidas são ignoradas. A conexão com o robô e as demais configurações não mudam.`
- Erros locais: `Cole aqui o conteúdo do arquivo de backup (.json).` e `Isso não parece um arquivo de backup. Cole o conteúdo completo do .json, do primeiro "{" ao último "}".`
- Botões: `Conferir arquivo`, `Importar`.
- Erro do servidor sem mensagem: `Não foi possível ler o arquivo.`
- Falha de banco: `Não foi possível importar. Nada foi alterado.` (`main.py:889`, com rollback).

Após importar com sucesso, o campo é limpo (`import_config_card.dart:83`). Editar o campo limpa a conferência anterior (linhas 204-211). Nota: o campo é desabilitado durante a operação (linha 203).

Registro: `config_imported` com contagens (`main.py:890-891`). Ver lacuna de rótulo na seção 1.3.

### 4.3 Configurações que não mudam pela importação

A importação não toca `bot_settings`. Liga/desliga, intervalo e demais opções continuam como estavam.

### 4.4 Opções de `bot_settings` (escritas por `PUT /settings/{user_id}`, `main.py:1038-1061`)

Campos aceitos (`BotSettingsUpdate`, `main.py:436-445`):
- `auto_messages_enabled` (bool)
- `message_interval_seconds` (10 a 3600)
- `moderation_enabled` (bool)
- `kick_permanent` (bool)
- `diamond_immunity_enabled` (bool)
- `diamond_immunity_threshold` (mínimo 50, máximo 1 000 000, `db.py` ~27)

Atualização parcial: só campos enviados são gravados. Registra `settings_updated` com a lista de chaves (`main.py:1060`).

Na tela de Mensagens só são usados `auto_messages_enabled` e `message_interval_seconds`. Os demais campos são editados em outras telas, que não foram lidas nesta análise.

Achado: `kick_permanent`, `moderation_enabled` e `diamond_immunity_*` existem no backend e no modelo Dart, mas não aparecem em `settings_screen.dart`. O `SettingsScreen` não tem controle para essas opções. Se elas são editadas em outra tela (moderação ou robô), a informação não está nas telas lidas.

---

## 5. Login e cadastro: código de agência e regras de senha

### 5.1 Código de agência

- Formato: 8 caracteres do alfabeto `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (sem 0, O, 1, I), exibido como `XXXX-XXXX` (`db.py`, `CODE_ALPHABET`, `CODE_LENGTH`, `format_agency_code`).
- Normalização na API: maiúsculas, sem espaços e sem traços (`normalize_agency_code`, `db.py`). Então `ab12-cd34` e `AB12CD34` valem igual.
- Na tela: o campo converte para maiúsculas ao digitar (`register_screen.dart:83-86`). Não remove o traço, mas o servidor aceita com ou sem.
- Código inválido ou agência desativada: mesma mensagem (`main.py:578`). Para o registro, só há desativação global com `SM_ALLOW_REGISTRATION`.

### 5.2 Regras de senha

Regras no cliente (`change_password_screen.dart:10-27`, função `passwordRuleError`, usada também no cadastro):
1. Mínimo 8 caracteres → `Use pelo menos 8 caracteres`
2. Pelo menos uma letra maiúscula → `Use pelo menos uma letra maiúscula`
3. Pelo menos um caractere especial (não letra, não dígito, não espaço) → `Use pelo menos um caractere especial (como ! @ # $ % & *)`

Regras no servidor (`backend/security.py:57-90`, função `password_problems`). Mensagens exatas, prefixadas por `senha fraca: ` no cadastro (`main.py:332-334`):
- `use pelo menos 8 caracteres`
- `use no máximo 128 caracteres`
- `use pelo menos uma letra maiúscula`
- `use pelo menos um caractere especial (como ! @ # $ % & *)`
- `não use o seu nome de usuário na senha` (quando o nome de usuário, sem símbolos, tem 3 ou mais caracteres e aparece na senha)
- `não use o seu nome de exibição na senha` (4 ou mais caracteres)
- `essa senha é muito comum, escolha outra` (lista em `security.py:47-55`, comparada sem dígitos nem símbolos)
- `a senha tem caracteres repetidos demais` (3 ou menos caracteres distintos)
- `não use sequências como 1234567890 ou abcdefghij`

Achado: o cliente só checa as três primeiras regras. As demais chegam como erro do servidor. Na tela de cadastro, a ajuda diz `Mínimo de 8 caracteres, com uma letra maiúscula e um caractere especial`, mas o servidor também rejeita nome de usuário, nome de exibição, senhas comuns, repetição e sequências. A ajuda da troca de senha menciona isso (`Não use seu usuário, nome ou senhas comuns.`), a do cadastro não.

Achado: a mensagem de erro do servidor no cadastro passa pela validação do Pydantic (`main.py:353-357`). O texto exibido depende de `_describe_validation_error` (`main.py:221-243`), que não li integralmente. Não confirmo a string exata que o usuário vê nesse caso. Na troca de senha ela vem de `main.py:671` como `Senha fraca: ...`.

Limite de tamanho: 128 caracteres (`security.PASSWORD_MAX_LENGTH`).

Troca de senha no servidor (`main.py:650-681`): exige a senha atual; a nova precisa ser diferente; grava a nova; apaga as outras sessões do usuário, mantendo a atual (`main.py:676`); registra `password_changed`.

### 5.3 Senha provisória

- Emitida pelo administrador (`main.py:1705`, rota admin, não lida em detalhe).
- Vale uma vez, dentro de uma janela de tempo. O login a consome de forma atômica (`main.py:625-634`).
- Depois do login, o usuário fica com `must_change_password` e todas as rotas exigem a troca (`main.py:280-285`, 403 com `Defina uma nova senha para continuar usando o sistema.`).

---

## 6. Roteiro de gravação em vídeo

Preparação comum: backend com banco de demonstração (seção 2.2), uma streamer com 3 a 4 lives, 10 a 15 palavras de regra, 6 a 8 mensagens ativas, uma desativada e um robô conectado para as telas de Configurações. Idioma do app: português. Tela em modo celular e desktop, para mostrar os dois layouts.

**Cena 1: Login (≈ 25 s)**
1. Abrir `/login`. Mostrar título `Entre na sua conta` e a raposa no layout largo.
2. Digitar usuário e senha. Mostrar `Mostrar senha` ao clicar no olho.
3. Errar a senha de propósito: mostrar `Credenciais inválidas` no banner.
4. Acertar e entrar em `/dashboard`.

**Cena 2: Cadastro (≈ 40 s)**
1. Em `/login`, clicar em `Criar conta`.
2. Digitar o código da agência em minúsculas e mostrar a conversão para maiúsculas.
3. Digitar nome de usuário com espaço: mostrar `Sem espaços`.
4. Digitar senha fraca (`senha`): mostrar `Use pelo menos 8 caracteres`, depois `Use pelo menos uma letra maiúscula` e `Use pelo menos um caractere especial (como ! @ # $ % & *)`.
5. Confirmar com senha diferente: `As senhas não coincidem`.
6. Cadastro válido e entrada no dashboard.

**Cena 3: Alterar senha (≈ 30 s)**
1. Em Configurações, `Alterar senha`. Mostrar a ajuda do campo.
2. Senha atual errada: `A senha atual está incorreta.`
3. Nova igual à atual: `Use uma senha diferente da atual`.
4. Senha válida: `Senha alterada` e volta ao dashboard.

**Cena 4: Mensagens automáticas, fila (≈ 60 s)**
1. Abrir `/messages`. Título `Mensagens automáticas` e subtítulo.
2. Mostrar a fila com `N mensagens`. Mostrar uma linha `Desativada: o robô pula esta mensagem`.
3. Adicionar uma mensagem em `Nova mensagem`, com o contador de 280 caracteres.
4. Arrastar pela alça `Reordenar` e mostrar a nova ordem.
5. Tocar numa mensagem: diálogo `Editar mensagem`. Salvar com texto novo.
6. Excluir: mostrar `Excluir mensagem` com a mensagem de confirmação e concluir.
7. Estado vazio: sem mensagens, mostrar `Nenhuma mensagem na fila`.

**Cena 5: Mensagens automáticas, envio (≈ 40 s)**
1. Ligar `Enviar mensagens automáticas`. Mostrar o campo de intervalo habilitado.
2. Digitar `5` e mostrar `O intervalo deve ficar entre 10 e 3600 segundos.`
3. Clicar no chip `1 min` e depois `Salvar configurações` → `Configurações salvas.`
4. Desligar o switch: o campo e os chips ficam desabilitados.

**Cena 6: Estatísticas (≈ 60 s)**
1. Abrir `/stats`. Título `Estatísticas` e `Moderação nos últimos 30 dias`.
2. Mostrar o número grande `ações no total`, com `silenciadas`, `banidas` e `taxa de sucesso`.
3. Mudar o período para `7 dias` e depois `90 dias`. Mostrar a atualização do subtítulo.
4. Mostrar `Palavras mais acionadas` (barras) e `Lives recentes` (datas `dd/MM 'às' HH:mm`).
5. Rolar até `Ações por dia` (datas mais recentes no topo).
6. Opcional: mostrar a versão vazia com um período sem dados.

**Cena 7: Configurações (≈ 60 s)**
1. Abrir `/settings`. Mostrar `Conta` com `Nome`, `Usuário` (`@...`) e `Tipo`.
2. Mostrar `Conta do robô` com o chip `Conectado` ou `Desconectado`.
3. Mostrar `Atividade da conta` com as linhas. Pode aparecer `config_imported` ou `password_changed` sem rótulo. Vale regravar depois de corrigir a lacuna de rótulo.
4. Mostrar `Sobre o Atila's Client` com `Versão` e `Plataforma` `SuperLive v2.31.0`.
5. Opcional, no navegador: `Instalar como app` (aparece só se o navegador oferecer a instalação).

**Cena 8: Importar configurações (≈ 45 s)**
1. Colar texto inválido: `Isso não parece um arquivo de backup...`.
2. Colar um backup válido (`"format":"atilas-config","version":1`). Clicar em `Conferir arquivo` e mostrar `O que vai acontecer`, com as linhas de palavras e mensagens. Mostrar um item inválido, se houver.
3. Clicar em `Importar`: `Importação concluída`. Mostrar que o campo foi limpo.
4. Importar de novo o mesmo arquivo: mostrar `já existiam` e `Nenhuma`, com o botão `Importar` desabilitado.

**Cena 9: Sair (≈ 10 s)**
1. Em Configurações, `Sair da conta` e a mensagem da seção `Sair`. Voltar ao login.

---

## 7. Achados para o produto

1. Limite de mensagem: tela 280, API 500, importação 500. Mensagens importadas acima de 280 não cabem na edição da tela.
2. Textos sem rótulo na Atividade: `config_imported` e `password_changed`.
3. Exclusão não persiste a renumeração de `sort_order` no servidor (`auto_message_provider.dart:137-143`).
4. Reordenação faz N PUTs sequenciais e ignora falhas individuais (`auto_message_provider.dart:110-112`).
5. Promessa "o robô pula esta mensagem" depende de o motor filtrar mensagens inativas. Não confirmado (seção 3.2).
6. Ajuda de senha no cadastro não menciona as regras que o servidor também aplica (seção 5.2).
7. Opções `kick_permanent`, `moderation_enabled` e `diamond_immunity_*` não aparecem na tela de Configurações lida.
8. A importação não tem seletor de arquivo; depende de copiar e colar o JSON inteiro. A origem do backup não está neste app.
9. Estatísticas: `by_day` usa datas em UTC (SQLite). Pode deslocar um dia para horários noturnos no Brasil.

## 8. Não verificado

- Filtro de mensagens inativas no motor (`load_engine_config`, `backend/db.py`).
- Texto exato de erro de senha fraca no cadastro (`_describe_validation_error`, `backend/main.py:221-243`).
- Rotas admin de senha provisória (`main.py:1705-1727`) e o restante de `superlive.py`.
- Telas de Moderação e Robô, fora do escopo pedido.
- Testes em `backend/tests/`, não lidos.
