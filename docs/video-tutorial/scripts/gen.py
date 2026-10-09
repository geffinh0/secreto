"""Generates the HyperFrames composition (index.html) for the Atila's Client tutorial."""
import json, html

T = json.load(open('/tmp/claude-0/hf/build/timing.json'))
REC = json.load(open('/tmp/claude-0/demo/frames.json'))['marks']
LEAD = 0.5
REC0 = REC['conta']['page']

order = ['intro', 'como', 'iniciar', 'conta', 'dash', 'silenciar', 'regras', 'banir',
         'mensagens', 'robo', 'moderador', 'favoritar', 'aovivo', 'painel', 'final']
rec_ids = order[3:]
slot = {'intro': 11.4, 'como': 21.9, 'iniciar': 19.4}
for i, k in enumerate(rec_ids):
    slot[k] = (REC[rec_ids[i + 1]]['page'] - REC[k]['page']) if i + 1 < len(rec_ids) else 18.4
start = {}
t = 0.0
for k in order:
    start[k] = round(t, 3)
    t += slot[k]
TOTAL = round(t, 3)
T_REC = start['conta']
SCREEN_LEN = 198.2
print('total', TOTAL)

chapters = {
    'como': ('Visão geral', 'Como funciona'),
    'iniciar': ('Passo 1', 'Ligar o sistema'),
    'conta': ('Passo 2', 'Criar sua conta'),
    'dash': ('Passo 3', 'Conhecer o painel'),
    'silenciar': ('Passo 4', 'Palavras para silenciar'),
    'regras': ('Dica', 'Como as palavras são comparadas'),
    'banir': ('Passo 5', 'Palavras para banir'),
    'mensagens': ('Passo 6', 'Mensagens automáticas'),
    'robo': ('Passo 7', 'Conectar o robô'),
    'moderador': ('Importante', 'O robô precisa ser moderador'),
    'favoritar': ('Passo 8', 'Escolher e favoritar a live'),
    'aovivo': ('Ao vivo', 'O robô em ação'),
    'painel': ('Passo 9', 'Estatísticas e conta'),
    'final': ('Resumo', 'Recapitulando'),
}

# camera moves on the recording: (scene, t0, t1, fx, fy, scale)  — screen px of the 1536x864 capture
zooms = [
    ('conta', 3.2, 13.6, 768, 420, 1.32),
    ('silenciar', 4.2, 14.4, 900, 620, 1.22),
    ('banir', 6.4, 11.6, 900, 640, 1.22),
    ('banir', 11.6, 19.4, 700, 330, 1.3),
    ('mensagens', 4.6, 13.2, 900, 560, 1.2),
    ('robo', 5.6, 12.4, 520, 230, 1.35),
    ('favoritar', 3.0, 17.6, 880, 560, 1.22),
    ('aovivo', 2.6, 9.2, 880, 690, 1.25),
]

E = html.escape
parts = []
js = []

# ── voice + music ───────────────────────────────────────────────────────────
audio = []
for k in order:
    audio.append(f'<audio id="vo-{k}" src="assets/vo/{k}.wav" data-start="{start[k] + LEAD:.3f}" '
                 f'data-duration="{T[k]["duration"]:.3f}" data-track-index="5" data-volume="1"></audio>')
audio.append(f'<audio id="bgm" src="assets/bgm.mp3" data-start="0" data-duration="{TOTAL:.3f}" '
             f'data-track-index="6" data-volume="0.13"></audio>')

# ── captions ────────────────────────────────────────────────────────────────
caps = []
ci = 0
for k in order:
    for c in T[k]['captions']:
        s = start[k] + LEAD + c['start']
        d = c['end'] - c['start'] + 0.25
        caps.append(f'<div id="cap{ci}" class="clip cap" data-start="{s:.3f}" data-duration="{d:.3f}" '
                    f'data-track-index="4"><span class="cap-in">{E(c["text"])}</span></div>')
        js.append(f'tl.fromTo("#cap{ci} .cap-in",{{y:14,opacity:0}},{{y:0,opacity:1,duration:.28,ease:"power2.out"}},{s:.3f});')
        ci += 1

# ── chapter labels ──────────────────────────────────────────────────────────
chap = []
for k, (tag, title) in chapters.items():
    s, d = start[k], slot[k]
    chap.append(f'<div id="ch-{k}" class="clip chapter" data-start="{s:.3f}" data-duration="{d:.3f}" data-track-index="3">'
                f'<div class="ch-in"><span class="ch-tag">{E(tag)}</span><span class="ch-title">{E(title)}</span></div></div>')
    js.append(f'tl.fromTo("#ch-{k} .ch-in",{{x:-30,opacity:0}},{{x:0,opacity:1,duration:.5,ease:"power3.out"}},{s + 0.1:.3f});')

# ── camera keyframes ────────────────────────────────────────────────────────
for (k, t0, t1, fx, fy, sc) in zooms:
    a, b = start[k] + t0, start[k] + t1
    js.append(f'tl.to("#cam",{{x:{fx * (1 - sc):.1f},y:{fy * (1 - sc):.1f},scale:{sc},duration:.9,ease:"power2.inOut"}},{a:.3f});')
    js.append(f'tl.to("#cam",{{x:0,y:0,scale:1,duration:.9,ease:"power2.inOut"}},{b - 0.9:.3f});')

S = start
cfg = dict(TOTAL=TOTAL, T_REC=T_REC)

html_out = f'''<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=1920, height=1080" />
<title>Atila's Client — Tutorial completo</title>
<script src="assets/gsap.min.js"></script>
<style>
@font-face {{ font-family: "Nunito"; src: url("assets/fonts/nunito-latin-400-normal.woff2") format("woff2"); font-weight: 400; }}
@font-face {{ font-family: "Nunito"; src: url("assets/fonts/nunito-latin-600-normal.woff2") format("woff2"); font-weight: 600; }}
@font-face {{ font-family: "Nunito"; src: url("assets/fonts/nunito-latin-700-normal.woff2") format("woff2"); font-weight: 700; }}
@font-face {{ font-family: "Nunito"; src: url("assets/fonts/nunito-latin-800-normal.woff2") format("woff2"); font-weight: 800; }}
@font-face {{ font-family: "Nunito"; src: url("assets/fonts/nunito-latin-900-normal.woff2") format("woff2"); font-weight: 900; }}
@font-face {{ font-family: "JetBrains Mono"; src: url("assets/fonts/jetbrains-mono-latin-400-normal.woff2") format("woff2"); font-weight: 400; }}
@font-face {{ font-family: "JetBrains Mono"; src: url("assets/fonts/jetbrains-mono-latin-600-normal.woff2") format("woff2"); font-weight: 600; }}
:root {{
  --bg: #1B140F; --card: #241B15; --surface: #2C2119; --elev: #362820;
  --orange: #E07B39; --rust: #A24A32; --gold: #D9A441; --cream: #F7EEE3;
  --text2: #CBB8A4; --muted: #8C7968; --border: #3A2D22; --ok: #6E9B5E; --err: #C2543A;
}}
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
html, body {{ width: 1920px; height: 1080px; overflow: hidden; background: var(--bg); }}
#root {{ position: relative; width: 100%; height: 100%; overflow: hidden; font-family: "Nunito", sans-serif; color: var(--cream); background: var(--bg); }}
.layer {{ position: absolute; inset: 0; }}
#bg {{ background: radial-gradient(1200px 700px at 15% 0%, #3a2416 0%, transparent 60%), radial-gradient(900px 600px at 100% 100%, #2e1a12 0%, transparent 60%), var(--bg); }}
.glow {{ position: absolute; border-radius: 50%; filter: blur(90px); opacity: .35; }}
#glow1 {{ width: 620px; height: 620px; left: -120px; top: -160px; background: #E07B39; opacity: .16; }}
#glow2 {{ width: 560px; height: 560px; right: -140px; bottom: -180px; background: #A24A32; opacity: .2; }}
#progress {{ position: absolute; left: 0; top: 0; height: 6px; width: 1920px; background: linear-gradient(90deg, var(--rust), var(--orange), var(--gold)); transform-origin: 0 50%; }}

/* chapter */
.chapter {{ position: absolute; left: 269px; top: 26px; width: 1382px; height: 56px; }}
.ch-in {{ display: flex; align-items: center; gap: 16px; height: 56px; }}
.ch-tag {{ background: var(--orange); color: #1B140F; font-weight: 900; font-size: 22px; padding: 7px 16px; border-radius: 999px; text-transform: uppercase; letter-spacing: .04em; }}
.ch-title {{ font-size: 32px; font-weight: 800; color: var(--cream); }}

/* browser window */
#win {{ position: absolute; left: 269px; top: 96px; width: 1382px; height: 816px; border-radius: 16px; overflow: hidden; background: #120d0a; border: 1px solid #4A3A2C; box-shadow: 0 30px 80px rgba(0,0,0,.55), 0 0 0 1px rgba(255,255,255,.03); }}
#bar {{ position: absolute; left: 0; top: 0; width: 1382px; height: 38px; background: #2a1f18; display: flex; align-items: center; padding: 0 16px; gap: 8px; border-bottom: 1px solid #3A2D22; }}
.dot {{ width: 12px; height: 12px; border-radius: 50%; display: block; }}
#url {{ margin-left: 18px; height: 24px; width: 560px; border-radius: 8px; background: #1B140F; color: var(--text2); font-family: "JetBrains Mono", monospace; font-size: 14px; display: flex; align-items: center; padding: 0 12px; }}
#viewport {{ position: absolute; left: 0; top: 38px; width: 1382px; height: 778px; overflow: hidden; }}
#stage {{ position: absolute; left: 0; top: 0; width: 1536px; height: 864px; transform: scale(0.8997); transform-origin: 0 0; }}
#cam {{ position: absolute; left: 0; top: 0; width: 1536px; height: 864px; transform-origin: 0 0; }}
#screen {{ position: absolute; left: 0; top: 0; width: 1536px; height: 864px; }}
#poster {{ position: absolute; left: 0; top: 0; width: 1536px; height: 864px; }}
#dim {{ position: absolute; left: 269px; top: 96px; width: 1382px; height: 816px; border-radius: 16px; background: rgba(18,12,9,.78); opacity: 0; }}

/* captions */
.cap {{ position: absolute; left: 160px; top: 936px; width: 1600px; height: 120px; display: flex; justify-content: center; align-items: flex-start; }}
.cap-in {{ display: block; max-width: 1560px; text-align: center; font-size: 34px; line-height: 1.3; font-weight: 700; color: #fff; background: rgba(15,10,7,.82); border: 1px solid rgba(224,123,57,.35); padding: 10px 26px; border-radius: 14px; }}

/* intro */
#intro {{ position: absolute; inset: 0; }}
#intro-fox {{ position: absolute; left: 660px; top: 120px; width: 600px; height: 400px; object-fit: contain; }}
#intro-title {{ position: absolute; left: 0; top: 520px; width: 1920px; text-align: center; font-size: 120px; font-weight: 900; letter-spacing: -2px; }}
#intro-title span {{ color: var(--orange); }}
#intro-sub {{ position: absolute; left: 0; top: 680px; width: 1920px; text-align: center; font-size: 40px; font-weight: 600; color: var(--text2); }}
#intro-pill {{ position: absolute; left: 660px; top: 770px; width: 600px; height: 58px; border-radius: 999px; border: 2px solid var(--orange); color: var(--orange); font-size: 26px; font-weight: 800; display: flex; align-items: center; justify-content: center; letter-spacing: .08em; }}

/* diagram */
#como {{ position: absolute; inset: 0; }}
.node {{ position: absolute; top: 250px; width: 440px; height: 300px; border-radius: 24px; background: var(--card); border: 2px solid var(--border); display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 14px; }}
.node .ic {{ width: 110px; height: 110px; border-radius: 28px; background: var(--surface); display: flex; align-items: center; justify-content: center; }}
.node h3 {{ font-size: 40px; font-weight: 900; }}
.node p {{ font-size: 24px; color: var(--text2); text-align: center; width: 380px; }}
#n1 {{ left: 140px; }} #n2 {{ left: 740px; }} #n3 {{ left: 1340px; }}
.arrow {{ position: absolute; top: 385px; height: 8px; width: 140px; border-radius: 4px; background: linear-gradient(90deg, var(--rust), var(--orange)); transform-origin: 0 50%; }}
#a1 {{ left: 590px; }} #a2 {{ left: 1190px; }}
.chips {{ position: absolute; left: 0; top: 620px; width: 1920px; display: flex; justify-content: center; gap: 26px; }}
.chip {{ display: block; font-size: 30px; font-weight: 800; padding: 16px 30px; border-radius: 16px; background: var(--surface); border: 2px solid var(--border); }}
.chip b {{ color: var(--orange); }}
#close-tab {{ position: absolute; left: 560px; top: 760px; width: 800px; height: 80px; border-radius: 18px; background: rgba(110,155,94,.16); border: 2px solid var(--ok); color: #cfe7c4; font-size: 30px; font-weight: 800; display: flex; align-items: center; justify-content: center; gap: 14px; }}

/* terminal */
#iniciar {{ position: absolute; inset: 0; }}
#term {{ position: absolute; left: 260px; top: 150px; width: 1400px; height: 640px; border-radius: 18px; background: #0f0b08; border: 1px solid #4A3A2C; box-shadow: 0 30px 80px rgba(0,0,0,.5); overflow: hidden; }}
#term-bar {{ height: 46px; background: #2a1f18; display: flex; align-items: center; gap: 8px; padding: 0 18px; color: var(--muted); font-size: 18px; font-weight: 700; }}
#term-body {{ padding: 30px 40px; font-family: "JetBrains Mono", monospace; font-size: 30px; line-height: 1.75; color: #e9dccd; }}
.ln {{ display: block; height: 52px; white-space: nowrap; }}
.ty {{ display: inline-block; overflow: hidden; white-space: nowrap; vertical-align: top; width: 0; }}
.pr {{ color: var(--orange); }}
.cm {{ color: var(--muted); }}
.okc {{ color: #9fd08a; }}
.bat {{ position: absolute; left: 1180px; top: 210px; width: 360px; height: 150px; border-radius: 18px; background: var(--card); border: 2px solid var(--orange); display: flex; align-items: center; gap: 20px; padding: 0 26px; }}
.bat .file {{ width: 70px; height: 86px; border-radius: 8px; background: #3b2a1f; border: 2px solid #6b4a33; display: flex; align-items: flex-end; justify-content: center; padding-bottom: 8px; font-family: "JetBrains Mono", monospace; font-size: 16px; color: var(--gold); font-weight: 600; }}
.bat .nm {{ font-family: "JetBrains Mono", monospace; font-size: 24px; font-weight: 600; }}
.bat .hint {{ font-size: 20px; color: var(--text2); }}

/* overlay cards */
.ovl {{ position: absolute; inset: 0; }}
.card {{ position: absolute; border-radius: 26px; background: var(--card); border: 2px solid var(--border); box-shadow: 0 30px 80px rgba(0,0,0,.6); }}
#rg-card {{ left: 360px; top: 170px; width: 1200px; height: 660px; padding: 46px 56px; }}
#rg-card h2 {{ font-size: 46px; font-weight: 900; margin-bottom: 26px; }}
.rule {{ display: flex; align-items: center; gap: 22px; height: 76px; margin-bottom: 14px; padding: 0 24px; border-radius: 16px; background: var(--surface); font-size: 30px; font-weight: 700; }}
.kw {{ font-family: "JetBrains Mono", monospace; color: var(--gold); background: #1B140F; padding: 4px 14px; border-radius: 10px; font-size: 28px; }}
.res {{ margin-left: auto; font-weight: 900; font-size: 28px; padding: 4px 16px; border-radius: 10px; }}
.yes {{ color: #cfe7c4; background: rgba(110,155,94,.25); }}
.no {{ color: #f3c2b5; background: rgba(194,84,58,.25); }}
.sep {{ height: 2px; background: var(--border); margin: 22px 0 22px; }}
#md-card {{ left: 410px; top: 230px; width: 1100px; height: 520px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 26px; border-color: var(--gold); text-align: center; padding: 0 70px; }}
#md-card h2 {{ font-size: 54px; font-weight: 900; color: var(--gold); }}
#md-card p {{ font-size: 34px; font-weight: 700; color: var(--cream); line-height: 1.35; }}
#rc-card {{ left: 410px; top: 130px; width: 1100px; height: 760px; padding: 44px 60px; }}
#rc-card h2 {{ font-size: 48px; font-weight: 900; margin-bottom: 24px; }}
.step {{ display: flex; align-items: center; gap: 24px; height: 88px; margin-bottom: 10px; padding: 0 26px; border-radius: 18px; background: var(--surface); font-size: 34px; font-weight: 800; }}
.num {{ width: 52px; height: 52px; border-radius: 50%; background: var(--orange); color: #1B140F; font-weight: 900; font-size: 28px; display: flex; align-items: center; justify-content: center; }}
.tick {{ margin-left: auto; width: 46px; height: 46px; border-radius: 50%; background: var(--ok); display: flex; align-items: center; justify-content: center; }}
#outro {{ position: absolute; inset: 0; background: var(--bg); z-index: 50; }}
.cap {{ z-index: 70; }}
#progress {{ z-index: 60; }}
#outro-fox {{ position: absolute; left: 760px; top: 170px; width: 400px; height: 400px; object-fit: contain; }}
#outro-title {{ position: absolute; left: 0; top: 590px; width: 1920px; text-align: center; font-size: 96px; font-weight: 900; }}
#outro-title span {{ color: var(--orange); }}
#outro-sub {{ position: absolute; left: 0; top: 730px; width: 1920px; text-align: center; font-size: 38px; font-weight: 700; color: var(--text2); }}
</style>
</head>
<body>
<div id="root" data-composition-id="main" data-start="0" data-duration="{TOTAL:.3f}" data-width="1920" data-height="1080">
  <div id="bg" class="layer"><div id="glow1" class="glow"></div><div id="glow2" class="glow"></div></div>

  <!-- INTRO -->
  <div id="intro" class="clip" data-start="0" data-duration="{slot['intro']:.3f}" data-track-index="1">
    <img id="intro-fox" src="assets/img/fox_hero.webp" alt="" />
    <div id="intro-title">Atila's <span>Client</span></div>
    <div id="intro-sub">Moderação automática para as suas lives no SuperLive</div>
    <div id="intro-pill">TUTORIAL COMPLETO · DO ZERO</div>
  </div>

  <!-- COMO FUNCIONA -->
  <div id="como" class="clip" data-start="{S['como']:.3f}" data-duration="{slot['como']:.3f}" data-track-index="1">
    <div id="n1" class="node"><div class="ic"><svg width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="#E07B39" stroke-width="2"><rect x="2" y="4" width="20" height="15" rx="2"/><path d="M2 8h20"/></svg></div><h3>Portal</h3><p>Você configura tudo no navegador</p></div>
    <div id="a1" class="arrow"></div>
    <div id="n2" class="node"><div class="ic"><svg width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="#D9A441" stroke-width="2"><rect x="3" y="3" width="18" height="7" rx="2"/><rect x="3" y="14" width="18" height="7" rx="2"/><path d="M7 6.5h.01M7 17.5h.01"/></svg></div><h3>Servidor</h3><p>Guarda as regras e controla o robô</p></div>
    <div id="a2" class="arrow"></div>
    <div id="n3" class="node"><div class="ic"><img src="assets/img/fox_avatar.png" alt="" style="width:92px;height:92px;object-fit:contain" /></div><h3>Robô na live</h3><p>Lê o chat em tempo real no SuperLive</p></div>
    <div class="chips">
      <span id="c1" class="chip"><b>Silencia</b> quem xinga</span>
      <span id="c2" class="chip"><b>Bane</b> golpistas</span>
      <span id="c3" class="chip"><b>Envia</b> mensagens</span>
    </div>
    <div id="close-tab">Pode fechar a aba: a moderação continua</div>
  </div>

  <!-- INICIAR -->
  <div id="iniciar" class="clip" data-start="{S['iniciar']:.3f}" data-duration="{slot['iniciar']:.3f}" data-track-index="1">
    <div id="term">
      <div id="term-bar"><span class="dot" style="background:#C2543A"></span><span class="dot" style="background:#D9A441"></span><span class="dot" style="background:#6E9B5E"></span><span style="margin-left:14px">Terminal</span></div>
      <div id="term-body">
        <span class="ln cm"><span id="t0" class="ty"># Windows: dois cliques em</span></span>
        <span class="ln"><span class="pr">&gt; </span><span id="t1" class="ty">start_server.bat</span></span>
        <span class="ln cm"><span id="t2" class="ty"># ou, manualmente:</span></span>
        <span class="ln"><span class="pr">$ </span><span id="t3" class="ty">cd backend &amp;&amp; pip install -r requirements.txt</span></span>
        <span class="ln"><span class="pr">$ </span><span id="t4" class="ty">python main.py</span><span id="t4b" class="okc" style="opacity:0">   API em :8000</span></span>
        <span class="ln"><span class="pr">$ </span><span id="t5" class="ty">flutter run -d web-server --web-port 3000</span></span>
        <span class="ln okc"><span id="t6" class="ty">Portal em http://localhost:3000</span></span>
      </div>
    </div>
    <div id="batcard" class="bat"><div class="file">.BAT</div><div><div class="nm">start_server.bat</div><div class="hint">duplo clique</div></div></div>
  </div>

  <!-- BROWSER WINDOW (recording) -->
  <div id="winwrap" class="layer">
    <div id="win">
      <div id="bar"><span class="dot" style="background:#C2543A"></span><span class="dot" style="background:#D9A441"></span><span class="dot" style="background:#6E9B5E"></span><div id="url"><span id="urltxt" class="ty">localhost:3000</span></div></div>
      <div id="viewport"><div id="stage"><div id="cam">
        <img id="poster" src="assets/img/login.jpg" alt="" />
        <video id="screen" src="assets/rec/screen.mp4" muted playsinline data-start="{T_REC:.3f}" data-duration="{min(SCREEN_LEN, TOTAL - T_REC):.3f}" data-track-index="0"></video>
      </div></div></div>
    </div>
    <div id="dim"></div>
  </div>

  <!-- REGRAS overlay -->
  <div id="regras" class="clip ovl" data-start="{S['regras'] + 0.3:.3f}" data-duration="{slot['regras'] - 0.5:.3f}" data-track-index="2">
    <div id="rg-card" class="card">
      <h2>Como as palavras são comparadas</h2>
      <div id="r1" class="rule"><span class="kw">passa zap</span><span>“Me PASSA &nbsp; o ZÁP?”</span><span class="res no">não pega</span></div>
      <div id="r2" class="rule"><span class="kw">passa zap</span><span>“me PASSA   ZÁP”</span><span class="res yes">pega</span></div>
      <div id="r3" class="rule"><span class="kw">zap</span><span>“zapzap”</span><span class="res no">palavra inteira</span></div>
      <div class="sep"></div>
      <div id="r4" class="rule"><span class="kw">divulg*</span><span>“divulguem” · “divulgação”</span><span class="res yes">prefixo</span></div>
    </div>
  </div>

  <!-- MODERADOR overlay -->
  <div id="moderador" class="clip ovl" data-start="{S['moderador'] + 0.3:.3f}" data-duration="{slot['moderador'] - 0.6:.3f}" data-track-index="2">
    <div id="md-card" class="card">
      <svg width="110" height="110" viewBox="0 0 24 24" fill="none" stroke="#D9A441" stroke-width="2"><path d="M12 2l8 4v6c0 5-3.5 8.5-8 10-4.5-1.5-8-5-8-10V6z"/><path d="M12 8v5M12 16h.01"/></svg>
      <h2>Adicione o robô como moderador</h2>
      <p>A streamer precisa tornar a conta do robô moderadora da live. Sem isso, o SuperLive recusa silenciar e banir.</p>
    </div>
  </div>

  <!-- RECAP -->
  <div id="recap" class="clip ovl" data-start="{S['final'] + 4.2:.3f}" data-duration="{slot['final'] - 4.2:.3f}" data-track-index="2">
    <div id="rc-card" class="card">
      <h2>Checklist</h2>
      {''.join(f'<div id="st{i}" class="step"><span class="num">{i + 1}</span><span>{E(s)}</span><span class="tick"><svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="3"><path d="M5 12l5 5 9-10"/></svg></span></div>' for i, s in enumerate(['Crie sua conta', 'Cadastre as palavras (silenciar / banir)', 'Monte as mensagens automáticas', 'Conecte o robô', 'Peça para virar moderador', 'Favorite a streamer']))}
    </div>
  </div>

  <div id="outro" class="clip" data-start="{S['final'] + 0.5 + T['final']['captions'][2]['start']:.3f}" data-duration="{TOTAL - (S['final'] + 0.5 + T['final']['captions'][2]['start']):.3f}" data-track-index="2">
    <img id="outro-fox" src="assets/img/fox_avatar.png" alt="" />
    <div id="outro-title">Atila's <span>Client</span></div>
    <div id="outro-sub">Suas lives moderadas no piloto automático</div>
  </div>

  {''.join(chap)}
  {''.join(caps)}
  <div id="progress"></div>
  {''.join(audio)}
</div>
<script>
const tl = gsap.timeline({{ paused: true }});
const TOTAL = {TOTAL:.3f};
tl.fromTo("#progress", {{ scaleX: 0 }}, {{ scaleX: 1, duration: TOTAL, ease: "none" }}, 0);
tl.fromTo("#glow1", {{ x: 0, y: 0 }}, {{ x: 260, y: 120, duration: TOTAL, ease: "sine.inOut" }}, 0);
tl.fromTo("#glow2", {{ x: 0, y: 0 }}, {{ x: -240, y: -90, duration: TOTAL, ease: "sine.inOut" }}, 0);

// intro
tl.fromTo("#intro-fox", {{ y: 60, opacity: 0, scale: .9 }}, {{ y: 0, opacity: 1, scale: 1, duration: 1, ease: "back.out(1.6)" }}, 0.2);
tl.fromTo("#intro-title", {{ y: 40, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .8, ease: "power3.out" }}, 0.7);
tl.fromTo("#intro-sub", {{ y: 30, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .7, ease: "power3.out" }}, 1.2);
tl.fromTo("#intro-pill", {{ scale: .8, opacity: 0 }}, {{ scale: 1, opacity: 1, duration: .6, ease: "back.out(2)" }}, 1.7);
tl.to("#intro-fox", {{ y: -14, duration: 2.2, ease: "sine.inOut", yoyo: true, repeat: 3 }}, 1.3);
tl.to(["#intro-fox", "#intro-title", "#intro-sub", "#intro-pill"], {{ opacity: 0, y: -30, duration: .5, stagger: .05, ease: "power2.in" }}, {slot['intro'] - 0.7:.3f});

// como funciona
const C = {S['como']:.3f}, cc = {json.dumps([c['start'] + LEAD for c in T['como']['captions']])};
tl.fromTo("#n1", {{ y: 40, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .6, ease: "power3.out" }}, C + 0.4);
tl.fromTo("#a1", {{ scaleX: 0 }}, {{ scaleX: 1, duration: .5, ease: "power2.out" }}, C + cc[1]);
tl.fromTo("#n2", {{ y: 40, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .6, ease: "power3.out" }}, C + cc[1] + 0.3);
tl.fromTo("#a2", {{ scaleX: 0 }}, {{ scaleX: 1, duration: .5, ease: "power2.out" }}, C + cc[2]);
tl.fromTo("#n3", {{ y: 40, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .6, ease: "power3.out" }}, C + cc[2] + 0.3);
tl.fromTo("#c1", {{ y: 30, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .45, ease: "back.out(2)" }}, C + cc[2] + 3.0);
tl.fromTo("#c2", {{ y: 30, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .45, ease: "back.out(2)" }}, C + cc[2] + 3.6);
tl.fromTo("#c3", {{ y: 30, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .45, ease: "back.out(2)" }}, C + cc[2] + 5.4);
tl.fromTo("#close-tab", {{ scale: .9, opacity: 0 }}, {{ scale: 1, opacity: 1, duration: .5, ease: "back.out(2)" }}, C + cc[3] + 1.0);
tl.to("#n3 .ic", {{ scale: 1.08, duration: .6, yoyo: true, repeat: 5, ease: "sine.inOut" }}, C + cc[2] + 1);
tl.to("#como .node, #como .arrow, #como .chips, #close-tab", {{ opacity: 0, duration: .5 }}, C + {slot['como'] - 0.6:.3f});

// iniciar (terminal)
const I = {S['iniciar']:.3f}, ic = {json.dumps([c['start'] + LEAD for c in T['iniciar']['captions']])};
const typeIt = (sel, n, at, dur) => tl.fromTo(sel, {{ width: 0 }}, {{ width: n + "ch", duration: dur, ease: "steps(" + n + ")" }}, at);
tl.fromTo("#term", {{ y: 50, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .6, ease: "power3.out" }}, I + 0.2);
typeIt("#t0", 26, I + ic[1], .8);
typeIt("#t1", 16, I + ic[1] + 1.0, .9);
tl.fromTo("#batcard", {{ x: 60, opacity: 0, scale: .9 }}, {{ x: 0, opacity: 1, scale: 1, duration: .5, ease: "back.out(2)" }}, I + ic[1] + 1.4);
tl.to("#batcard", {{ scale: 1.06, duration: .18, yoyo: true, repeat: 3 }}, I + ic[1] + 2.4);
tl.to("#batcard", {{ opacity: 0, x: 60, duration: .4 }}, I + ic[2] - 0.2);
typeIt("#t2", 18, I + ic[2], .6);
typeIt("#t3", 46, I + ic[2] + 0.8, 1.6);
typeIt("#t4", 14, I + ic[2] + 3.2, .7);
tl.fromTo("#t4b", {{ opacity: 0 }}, {{ opacity: 1, duration: .3 }}, I + ic[2] + 4.2);
typeIt("#t5", 41, I + ic[3], 1.5);
typeIt("#t6", 33, I + ic[3] + 2.0, .9);
tl.to("#term", {{ y: -40, opacity: 0, scale: .96, duration: .6, ease: "power2.in" }}, I + ic[3] + 3.4);

// browser window
const W0 = I + ic[3] + 3.6;
tl.fromTo("#win", {{ y: 80, opacity: 0, scale: .96 }}, {{ y: 0, opacity: 1, scale: 1, duration: .8, ease: "power3.out" }}, W0);
tl.fromTo("#urltxt", {{ width: 0 }}, {{ width: "14ch", duration: .8, ease: "steps(14)" }}, W0 + 0.6);

// regras / moderador / recap dimming
const dimIn = (a, b) => {{ tl.to("#dim", {{ opacity: 1, duration: .4 }}, a); tl.to("#dim", {{ opacity: 0, duration: .4 }}, b); }};
dimIn({S['regras'] + 0.3:.3f}, {S['regras'] + slot['regras'] - 0.5:.3f});
dimIn({S['moderador'] + 0.3:.3f}, {S['moderador'] + slot['moderador'] - 0.6:.3f});
tl.to("#dim", {{ opacity: 1, duration: .4 }}, {S['final'] + 4.2:.3f});

const R = {S['regras']:.3f}, rc = {json.dumps([c['start'] + LEAD for c in T['regras']['captions']])};
tl.fromTo("#rg-card", {{ y: 40, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .5, ease: "power3.out" }}, R + 0.4);
tl.fromTo("#r1", {{ x: -30, opacity: 0 }}, {{ x: 0, opacity: 1, duration: .4 }}, R + rc[0] + 1.0);
tl.fromTo("#r2", {{ x: -30, opacity: 0 }}, {{ x: 0, opacity: 1, duration: .4 }}, R + rc[1] + 0.4);
tl.fromTo("#r3", {{ x: -30, opacity: 0 }}, {{ x: 0, opacity: 1, duration: .4 }}, R + rc[1] + 2.2);
tl.fromTo("#r4", {{ x: -30, opacity: 0 }}, {{ x: 0, opacity: 1, duration: .4 }}, R + rc[2] + 1.6);
tl.to("#rg-card", {{ opacity: 0, y: -20, duration: .4 }}, R + {slot['regras'] - 0.9:.3f});

const M = {S['moderador']:.3f};
tl.fromTo("#md-card", {{ scale: .9, opacity: 0 }}, {{ scale: 1, opacity: 1, duration: .5, ease: "back.out(1.8)" }}, M + 0.4);
tl.to("#md-card svg", {{ rotation: 8, duration: .12, yoyo: true, repeat: 5 }}, M + 1.0);
tl.to("#md-card", {{ opacity: 0, duration: .4 }}, M + {slot['moderador'] - 1.0:.3f});

const F = {S['final']:.3f}, fc = {json.dumps([c['start'] + LEAD for c in T['final']['captions']])};
tl.fromTo("#rc-card", {{ y: 40, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .5, ease: "power3.out" }}, F + 4.3);
const stepT = [0.2, 1.3, 2.9, 4.4, 5.6, 7.0];
stepT.forEach((d, i) => {{
  tl.fromTo("#st" + i, {{ x: -30, opacity: 0 }}, {{ x: 0, opacity: 1, duration: .35, ease: "power2.out" }}, F + fc[1] + d);
  tl.fromTo("#st" + i + " .tick", {{ scale: 0 }}, {{ scale: 1, duration: .35, ease: "back.out(3)" }}, F + fc[1] + d + 0.5);
}});
tl.fromTo("#outro-fox", {{ scale: .6, opacity: 0 }}, {{ scale: 1, opacity: 1, duration: .8, ease: "back.out(1.7)" }}, F + fc[2] + 0.1);
tl.fromTo("#outro-title", {{ y: 30, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .6, ease: "power3.out" }}, F + fc[2] + 0.5);
tl.fromTo("#outro-sub", {{ y: 20, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .6, ease: "power3.out" }}, F + fc[2] + 0.9);

// camera, chapters, captions
{chr(10).join(js)}

window.__timelines["main"] = tl;
</script>
</body>
</html>
'''
open('/tmp/claude-0/hf/tutorial/index.html', 'w').write(html_out)
json.dump({'start': start, 'slot': slot, 'total': TOTAL}, open('/tmp/claude-0/hf/build/layout.json', 'w'), indent=1)
