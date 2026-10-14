# Atila's Client — filme de apresentação v2 (9:16)

**Entrega:** `atila-apresentacao-v2-9x16.mp4` — 1080×1920, 30 fps, H.264 + AAC, **4 min 29 s**, −14 LUFS.
Destino exibido no filme: **atilaclient.tech**.

## O que mudou em relação à v1
A v1 foi considerada "simples, muito print, pouco desenvolvimento gráfico, rápida demais e sem aprofundar no app". A v2:
- **Aprofunda o app inteiro** (17 cenas): painel, lista de silenciar/banir, "Testar uma frase", opções de moderação,
  mensagens automáticas, conexão do robô (3 formas de entrar), chat ao vivo com ações marcadas, streamer favorita (sentinela),
  estatísticas, resumo da live, configurações (importar backup, alterar senha, instalar como app) e "pode fechar a aba".
- **Usa o app real em movimento**: gravações de interação (digitando, ativando, buscando, favoritando), não prints parados.
- **Desenvolve o grafismo**: cada cena tem uma ideia própria — prancha de herbário na abertura, sobrecarga de chat, diagrama do caminho
  da mensagem, tipografia cinética do "normalizador" (SP4M → spam), livros de registro, anel de intervalo + carrossel de mensagens,
  linha do tempo da sentinela, gráfico de barras redesenhado, pergaminho do resumo, caderno de configurações.
- **Ritmo calmo**: locução ~2 palavras/s, textos-chave ≥1,6 s na tela, respiros finais em cada cena.

## Direção de arte e som
Identidade real do app (Herbário da raposa, Art Nouveau, tema claro): papel, floresta, terracota, ouro; Fraunces + Source Sans 3;
raposa original do app. Transição única entre cenas (painel floresta com filete dourado). Textura de papel discreta.
Narração pt-BR gerada com Gemini TTS (voz "Kore"; modelos 3.1 nas cenas 1–9 e 3.8 nas cenas 10–17, com ritmo igualado). Trilha (Ré maior, 76 bpm) e
efeitos sintetizados por código — sem material de terceiros.

## Fidelidade — real × ilustração
- **Real:** todas as telas do app, os textos de interface e as ações do robô (silenciar/banir) gravados contra um SuperLive simulado.
- **Dados de demonstração:** usuária fictícia "Aurora", números das estatísticas, histórico e usuários de chat. Onde há números,
  o filme avisa "dados de demonstração".
- **Ilustração:** bolhas de chat das cenas 1–2, diagramas, ícones, gráficos redesenhados e a cena "pode fechar a aba".
- Nada de métricas de clientes, depoimentos, preços ou integrações inventadas.

## Pontos de atenção (para revisão humana antes de publicar)
1. **Escute a locução inteira.** Foi verificada só por medições (volume, pico, silêncio). Pronúncia de "Átila Client" e de
   "atila client ponto tech" precisa de ouvido humano. As cenas 10–17 usam outro modelo de voz e foram aceleradas para igualar o ritmo.
2. **Regra fixa do nome "w"**: o robô bane quem tem exatamente o nome "w" (código `engine.py`), regra que não é configurável nem citada no portal ou na
   documentação. O filme diz "aplica as regras que você escolheu"; a regra fixa existe além delas.
3. **O que o produto não faz** (e o filme não afirma): não apaga mensagens, não é inteligência artificial (compara palavras cadastradas), não avisa por
   e-mail/celular, a vigia da streamer favorita não é instantânea (consulta em intervalos), a imunidade por diamantes não foi confirmada contra o serviço real,
   e o produto depende de uma API não oficial do SuperLive (pode mudar ou violar termos).
4. A exigência "o robô precisa ser moderador da live" é mostrada como aviso; no ambiente de gravação o mock não recusa ações.

## Revisão e correções
Revisores (arte/ritmo, QA visual, fatos, som/pós). Correções aplicadas: frase sem respaldo removida (cena 10), títulos que exageravam
("não se deixa enganar" → "Reconhece disfarces comuns"; "Registra tudo" → "Registra as ações"), celular vazio na cena 10, celulares maiores e quadros mais
cheios nas cenas 5, 6, 8, 12, 13 e 14, nova cena 17 (Configurações), lint (fontes e animações por transform) e normalização de loudness (−14 LUFS).
Limitações conhecidas: algumas linhas-guia das etiquetas foram posicionadas à mão sobre a inclinação 3D; a vozes das cenas 10–17 soam um pouco diferentes das 1–9.

## Editável
`projeto-v2/` é um projeto HyperFrames (HTML + GSAP): cenas em `compositions/`, `timing.json`, `assets/` (clips reduzidos), scripts em `fonte-v2/` (análises do app em `fonte-v2/analise-do-app/`).
