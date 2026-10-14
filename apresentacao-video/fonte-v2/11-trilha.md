# 11. Trilha sonora (sintetizada por código Python/numpy)

**Clima:** caloroso, artesanal, "jardim" de fim de tarde. Cordas dedilhadas e tons de madeira, sem bateria, sem voz, nada eletrônico. Calma e orgânica, nunca épica.

**Andamento:** 76 BPM, 4/4. 16 compassos = 50,5 s.

**Tonalidade:** Ré maior, pentatônica (D E F# A B). A quarta e a sétima aparecem pouco, sem destaque.

**Progressão (ciclo de 4 compassos, repetido 4 vezes):** D | Bm7 | G | A (I–vi7–IV–V). O último ciclo fecha em D.

**Timbres:**
- *Pluck (dedilhado):* senoides em 1x, 2x e 3x a frequência fundamental, com amplitudes 1 / 0,3 / 0,1. Ataque de 4 ms e decaimento exponencial (tau ≈ 0,5 s), sem sustain. Notas em colcheias, panorama alternado ±0,3.
- *Pad:* 3 senoides por nota, com detune de ±6 cents, passadas por filtro passa-baixa de 1,8 kHz. Ataque de 1,2 s, release de 1,5 s, volume 0,25.
- *Sino suave:* parciais 1 / 2,0 / 2,76 com amplitudes 1 / 0,25 / 0,12. Ataque de 2 ms e tau ≈ 2,2 s. Usado só em dois pontos.

**Estrutura (compassos de ~3,16 s):**
- 0:00–0:06 (c. 1–2): abertura, só pad em D.
- 0:06–0:19 (c. 3–6): entra o pluck, melodia de oitavas na pentatônica.
- 0:19–0:32 (c. 7–10): movimento. Pluck e pad uma oitava acima; sino no c. 7 marca a virada.
- 0:32–0:44 (c. 11–14): ápice suave. Pluck em terças paralelas, mesmo andamento, dinâmica estável, sem crescendo agressivo.
- 0:44–0:50 (c. 15–16): resolução. Pad com release longo e sino final em D.

**Mix:** reverb leve (delay com feedback 0,3 mais ruído decaindo em 1,8 s). Fade-in de 1 s e fade-out de 2,5 s. Ducking: quando a narração fala, a trilha cai cerca de 10 dB, com seguidor de envelope (ataque 50 ms, release 400 ms). Pico em -1 dBFS, estéreo, 44,1 kHz.
