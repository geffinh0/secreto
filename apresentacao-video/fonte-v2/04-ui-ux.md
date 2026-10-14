# UI/UX: estados a capturar, dados de exemplo e recortes

## Regra geral de captura
- Capturar em viewport de celular (abaixo de 900 px, limite do `isWide`). Em 1080 px de largura o shell troca para a barra lateral de 248 px e o vídeo deixa de mostrar o layout mobile.
- Renderizar em escala 2 a 3x para o texto `AppType.meta` e `label` (peso 600) não ficar borrado ao virar 1080x1920.
- Não capturar o aviso "Há uma nova versão do app." (`_UpdateNotice`).

## Por tela
- **Painel**: estado "Aguardando a live" (robô conectado, sem live) com 4 regras e 4 mensagens na fila. Evitar "Moderando a live" com contadores, porque "mensagens enviadas" e "ações realizadas" são métricas de uso. Mostrar a raposa `fox_head_calm`.
- **Moderação**: lista com 4 palavras de exemplo, chips "Silenciar (n)" e "Banir (n)", e o painel "Testar uma frase" com resultado "O robô silenciaria: bateu na regra...". Usar os exemplos que o próprio app mostra: "feia", "chata", "mal educada", "spam", "g0z4". Evitar palavrões no vídeo.
- **Mensagens automáticas**: fila com 3 a 4 itens, ícone de arrastar e chips "#1 a #4", chip de intervalo "2 min" selecionado. Texto de exemplo: "Obrigada por acompanharem a live."
- **Robô**: (a) formulário de conexão com chip "E-mail e senha" ativo; (b) conectado, com `_StateHero` "Parado" ou "Sentinela armada" e a linha do streamer favorito. Usar avatar de fallback (ícone da raposa) e um ID público fictício, não o ID da dica do app. Feed de chat com linhas "silenciado" e "banido" usando usuários fictícios.
- **Mais > Mensagens/Estatísticas/Configurações**: em Configurações, mostrar "Conta" e "Conta do robô" com chip "Conectado". Ocultar "Instalar como app", que depende do navegador. Estatísticas: não há dado de exemplo sem parecer métrica real; deixar de fora ou usar só o título.

## Elementos para recortar e animar
- Barra inferior: pílula ativa (`AppColors.raised`, 56x28) que se move entre Painel, Moderação, Robô e Mais.
- Chip "Robô online" / "Robô offline" da barra superior.
- Chips de regra (Silenciar em ouro, Banir em vermelho) entrando na lista.
- Switch de ativar/desativar regra e o "Sentinela armada".
- Raposa em poses diferentes: `fox_sleeping` (offline), `fox_head_calm` (conectado), `fox_head_laugh` (ao vivo).
- Reordenação de mensagens da fila.

## Riscos de legibilidade em 1080 px
- Texto `meta` e `label` pequenos: manter pelo menos 28 px de altura no vídeo final.
- Títulos com `maxLines: 2` e reticências cortam nomes longos de regras e mensagens. Usar exemplos curtos.
- Textos de ajuda longos ("Como as regras funcionam") ficam ilegíveis em tela cheia; mostrar só o título.
- Barra inferior fixa em 64 px, com rótulos ajustados (`FittedBox`) e escala de texto limitada a 1,3x. Em 1080 px os rótulos ficam pequenos; fazer zoom no recorte da barra.
- Em tela de moderação, o chip "Silenciar (n)" e "Banir (n)" mostram contagens reais; usar valores pequenos e coerentes com a lista.
