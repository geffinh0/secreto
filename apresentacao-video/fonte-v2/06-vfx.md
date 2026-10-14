# 06 — Efeitos de composição e VFX

Princípio: a tela real do app é a protagonista. Os efeitos só reforçam a ideia e nunca competem com a tela. Tudo em HTML/CSS/SVG/Canvas.

## 5 efeitos recomendados

1. **Papel e grão (fundo)**: `<svg>` com `feTurbulence` (baseFrequency 0.8, numOctaves 2) em `position:fixed`, `opacity:.05`, `mix-blend-mode:multiply` sobre `#F4ECDC`. Evoca o herbário sem ruído visível após a compressão do vídeo.

2. **Tela com sombra de tinta (profundidade)**: screenshot em `<div>` com `border-radius:28px` e duas camadas de `box-shadow`, por exemplo `0 2px 4px rgba(31,58,46,.12), 0 24px 48px -12px rgba(31,58,46,.28)`. Entrada com `y: 12px → 0` em 0,6 s via GSAP.

3. **Palavra proibida carimbada**: selo SVG com `<text>` em Fraunces Bold, cor `#A8461F`, e `feTurbulence` + `feDisplacementMap` (scale 4) na borda para simular falha de tinta. Anima `scale 1.4 → 1`, `rotate -8°`, `opacity 0 → .92`, no instante em que a narração cita a palavra.

4. **Riscar a palavra da lista**: `<path>` sobre o termo com `stroke-dashoffset` animado (0,4 s). Ouro `#9A7B2F` para silenciar e terracota para banir, sincronizado com a legenda.

5. **Filete Art Nouveau nos títulos**: linha `#CFC3A8` em SVG desenhada com `stroke-dashoffset` na entrada, com cantos de curva simples. Reforça a identidade sem ornamento excessivo.

## 3 efeitos a NÃO usar

1. **Glitch e separação RGB**: agride a identidade calma e pode ser lido como erro do próprio app.
2. **Partículas, confete e brilhos**: infantilizam o vídeo e fogem do tom de ferramenta confiável.
3. **Moldura 3D de celular com reflexo**: esconde área útil da tela real e contradiz a proposta de mostrar o app fielmente.

## Regras gerais

- No máximo um efeito de destaque por cena.
- Nenhum efeito sugere IA, números, depoimentos ou integrações.
- Validar cada efeito em 1080x1920, 30 fps, antes da renderização final.
