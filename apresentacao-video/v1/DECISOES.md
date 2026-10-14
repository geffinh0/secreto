# Atila's Client — vídeo de apresentação (9:16)

**Entrega:** `atila-apresentacao-9x16.mp4` — 1080×1920, 30 fps, H.264 + AAC, 63,5 s, −13,8 LUFS, pico −1,5 dBFS.
Destino exibido no vídeo: **atilaclient.tech**.

## Conceito
"A raposa de guarda" (conceito A do diretor criativo): a raposa do herbário guia a leitura; o app é o protagonista.
Narrativa: gancho (o chat não para) → problema (moderar sozinha cansa) → solução (conta robô) → 3 funções
(silenciar/banir, mensagens automáticas, robô + streamer favorita) → tranquilidade (pode fechar a aba) → CTA.

## Direção de arte
Identidade real do app ("Herbário da raposa"): papel `#F4ECDC`, floresta `#1F3A2E`, terracota `#A8461F`, ouro `#9A7B2F/#D2B568`,
Fraunces nos títulos e Source Sans 3 no corpo (as mesmas fontes do app). Raposa = ilustrações originais do app.
Telas = **capturas reais** do app em viewport de celular (390×844 @3x), recortadas em cartões e animadas por cima.
Transição entre cenas: painel verde-floresta com filete de ouro e folhas subindo (um único motivo, repetido).
Sem neon, glitch, partículas ou vidro. Textura de papel discreta em todo o quadro.

## Som
Narração em pt-BR gerada com Gemini TTS (voz "Kore"), uma faixa por cena. Trilha (Ré maior, 76 bpm: pluck, pad, sinos) e efeitos
(whoosh, ticks, pops, carimbo, sino) **sintetizados por código** — sem material de terceiros. Trilha reduz sob a voz (ducking).
Fontes: `fonte-audio/` (`tts.py`, `mix.py`, locuções por cena).

## Fidelidade ao app — o que é real e o que é ilustração
- Real: todas as telas mostradas (Painel, Moderação, Mensagens automáticas, Robô). Textos, ícones e componentes vêm direto do app.
- Dados de demonstração: usuária fictícia "Aurora"; palavras e mensagens são exemplos do próprio app; o robô foi conectado a um
  SuperLive **simulado**, e as ações "Baniu bot77" vieram de um chat de teste. Nenhum dado de cliente real aparece.
- Ilustração (não é tela do app): as bolhas de chat das cenas 1 e 2 e as etiquetas/pílulas ("Entra na live", "Palavra inteira", etc.).
- Nenhuma métrica de uso, depoimento, preço ou integração foi inventada.

## Limitações (sinalizadas, não escondidas)
- A tela de **streamer favorita já cadastrada** (botão de favoritar) não foi capturada: a cena mostra as seções reais "Live" e
  "Streamer" do app, cujo texto menciona o streamer favoritado, e a locução descreve o comportamento. Vale gravar essa tela em um
  próximo corte, se quiser mostrar o interruptor em si.
- A afirmação "pode fechar a aba, a moderação continua" vem da documentação do app (o robô roda no servidor); a cena é ilustrativa.
- O áudio foi verificado **por medições** (loudness, pico, silêncio, cortes). A pronúncia de "Átila Client" e de
  "atila client ponto tech" precisa de uma escuta humana antes de publicar.

## Revisão e correções
Tribunal de revisão (arte, edição, QA, som/pós). Correções aplicadas após a primeira rodada: rodapé do celular fora da zona de
interface (celular subiu ~130 px), pílulas sobre a tela do app trocadas por uma legenda única, sobreposição de cartões na cena do robô,
raposa aparecendo antes da hora, movimento lento nas cenas longas, textura/filetes mais discretos.
Não aceitos: encurtar para 50 s (a duração é livre e a locução precisa dos ~54 s) e trocar os blocos verdes por papel (o contraste
claro/escuro dá ritmo; o escuro é usado em 2 de 8 cenas).

## Editável
`projeto/` é um projeto HyperFrames (HTML + GSAP): `index.html` + `assets/`. Re-render: `npx hyperframes@0.8.155 render --quality delivery --fps 30`.
