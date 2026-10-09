# Vídeos tutoriais: Atila's Client do zero

Duas versões do mesmo tutorial, narradas em pt-BR, com legendas e trilha:

| Arquivo | Formato | Para |
|---|---|---|
| `atilas-client-computador.mp4` | 1920×1080 (16:9) | YouTube, site, apresentação. Mostra o site no navegador do computador |
| `atilas-client-celular.mp4` | 1080×1920 (9:16) | Reels, TikTok, Shorts, Status. Mostra o site no celular |
| `atilas-client-celular-cinematico.mp4` | 1080×1920 (9:16) | Versão cinematográfica do celular: luz âmbar volumétrica, partículas com profundidade de campo, celular em 3D, cartões de status brilhando, voz masculina Piper "Cadu" (`scripts/tts3.py`, `scripts/gen3.py`) |

Roteiro (cerca de 4 min):

| # | Cena | O que mostra |
|---|------|--------------|
| — | Abertura | O que é o Atila's Client |
| — | Como funciona | Site → servidor → robô na live (silencia, expulsa, manda mensagens) |
| 1 | Acessar o site | `atilaclient.tech`, no computador ou no celular, e como instalar como app |
| 2 | Criar sua conta | Cadastro |
| 3 | Conhecer o painel | Dashboard e abas |
| 4 | Palavras para silenciar | `zap`, `passa zap` |
| — | Dica | Comparação por palavra inteira e `*` como prefixo |
| 5 | Palavras para banir | `golpe`, `divulg*` e as três chaves da tela |
| 6 | Mensagens automáticas | Fila, intervalo e envio automático |
| 7 | Conectar o robô | E-mail e senha, celular (SMS) ou token |
| — | Importante | O robô precisa ser moderador da live |
| 8 | Escolher a live | Busca pelo ID público e Favoritar |
| — | Ao vivo | Chat em tempo real, com silenciamentos e banimentos acontecendo |
| 9 | Estatísticas e conta | Dashboard, Estatísticas e Configurações |
| — | Resumo | Parar a moderação, checklist e encerramento |

## Como foi feito

- **O que aparece na tela é o app real**: o build Flutter Web deste repositório, junto com o
  backend, gravado em uma sessão automatizada. A barra de endereço mostra `atilaclient.tech`.
  O SuperLive é o simulador de `backend/tests/mock_superlive.py`, então nenhuma conta real
  foi usada, e as mensagens do chat são injetadas por ele.
- **Edição**: [HyperFrames](https://github.com/heygen-com/hyperframes) (HTML + GSAP com
  render determinístico). O layout é dividido em faixas: título no topo, a tela no meio e a
  legenda embaixo. Nenhum texto entra na faixa do outro. O `hyperframes check` passa sem
  problemas de layout nem de contraste.
- **Voz**: Kokoro-82M local (`npx hyperframes tts`, voz `pf_dora`, pt-BR), gerada frase a
  frase para as legendas ficarem sincronizadas. A versão de celular diz "toca" onde a de
  computador diz "clica".
- **Trilha**: pad ambiente sintetizado, sem direitos autorais de terceiros.

## Regenerar

O texto da narração fica em `scripts/script2.json`. Cada linha tem a versão fonética
enviada ao TTS e o texto da legenda.

```bash
flutter build web --release --no-web-resources-cdn
bash scripts/restart.sh                       # simulador SuperLive + backend (DB limpo) + portal :3000
python3 scripts/tts2.py                       # narração + timing (computador e celular)
MODE=desktop node scripts/record2.mjs         # grava o app (precisa de `npm i playwright`)
MODE=mobile  node scripts/record2.mjs
bash scripts/master.sh desktop && python3 scripts/retime.py desktop
bash scripts/master.sh mobile  && python3 scripts/retime.py mobile
python3 scripts/gen2.py desktop && python3 scripts/gen2.py mobile
cd <projeto> && npx hyperframes render --video-frame-format png
```

Requisitos: Node 22+, Python 3, FFmpeg, Flutter, `espeak-ng`, `pip install kokoro-onnx soundfile`.
Os scripts usam caminhos de trabalho absolutos (`/tmp/claude-0/...`). Ajuste as constantes
no topo de cada arquivo antes de rodar em outra máquina.
