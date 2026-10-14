# Sound design: Atila's Client

## Identidade sonora
Calma, orgânica e artesanal, como o "Herbário da raposa". Timbres de senoide e ruído de papel. Nada agudo, estridente ou com cara de notificação de app. Tonalidade em Ré dórico, 72 BPM, sem percussão marcada. Todo o material é gerado por código (numpy/ffmpeg), sem samples externos.

## Níveis do mix
- Locução (TTS Gemini): -16 dBFS RMS, pico -3 dBFS. Referência do mix.
- Trilha: -26 dBFS RMS, cerca de 10 dB abaixo da locução. Ducking por sidechain: -10 dB, ataque 30 ms, liberação 600 ms, disparado pela locução.
- SFX: pico -12 dBFS, cerca de 4 dB abaixo da locução. Nunca tocam sobre palavras.
- Master: limitador com true peak em -1 dBTP.
- Loudness alvo: -14 LUFS integrado (`loudnorm=I=-14:TP=-1:LRA=11`), 48 kHz, AAC 192 kbps.

## SFX sintetizados
| # | Nome | Síntese | Duração | Envelope | Uso |
|---|------|---------|---------|----------|-----|
| 1 | Carimbo suave | senoides 180 + 360 Hz (-12 dB) + ruído lowpass 800 Hz | 0,35 s | ataque 5 ms, decaimento exp. τ 80 ms | selo do logotipo, fim do título |
| 2 | Clique de papel | ruído banda 2–4 kHz | 25 ms | ataque 1 ms, τ 12 ms | troca de botão ou aba |
| 3 | Folha virando | ruído lowpass 1,2 kHz, filtro varrendo 900→2200 Hz | 0,6 s | janela sen² | transição entre seções |
| 4 | Tick de mensagem | senoide 1320 Hz | 60 ms | ataque 2 ms, τ 20 ms | mensagem automática enviada |
| 5 | Sino de ouro | senoides 880, 1320, 1760 Hz | 1,2 s | ataque 3 ms, τ 500 ms | robô conectado |
| 6 | Dois tons | 523 Hz e 659 Hz, 80 ms cada, pausa 120 ms | 0,3 s | ataque 5 ms, release 20 ms | status "Conectado" |
| 7 | Toque de madeira | senoide 260→200 Hz em 40 ms + clique | 0,15 s | τ 30 ms | regra adicionada à lista |
| 8 | Descida suave | senoide 440→330 Hz | 0,2 s | fade linear | regra desativada |
| 9 | Vento de sálvia | ruído rosa lowpass 600 Hz | 1,5 s | sen² lento | fundo de cena, abaixo de -30 dBFS |
| 10 | Raposa | senoide 330→440 Hz, vibrato 5 Hz ±8 cents | 0,5 s | ataque 40 ms, release 150 ms | entrada da raposa |
