# Atila's Client — filme de apresentação v2 (9:16, 1080×1920, 30 fps) — CONTRATO DAS CENAS

Chefe de produção: Sonnet. Você é um artista (motion designer + diretor de arte) construindo UMA cena como sub-composição HyperFrames (HTML + GSAP).
O filme é lento o bastante para ler, tem desenho gráfico próprio (não é só print) e usa gravações REAIS do app em movimento.

## O que o cliente reclamou da v1 (NÃO repita)
"muito simples, muito print, pouco desenvolvimento gráfico, rápido demais, sem aprofundar no app".
→ Cada cena precisa de: (1) uma ideia gráfica própria (diagrama, tipografia cinética, ilustração SVG/CSS, ornamento botânico),
(2) o app REAL em movimento (clips) integrado à composição — não só um cartão parado, (3) tempo para respirar: texto-chave fica ≥1,6 s legível,
nada de cortes de 1 s, movimentos de 0,7–1,4 s, easing suave, (4) camadas e profundidade (paralaxe, sombras, câmera lenta), (5) acabamento.

## Identidade visual (Herbário da raposa, Art Nouveau, tema claro) — tokens em assets/base.css
Papel #F4ECDC / #FBF6EA, sálvia #E3E8D6, floresta #1F3A2E (#2D5242), terracota #A8461F (ação), ouro #9A7B2F / #D2B568, linhas #CFC3A8.
Fraunces 600/700 (títulos serifados suaves) + Source Sans 3 (corpo). Raposa = ilustrações em assets/fox_*.webp (baixa resolução: use ≤ 1,3× do tamanho nativo; veja tamanhos com `python3 -c "from PIL import Image;print(Image.open('assets/fox_head_calm.webp').size)"`).
Ornamentos: hastes/folhas/filetes dourados em SVG (stroke #D2B568 ou #9A7B2F, 3 px, linecap round), desenhados com HF.draw. Textura de papel é aplicada no filme todo (não faça você).
PROIBIDO: neon, glitch, glassmorphism, partículas/confete, gradiente arco-íris, emojis (a fonte não tem), texto genérico de "tech".
Alternância de fundos do filme: papel (#F4ECDC) na maioria, floresta (#1F3A2E) em 2–3 cenas de destaque (3, 15).

## Formato e segurança
Canvas da sua cena: 1080×1920. Conteúdo importante entre y=240 e y=1500 (topo e rodapé são cobertos por UI de redes). Margens laterais ≥ 70 px.
Texto: títulos 96–140 px (Fraunces), subtítulos/legendas ≥ 44 px, rótulos pequenos ≥ 38 px. Contraste AA.
Celular com tela real: use `.phone` (600×1298; escale com GSAP `scale`), tela = `<video muted playsinline>` dentro de `.phone .screen`. Inclinação 3D leve: pai com `perspective:1800px`, filho `rotateY` ±8–14°, `rotateX` ≤ 6°. NUNCA gire texto continuamente (serrilha). Sem moldura de marca de terceiros.
Clips gravados do app (assets/clips/*.mp4, 780×1688, sem áudio, 30 fps): k01 login→painel(6,4s) · k02 painel parado, scroll (12,6s) · k02b painel "Moderando a live" com contadores e scroll (15,8s) · k03 moderação: cadastrar palavra, ativar/desativar, aba Banir (25s) · k04 "Testar uma frase": SP4M→baniria "spam", ch4t4→silenciaria "chata", chatas→nenhuma regra (24,5s) · k05 "Como o robô aplica": liga/desliga banimento permanente (8,4s) · k06 mensagens automáticas: intervalos 30 s/1 min/5 min/2 min, adicionar à fila, reordenar (34s) · k07 conectar o robô: e-mail e senha / celular / código por e-mail (20,5s) · k08 robô na live: iniciar, chat ao vivo com chips "silenciado/banido" e ações (38s) · k09 streamer: buscar ID público, favoritar, sentinela armada, "avisar que entrei ao vivo", moderando (36,5s) · k10 estatísticas 7/30/90 dias (24s) · k11 configurações + atividade da conta (24s) · k12 menu Mais (3,5s).
Stills em assets/stills/*.png (780×1688): feed, painel_live, robo_moderando, teste_ban, teste_mute, teste_none, atividade, mais.
Para escolher trechos: extraia quadros com ffmpeg (`ffmpeg -ss 5 -i assets/clips/k04.mp4 -frames:v 1 f.png`) ou monte uma folha de contatos com `python3 /tmp/claude-0/-home-user-secreto/5a577aff-184f-5ecc-81ef-0546d19cec6e/scratchpad/cap/sheet.py assets/clips/k04.mp4 16` (gera /tmp/sh_k04.mp4.jpg; abra com Read). Use `data-media-start` e `data-duration` no <video> para recortar; pode usar `playbackRate`-free (sem acelerar) — se precisar acelerar, mantenha ≤1,5× e só em trechos de espera.
Para destaque/zoom no app: escale o <video> dentro do `.screen` (transform-origin no ponto de interesse), ou faça um "close-up card" (div overflow hidden + o mesmo vídeo ampliado, ≤1,6× — a resolução é 2x do celular).
Dados de demonstração (usuária fictícia "Aurora", números das estatísticas, usuários do chat) aparecem em algumas cenas: quando mostrar NÚMEROS (cenas 5 e 13), inclua a nota discreta "dados de demonstração" (≥34 px, cor #4A5B4F).

## Regras técnicas HyperFrames (obrigatórias)
- Seu arquivo: compositions/sNN.html. Estrutura: <template> com <style> + <div id="root" data-composition-id="sNN" data-width="1080" data-height="1920"> ... + <script> ... window.__timelines["sNN"] = tl </template>. Estilos do root por #root. Tudo dentro do template. Veja /root/.agents/skills/hyperframes-core/SKILL.md e references/sub-compositions.md.
- A linha do tempo da sua cena é LOCAL: t=0 é o início da cena; duração = DUR (timing.json). Não anime além disso.
- Um único `gsap.timeline({paused:true})`, determinístico (sem Date.now/Math.random/rede/repeat:-1 infinito). NÃO inclua <link> de CSS: o host já carrega assets/base.css e assets/lib.js (window.HF). Use as classes de base.css e escreva o resto do CSS dentro do <style> do template.
- Elementos de vídeo: `<video src="assets/clips/kXX.mp4" data-start="0" data-duration="D" data-media-start="M" muted playsinline>` com class="clip" e um `id` único (prefixe com sNN-). Não coloque data-start em ancestral do <video>. Sem `crossorigin`.
- Nunca anime visibility/display/autoAlpha em elemento .clip; não use transform CSS inicial + GSAP na mesma propriedade (use fromTo). Centralize com flex/left:0;width:1080px, não com translate(-50%).
- Sem <br> em texto corrido. Ids únicos (prefixo sNN-). Sem `repeat:-1`.
- Cada cena termina com um respiro: os últimos 0,4 s estáticos (o filme faz a transição por cima).
- Entregue também `compositions/sNN.sfx.json`: lista de cues de som `[{"t":2.4,"type":"pop|tick|stamp|chime|whoosh|click|type|toggle|swoosh","gain":0.3}]` com t LOCAL, sincronizados aos movimentos (um cue por evento visual relevante; sem excesso).
- Teste: `cd work/sNN && npx --yes hyperframes@0.8.155 check` e `npx --yes hyperframes@0.8.155 snapshot --at <tempos>` (use o script de preparo abaixo). Olhe os quadros (Read nas imagens) e CORRIJA: texto cortado, sobreposição, vazio demais, elementos fora de segurança, clips errados. Itere até a cena estar bonita e legível.

## Timing e áudio
timing.json (neste diretório) tem, por cena: start (s absolutos no filme), dur (s), voiceStart/voiceEnd (s locais) e cues das frases (silêncios da locução). Sincronize os eventos visuais com a fala (um conceito novo aparece quando a frase correspondente começa). A locução é adicionada pelo host (não inclua áudio na cena).

## Preparo do seu ambiente de teste
`python3 /tmp/claude-0/-home-user-secreto/5a577aff-184f-5ecc-81ef-0546d19cec6e/scratchpad/video2/mkwork.py sNN` cria work/sNN (cópia leve do projeto com um host index.html que monta compositions/sNN.html em t=0 e toca a locução). Edite SOMENTE `compositions/sNN.html` (+ .sfx.json) no projeto principal: /tmp/claude-0/-home-user-secreto/5a577aff-184f-5ecc-81ef-0546d19cec6e/scratchpad/video2/atila2/compositions/ — o script work usa um link simbólico para esse arquivo.

## Fatos verdadeiros que você pode usar (verificados no código) / proibido afirmar
Pode: lê o chat ao vivo; compara palavra inteira, sem diferenciar maiúsculas/acentos; reconhece número no lugar de letra (0→o 1→i 3→e 4→a 5→s 7→t 8→b 9→g @→a $→s), letra esticada (3+ iguais viram 1), separadores/pontos no meio ("passa zap" pega passazap, passa-zap, passa_zap, passa.zap); asterisco no fim pega variações ("chat*" pega chatas); banir vence silenciar; cada pessoa punida uma vez por nível por live; mute/kick têm prioridade; ações com intervalo de 0,5 s; tudo registrado no histórico; mensagens automáticas: em ordem, em repetição, só com live no ar, intervalo mínimo 10 s (padrão 120 s; chips 30 s/1 min/2 min/5 min); reordenar arrastando; "Testar uma frase"; opções "Moderação automática", "Banimento permanente", "Imunidade por diamantes" (não afirmar que funciona); robô precisa ser moderador da live; streamer favorita vigiada em segundo plano e o robô entra sozinho (não é instantâneo — "o robô verifica em intervalos"); quando a live acaba o robô espera a próxima; Estatísticas (ações no total, silenciadas, banidas, taxa de sucesso, palavras mais acionadas, lives recentes, ações por dia; 7/30/90 dias); resumo da live no histórico (duração, chat monitorado, moderações, mensagens automáticas); roda no servidor — fechar a aba não interrompe.
PROIBIDO afirmar: "na hora/instantâneo", "inteligência artificial", "apaga mensagens", "avisa no celular/e-mail", "100% seguro", números de clientes/resultados, "funciona com qualquer plataforma", imunidade por diamantes funcionando. NUNCA mostrar/mencionar .bat, scripts, servidores locais, Docker. Evite palavrões: use as palavras do app "spam", "chata", "feia", "mal educada", "passa zap"; as explícitas que aparecem em textos de ajuda do app não devem ser mostradas.

## Cenas (cada uma: ideia gráfica obrigatória + clips)
Veja a seção da sua cena no final deste arquivo (SCENES) e em timing.json.


## Nota sobre o tempo da fala
timing.json[sNN].words = lista [palavra, tempo local estimado em s] (estimativa por comprimento; erro ≈ ±0,5 s). phraseStarts = instantes locais em que a voz retoma após pausas (mais confiável). Sincronize conceitos às palavras-chave com ~0,3 s de antecedência (o olho antecipa o som).
