# Finalização (Pós-produção)

**Cor (sutil)**
- Curva suave: sombras levemente puxadas para verde-floresta (#1F3A2E), sem preto puro; papel (#F4ECDC) claro, sem estourar.
- Saturação ~0,94. Ouro (#9A7B2F/#D2B568) e terracota (#A8461F) preservados.
- Capturas do app: ajuste mínimo, para continuar parecendo a interface real.

**Textura**
- Grão leve (noise alls≈4–6, temporal) só sobre a camada de apresentação. Vinheta opcional, PI/5.

**Mixagem (48 kHz)**
- Narração em nível base. Trilha sintética baixa, com sidechain sob a voz. SFX pontuais.

```
ffmpeg -i narr.wav -i trilha.wav -i sfx.wav -filter_complex "[0:a]asplit=2[nsc][nmix];[1:a]volume=0.35[m];[m][nsc]sidechaincompress=threshold=0.03:ratio=8:attack=20:release=400[duck];[nmix][duck][2:a]amix=inputs=3:duration=longest:normalize=0,loudnorm=I=-16:TP=-1.5:LRA=11[out]" -map "[out]" -ar 48000 mix.wav
```

**Codificação final**

```
ffmpeg -i video_sem_audio.mp4 -i mix.wav -map 0:v -map 1:a -c:v libx264 -preset slow -crf 19 -pix_fmt yuv420p -r 30 -s 1080x1920 -c:a aac -b:a 192k -movflags +faststart final.mp4
```

**Verificação final**
- `ffprobe`: 1080x1920, 30 fps, yuv420p, AAC 192k.
- Faststart (moov antes de mdat): `ffprobe -v trace -i final.mp4 2>&1 | grep -m2 -E "type:'(moov|mdat)'"`
- Loudness: `ffmpeg -i final.mp4 -af ebur128=peak=true -f null - 2>&1 | tail -n 12` (alvo ≈ -16 LUFS, true peak ≤ -1,5 dBTP).
- Erros de decodificação: `ffmpeg -v error -i final.mp4 -f null -` (sem saída).
- Duração 40–60 s.
- Quadros-chave: texto legível no celular; "atilaclient.tech" correto; nenhum termo técnico (.bat, script, servidor, Docker, deploy) visível ou narrado; áudio só sintetizado ou próprio.
