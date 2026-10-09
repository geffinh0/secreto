"""Builds the HyperFrames composition for the Atila's Client tutorial.
usage: python3 gen2.py desktop|mobile   -> /tmp/claude-0/hf/<mode>/index.html

Layout is band-based so text never touches anything: a header band (chapter label),
a media band (browser window / phone) and a caption band that nothing else enters."""
import json, html, sys

MODE = sys.argv[1]
MOB = MODE == 'mobile'
B = '/tmp/claude-0/hf/build'
T = json.load(open(f'{B}/timing_{MODE}.json'))
SEG = json.load(open(f'{B}/slots_{MODE}.json'))
LEAD = 0.5
E = html.escape

order = ['intro', 'como', 'acessar', 'conta', 'dash', 'silenciar', 'regras', 'banir',
         'mensagens', 'robo', 'moderador', 'favoritar', 'aovivo', 'painel', 'final']
rec_ids = order[3:]
slot = {'intro': T['intro']['duration'] + 1.6, 'como': T['como']['duration'] + 1.4,
        'acessar': T['acessar']['duration'] + 1.8}
for k in rec_ids:
    slot[k] = SEG[k]
slot['final'] = max(SEG['final'], T['final']['duration'] + 1.6)
start, t = {}, 0.0
for k in order:
    start[k] = round(t, 3); t += slot[k]
TOTAL = round(t, 3)
T_REC = start['conta']
S = start
cap = lambda k, i: start[k] + LEAD + T[k]['captions'][i]['start']   # absolute time of caption i

chapters = {
    'como': ('Visão geral', 'Como funciona'),
    'acessar': ('Passo 1', 'Acessar o site'),
    'conta': ('Passo 2', 'Criar sua conta'),
    'dash': ('Passo 3', 'Conhecer o painel'),
    'silenciar': ('Passo 4', 'Palavras para silenciar'),
    'regras': ('Dica', 'Como o robô compara'),
    'banir': ('Passo 5', 'Palavras para banir'),
    'mensagens': ('Passo 6', 'Mensagens automáticas'),
    'robo': ('Passo 7', 'Conectar o robô'),
    'moderador': ('Importante', 'Robô como moderador'),
    'favoritar': ('Passo 8', 'Escolher a live'),
    'aovivo': ('Ao vivo', 'O robô em ação'),
    'painel': ('Passo 9', 'Estatísticas e conta'),
    'final': ('Resumo', 'Recapitulando'),
}

# ── captions: short chunks, timed by character share inside each spoken line ──
MAXC = 44 if MOB else 74
def chunk(text):
    if len(text) <= MAXC:
        return [text]
    words = text.split(' ')
    best, bscore = None, 1e9
    for i in range(1, len(words)):
        a, b = ' '.join(words[:i]), ' '.join(words[i:])
        score = abs(len(a) - len(b))
        if a[-1] in ',.:;?!': score -= 18          # prefer breaking after punctuation
        if len(a) > MAXC: score += 50
        if score < bscore: best, bscore = (a, b), score
    return chunk(best[0]) + chunk(best[1])

caps, js = [], []
ci = 0
for k in order:
    for c in T[k]['captions']:
        pieces = chunk(c['text'])
        tot = sum(len(p) for p in pieces)
        t0, span = cap(k, 0) - T[k]['captions'][0]['start'] + c['start'], c['end'] - c['start']
        for p in pieces:
            d = span * len(p) / tot
            dur = d + (0.18 if p is pieces[-1] else -0.02)
            caps.append(f'<div id="cap{ci}" class="clip cap" data-start="{t0:.3f}" data-duration="{dur:.3f}" data-track-index="4">'
                        f'<span class="cap-in">{E(p)}</span></div>')
            js.append(f'tl.fromTo("#cap{ci} .cap-in",{{opacity:0,y:10}},{{opacity:1,y:0,duration:.2,ease:"power2.out"}},{t0:.3f});')
            t0 += d; ci += 1

chap = []
for k, (tag, title) in chapters.items():
    chap.append(f'<div id="ch-{k}" class="clip chapter" data-start="{S[k]:.3f}" data-duration="{slot[k]:.3f}" data-track-index="3">'
                f'<div class="ch-in"><span class="ch-tag">{E(tag)}</span><span class="ch-title">{E(title)}</span></div></div>')
    js.append(f'tl.fromTo("#ch-{k} .ch-in",{{y:-16,opacity:0}},{{y:0,opacity:1,duration:.45,ease:"power3.out"}},{S[k] + 0.1:.3f});')

# ── camera moves on the desktop recording (capture px 1536x864) ──
zooms = [] if MOB else [
    ('conta', 2.8, slot['conta'] - 0.4, 768, 430, 1.28),
    ('silenciar', cap('silenciar', 1) - S['silenciar'], slot['silenciar'] - 0.3, 900, 600, 1.18),
    ('banir', cap('banir', 1) - S['banir'], cap('banir', 2) - S['banir'] + 0.2, 900, 620, 1.18),
    ('banir', cap('banir', 2) - S['banir'] + 0.2, slot['banir'] - 0.3, 700, 330, 1.25),
    ('mensagens', cap('mensagens', 1) - S['mensagens'] + 0.6, cap('mensagens', 2) - S['mensagens'], 900, 560, 1.16),
    ('robo', cap('robo', 1) - S['robo'] + 1.2, slot['robo'] - 0.8, 560, 260, 1.3),
    ('favoritar', cap('favoritar', 1) - S['favoritar'], slot['favoritar'] - 0.5, 880, 520, 1.18),
    ('aovivo', 2.2, cap('aovivo', 2) - S['aovivo'] - 0.2, 820, 430, 1.2),
]
for (k, a, b, fx, fy, sc) in zooms:
    a, b = S[k] + a, S[k] + b
    js.append(f'tl.to("#cam",{{x:{fx * (1 - sc):.1f},y:{fy * (1 - sc):.1f},scale:{sc},duration:.9,ease:"power2.inOut"}},{a:.3f});')
    js.append(f'tl.to("#cam",{{x:0,y:0,scale:1,duration:.9,ease:"power2.inOut"}},{b - 0.9:.3f});')

audio = [f'<audio id="vo-{k}" src="assets/vo/{k}.wav" data-start="{S[k] + LEAD:.3f}" data-duration="{T[k]["duration"]:.3f}" data-track-index="5" data-volume="1"></audio>' for k in order]
audio.append(f'<audio id="bgm" src="assets/bgm.mp3" data-start="0" data-duration="{TOTAL:.3f}" data-track-index="6" data-volume="0.12"></audio>')

W, H = (1080, 1920) if MOB else (1920, 1080)
REC_LEN = 192.0 if MOB else 193.6
check = '<svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="3"><path d="M5 12l5 5 9-10"/></svg>'
steps = ['Crie sua conta', 'Cadastre as palavras', 'Monte as mensagens', 'Conecte o robô', 'Coloque ele de moderador', 'Favorite a streamer']

# ── device frame (browser window on desktop, phone on mobile) ──
if MOB:
    device = f'''
  <div id="devwrap" class="layer">
    <div id="phone">
      <div id="pscreen">
        <div id="status"><span>9:41</span><span class="sicons"><i></i><i></i><i></i></span></div>
        <div id="urlbar"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#CBB8A4" stroke-width="2"><rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></svg><span id="urltxt" class="ty">atilaclient.tech</span></div>
        <div id="viewport"><div id="stage"><div id="cam">
          <img id="poster" src="assets/img/first.jpg" alt="" />
          <video id="screen" src="assets/rec/screen.mp4" muted playsinline data-start="{T_REC:.3f}" data-duration="{min(REC_LEN, TOTAL - T_REC):.3f}" data-track-index="0"></video>
        </div></div><div id="blank"></div></div>
      </div>
    </div>
    <div id="dim"></div>
  </div>'''
else:
    device = f'''
  <div id="devwrap" class="layer">
    <div id="win">
      <div id="bar"><span class="dot" style="background:#C2543A"></span><span class="dot" style="background:#D9A441"></span><span class="dot" style="background:#6E9B5E"></span>
        <div id="urlbar"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#CBB8A4" stroke-width="2.4"><rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></svg><span id="urltxt" class="ty">atilaclient.tech</span></div></div>
      <div id="viewport"><div id="stage"><div id="cam">
        <img id="poster" src="assets/img/first.jpg" alt="" />
        <video id="screen" src="assets/rec/screen.mp4" muted playsinline data-start="{T_REC:.3f}" data-duration="{min(REC_LEN, TOTAL - T_REC):.3f}" data-track-index="0"></video>
      </div></div><div id="blank"></div></div>
    </div>
    <div id="dim"></div>
  </div>'''

# ── mode-specific geometry ──
if MOB:
    geo = '''
.chapter { position: absolute; left: 60px; top: 58px; width: 960px; height: 64px; }
.ch-in { display: flex; justify-content: center; align-items: center; gap: 16px; height: 64px; white-space: nowrap; }
.ch-tag { font-size: 24px; padding: 8px 18px; }
.ch-title { font-size: 38px; }
#phone { position: absolute; left: 182px; top: 160px; width: 716px; height: 1509px; border-radius: 86px; background: #0c0907; border: 3px solid #4A3A2C; box-shadow: 0 40px 100px rgba(0,0,0,.6); }
#pscreen { position: absolute; left: 16px; top: 16px; width: 682.5px; height: 1477px; border-radius: 70px; overflow: hidden; background: #1B140F; }
#status { position: absolute; left: 0; top: 0; width: 682.5px; height: 77px; display: flex; align-items: center; justify-content: space-between; padding: 14px 56px 0 64px; font-size: 26px; font-weight: 800; color: var(--cream); }
.sicons { display: flex; gap: 8px; } .sicons i { display: block; width: 22px; height: 14px; border-radius: 3px; background: var(--cream); opacity: .85; }
#urlbar { position: absolute; left: 24px; top: 82px; width: 634px; height: 58px; border-radius: 29px; background: #2a1f18; display: flex; align-items: center; gap: 12px; padding: 0 24px; }
#urltxt { font-family: "JetBrains Mono", monospace; font-size: 25px; color: var(--cream); }
#viewport { position: absolute; left: 0; top: 147px; width: 682.5px; height: 1330px; overflow: hidden; }
#stage { position: absolute; left: 0; top: 0; width: 780px; height: 1520px; transform: scale(0.875); transform-origin: 0 0; }
#cam, #screen, #poster { position: absolute; left: 0; top: 0; width: 780px; height: 1520px; }
#blank { position: absolute; inset: 0; background: #1B140F; }
#dim { position: absolute; left: 198px; top: 323px; width: 682.5px; height: 1330px; border-radius: 0 0 70px 70px; background: rgba(18,12,9,.8); opacity: 0; }
.cap { position: absolute; left: 50px; top: 1712px; width: 980px; height: 170px; display: flex; justify-content: center; align-items: center; }
.cap-in { font-size: 40px; max-width: 980px; padding: 12px 26px; }
/* intro */
#intro-box { position: absolute; left: 60px; top: 330px; width: 960px; height: 1200px; display: flex; flex-direction: column; align-items: center; gap: 36px; }
#intro-fox { width: 640px; height: 426px; object-fit: contain; }
#intro-title { font-size: 120px; }
#intro-sub { font-size: 38px; width: 900px; }
/* como */
#como-box { position: absolute; left: 90px; top: 210px; width: 900px; height: 1440px; display: flex; flex-direction: column; align-items: center; gap: 22px; }
.node { width: 900px; height: 200px; flex-direction: row; justify-content: flex-start; padding: 0 40px; gap: 32px; }
.node .txt { align-items: flex-start; text-align: left; }
.arrow { width: 8px; height: 46px; background: linear-gradient(180deg, var(--rust), var(--orange)); transform-origin: 50% 0; }
.chips { flex-direction: column; align-items: center; gap: 16px; margin-top: 14px; }
#close-tab { width: 900px; margin-top: 12px; }
/* acessar */
#ac-box { position: absolute; left: 90px; top: 330px; width: 900px; height: 1250px; display: flex; flex-direction: column; align-items: center; gap: 44px; }
#ac-url { width: 900px; }
.dev-row { gap: 30px; }
.dev { width: 280px; height: 230px; }
#ac-pwa { width: 900px; }
/* cards */
#rg-card { left: 70px; top: 470px; width: 940px; }
.rule { flex-wrap: nowrap; }
#md-card { left: 90px; top: 560px; width: 900px; }
#rc-card { left: 90px; top: 380px; width: 900px; }
#outro-box { position: absolute; left: 60px; top: 520px; width: 960px; height: 900px; display: flex; flex-direction: column; align-items: center; gap: 30px; }
#outro-fox { width: 420px; height: 420px; }
#outro-title { font-size: 104px; }
#outro-sub { font-size: 40px; }
#site { position: absolute; left: 0; top: 1220px; width: 1080px; display: flex; justify-content: center; }
'''
else:
    geo = '''
.chapter { position: absolute; left: 334px; top: 38px; width: 900px; height: 56px; }
.ch-in { display: flex; align-items: center; gap: 16px; height: 56px; white-space: nowrap; }
.ch-tag { font-size: 20px; padding: 7px 16px; }
#brand { position: absolute; right: 334px; top: 38px; height: 56px; display: flex; align-items: center; gap: 12px; font-family: "JetBrains Mono", monospace; font-size: 22px; color: var(--text2); white-space: nowrap; }
#brand img { width: 40px; height: 40px; object-fit: contain; }
.ch-title { font-size: 32px; }
#win { position: absolute; left: 334px; top: 122px; width: 1252px; height: 744px; border-radius: 16px; overflow: hidden; background: #120d0a; border: 1px solid #4A3A2C; box-shadow: 0 30px 80px rgba(0,0,0,.55); }
#bar { position: absolute; left: 0; top: 0; width: 1252px; height: 40px; background: #2a1f18; display: flex; align-items: center; padding: 0 16px; gap: 8px; border-bottom: 1px solid #3A2D22; }
.dot { width: 12px; height: 12px; border-radius: 50%; display: block; }
#urlbar { margin-left: 18px; height: 26px; width: 520px; border-radius: 13px; background: #1B140F; display: flex; align-items: center; gap: 8px; padding: 0 12px; }
#urltxt { font-family: "JetBrains Mono", monospace; font-size: 15px; color: var(--cream); }
#viewport { position: absolute; left: 0; top: 40px; width: 1252px; height: 704px; overflow: hidden; }
#stage { position: absolute; left: 0; top: 0; width: 1536px; height: 864px; transform: scale(0.81515); transform-origin: 0 0; }
#cam, #screen, #poster { position: absolute; left: 0; top: 0; width: 1536px; height: 864px; }
#cam { transform-origin: 0 0; }
#blank { position: absolute; inset: 0; background: #1B140F; }
#dim { position: absolute; left: 335px; top: 163px; width: 1250px; height: 702px; border-radius: 0 0 15px 15px; background: rgba(18,12,9,.8); opacity: 0; }
.cap { position: absolute; left: 160px; top: 902px; width: 1600px; height: 140px; display: flex; justify-content: center; align-items: center; }
.cap-in { font-size: 36px; max-width: 1560px; padding: 12px 30px; }
#intro-box { position: absolute; left: 160px; top: 130px; width: 1600px; height: 760px; display: flex; flex-direction: column; align-items: center; gap: 26px; }
#intro-fox { width: 520px; height: 346px; object-fit: contain; }
#intro-title { font-size: 116px; }
#intro-sub { font-size: 40px; }
#como-box { position: absolute; left: 140px; top: 170px; width: 1640px; height: 700px; display: flex; flex-direction: column; align-items: center; gap: 44px; }
.node-row { display: flex; align-items: center; gap: 36px; }
.node { width: 440px; height: 290px; flex-direction: column; justify-content: center; gap: 14px; }
.node .txt { align-items: center; text-align: center; }
.arrow { width: 90px; height: 8px; background: linear-gradient(90deg, var(--rust), var(--orange)); transform-origin: 0 50%; }
.chips { flex-direction: row; gap: 22px; }
#close-tab { width: 820px; }
#ac-box { position: absolute; left: 260px; top: 170px; width: 1400px; height: 700px; display: flex; flex-direction: column; align-items: center; gap: 48px; }
#ac-url { width: 1000px; }
.dev-row { gap: 40px; }
.dev { width: 300px; height: 230px; }
#ac-pwa { width: 1000px; }
#rg-card { left: 420px; top: 190px; width: 1080px; }
#md-card { left: 460px; top: 260px; width: 1000px; }
#rc-card { left: 460px; top: 150px; width: 1000px; }
#outro-box { position: absolute; left: 160px; top: 160px; width: 1600px; height: 720px; display: flex; flex-direction: column; align-items: center; gap: 26px; }
#outro-fox { width: 360px; height: 360px; }
#outro-title { font-size: 96px; }
#outro-sub { font-size: 38px; }
#site { position: absolute; left: 0; top: 0; width: 0; height: 0; }
'''

if MOB:
    como_nodes = '''
      <div id="n1" class="node"><div class="ic"><svg width="60" height="60" viewBox="0 0 24 24" fill="none" stroke="#E07B39" stroke-width="2"><rect x="6" y="2" width="12" height="20" rx="2"/><path d="M11 18h2"/></svg></div><div class="txt"><h3>Site</h3><p>Você configura tudo pelo navegador</p></div></div>
      <div id="a1" class="arrow"></div>
      <div id="n2" class="node"><div class="ic"><svg width="60" height="60" viewBox="0 0 24 24" fill="none" stroke="#D9A441" stroke-width="2"><rect x="3" y="3" width="18" height="7" rx="2"/><rect x="3" y="14" width="18" height="7" rx="2"/><path d="M7 6.5h.01M7 17.5h.01"/></svg></div><div class="txt"><h3>Servidor</h3><p>Guarda as regras e controla o robô</p></div></div>
      <div id="a2" class="arrow"></div>
      <div id="n3" class="node"><div class="ic"><img src="assets/img/fox_avatar.png" alt="" /></div><div class="txt"><h3>Robô na live</h3><p>Fica de olho no chat do SuperLive</p></div></div>'''
else:
    como_nodes = '''
      <div class="node-row">
      <div id="n1" class="node"><div class="ic"><svg width="60" height="60" viewBox="0 0 24 24" fill="none" stroke="#E07B39" stroke-width="2"><rect x="2" y="4" width="20" height="15" rx="2"/><path d="M2 8h20"/></svg></div><div class="txt"><h3>Site</h3><p>Você configura tudo pelo navegador</p></div></div>
      <div id="a1" class="arrow"></div>
      <div id="n2" class="node"><div class="ic"><svg width="60" height="60" viewBox="0 0 24 24" fill="none" stroke="#D9A441" stroke-width="2"><rect x="3" y="3" width="18" height="7" rx="2"/><rect x="3" y="14" width="18" height="7" rx="2"/><path d="M7 6.5h.01M7 17.5h.01"/></svg></div><div class="txt"><h3>Servidor</h3><p>Guarda as regras e controla o robô</p></div></div>
      <div id="a2" class="arrow"></div>
      <div id="n3" class="node"><div class="ic"><img src="assets/img/fox_avatar.png" alt="" /></div><div class="txt"><h3>Robô na live</h3><p>Fica de olho no chat do SuperLive</p></div></div>
      </div>'''

ARROW_PROP = 'scaleY' if MOB else 'scaleX'
cc = lambda k: json.dumps([round(start[k] + LEAD + c['start'], 3) for c in T[k]['captions']])
W0 = S['acessar'] + slot['acessar'] - 0.9   # device window enters right before "Criar conta"

doc = f'''<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width={W}, height={H}" />
<title>Atila's Client — Tutorial ({'celular' if MOB else 'computador'})</title>
<script src="assets/gsap.min.js"></script>
<style>
@font-face {{ font-family: "Nunito"; src: url("assets/fonts/nunito-latin-400-normal.woff2") format("woff2"); font-weight: 400; }}
@font-face {{ font-family: "Nunito"; src: url("assets/fonts/nunito-latin-600-normal.woff2") format("woff2"); font-weight: 600; }}
@font-face {{ font-family: "Nunito"; src: url("assets/fonts/nunito-latin-700-normal.woff2") format("woff2"); font-weight: 700; }}
@font-face {{ font-family: "Nunito"; src: url("assets/fonts/nunito-latin-800-normal.woff2") format("woff2"); font-weight: 800; }}
@font-face {{ font-family: "Nunito"; src: url("assets/fonts/nunito-latin-900-normal.woff2") format("woff2"); font-weight: 900; }}
@font-face {{ font-family: "JetBrains Mono"; src: url("assets/fonts/jetbrains-mono-latin-400-normal.woff2") format("woff2"); font-weight: 400; }}
@font-face {{ font-family: "JetBrains Mono"; src: url("assets/fonts/jetbrains-mono-latin-600-normal.woff2") format("woff2"); font-weight: 600; }}
:root {{ --bg: #1B140F; --card: #241B15; --surface: #2C2119; --orange: #E07B39; --rust: #A24A32; --gold: #D9A441; --cream: #F7EEE3; --text2: #CBB8A4; --muted: #8C7968; --border: #3A2D22; --ok: #6E9B5E; }}
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
html, body {{ width: {W}px; height: {H}px; overflow: hidden; background: var(--bg); }}
#root {{ position: relative; width: 100%; height: 100%; overflow: hidden; font-family: "Nunito", sans-serif; color: var(--cream); background: var(--bg); }}
.layer {{ position: absolute; inset: 0; }}
#bg {{ background: radial-gradient(1100px 800px at 10% 0%, #3a2416 0%, transparent 60%), radial-gradient(900px 700px at 100% 100%, #2e1a12 0%, transparent 60%), var(--bg); }}
.glow {{ position: absolute; border-radius: 50%; filter: blur(90px); }}
#glow1 {{ width: 620px; height: 620px; left: -160px; top: -200px; background: #E07B39; opacity: .14; }}
#glow2 {{ width: 560px; height: 560px; right: -160px; bottom: -200px; background: #A24A32; opacity: .18; }}
#progress {{ position: absolute; left: 0; top: 0; height: 6px; width: {W}px; background: linear-gradient(90deg, var(--rust), var(--orange), var(--gold)); transform-origin: 0 50%; z-index: 60; }}
.ch-tag {{ background: var(--orange); color: #1B140F; font-weight: 900; border-radius: 999px; text-transform: uppercase; letter-spacing: .05em; }}
.ch-title {{ font-weight: 800; color: var(--cream); }}
.ty {{ display: inline-block; overflow: hidden; white-space: nowrap; vertical-align: middle; width: 0; }}
.cap {{ z-index: 70; }}
.cap-in {{ display: block; text-align: center; line-height: 1.3; font-weight: 800; color: #fff; background: rgba(15,10,7,.9); border: 1px solid rgba(224,123,57,.4); border-radius: 16px; }}
#intro-title, #outro-title {{ font-weight: 900; letter-spacing: -2px; text-align: center; white-space: nowrap; }}
#intro-title span, #outro-title span {{ color: var(--orange); }}
#intro-sub, #outro-sub {{ font-weight: 700; color: var(--text2); text-align: center; line-height: 1.35; }}
.pill {{ display: inline-flex; align-items: center; justify-content: center; white-space: nowrap; border-radius: 999px; border: 2px solid var(--orange); color: var(--orange); font-weight: 900; letter-spacing: .06em; font-size: 26px; padding: 12px 30px; }}
.node {{ display: flex; align-items: center; border-radius: 24px; background: var(--card); border: 2px solid var(--border); }}
.node .ic {{ width: 104px; height: 104px; flex: none; border-radius: 26px; background: var(--surface); display: flex; align-items: center; justify-content: center; }}
.node .ic img {{ width: 86px; height: 86px; object-fit: contain; }}
.node .txt {{ display: flex; flex-direction: column; gap: 8px; }}
.node h3 {{ font-size: 40px; font-weight: 900; }}
.node p {{ font-size: 26px; color: var(--text2); line-height: 1.3; }}
.arrow {{ display: block; flex: none; border-radius: 4px; }}
.chips {{ display: flex; }}
.chip {{ display: block; white-space: nowrap; font-size: 30px; font-weight: 800; padding: 16px 30px; border-radius: 16px; background: var(--surface); border: 2px solid var(--border); }}
.chip b {{ color: var(--orange); }}
#close-tab {{ display: flex; align-items: center; justify-content: center; text-align: center; padding: 20px 30px; border-radius: 18px; background: rgba(110,155,94,.16); border: 2px solid var(--ok); color: #d5ebcb; font-size: 30px; font-weight: 800; line-height: 1.3; }}
#ac-url {{ height: 110px; border-radius: 55px; background: #2a1f18; border: 2px solid #4A3A2C; display: flex; align-items: center; gap: 22px; padding: 0 44px; box-shadow: 0 20px 60px rgba(0,0,0,.45); }}
#ac-url .ty {{ font-family: "JetBrains Mono", monospace; font-size: 48px; font-weight: 600; color: var(--cream); }}
.dev-row {{ display: flex; }}
.dev {{ border-radius: 24px; background: var(--card); border: 2px solid var(--border); display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 18px; font-size: 32px; font-weight: 900; }}
#ac-pwa {{ display: flex; align-items: center; justify-content: center; text-align: center; padding: 22px 30px; border-radius: 18px; background: rgba(217,164,65,.12); border: 2px solid var(--gold); color: #f1dcae; font-size: 30px; font-weight: 800; line-height: 1.3; }}
.card {{ position: absolute; border-radius: 28px; background: var(--card); border: 2px solid var(--border); box-shadow: 0 30px 80px rgba(0,0,0,.6); padding: 44px 48px; display: flex; flex-direction: column; gap: 16px; }}
.card h2 {{ font-size: 44px; font-weight: 900; line-height: 1.2; margin-bottom: 8px; }}
.rule {{ display: flex; align-items: center; gap: 18px; min-height: 76px; padding: 14px 22px; border-radius: 16px; background: var(--surface); font-size: 28px; font-weight: 700; }}
.rule .ex {{ flex: 1; white-space: nowrap; }}
.kw {{ flex: none; font-family: "JetBrains Mono", monospace; color: var(--gold); background: #1B140F; padding: 4px 14px; border-radius: 10px; font-size: 26px; white-space: nowrap; }}
.res {{ flex: none; white-space: nowrap; font-weight: 900; font-size: 24px; padding: 6px 14px; border-radius: 10px; }}
.yes {{ color: #d5ebcb; background: rgba(110,155,94,.28); }}
.no {{ color: #f3c9bd; background: rgba(194,84,58,.28); }}
#md-card {{ align-items: center; text-align: center; border-color: var(--gold); gap: 24px; padding: 54px 60px; }}
#md-card h2 {{ color: var(--gold); }}
#md-card p {{ font-size: 32px; font-weight: 700; line-height: 1.4; }}
.step {{ display: flex; align-items: center; gap: 22px; min-height: 84px; padding: 0 24px; border-radius: 18px; background: var(--surface); font-size: 32px; font-weight: 800; }}
.num {{ width: 50px; height: 50px; flex: none; border-radius: 50%; background: var(--orange); color: #1B140F; font-weight: 900; font-size: 26px; display: flex; align-items: center; justify-content: center; }}
.tick {{ margin-left: auto; width: 46px; height: 46px; flex: none; border-radius: 50%; background: var(--ok); display: flex; align-items: center; justify-content: center; }}
#outro {{ position: absolute; inset: 0; background: var(--bg); z-index: 50; }}
#outro-fox {{ object-fit: contain; }}
{geo}
</style>
</head>
<body>
<div id="root" data-composition-id="main" data-start="0" data-duration="{TOTAL:.3f}" data-width="{W}" data-height="{H}">
  <div id="bg" class="layer"><div id="glow1" class="glow"></div><div id="glow2" class="glow"></div></div>
  {'' if MOB else '<div id="brand"><img src="assets/img/fox_avatar.png" alt="" /><span>atilaclient.tech</span></div>'}

  <div id="intro" class="clip layer" data-start="0" data-duration="{slot['intro']:.3f}" data-track-index="1">
    <div id="intro-box">
      <img id="intro-fox" src="assets/img/fox_hero.webp" alt="" />
      <div id="intro-title">Atila's <span>Client</span></div>
      <div id="intro-sub">O robô que modera as suas lives no SuperLive</div>
      <div id="intro-pill" class="pill">TUTORIAL COMPLETO · DO ZERO</div>
    </div>
  </div>

  <div id="como" class="clip layer" data-start="{S['como']:.3f}" data-duration="{slot['como']:.3f}" data-track-index="1">
    <div id="como-box">
      {como_nodes}
      <div class="chips">
        <span id="c1" class="chip"><b>Silencia</b> quem xinga</span>
        <span id="c2" class="chip"><b>Expulsa</b> golpistas</span>
        <span id="c3" class="chip"><b>Manda</b> mensagens por você</span>
      </div>
      <div id="close-tab">Pode fechar o navegador: a moderação continua</div>
    </div>
  </div>

  <div id="acessar" class="clip layer" data-start="{S['acessar']:.3f}" data-duration="{slot['acessar']:.3f}" data-track-index="1">
    <div id="ac-box">
      <div id="ac-url"><svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="#E07B39" stroke-width="2.2"><rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></svg><span id="ac-ty" class="ty">atilaclient.tech</span></div>
      <div class="dev-row">
        <div id="d1" class="dev"><svg width="90" height="90" viewBox="0 0 24 24" fill="none" stroke="#E07B39" stroke-width="1.8"><rect x="3" y="4" width="18" height="12" rx="2"/><path d="M1 20h22"/></svg>Computador</div>
        <div id="d2" class="dev"><svg width="90" height="90" viewBox="0 0 24 24" fill="none" stroke="#E07B39" stroke-width="1.8"><rect x="6" y="2" width="12" height="20" rx="2"/><path d="M11 18h2"/></svg>Celular</div>
      </div>
      <div id="ac-pwa">Dá pra instalar como app em Configurações</div>
    </div>
  </div>
{device}

  <div id="regras" class="clip layer" data-start="{S['regras'] + 0.3:.3f}" data-duration="{slot['regras'] - 0.5:.3f}" data-track-index="2">
    <div id="rg-card" class="card">
      <h2>O robô compara a palavra inteira</h2>
      <div id="r1" class="rule"><span class="kw">passa zap</span><span class="ex">“me PASSA ZÁP”</span><span class="res yes">pega</span></div>
      <div id="r2" class="rule"><span class="kw">zap</span><span class="ex">“zapzap”</span><span class="res no">não pega</span></div>
      <div id="r3" class="rule"><span class="kw">divulg*</span><span class="ex">“divulguem”</span><span class="res yes">pega</span></div>
      <div id="r4" class="rule"><span class="kw">divulg*</span><span class="ex">“divulgação”</span><span class="res yes">pega</span></div>
    </div>
  </div>

  <div id="moderador" class="clip layer" data-start="{S['moderador'] + 0.3:.3f}" data-duration="{slot['moderador'] - 0.6:.3f}" data-track-index="2">
    <div id="md-card" class="card">
      <svg width="100" height="100" viewBox="0 0 24 24" fill="none" stroke="#D9A441" stroke-width="2"><path d="M12 2l8 4v6c0 5-3.5 8.5-8 10-4.5-1.5-8-5-8-10V6z"/><path d="M12 8v5M12 16h.01"/></svg>
      <h2>Coloque o robô como moderador</h2>
      <p>Sem isso, o SuperLive não deixa o robô silenciar nem banir ninguém.</p>
    </div>
  </div>

  <div id="recap" class="clip layer" data-start="{S['final'] + 4.0:.3f}" data-duration="{cap('final', 2) - S['final'] - 4.0:.3f}" data-track-index="2">
    <div id="rc-card" class="card">
      <h2>Checklist</h2>
      {''.join(f'<div id="st{i}" class="step"><span class="num">{i + 1}</span><span>{E(s)}</span><span class="tick">{check}</span></div>' for i, s in enumerate(steps))}
    </div>
  </div>

  <div id="outro" class="clip" data-start="{cap('final', 2):.3f}" data-duration="{TOTAL - cap('final', 2):.3f}" data-track-index="2">
    <div id="outro-box">
      <img id="outro-fox" src="assets/img/fox_avatar.png" alt="" />
      <div id="outro-title">Atila's <span>Client</span></div>
      <div id="outro-sub">Suas lives no piloto automático</div>
      <div id="outro-url" class="pill">atilaclient.tech</div>
    </div>
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
tl.fromTo("#glow1", {{ x: 0, y: 0 }}, {{ x: 240, y: 160, duration: TOTAL, ease: "sine.inOut" }}, 0);
tl.fromTo("#glow2", {{ x: 0, y: 0 }}, {{ x: -220, y: -140, duration: TOTAL, ease: "sine.inOut" }}, 0);
const typeIt = (sel, n, at, dur) => tl.fromTo(sel, {{ width: 0 }}, {{ width: n + "ch", duration: dur, ease: "steps(" + n + ")" }}, at);

// intro
tl.fromTo("#intro-fox", {{ y: 50, opacity: 0, scale: .9 }}, {{ y: 0, opacity: 1, scale: 1, duration: 1, ease: "back.out(1.6)" }}, 0.2);
tl.fromTo("#intro-title", {{ y: 30, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .7, ease: "power3.out" }}, 0.7);
tl.fromTo("#intro-sub", {{ y: 24, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .6, ease: "power3.out" }}, 1.1);
tl.fromTo("#intro-pill", {{ scale: .85, opacity: 0 }}, {{ scale: 1, opacity: 1, duration: .5, ease: "back.out(2)" }}, 1.6);
tl.to("#intro-box", {{ opacity: 0, y: -24, duration: .5, ease: "power2.in" }}, {slot['intro'] - 0.6:.3f});

// como funciona
const cc = {cc('como')};
tl.fromTo("#n1", {{ y: 30, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .5, ease: "power3.out" }}, cc[1]);
tl.fromTo("#a1", {{ {ARROW_PROP}: 0 }}, {{ {ARROW_PROP}: 1, duration: .4 }}, cc[1] + 1.4);
tl.fromTo("#n2", {{ y: 30, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .5, ease: "power3.out" }}, cc[1] + 1.7);
tl.fromTo("#a2", {{ {ARROW_PROP}: 0 }}, {{ {ARROW_PROP}: 1, duration: .4 }}, cc[1] + 3.2);
tl.fromTo("#n3", {{ y: 30, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .5, ease: "power3.out" }}, cc[2]);
tl.fromTo("#c1", {{ y: 24, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .4, ease: "back.out(2)" }}, cc[2] + 3.4);
tl.fromTo("#c2", {{ y: 24, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .4, ease: "back.out(2)" }}, cc[2] + 4.2);
tl.fromTo("#c3", {{ y: 24, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .4, ease: "back.out(2)" }}, cc[2] + 6.4);
tl.fromTo("#close-tab", {{ scale: .92, opacity: 0 }}, {{ scale: 1, opacity: 1, duration: .45, ease: "back.out(2)" }}, cc[3] + 1.2);
tl.to("#como-box", {{ opacity: 0, duration: .45 }}, {S['como'] + slot['como'] - 0.55:.3f});

// acessar
const ac = {cc('acessar')};
tl.fromTo("#ac-url", {{ y: 30, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .5, ease: "power3.out" }}, {S['acessar'] + 0.3:.3f});
typeIt("#ac-ty", 16, ac[1] + 1.4, 1.1);
tl.fromTo("#d1", {{ y: 30, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .45, ease: "back.out(2)" }}, ac[2] + 0.6);
tl.fromTo("#d2", {{ y: 30, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .45, ease: "back.out(2)" }}, ac[2] + 1.2);
tl.fromTo("#ac-pwa", {{ y: 20, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .45 }}, ac[2] + 3.0);
tl.to("#ac-box", {{ opacity: 0, scale: .96, duration: .45, ease: "power2.in" }}, {W0 - 0.5:.3f});

// device (browser / phone)
const DEV = "{'#phone' if MOB else '#win'}";
tl.fromTo(DEV, {{ y: 70, opacity: 0, scale: .96 }}, {{ y: 0, opacity: 1, scale: 1, duration: .7, ease: "power3.out" }}, {W0:.3f});
typeIt("#urltxt", 16, {W0 + 0.3:.3f}, .5);
tl.to("#blank", {{ opacity: 0, duration: .35 }}, {W0 + 0.8:.3f});
tl.set("#poster", {{ opacity: 0 }}, {T_REC + 0.2:.3f});

// overlays
const dim = (a, b) => {{ tl.to("#dim", {{ opacity: 1, duration: .35 }}, a); if (b) tl.to("#dim", {{ opacity: 0, duration: .35 }}, b); }};
dim({S['regras'] + 0.3:.3f}, {S['regras'] + slot['regras'] - 0.5:.3f});
dim({S['moderador'] + 0.3:.3f}, {S['moderador'] + slot['moderador'] - 0.6:.3f});
dim({S['final'] + 4.0:.3f}, 0);
const rc = {cc('regras')};
tl.fromTo("#rg-card", {{ y: 30, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .45, ease: "power3.out" }}, {S['regras'] + 0.4:.3f});
tl.fromTo("#r1", {{ x: -24, opacity: 0 }}, {{ x: 0, opacity: 1, duration: .35 }}, rc[1] + 0.8);
tl.fromTo("#r2", {{ x: -24, opacity: 0 }}, {{ x: 0, opacity: 1, duration: .35 }}, rc[1] + 2.6);
tl.fromTo("#r3", {{ x: -24, opacity: 0 }}, {{ x: 0, opacity: 1, duration: .35 }}, rc[2] + 4.4);
tl.fromTo("#r4", {{ x: -24, opacity: 0 }}, {{ x: 0, opacity: 1, duration: .35 }}, rc[2] + 5.4);
tl.to("#rg-card", {{ opacity: 0, duration: .35 }}, {S['regras'] + slot['regras'] - 0.85:.3f});
tl.fromTo("#md-card", {{ scale: .92, opacity: 0 }}, {{ scale: 1, opacity: 1, duration: .45, ease: "back.out(1.8)" }}, {S['moderador'] + 0.4:.3f});
tl.to("#md-card svg", {{ rotation: 8, duration: .12, yoyo: true, repeat: 5 }}, {S['moderador'] + 1.0:.3f});
tl.to("#md-card", {{ opacity: 0, duration: .35 }}, {S['moderador'] + slot['moderador'] - 0.95:.3f});
const fc = {cc('final')};
tl.fromTo("#rc-card", {{ y: 30, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .45, ease: "power3.out" }}, {S['final'] + 4.1:.3f});
[0.9, 2.1, 3.5, 4.9, 6.1, 7.7].forEach((d, i) => {{
  tl.fromTo("#st" + i, {{ x: -24, opacity: 0 }}, {{ x: 0, opacity: 1, duration: .3, ease: "power2.out" }}, fc[1] + d);
  tl.fromTo("#st" + i + " .tick", {{ scale: 0 }}, {{ scale: 1, duration: .3, ease: "back.out(3)" }}, fc[1] + d + 0.4);
}});
tl.fromTo("#outro-fox", {{ scale: .6, opacity: 0 }}, {{ scale: 1, opacity: 1, duration: .7, ease: "back.out(1.7)" }}, fc[2] + 0.1);
tl.fromTo("#outro-title", {{ y: 24, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .5, ease: "power3.out" }}, fc[2] + 0.5);
tl.fromTo("#outro-sub", {{ y: 18, opacity: 0 }}, {{ y: 0, opacity: 1, duration: .5, ease: "power3.out" }}, fc[2] + 0.8);
tl.fromTo("#outro-url", {{ scale: .85, opacity: 0 }}, {{ scale: 1, opacity: 1, duration: .45, ease: "back.out(2)" }}, fc[2] + 1.2);

{chr(10).join(js)}

window.__timelines["main"] = tl;
</script>
</body>
</html>
'''
open(f'/tmp/claude-0/hf/{MODE}/index.html', 'w').write(doc)
print(MODE, 'total', TOTAL, 'captions', ci)
