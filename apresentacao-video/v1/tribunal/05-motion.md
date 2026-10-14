# Linguagem de movimento: Atila's Client

Princípio: o movimento imita papel prensado e crescimento botânico. Nada quica.

## Easings (GSAP)
1. **Folha**: `power3.out`. Títulos, cards e telas. Duração 0,7 s.
2. **Haste**: `sine.inOut`. Linhas SVG (stroke-dashoffset). Duração 1,4 a 2,0 s.
3. **Pressão**: `power2.inOut`. Push-in e pan de telas. Duração 1,2 a 1,6 s.
4. **Respiro**: `back.out(1.2)`. Raposa e medalhões. Duração 0,6 s. Overshoot máximo, sem bounce.
5. **Corte**: `power2.in`. Todas as saídas. Duração 0,25 s.

Padrão global: `gsap.defaults({ ease: "power3.out" })`.

## Tipografia
- Títulos (Fraunces): revelação por máscara de baixo para cima (clip-path inset 100% para 0), y 16 px para 0, Folha 0,7 s.
- Corpo (Source Sans 3): opacidade 0 para 1 com y 8 px, Folha 0,5 s, por bloco de linha. Nunca palavra a palavra.
- Saída: opacidade para 0 e y -8 px, Corte 0,25 s.
- Palavras-chave entram no instante em que a narração as pronuncia.

## Escalonamento (stagger)
- Intervalo de 0,08 s, no máximo 5 itens por grupo, ordem de leitura de cima para baixo.
- Se o grupo passar de 0,6 s, reduzir o intervalo, nunca aumentar.

## Telas do celular
- Push-in: scale 1,00 para 1,06 em 1,4 s (Pressão), centrado no elemento citado. Nunca acima de 1,12.
- Pan vertical de 0,9 a 1,2 s para acompanhar a seção descrita. Sem deslocamento horizontal.
- Moldura do celular entra com Folha, 0,6 s, sem rotação.

## Transições motivadas
- **Folha de herbário**: a cena anterior é coberta por retângulo #FBF6EA com sombra suave que sobe por clip-path (1,0 s, Pressão). Usada entre seções.
- **Haste vegetal**: linha SVG #6F8A6A cresce do elemento de saída até o de entrada (Haste, 1,6 s). Uma folha surge no fim. Usada entre Moderação e Robô.
- **Raposa**: `fox_lookback` olha para a cena seguinte antes do corte. No fecho, `fox_sleeping` troca para `fox_head_calm` com Respiro.

## Evitar
- Elástico, bounce, rotação, shake, glitch e flashes.
- Whip pan e slides genéricos.
- Digitação letra por letra.
- Mais de dois easings numa mesma cena.
- Tela e texto principal se movendo ao mesmo tempo.
- Parallax rápido e animação do logotipo com efeitos.
