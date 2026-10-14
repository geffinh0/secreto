# Como o motor do Atila's Client funciona (para o marketing)

Base: `SUPER_MODERATOR.md` (269 linhas, lido inteiro), `backend/engine.py` (1649 linhas, lido inteiro), `backend/superlive.py` (trechos de ritmo, fila e ações), `backend/main.py` (trechos de início, parada, vigia, status e alertas), e `backend/db.py` (padrões e limites).

Todas as referências são `arquivo:linha`. Os caminhos estão relativos a `/home/user/secreto/`.

---

## 1. Do chat até a ação

Imagine uma live onde a streamer tem a palavra proibida "passa zap" na lista de silenciar.

1. **Leitura em tempo real.** O robô fica conectado ao chat ao vivo do SuperLive (a mesma conexão que o app usa). Cada mensagem chega como um evento. (`engine.py:510-570`, `engine.py:965-981`)
2. **Filtros de entrada.** A mensagem é descartada se:
   - o autor for o próprio robô ou a streamer (`engine.py:1027-1028`);
   - a moderação estiver desligada nas configurações (`engine.py:1029-1031`).
3. **Regra fixa do nome "w".** Se o nome de quem fala for exatamente "w" (sem diferenciar maiúscula e ignorando espaços invisíveis), a pessoa é expulsa. Isso vem antes da imunidade por diamantes (`engine.py:1033-1044`, `engine.py:114-121`).
4. **Imunidade por diamantes (opcional).** Se ligada, quem já mandou diamantes suficientes nesta live não é moderado (`engine.py:1046-1047`, `engine.py:1062-1064`).
5. **Comparação com as regras.** O texto é "limpo" (minúsculas, sem acento, números trocados por letras, letras repetidas reduzidas) e comparado palavra por palavra (`engine.py:156-165`, `engine.py:180-246`).
   - Exemplo: "Me PASSA   ZÁP?" casa com "passa zap". "passa o zap" não casa, porque o "o" separa as palavras. (`SUPER_MODERATOR.md:86-89`)
   - Exemplo: "g0z4" vira "goza" e casa com a regra "goza". (`engine.py:135-165`)
   - Exemplo: "passazap", "passa_zap" e "p.u.t.a" também casam. (`engine.py:186-189`, `engine.py:207-215`)
   - Se a mensagem casa com silenciar e com banir, vale banir (`engine.py:221`, `SUPER_MODERATOR.md:91`).
6. **Não repete.** A mesma pessoa não é punida duas vezes no mesmo nível na mesma live. Ela pode ser silenciada e depois banida. (`engine.py:1052`, `engine.py:1129`, `engine.py:871`)
7. **Fila de ações.** A ação entra numa fila de até 200 itens (`engine.py:95`, `engine.py:1055`). Se a fila encher, a ação é descartada com aviso no log (`engine.py:1056-1058`).
8. **Execução.** Um único trabalhador executa as ações em ordem (`engine.py:1089-1096`). Para cada ação:
   - Confere se a live ainda é a mesma em que a ação foi decidida. Se mudou, a ação é descartada (`engine.py:1118-1121`).
   - Silenciar chama o SuperLive (`engine.py:1124-1125`, `superlive.py:775-780`).
   - Banir chama o SuperLive com a opção de banimento permanente se estiver ligada (`engine.py:1126-1128`, `superlive.py:781-788`).
9. **Registro.** Toda tentativa é gravada no histórico, com o texto da mensagem (até 300 caracteres), a palavra, o alvo e se deu certo (`engine.py:1151-1156`, `db.py:552-570`). O histórico guarda até 2000 registros por usuária (`db.py:16`).

**Exemplo completo.** Alguém escreve "passa zap" no chat às 21h10:01. A mensagem chega, passa pelos filtros, casa com a regra, entra na fila, o trabalhador a executa e o silenciamento sai no SuperLive. Tudo fica registrado no histórico com a hora, o nome, o texto e o resultado.

**Mudanças de regra.** As regras e configurações são relidas do banco a cada 5 segundos, então uma mudança feita no portal vale em poucos segundos (`engine.py:94`, `engine.py:496-507`).

---

## 2. Ritmo e espaçamento das ações

O objetivo é evitar que o SuperLive recuse ou limite o robô, e garantir que mute e kick sejam os primeiros a sair.

**Camada 1: o trabalhador de ações.** Após cada ação, espera 0,5 segundo (`engine.py:93`, `engine.py:1096`). Isso dá tempo para o SuperLive processar, e impede rajadas de ações.

**Camada 2: a fila de saída única por conexão de rede.** Todas as chamadas ao SuperLive (de todas as robôs que rodam no mesmo endereço de saída) passam por uma única fila com prioridades (`superlive.py:117-125`, `superlive.py:534-552`).
- Prioridade máxima (urgente): silenciar e banir. Elas furam a fila e não esperam o espaçamento de mensagens (`superlive.py:110`, `superlive.py:318-321`, `superlive.py:545-546`).
- Prioridade normal: mensagens automáticas e consultas essenciais (`superlive.py:111`).
- Prioridade baixa: a "vigia" da streamer favorita. Se a fila de saída estiver com 40 ou mais pedidos esperando, a consulta baixa é descartada e tenta de novo no próximo ciclo (`superlive.py:112`, `superlive.py:263-264`, `superlive.py:537-538`).

**Camada 3: espaçamento entre chamadas.** Entre duas chamadas quaisquer, espera pelo menos 0,35 segundo (`superlive.py:260`). A fila é atendida uma chamada por vez (`superlive.py:314-316`).

**Camada 4: espaçamento de mensagens de chat.** Duas mensagens de chat são separadas por pelo menos 3 segundos (`superlive.py:267-268`, `superlive.py:324-325`). Mensagens não atrasam mute ou kick (`superlive.py:320-321` e o comentário em `superlive.py:307-310`).

**Camada 5: pausa quando o SuperLive pede calma (erro 429).** Quando o SuperLive devolve 429, a fila inteira para pelo menos 2 segundos, dobrando a cada novo 429, até 120 segundos (`superlive.py:354-356`). O motivo é que o limite vale para o endereço, não para uma conta. Quem faz a pausa é a fila inteira, inclusive mute e kick. Nada é repetido automaticamente, porque repetir uma mensagem ou um banimento é pior do que falhar (`superlive.py:307-310`).

**Mensagens automáticas.** O intervalo mínimo é de 10 segundos e o padrão é de 120 segundos (`engine.py:92`, `engine.py:1193-1198`, `db.py:20`). O portal aceita de 10 a 3600 segundos (`main.py:440`).

**Por quê assim.** Mute e kick são o que protege a live de verdade, então eles nunca esperam atrás de mensagens ou consultas. Mensagens promocionais podem esperar sem problema. O próprio código deixa isso explícito (`superlive.py:98-108`).

**Limite importante.** O código não mede tempo real de reação. Os números acima são os teto e piso do desenho. O tempo que uma ação leva depende da fila naquele momento e do tempo de resposta do SuperLive. Não há medição publicada contra o serviço real.

---

## 3. Mensagens automáticas na live

- **Liga/desliga.** Vem desligado por padrão (`db.py:19`). A streamer liga em configurações.
- **Conteúdo.** Cada mensagem é cadastrada no portal. Não há limite fixo de quantas, além do próprio banco.
- **Ordem.** Saem em rodízio, na ordem da lista, uma a cada intervalo configurado (`engine.py:1164-1178`).
- **Só com live no ar.** Se a live não estiver ao ar (o robô está esperando a próxima), nada é enviado (`engine.py:1170-1171`).
- **Cada mensagem tem identificador próprio** (um código único por envio), para não ser tratada como repetida (`superlive.py:769-773`).
- **Contagem.** Cada envio conta no total da live e aparece no resumo final (`engine.py:1177-1178`, `engine.py:392-451`).
- **Falha.** Se o envio falhar, a mensagem de erro aparece no portal e a tentativa segue no próximo intervalo (`engine.py:1182-1187`).

---

## 4. Quando a live acaba, cai a conexão, ou o robô não é moderador

**A live termina.** O SuperLive avisa com um evento de fim de live (`engine.py:1004-1005`). Antes de aceitar que acabou, o robô confere mais uma vez, a cada 4 segundos (`engine.py:105-106`, `engine.py:700-724`). Isso evita encerrar a moderação por uma falha passageira.
- Se a streamer tem vínculo com o robô, o robô **não para**. Ele:
  - gera o resumo da live (`engine.py:392-451`);
  - descarta as ações que estavam na fila, porque eram da live que acabou (`engine.py:1098-1111`, `engine.py:935`);
  - entra no estado de espera (`engine.py:908-941`);
  - consulta a streamer a cada 20 segundos até ela abrir nova live, e então retoma sozinho (`engine.py:107`, `engine.py:814-847`).
- Se não houver vínculo, o robô para (`engine.py:926-928`).

**A conexão cai.** O robô reconecta sozinho, esperando de 1 a 30 segundos entre tentativas (`engine.py:510-636`). Antes de reconectar, confere se a live mudou ou acabou (`engine.py:615-627`). Depois de 12 falhas seguidas, para e avisa (`engine.py:96`, `engine.py:632-634`).

**A saída de rede cai.** Se o caminho de saída do robô estiver fora do ar, ele espera mais: até 120 tentativas seguidas, cerca de uma hora (`engine.py:97-99`, `engine.py:603-610`).

**O robô não é moderador.** O SuperLive recusa a ação com erro 403. O robô **não para**. Ele mostra no portal a mensagem "O robô precisa ser moderador desta live" (`engine.py:1140-1144`) e continua registrando cada tentativa como falha (`engine.py:1151-1156`). Assim que a streamer der o cargo, as próximas ações passam (`SUPER_MODERATOR.md:77-78`).

**O token expira.** Se o SuperLive recusar por autenticação (401), ou se o WebSocket recusar com 401 ou 403, o robô para com aviso para reconectar (`engine.py:583-588`, `engine.py:1138-1139`, `main.py:1069-1070`).

**Alertas que o portal mostra.**
- Resumo de cada live encerrada (duração, moderações, silenciamentos, expulsões, mensagens enviadas, diamantes) (`engine.py:392-451`).
- Aviso quando a streamer favorita entra ao vivo e o robô conecta (`engine.py:548-566`).
- Histórico de atividade da conta, com até 500 registros (`db.py:574`, `db.py:577-592`).
- Status de cada robô na área administrativa: não configurado, conectado (parado), aguardando, ativo ou erro (`main.py:1688-1700`).

**Não há aviso fora do portal.** Não existe envio de e-mail, notificação no celular ou mensagem para outro aplicativo. Os avisos aparecem só no portal e no histórico (busca feita nos três arquivos sem resultado para isso).

---

## 5. Streamer favorita e vigilância em segundo plano

**Como ativa.** Depois de buscar a streamer pelo ID público, a usuária favorita o perfil (`main.py:1376-1425`). Isso grava a vigia no banco (`db.py`, tabela `streamer_watch`, coluna `active` em `db.py:162`).

**O que faz em segundo plano.** Uma tarefa por usuária consulta o perfil da streamer (`engine.py:1504-1648`). Quando ela entra ao vivo, o robô inicia a moderação sozinho (`engine.py:1594-1618`) e registra a ação no histórico (`engine.py:1615-1618`).

**Não é instantâneo.** Ela é consultada em intervalos, não o tempo todo:
- Intervalo mínimo de 30 segundos (`engine.py:1311`).
- Streamers com pouca atividade são consultadas com menos frequência, com teto de 15 minutos (`engine.py:1321-1322`, `engine.py:1456`).
- Streamers com atividade recente são consultadas com mais frequência (`engine.py:1331-1357`).
- Existe um pedido de consulta imediata quando o portal avisa que ela acabou de entrar (`main.py:1432-1446`, `engine.py:1396-1402`), limitado a um pedido a cada 30 segundos (`main.py:1429`).
- Isso significa que o início da moderação pode levar desde segundos até alguns minutos depois que a live começa. Não prometa "na hora".

**Continua vigiando.** Parar a moderação manualmente, ou a live terminar, não desliga a vigia (`SUPER_MODERATOR.md:81-83`). A vigia só para se a favorita for removida ou o robô desconectado (`main.py:1347-1348`, `main.py:1423`).

**Sobrevive a reinício.** Ao iniciar o servidor, todas as vigias ativas são religadas (`main.py:166-168`).

**Consumo de consultas.** O número de consultas por conexão de saída é limitado (2 por segundo por padrão), dividido entre as streamers daquela saída (`engine.py:1312-1316`, `engine.py:1442-1474`). Quando o SuperLive devolve 429, o orçamento cai pela metade por 5 minutos (`engine.py:1448-1449`, `superlive.py:291-300`, `superlive.py:278-284`).

---

## 6. Limites e honestidade: o que o produto NÃO faz

- **Não apaga mensagens do chat.** Não existe nenhuma rotina de apagar mensagem do chat. O único apagar é o de mensagens automáticas da própria streamer (`main.py:1016-1022`). Ofensas ficam visíveis; o que se faz é silenciar ou expulsar quem as escreveu.
- **Não entende contexto.** Não é inteligência artificial. Compara palavras e variações cadastradas (`engine.py:180-246`). Palavras que não estão na lista passam. Também pode haver casos em que uma palavra cadastrada apareça em contexto inocente.
- **Não modera a própria streamer nem o robô** (`engine.py:1027-1028`).
- **Não funciona sem o cargo de moderador** (`engine.py:1140-1144`, `SUPER_MODERATOR.md:77-78`).
- **Não avisa no celular ou por e-mail** (ver seção 4).
- **Depende de uma API privada e não oficial** do SuperLive, que pode mudar sem aviso e pode ir contra os termos do serviço (`SUPER_MODERATOR.md:214-216`).
- **O login pode ser recusado** pelo SuperLive, dependendo da conta, do endereço de rede ou de exigências futuras. Há uma alternativa de colar o token (`SUPER_MODERATOR.md:184-187`, `main.py:1072-1073`).
- **A imunidade por diamantes ainda não foi confirmada contra o serviço real.** Os nomes dos campos vêm do código decompilado, mas o evento de presente nunca foi observado de verdade. Se o formato for diferente, a imunidade fica desligada sem erro (`SUPER_MODERATOR.md:204-209`, `engine.py:1067-1087`).
- **Guarda o token da conta do robô em texto puro** no banco local. Não guarda a senha (`SUPER_MODERATOR.md:250-251`).
- **Guarda o texto das mensagens moderadas** (até 300 caracteres) no histórico, e a privacidade desses dados depende de quem tem acesso ao banco (`SUPER_MODERATOR.md:252-253`, `db.py:560`).
- **Não tem rede de segurança para expulsar fora da live.** O banimento permanente só vale se a opção estiver ligada, que vem desligada (`db.py:22`).
- **Discrepância com a documentação.** A regra fixa do nome "w" existe no código (`engine.py:114-121`, `engine.py:983-1003`, `engine.py:1033-1044`), mas não aparece no `SUPER_MODERATOR.md`. Ela não é configurável no portal. Vale corrigir a documentação ou deixar a regra explícita para a equipe de marketing.
- **Só atua em live pública que o robô conseguir acompanhar.** Não lê mensagens privadas.

---

## 7. Afirmações de marketing

### 7a. Doze afirmações 100% verdadeiras e verificáveis

1. **Lê o chat ao vivo sem ninguém precisar deixar o navegador aberto.** Fechar a aba não interrompe a moderação. Prova: `engine.py:510-570` (conexão e leitura do chat); `SUPER_MODERATOR.md:10-11`.

2. **Compara palavras inteiras, sem diferenciar maiúsculas, acentos ou espaços repetidos.** "Me PASSA   ZÁP?" casa com "passa zap". Prova: `engine.py:156-165` (normalização); `engine.py:180-222` (comparação); `SUPER_MODERATOR.md:87-89`.

3. **Reconhece disfarces comuns, como números no lugar de letras e letras repetidas.** "g0z4" vira "goza"; "gozzzaaa" também. Prova: `engine.py:135-165`.

4. **Reconhece palavras juntas, separadas por símbolo ou com pontuação no meio.** "passazap", "passa_zap" e "p.u.t.a" são pegos. Prova: `engine.py:186-189`, `engine.py:207-215`.

5. **Se a mensagem casa com as duas listas, o robô bane.** Prova: `engine.py:221` (ordenação por gravidade); `SUPER_MODERATOR.md:91`.

6. **Nunca modera a streamer nem o próprio robô.** Prova: `engine.py:1027-1028`.

7. **Cada pessoa é punida no máximo uma vez por nível em cada live.** Ela pode ser silenciada e depois banida, mas não é punida duas vezes igual. Prova: `engine.py:1052`, `engine.py:1129`, `engine.py:871`.

8. **Mute e kick passam na frente de qualquer outra chamada ao SuperLive.** Prova: `superlive.py:110`, `superlive.py:318-321`, `superlive.py:545-546`.

9. **As mensagens automáticas só saem com a live no ar, em rodízio, e com intervalo de no mínimo 10 segundos.** Prova: `engine.py:1170-1178`, `engine.py:92`, `engine.py:1193-1198`, `main.py:440`.

10. **Quando a live termina, o robô não se desliga: espera a próxima live e retoma sozinho.** Prova: `engine.py:908-941`, `engine.py:814-847`, `SUPER_MODERATOR.md:102-108`.

11. **Antes de considerar a live encerrada, o robô confere de novo.** São duas checagens, com 4 segundos entre elas. Prova: `engine.py:105-106`, `engine.py:700-724`.

12. **Quando o robô não é moderador, o portal mostra o motivo e cada tentativa fica registrada.** Prova: `engine.py:1140-1144`, `engine.py:1151-1156`, `SUPER_MODERATOR.md:76-78`.

Afirmações adicionais que também são verdadeiras, se a equipe quiser usar: a streamer favorita é vigiada em segundo plano mesmo depois de "Parar" (`SUPER_MODERATOR.md:81-83`, `main.py:1347-1348`); a vigia volta sozinha depois de um reinício (`main.py:166-168`); e ao fim de cada live o portal mostra um resumo com duração, moderações e mensagens enviadas (`engine.py:392-451`).

### 7b. Oito coisas que NÃO se pode afirmar

1. **"Funciona com todas as lives do SuperLive".** A API é privada e não documentada (`SUPER_MODERATOR.md:214-216`).
2. **"Login sempre funciona".** Pode ser recusado, e o próprio projeto admite isso (`SUPER_MODERATOR.md:184-187`).
3. **"A imunidade por diamantes funciona".** Não foi confirmada contra o serviço real (`SUPER_MODERATOR.md:204-209`).
4. **"Modera na hora" ou "reage em segundos".** O início da moderação pela vigia depende de consultas em intervalos de 30 segundos até 15 minutos (`engine.py:1311`, `engine.py:1321-1322`). Nenhuma medição de tempo real foi publicada.
5. **"Detecta qualquer ofensa" ou "usa inteligência artificial".** Só compara palavras cadastradas (`engine.py:180-246`).
6. **"Apaga as mensagens ofensivas".** Não apaga; só silencia ou expulsa (ver seção 6).
7. **"Avisa você no celular ou por e-mail".** Não há esse envio (ver seção 4).
8. **"Seus dados e o acesso à sua conta estão criptografados" ou "seguro".** O token do robô fica em texto puro no banco local (`SUPER_MODERATOR.md:250-251`).
   Também não se pode dizer que o uso "respeita os termos do SuperLive". O próprio projeto diz que pode não respeitar (`SUPER_MODERATOR.md:215-216`).

---

## Apêndice: discrepâncias para revisar antes de publicar

- A regra fixa do nome "w" (expulsa quem tem esse nome, `engine.py:114-121`) não está documentada no `SUPER_MODERATOR.md`.
- A seção "Como as palavras são comparadas" diz que "Nunca são moderados: o próprio robô e a streamer da live" (`SUPER_MODERATOR.md:92`). Isso vale para o código, mas vale notar que a regra "w" é uma exceção: ela expulsa independentemente das listas, e vem antes da imunidade por diamantes.
