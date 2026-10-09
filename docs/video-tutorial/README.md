# Vídeo tutorial — Atila's Client do zero

`atilas-client-tutorial.mp4` (1920×1080, ~4 min 10 s, narrado em pt-BR com legendas) ensina
a usar o portal do começo ao fim:

| # | Cena | O que mostra |
|---|------|--------------|
| — | Abertura | O que é o Atila's Client |
| — | Como funciona | Portal → Servidor → Robô na live (silencia, bane, envia mensagens) |
| 1 | Ligar o sistema | `start_server.bat` ou `python main.py` + `flutter run`, abrir `localhost:3000` |
| 2 | Criar sua conta | Cadastro no portal |
| 3 | Conhecer o painel | Dashboard e menu lateral |
| 4 | Palavras para silenciar | `zap`, `passa zap` |
| — | Dica | Palavra inteira, maiúsculas/acentos ignorados, `*` como prefixo |
| 5 | Palavras para banir | `golpe`, `divulg*` e as três opções (automática, permanente, imunidade por diamantes) |
| 6 | Mensagens automáticas | Fila, intervalo, envio automático |
| 7 | Conectar o robô | E-mail e senha / celular / token |
| — | Importante | O robô precisa ser moderador da live |
| 8 | Escolher e favoritar a live | Busca pelo ID público, favoritar |
| — | Ao vivo | Chat em tempo real, silenciamento e banimentos acontecendo |
| 9 | Estatísticas e conta | Dashboard, Estatísticas, Configurações |
| — | Resumo | Parar a moderação e checklist final |

Tudo o que aparece na tela é o **app real** (build Flutter Web + backend FastAPI) gravado em
uma sessão automatizada. O SuperLive é o simulador que já existe em
`backend/tests/mock_superlive.py`, então nenhuma conta real foi usada. As mensagens do chat são
injetadas pelo simulador.

## Como foi feito

- **Edição/composição:** [HyperFrames](https://github.com/heygen-com/hyperframes), com HTML,
  GSAP e render determinístico para MP4.
- **Voz:** Kokoro-82M local (`npx hyperframes tts`, voz `pf_dora`, pt-BR), gerada frase a frase
  para as legendas ficarem sincronizadas.
- **Trilha:** um pad ambiente sintetizado (sem direitos autorais de terceiros).
- **Gravação de tela:** Playwright + CDP screencast, com cursor visível e efeito de clique, e
  ações cronometradas pela narração.

## Regenerar

Requisitos: Node 22+, Python 3, FFmpeg, Flutter, `espeak-ng`, `pip install kokoro-onnx soundfile`.

```bash
flutter build web --release --no-web-resources-cdn
python3 -m http.server 3000 --directory build/web &      # portal
bash docs/video-tutorial/scripts/restart.sh              # simulador SuperLive + backend (DB limpo)

npx hyperframes init tutorial --example blank --non-interactive
python3 docs/video-tutorial/scripts/tts.py               # narração + timing.json
node docs/video-tutorial/scripts/record.mjs              # grava o app (precisa de `npm i playwright`)
python3 docs/video-tutorial/scripts/gen.py               # gera tutorial/index.html
cd tutorial && npx hyperframes render --video-frame-format png
```

Os scripts usam caminhos de trabalho absolutos (`/tmp/claude-0/...`); ajuste as constantes no
topo de cada um antes de rodar em outra máquina. O texto da narração fica em
`scripts/script.json`: cada linha tem a versão fonética que vai para o TTS e o texto da legenda.
