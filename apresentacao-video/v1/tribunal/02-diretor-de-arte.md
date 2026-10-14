# Direção de arte: vídeo vertical 1080x1920

**Conceito:** herbário ilustrado da raposa. Papel envelhecido, tinta de floresta e filetes Art Nouveau. Calmo, artesanal, nunca tecnológico.

## Paleta
- Papel (fundo): #F4ECDC
- Cartão: #FBF6EA
- Sálvia clara: #E3E8D6
- Tinta (texto, títulos): #1F3A2E
- Terracota (ação, destaque único): #A8461F
- Ouro: #9A7B2F; sobre floresta, #D2B568
- Sálvia média: #6F8A6A
- Filetes: #CFC3A8

Proporção aproximada: papel 60%, tinta e sálvia 30%, terracota e ouro 10%.

## Tipografia (1080 px de largura)
- Títulos: Fraunces SemiBold, 104–120 px, entrelinha 1,1.
- Subtítulos: Fraunces SemiBold, 60–68 px.
- Corpo e legendas: Source Sans 3 Regular, 42–46 px, entrelinha 1,4.
- Rótulos (caixa alta, tracking 0,12em): Source Sans 3 SemiBold, 30 px.
- Piso absoluto: 30 px. Máximo de 3 linhas por bloco.

## Grid e margens
- Margens laterais: 88 px.
- Zona segura: 240 px no topo e 320 px embaixo (interface do Reels e Stories).
- Textos alinhados à esquerda; títulos de abertura e fechamento podem centralizar.
- Telas do app: 82% da largura útil, cantos de 24 px, sombra suave em tinta a 12%.

## Ornamentos
- Moldura de filete duplo (#CFC3A8, 2 px), cantos arredondados, inspirada em Art Nouveau.
- Folhas e arcos em traço (SVG, 3 px) só nas bordas, dentro da zona segura.
- Raposa: usar os assets existentes. fox_head_calm na abertura, fox_medallion_smile no fechamento, fox_lookback nas transições. Não redesenhar nem recolorir.
- Cartela de herbário: retângulo #FBF6EA, borda #CFC3A8, rótulo em caixa alta.

## Composição
- Uma ideia por cena: no máximo uma tela do app e um bloco de texto.
- Entradas suaves: fade e deslize de 24–40 px, 0,6–0,8 s, ease-out.
- Terracota só para o que deve ser notado (botão, palavra-chave).
- Textos sempre sobre área de contraste; nunca sobre a raposa.

## Evitar
- Neon, glow, gradientes saturados.
- Glitch, ruído, scanlines, distorção.
- Glassmorphism, blur de fundo, azul tecnológico.
- Fundo escuro dominante (exceto, se necessário, um fechamento em floresta com ouro #D2B568).
- Emojis, ícones coloridos de sistema, fotos de banco de imagens.
