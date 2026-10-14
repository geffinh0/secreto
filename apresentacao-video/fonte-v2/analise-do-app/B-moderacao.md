# B - Moderação: análise de produto (tela, regras, motor, gravação)

Escopo lido: `lib/screens/moderation/moderation_screen.dart` (932 linhas, inteiro), `lib/providers/moderation_provider.dart` (138, inteiro), `backend/main.py` (rotas `/moderation/*`, `/settings`, `/config/import`), `backend/engine.py` (normalização, `RuleMatcher`, `_on_chat`, `_on_gift`, `_execute`), `backend/db.py` (defaults), `lib/screens/settings/import_config_card.dart` (importação).

Os exemplos de correspondência da seção 2 foram executados de verdade com `engine.RuleMatcher` (Python, `backend/`). Os textos da UI estão copiados do código.

---

## 1. Funções da tela e textos exatos

Arquivo: `lib/screens/moderation/moderation_screen.dart`

### 1.1 Cabeçalho e chips de ação
- Título da página: **"Moderação"**; subtítulo: **"Palavras que o robô silencia ou bane no chat da live."** (linhas 188-191).
- Chips de ação (linhas 110-127):
  - **"Silenciar (N)"** (ícone volume_off), N = total de regras `mute` (linha 115).
  - **"Banir (N)"** (ícone block), N = total de regras `kick` (linha 121).
  - Trocar o chip troca a lista exibida inteira (`_action`, linhas 118 e 124). Os contadores usam o total, não o filtrado.
- Ao abrir a tela, carrega regras e mensagens automáticas (linhas 30, 39-44). Puxar para atualizar também recarrega (linha 186).

### 1.2 Bloco "Adicionar palavra" (linhas 209-269)
- Rótulo do campo:
  - silenciar: **"Palavra para silenciar"**, dica **"Exemplo: xingamento"** (linhas 256-257);
  - banir: **"Palavra para banir"**, dica **"Exemplo: spam"**.
- Ajuda do campo (linhas 258-259), texto exato:
  **"A palavra vale inteira, sem diferenciar maiúsculas nem acentos. Use * no fim para pegar variações, como puta*."**
- Botão **"Adicionar palavra"** (ícone add, linha 231). Enter no campo também adiciona (linhas 260-261).
- Botão de texto **"Adicionar várias"** (ícone playlist_add, linha 238), abre o diálogo de lote (seção 4).
- Campo vazio: `_addRule` retorna sem mensagem (linhas 47-48).
- Sucesso: limpa o campo (linha 63). Sem mensagem de sucesso.
- Falha: snack de erro com a mensagem do servidor ou o fallback **"Não foi possível adicionar a palavra. Tente de novo."** (linhas 65-69).
- Durante o envio o botão mostra carregamento (`loading`, linha 233).

### 1.3 Lista de palavras (linhas 271-365)
- Título da seção, `_countTitle` (linhas 203-206):
  - silenciar: **"1 palavra para silenciar"** / **"N palavras para silenciar"**;
  - banir: **"1 palavra para banir"** / **"N palavras para banir"**.
- Estado de carregamento: **"Carregando palavras"** (linha 297).
- Lista vazia (linhas 299-306), ilustração de raposa dormindo:
  - título **"Nenhuma palavra cadastrada"**;
  - silenciar: **"Adicione uma palavra acima para o robô começar a silenciar."**;
  - banir: **"Adicione uma palavra acima para o robô começar a banir."**
- Campo de busca: rótulo **"Buscar palavra"**, dica **"Digite parte da palavra"** (linhas 336-340). A busca é "contém", sem diferenciar caixa (linhas 90-93).
- Filtros (linhas 309-331): **"Todas"**, **"Ativas"** (ícone check), **"Desativadas"** (ícone pause).
- Lista filtrada vazia (linhas 345-349): título **"Nenhuma palavra encontrada"**, mensagem **"Mude a busca ou o filtro para ver outras palavras."**
- Cada linha (linhas 382-405):
  - nome = palavra; subtítulo **"Ativa"** ou **"Desativada"** (linha 389);
  - switch com rótulo de acessibilidade **"Ativar {palavra}"** (linha 395);
  - botão lixeira com tooltip **"Remover {palavra}"** (linha 400).
- Ativar/desativar (linha 156): chama `toggleRule`, que faz PUT. Falha **sem nenhuma mensagem para o usuário** (ver seção 6, "Lacunas").
- Remover (linhas 73-88): diálogo com
  - título **"Remover palavra"**;
  - mensagem **"A palavra "{palavra}" sai da lista. "** + efeito + **" Para voltar a usar, adicione de novo."**;
  - efeito, silenciar: **"O robô deixa de silenciar quem usar essa palavra."**; banir: **"O robô deixa de banir quem usar essa palavra."**;
  - botões: confirmação **"Remover palavra"** (destrutiva) e cancelar (padrão do `showAppConfirm`).
  - Falha ao remover também fica silenciosa (`deleteRule`, provider linha 85-87 e 80).

### 1.4 Bloco "Como o robô aplica" (linhas 412-525)
Cada opção salva na hora (`_save`, linhas 441-453). Os textos exatos:
- **"Moderação automática"** (linha 486). Subtítulo: **"Desligada, o robô só observa o chat e não silencia nem bane ninguém."** Chave: `moderation_enabled`.
- **"Banimento permanente"** (linha 495). Subtítulo: **"Ao banir, remove o usuário de forma permanente, e não só nesta live. Cuidado com palavras que peguem mensagens normais."** Chave: `kick_permanent`.
- **"Imunidade por diamantes"** (linha 503). Subtítulo: **"Quem já enviou diamantes suficientes nesta live não é silenciado nem banido, mesmo usando uma palavra da lista."** Chave: `diamond_immunity_enabled`.
- Se a imunidade estiver ligada, aparece o campo (linhas 509-520):
  - rótulo **"Diamantes mínimos na live para ficar imune"**;
  - ajuda **"Mínimo: 50"** (vem de `BotSettings.minDiamondImmunityThreshold`).
- Mensagem de erro ao salvar: **"Não foi possível salvar. Tente de novo."** ou a do servidor (linhas 446-452).
- Regra do campo de limiar (linhas 455-465): ao perder o foco ou dar Enter, valor vazio, não numérico ou menor que 50 vira **50 sem aviso**. Não há teto na tela; o backend aceita até 1.000.000.

### 1.5 Bloco "Testar regras" (linhas 527-572)
- Título da seção: **"Testar regras"**.
- Texto: **"Veja se uma mensagem de exemplo seria pega por alguma regra ativa, antes de confiar nela ao vivo."** (linhas 536-539).
- Botões: **"Testar uma frase"** (ícone science) e **"Como as regras funcionam"** (ícone help).

### 1.6 Folha "Testar uma frase" (linhas 574-655)
- Título **"Testar uma frase"**; texto **"Digite uma mensagem de exemplo. O teste também pega número no lugar de letra e letra repetida."**
- Campo: rótulo **"Mensagem de exemplo"**, dica **"Exemplo: g0z4 gostoso"**, com foco automático.
- Botão **"Testar frase"**.
- Resultado (linhas 666-678), três textos exatos:
  - sem casamento: **"Nenhuma regra ativa pegaria essa frase."** (ícone verde);
  - banir: **"O robô baniria: bateu na regra "{palavra}"."** (ícone de bloqueio, vermelho);
  - silenciar: **"O robô silenciaria: bateu na regra "{palavra}"."** (ícone de silêncio, âmbar).
- Falha: snack com o erro ou **"Não foi possível testar a frase. Tente de novo."** (linhas 608-612).

### 1.7 Diálogo "Como as regras funcionam" (linhas 693-766)
Título **"Como as regras funcionam"**. Cinco itens, textos exatos:
1. **"Asterisco no fim (ex.: puta*)"**: "Pega a palavra e qualquer coisa colada depois dela ("putaria", "putasso"). Sem o *, só a palavra inteira conta."
2. **"Palavras compostas"**: "Uma regra "passa zap" também pega "passazap", "passa-zap", "passa_zap" e "passa.zap"."
3. **"Número no lugar de letra"**: "0 vira o, 1 vira i, 3 vira e, 4 vira a, 5 vira s, 7 vira t, 8 vira b, 9 vira g, @ vira a, $ vira s, + vira t e | vira i. "g0z4" é reconhecido como "goza"; uma regra só cobre as grafias disfarçadas."
4. **"Letra esticada (ex.: gozzzaaa)"**: "Três ou mais letras iguais em sequência contam como uma só antes de comparar. "goooza" também é pego."
5. **"Regra com número (ex.: d4)"**: "Se a própria palavra tem número ou símbolo, só pega quem digitar exatamente assim. Então "d4" não pega quem escreve "amei da live"."

Botão **"Fechar"**.

---

## 2. Regras de correspondência (motor real)

Código: `backend/engine.py`.
- Normalização (linhas 135-177): minúsculas e sem acento (`_strip_accents_and_case`, 142-145); troca de dígito/símbolo por letra (`_LEETSPEAK_SUBS`, 135-138: 0→o, 1→i, 3→e, 4→a, 5→s, 7→t, 8→b, 9→g, @→a, $→s, +→t, |→i; "!" fica de fora de propósito); letra repetida 3+ vezes vira 1 (linha 164); espaços colapsados.
- Palavra com dígito/símbolo (ex.: `d4`) usa `normalize_literal`, que não faz a troca de leetspeak (linhas 195-196).
- Palavra inteira: borda `(?<![a-zA-Z0-9])` antes e `(?![a-zA-Z0-9])` depois, a não ser que haja `*` (linha 215).
- Entre letras de uma palavra com 3+ letras aceita qualquer separador `[\W_]*` (linha 207). Palavras de 1-2 letras são literais.
- Entre palavras de uma regra composta aceita separador ou nada (`[\s\W_]*`, linha 213), o que faz "passazap" casar com "passa zap".
- Fallback condensado (linhas 237-244): só para regra com espaço e com 4+ caracteres sem separadores. Só é aplicado a regras compostas.
- Ordem: regras de banir são testadas antes das de silenciar (linha 221). Só uma correspondência é retornada por mensagem.
- Regra só entra no motor se estiver ativa (`is_active = 1`, `db.py`, `load_engine_config`, linhas 467-470).
- Cache de regras e configurações: 5 segundos (`CONFIG_TTL_SECONDS`, engine.py:94). É por isso que a ajuda da tela diz "em alguns segundos".

### 2.1 Resultados observados (executados com `engine.RuleMatcher`)

| Regra | Mensagem | Resultado |
|---|---|---|
| goza (silenciar) | `g0z4` | CASA (goza) |
| goza | `GOZA` | CASA |
| goza | `gozzzaaa` | CASA (vira goza) |
| goza | `goooza` | CASA |
| goza | `gozá` | CASA (acento ignorado) |
| goza | `a goza b` | CASA (palavra inteira no meio) |
| goza | `g.o.z.a` | CASA |
| goza | `g o z a` | CASA |
| goza | `gozando` | NÃO casa (sem `*`) |
| goza | `goza1` | NÃO casa (dígito colado conta como letra na borda) |
| goza | `agoza` | NÃO casa |
| puta* | `putaria` | CASA (regra "puta*") |
| puta* | `putasso` | CASA |
| puta* | `puta` | CASA |
| puta* | `eu sou a puta` | CASA |
| puta | `putaria` | NÃO casa |
| puta | `puta!` | CASA (`!` é separador) |
| puta | `p.u.t.a` | CASA |
| puta | `put@` | CASA (@ vira a) |
| passa zap | `passazap` | CASA |
| passa zap | `passa-zap` | CASA |
| passa zap | `passa_zap` | CASA |
| passa zap | `passa.zap` | CASA |
| passa zap | `passa zap` | CASA |
| passa zap | `passaszap` | NÃO casa |
| d4 | `d4` | CASA |
| d4 | `amei da live` | NÃO casa |
| da | `d4` | CASA (d4 vira da; ver lacuna 1) |
| cu | `cuidado` | NÃO casa |
| cu | `cu` | CASA |
| spam (banir) | `SPAM` | CASA (banir) |
| spam (banir) | `spamm` | NÃO casa |
| spam (banir) | `spamer` | NÃO casa |
| ação | `acao` | CASA |
| acao | `AÇÃO` | CASA |
| goza (silenciar) + goza (banir) | `goza` | banir (kick vence) |
| goza (silenciar) + spam (banir) | `goza spam` | banir ("spam") |
| ok | `ok!` | CASA |
| ok | `okay` | NÃO casa |

Normalizações verificadas: `normalize("g0z4") = "goza"`, `normalize("gozzzaaa") = "goza"`, `normalize("d4") = "da"`, `normalize_literal("d4") = "d4"`.

Leitura para o produto: a regra casa a palavra inteira, mas aceita disfarces (número, símbolo, espaço, ponto, traço, letra repetida, acento). Não casa palavra que contém a regra colada sem `*`. Com `*`, casa qualquer sufixo.

---

## 3. Painel "Testar regras" e "Como o robô aplica"

### 3.1 "Testar uma frase"
- Chama `POST /moderation/test` (main.py:901-918). Usa só as regras ativas do usuário e o mesmo `RuleMatcher` do robô.
- O que ele NÃO considera (verificado no código): não checa a chave "Moderação automática" (main.py:909-913 só filtra `is_active = 1`); não aplica imunidade por diamantes; não aplica a regra do nome "w"; não aplica a trava de "já silenciado/banido" (`_acted`). Ou seja, mostra o casamento, não a decisão final.
- A resposta traz só a regra mais forte (kick antes de mute), não a lista de todas.

### 3.2 Opções de "Como o robô aplica" (o que fazem de fato)
- **Moderação automática** (`moderation_enabled`, padrão ligado, db.py:21):
  - Desligada: `_on_chat` (engine.py:1030-1031) sai antes de qualquer ação, inclusive antes da regra do nome "w" (linha 1034). `_on_frame` também checa (linha 988).
  - A mensagem continua sendo guardada no histórico recente (engine.py:1023-1025), por isso o texto "só observa o chat" é verdadeiro.
- **Banimento permanente** (`kick_permanent`, padrão desligado, db.py:22): só muda o parâmetro `permanent` enviado à ação de banir (engine.py:1127-1128; superlive.py:781-786). Silenciar não tem duração nem essa opção.
- **Imunidade por diamantes** (`diamond_immunity_enabled`, padrão desligado, db.py:23):
  - Verificada em `_on_chat` antes do casamento de palavras (engine.py:1046-1047). Quem está imune não é silenciado nem banido por palavra.
  - NÃO vale para a regra do nome "w" (a checagem do nome vem antes, engine.py:1034-1044).
  - O total é a soma de diamantes enviados na live atual (`_on_gift`, engine.py:1067-1087: custo do presente × combo ou batch). É zerado ao trocar de live (engine.py:870). Comportamento no fim da live não verificado.
- **Limiar de diamantes** (`diamond_immunity_threshold`, padrão 50, db.py:24): mínimo 50 (db.py:27, `MIN_DIAMOND_IMMUNITY_THRESHOLD`) e máximo 1.000.000 (main.py:445). A checagem é `>=` (engine.py:1064).
- Regras de ação (engine.py:1048-1059): uma ação por usuário por nível. Silenciar é nível 1, banir é nível 2 (engine.py:100). Quem já foi silenciado ainda pode ser banido. Quem já foi banido não recebe mais nada (engine.py:1052).
- Fila: uma ação a cada 0,5 segundo (`ACTION_SPACING_SECONDS`, engine.py:93). Ações pendentes são descartadas ao trocar de live (engine.py:1098-1112).
- Regra fixa, não aparece na tela: nome de usuário exatamente "w" (sem diferenciar caixa e ignorando espaços e caracteres invisíveis) é banido ao falar no chat ou ao entrar na live (`is_banned_username`, engine.py:114-121; uso em 986 e 1034).

---

## 4. "Adicionar várias" e importação

### 4.1 Diálogo "Adicionar várias" (linhas 789-932)
- Título: **"Adicionar várias para silenciar"** ou **"Adicionar várias para banir"** (linhas 863-866).
- Texto: **"Uma palavra por linha ou separadas por vírgula. Palavras já cadastradas e repetidas são ignoradas."** (linhas 870-873).
- Campo: rótulo **"Palavras"**, dica **"feia\nchata\nmal educada"**, 4 a 6 linhas (linhas 876-882).
- Separação: quebra de linha ou vírgula (linha 810). Espaços em volta são removidos e linhas vazias são descartadas (linhas 811-812). Aqui "mal educada" continua uma palavra só.
- Botões: **"Fechar"** (linha 916) e **"Adicionar palavras"** (linha 920).
- Se a lista vier vazia, nada acontece e não há mensagem (linhas 814).
- Resultado (linhas 839-845, 883-908):
  - resumo: **"N adicionada(s)."** ou **"N adicionada(s), M ignorada(s)."** (singular "adicionada" / "ignorada" quando for 1);
  - cada ignorada aparece como **`"palavra": motivo`**.
  - Motivos vindos do servidor (main.py:746-757): **"duplicada no lote colado"** (a mesma palavra aparece duas vezes na colagem); **"já cadastrada"** (já existe na mesma lista); "vazia" existe no servidor, mas o cliente já filtra linhas vazias.
- Depois de adicionar, o diálogo continua aberto e o texto não é limpo (não há `clear` após sucesso). O servidor insere no topo da lista (provider, linha 116).
- Falha de rede ou de validação: snack **"Não foi possível adicionar as palavras. Tente de novo."** ou a mensagem do servidor (linhas 831-835).
- Limite: até 200 palavras por colagem (main.py:391). Acima disso o servidor responde 422 e o app mostra a mensagem de validação do FastAPI.

### 4.2 Importação de backup (fica fora da tela de moderação)
Arquivo: `lib/screens/settings/import_config_card.dart`. Não verifiquei em qual tela o card aparece; ele pertence à pasta `settings`.
- Título da seção: **"Importar configurações"**.
- Texto: **"Traga as palavras de moderação e as mensagens automáticas de um arquivo de backup para esta conta. Nada é apagado: o que já existe é mantido e repetidas são ignoradas. A conexão com o robô e as demais configurações não mudam."** (linhas 187-191).
- Campo: rótulo **"Conteúdo do backup"**, dica **"Cole aqui o conteúdo do arquivo .json de backup"** (linhas 199-200).
- Botões: **"Conferir arquivo"** (linha 247, envia `dry_run=true`) e **"Importar"** (linha 253, a variável `canImport`, linhas 180-184, indica que só faz sentido quando a conferência traz algo a criar).
- Erros do app (import_config_card.dart):
  - campo vazio: **"Cole aqui o conteúdo do arquivo de backup (.json)."** (linha 43);
  - não é JSON de objeto: **"Isso não parece um arquivo de backup. Cole o conteúdo completo do .json, do primeiro "{" ao último "}"."** (linhas 50-52);
  - falha do servidor: a mensagem do servidor ou **"Não foi possível ler o arquivo."** (linha 91).
- Resumo (linhas 107-117, 127-172):
  - títulos **"O que vai acontecer"** (conferência) e **"Importação concluída"** (depois de importar);
  - linhas **"Palavras de moderação: N serão adicionadas · M já existiam · K inválidas"** (na conferência) e **"Palavras de moderação: N adicionadas · ..."** (depois);
  - mesmo formato para **"Mensagens automáticas"**;
  - itens inválidos: **"Palavra #N: motivo"** / **"Mensagem #N: motivo"** (até 8 na tela).
- Após importar: o campo é limpo e as listas de palavras e mensagens são recarregadas (linhas 83, 86, 96-102).

Backend (main.py:774-898):
- Formato esperado: `"format": "atilas-config"` e `"version": 1` (linhas 774-775). Outro formato ou versão são recusados com **"Arquivo inválido: não é um backup de configurações do Atila's Client."** ou **"Versão N do arquivo não é suportada por este app."** (linhas 793 e 795).
- Só são lidas as chaves `rules` e `messages` (linhas 781-788). Limites: 5.000 regras e 500 mensagens por arquivo (linhas 776-777, 787-788). Acima disso o arquivo inteiro é recusado.
- Item de regra (linhas 799-810): precisa de `keyword` (texto), `action` (`mute` ou `kick`) e `is_active` (padrão verdadeiro). Palavra com mais de 60 caracteres é inválida (linhas 806-807).
- Item de mensagem (linhas 813-825): `content` não vazio até 500 caracteres; `sort_order` opcional.
- Mesclagem, nunca substituição (linhas 834-837, 839-860): repetida dentro da mesma ação é pulada, comparando com `normalize` (a mesma regra da lista). Mensagem repetida compara texto em minúsculas com espaços colapsados (linhas 842-844, 869-872).
- Tudo ou nada: uma transação (linhas 880-889). Falha grava **"Não foi possível importar. Nada foi alterado."** (linha 889).
- Registro de atividade: **"N palavras e M mensagens importadas"** (linhas 890-891).
- Resposta: `dry_run`, `rules` e `messages`, cada um com `created`, `skipped`, `invalid`, `invalid_items` (até 20, linha 778).

### 4.3 Rotas de moderação (main.py)
- `GET /moderation/rules?user_id=` (709-717): lista do usuário, mais novas primeiro.
- `POST /moderation/rules` (720-733): cria. Palavra de 1 a 60 caracteres e ação `mute` ou `kick` (371-380). Repetida na mesma ação: 409 **"Essa palavra já está cadastrada nessa lista"** (linha 725).
- `POST /moderation/rules/bulk` (736-770): até 200 palavras. Não checa 60 caracteres (só `_clean_keyword`, linha 748).
- `POST /moderation/test` (901-918): ver seção 3.1.
- `PUT /moderation/rules/{id}` (921-951): altera palavra, ação ou ativação. Repetida gera 409 (929-931). Sem campo, 400 **"Nenhum campo para atualizar"** (943-944).
- `DELETE /moderation/rules/{id}` (954-961).
- `GET/PUT /settings/{user_id}` (1028-1061): aceita `moderation_enabled`, `kick_permanent`, `diamond_immunity_enabled`, `diamond_immunity_threshold`.
- `_clean_keyword` (main.py:325-329): minúsculas e espaços colapsados. Não remove acento; a comparação é que ignora.
- Unicidade por lista (`_keyword_taken`, main.py:696-706): é por ação, então a mesma palavra pode estar em silenciar e em banir.

---

## 5. Fluxo ideal para gravar em vídeo

Use uma conta de teste. Não mostre chat real de terceiros. Antes de gravar, rode uma vez para confirmar os resultados esperados abaixo.

1. Abra **Moderação**. Mostre o título e o subtítulo "Palavras que o robô silencia ou bane no chat da live." Mostre os chips **"Silenciar (N)"** e **"Banir (N)"**.
2. Chip **Silenciar** selecionado. No campo **"Palavra para silenciar"**, digite `puta*` e clique **"Adicionar palavra"**. A linha aparece com a etiqueta **"Ativa"**.
3. Digite `goza` e clique **"Adicionar palavra"**.
4. Digite `g0z4` e clique **"Adicionar palavra"**. Resultado esperado: erro **"Essa palavra já está cadastrada nessa lista"**. Esta é uma boa cena para mostrar que o disfarce já está coberto. Confirme antes de gravar, porque o caminho foi derivado do código (lacuna 1).
5. Role até **"Testar regras"**. Clique **"Testar uma frase"**. Digite `g0z4 gostoso` e clique **"Testar frase"**. Resultado esperado: **"O robô silenciaria: bateu na regra "goza"."**
6. Teste `putaria`. Resultado esperado: **"O robô silenciaria: bateu na regra "puta*"."**
7. Teste `puta!` ou `p.u.t.a`. Resultado esperado: o mesmo tipo de resposta, citando `puta*`.
8. Teste `gozando`. Resultado esperado: **"Nenhuma regra ativa pegaria essa frase."** Mostra o limite da regra sem `*`.
9. Abra **"Como as regras funcionam"** e mostre os cinco itens. Feche com **"Fechar"**.
10. Chip **Banir**. Digite `spam` e clique **"Adicionar palavra"**. Teste `SPAM` na folha. Resultado: **"O robô baniria: bateu na regra "spam"."**
11. Em **"Como o robô aplica"**, ligue **"Imunidade por diamantes"**. Aparece **"Diamantes mínimos na live para ficar imune"** com ajuda **"Mínimo: 50"**. Mostre que 10 vira 50 ao sair do campo (lacuna 6). Não é preciso ligar a live.
12. Desligue **"Moderação automática"** e mostre a legenda "Desligada, o robô só observa o chat e não silencia nem bane ninguém.". Volte a ligar.
13. Clique **"Adicionar várias"** (chip Silenciar). Digite, em linhas separadas:
    ```
    feia
    chata
    feia
    ```
    Clique **"Adicionar palavras"**. Resultado esperado: "2 adicionadas, 1 ignorada." e a linha `"feia": duplicada no lote colado`. Confirme antes de gravar.
14. Mostre a importação em **"Importar configurações"** (tela de configurações). Cole:
    ```json
    {"format":"atilas-config","version":1,"rules":[{"keyword":"chata","action":"mute"}],"messages":[]}
    ```
    Clique **"Conferir arquivo"**. Mostre **"O que vai acontecer"** e a linha "Palavras de moderação: ...". Depois clique **"Importar"** e mostre **"Importação concluída"**. Se "chata" já estiver na lista, a linha mostrará "já existiam" em vez de "adicionadas".
15. Feche no filtro: chip **Ativas** e **"Desativadas"**. Mostre a busca com "Digite parte da palavra".

Evite na gravação: texto real de chat, nomes de usuários reais e o campo de "Banimento permanente" ligado sem explicar.

---

## 6. Fatos verificáveis para infográficos (sem números inventados)

Todos abaixo estão no código. Cite o arquivo e a linha.
- Limite de palavra individual: **60 caracteres** (main.py:373, 395, 806).
- Limite de palavras por colagem: **200** (main.py:391).
- Limite da mensagem de teste: **500 caracteres** (main.py:385).
- Limite de importação: **5.000 regras** e **500 mensagens** por arquivo (main.py:776-777).
- Itens de erro mostrados na importação: **20** no servidor (main.py:778) e **8** na tela (import_config_card.dart:153).
- Imunidade: **mínimo 50** diamantes (db.py:27), **máximo 1.000.000** (main.py:445), **padrão 50** (db.py:24).
- Intervalo entre ações: **0,5 s** (engine.py:93). Atualização de regras e configurações: **5 s** (engine.py:94).
- Letras repetidas: **3 ou mais** viram uma (engine.py:164).
- Substituições de leetspeak: **12** (engine.py:135-138).
- Níveis de ação: silenciar **1**, banir **2**; uma ação por nível por usuário por live (engine.py:100, 1052).
- Regra fixa do nome: exatamente **"w"** (engine.py:121).
- Formato do backup: **"atilas-config"**, versão **1** (main.py:774-775).

### Lacunas e inconsistências encontradas (valem para a apresentação)
1. **Colisão de disfarces na lista**: `_keyword_taken` usa `normalize` (com troca de leetspeak, main.py:701-706). Então `g0z4` e `goza` são "a mesma" palavra, e `d4` e `da` também (`normalize("d4") == normalize("da") == "da"`). Em consequência, cadastrar a segunda bloqueia com 409. Derivado do código e da normalização verificada; a resposta 409 não foi chamada pela API.
2. **Lote sem limite de 60 caracteres**: o endpoint em lote não checa tamanho (main.py:746-759), ao contrário do cadastro individual (main.py:373).
3. **Falhas silenciosas**: ativar/desativar (screen linha 156) e remover (linhas 85-87) não mostram erro. O provider guarda o erro, mas nada o exibe.
4. **Teste de frase ignora as travas**: não considera "Moderação automática" desligada, imunidade ou a regra "w". A tela não avisa.
5. **Regra "w" escondida**: o banimento por nome "w" é fixo no código e não aparece em nenhum texto da tela. Não é afetado pela imunidade.
6. **Limiar corrigido em silêncio**: qualquer valor abaixo de 50 vira 50 sem aviso (screen linhas 455-461). Não há teto na tela; valor acima de 1.000.000 gera erro do servidor, que chega como mensagem de validação do FastAPI, provavelmente em inglês (`errorMessage`, portal_api_service.dart:107-116). Não verifiquei o texto real.
7. **Sem desfazer no motor**: a busca por "unmute|unban" em `backend/*.py` não retornou nada, e o cliente do SuperLive só expõe `mute` e `kick` (superlive.py:775-786). O app não tem como desfazer um silenciamento; a única forma de reverter é fora dele.
8. **Mensagem de importação cita "Atila's Client"** (main.py:793). Confirme se esse nome deve aparecer no produto antes de mostrar a tela.
9. **Lote não limpa o texto após sucesso**: o diálogo continua aberto com as palavras digitadas (import/bulk, linhas 808-837).
10. **Lote acima de 200**: o cliente não divide a colagem; o servidor responde 422 e o usuário vê a mensagem de validação do FastAPI.

Arquivos citados: `/home/user/secreto/lib/screens/moderation/moderation_screen.dart`, `/home/user/secreto/lib/providers/moderation_provider.dart`, `/home/user/secreto/lib/core/models/models.dart` (ModerationRule 85-138, PhraseTestResult 142-154, BulkSkip/BulkRuleResult 158-180, BotSettings 243-249), `/home/user/secreto/lib/screens/settings/import_config_card.dart`, `/home/user/secreto/backend/main.py`, `/home/user/secreto/backend/engine.py`, `/home/user/secreto/backend/db.py`, `/home/user/secreto/backend/superlive.py`.
