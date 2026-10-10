"""Cinematic vertical (9:16) tutorial for Atila's Client -> /tmp/claude-0/hf/eleven/index.html

Look: dark minimal stage, warm amber volumetric light, depth-of-field bokeh, a 3D phone that
floats with parallax, a camera that glides through the UI, glowing status chips, push-through
transitions. Layout bands keep text apart: chapter (top), phone (middle), status rail, captions."""
import json, html, random

B = '/tmp/claude-0/hf/build'
T = json.load(open(f'{B}/timing_eleven.json'))
SEG = json.load(open(f'{B}/slots_eleven.json'))
LEAD = 0.55
E = html.escape
W, H = 1080, 1920
rnd = random.Random(11)

order = ['intro', 'como', 'acessar', 'conta', 'dash', 'silenciar', 'regras', 'banir',
         'mensagens', 'robo', 'moderador', 'favoritar', 'aovivo', 'painel', 'final']
rec = order[3:]
slot = {'intro': T['intro']['duration'] + 2.0, 'como': T['como']['duration'] + 1.4,
        'acessar': T['acessar']['duration'] + 2.0}
for k in rec:
    slot[k] = SEG[k]
slot['final'] = max(SEG['final'], T['final']['duration'] + 2.2)
S, t = {}, 0.0
for k in order:
    S[k] = round(t, 3); t += slot[k]
TOTAL = round(t, 3)
T_REC = S['conta']
cap = lambda k, i: S[k] + LEAD + T[k]['captions'][i]['start']
cc = lambda k: json.dumps([round(cap(k, i), 3) for i in range(len(T[k]['captions']))])
js = []

# ── captions (short chunks inside the caption band) ──
MAXC = 40
def chunk(text):
    if len(text) <= MAXC:
        return [text]
    words = text.split(' ')
    best, bs = None, 1e9
    for i in range(1, len(words)):
        a, b = ' '.join(words[:i]), ' '.join(words[i:])
        sc = abs(len(a) - len(b)) - (18 if a[-1] in ',.:;?!' else 0) + (50 if len(a) > MAXC else 0)
        if sc < bs: best, bs = (a, b), sc
    return chunk(best[0]) + chunk(best[1])
caps, ci = [], 0
for k in order:
    for c in T[k]['captions']:
        pcs = chunk(c['text']); tot = sum(len(p) for p in pcs)
        t0, span = S[k] + LEAD + c['start'], c['end'] - c['start']
        for p in pcs:
            d = span * len(p) / tot
            caps.append(f'<div id="cap{ci}" class="clip cap" data-start="{t0:.3f}" data-duration="{d + (0.2 if p is pcs[-1] else -0.02):.3f}" data-track-index="4"><span class="cap-in">{E(p)}</span></div>')
            js.append(f'tl.fromTo("#cap{ci} .cap-in",{{opacity:0,y:12,filter:"blur(6px)"}},{{opacity:1,y:0,filter:"blur(0px)",duration:.28,ease:"power2.out"}},{t0:.3f});')
            t0 += d; ci += 1

# ── chapters ──
chapters = {
    'como': ('Visão geral', 'Como funciona'), 'acessar': ('Passo 1', 'Acesse o site'),
    'conta': ('Passo 2', 'Crie sua conta'), 'dash': ('Passo 3', 'O painel'),
    'silenciar': ('Passo 4', 'Silenciar palavras'), 'regras': ('Dica', 'Palavra inteira'),
    'banir': ('Passo 5', 'Banir palavras'), 'mensagens': ('Passo 6', 'Mensagens automáticas'),
    'robo': ('Passo 7', 'Conecte o robô'), 'moderador': ('Importante', 'Robô moderador'),
    'favoritar': ('Passo 8', 'Escolha a live'), 'aovivo': ('Ao vivo', 'Robô em ação'),
    'painel': ('Passo 9', 'Estatísticas'), 'final': ('Resumo', 'Checklist'),
}
chap = []
for k, (tag, title) in chapters.items():
    chap.append(f'<div id="ch-{k}" class="clip chapter" data-start="{S[k]:.3f}" data-duration="{slot[k]:.3f}" data-track-index="3"><div class="ch-in"><span class="ch-dot"></span><span class="ch-tag">{E(tag)}</span><span class="ch-title">{E(title)}</span></div></div>')
    js.append(f'tl.fromTo("#ch-{k} .ch-in",{{y:-20,opacity:0,filter:"blur(8px)"}},{{y:0,opacity:1,filter:"blur(0px)",duration:.6,ease:"power3.out"}},{S[k] + 0.15:.3f});')
    js.append(f'tl.to("#ch-{k} .ch-in",{{opacity:0,y:-10,duration:.3}},{S[k] + slot[k] - 0.35:.3f});')

# ── status rail chips (between phone and captions) ──
# (scene, offset-from-caption, caption index, kind, text)
chips = [
    ('conta', 2, 3.2, 'ok', 'Conta criada'),
    ('dash', 1, 2.0, 'off', 'Robô desconectado'),
    ('dash', 1, 5.0, 'amb', '0 regras ativas'),
    ('silenciar', 1, 2.6, 'amb', 'zap  →  silenciar'),
    ('silenciar', 3, 2.4, 'amb', 'passa zap  →  silenciar'),
    ('banir', 1, 1.6, 'red', 'golpe  →  banir'),
    ('banir', 1, 3.6, 'red', 'divulg*  →  banir'),
    ('mensagens', 1, 3.0, 'amb', '2 mensagens na fila'),
    ('mensagens', 2, 4.0, 'ok', 'Envio automático: a cada 30s'),
    ('robo', 3, 0.3, 'ok', 'Robô conectado'),
    ('favoritar', 2, 0.6, 'live', 'Streamer ao vivo agora'),
    ('favoritar', 3, 2.6, 'ok', 'Moderando automaticamente'),
    ('painel', 0, 1.6, 'amb', '3 ações de moderação'),
    ('painel', 1, 2.6, 'ok', '100% de sucesso'),
]
chip_html, sfx = [], []
by_scene = {}
for c in chips:
    by_scene.setdefault(c[0], []).append(c)
for k, items in by_scene.items():
    for j, (_, ci_, off, kind, text) in enumerate(items):
        a = cap(k, ci_) + off
        nxt = cap(items[j + 1][0], items[j + 1][1]) + items[j + 1][2] if j + 1 < len(items) else S[k] + slot[k] - 0.2
        b = min(nxt, S[k] + slot[k] - 0.2)
        cid = f'chip-{k}-{j}'
        chip_html.append(f'<div id="{cid}" class="clip rail" data-start="{a:.3f}" data-duration="{b - a:.3f}" data-track-index="2"><div class="chip-in {kind}"><span class="sd"></span><span>{E(text)}</span></div></div>')
        js.append(f'tl.fromTo("#{cid} .chip-in",{{y:26,opacity:0,scale:.9,rotationX:-50}},{{y:0,opacity:1,scale:1,rotationX:0,duration:.55,ease:"back.out(1.6)"}},{a:.3f});')
        js.append(f'tl.to("#{cid} .chip-in",{{y:-14,opacity:0,duration:.3,ease:"power2.in"}},{b - 0.32:.3f});')
        sfx.append(a + 0.05)

# ── live moderation side cards (3D, overlapping the phone edge) ──
av = [('left', 'mute', 'Carlos_88', 'silenciado', '“me passa o zap?”', cap('aovivo', 1) + 0.4),
      ('right', 'ban', 'Promo_Fake', 'banido', '“... nao e golpe”', cap('aovivo', 1) + 2.0),
      ('left', 'ban', 'Lucas', 'banido', '“divulguem meu canal”', cap('aovivo', 1) + 3.6)]
side = []
for i, (sd, kind, name, verb, quote, a) in enumerate(av):
    b = S['aovivo'] + slot['aovivo'] - 0.3
    top = 520 + i * 250
    side.append(f'<div id="ev{i}" class="clip ev {sd}" data-start="{a:.3f}" data-duration="{b - a:.3f}" data-track-index="2" style="top:{top}px"><div class="ev-in {kind}"><div class="ev-h"><span class="sd"></span><b>{E(name)}</b><span class="ev-v">{E(verb)}</span></div><div class="ev-q">{E(quote)}</div></div></div>')
    rx = 30 if sd == 'left' else -30
    js.append(f'tl.fromTo("#ev{i} .ev-in",{{x:{-120 if sd == "left" else 120},opacity:0,rotationY:{rx},z:-200}},{{x:0,opacity:1,rotationY:{rx / 3:.0f},z:80,duration:.7,ease:"power3.out"}},{a:.3f});')
    js.append(f'tl.to("#ev{i} .ev-in",{{y:-12,duration:2.2,ease:"sine.inOut",yoyo:true,repeat:1}},{a + 0.7:.3f});')
    js.append(f'tl.to("#ev{i} .ev-in",{{opacity:0,x:{-60 if sd == "left" else 60},duration:.35}},{b - 0.4:.3f});')
    sfx.append(a + 0.05)

# ── camera that glides through the UI inside the phone (capture px 780x1520) ──
focus = {'conta': (1.12, 0.45), 'dash': (1.1, 0.25), 'silenciar': (1.14, 0.75), 'regras': (1.0, 0.5),
         'banir': (1.12, 0.6), 'mensagens': (1.12, 0.55), 'robo': (1.12, 0.35), 'moderador': (1.0, 0.5),
         'favoritar': (1.12, 0.5), 'aovivo': (1.1, 0.3), 'painel': (1.1, 0.3), 'final': (1.08, 0.6)}
for k in rec:
    s, f = focus[k]
    x = -(s - 1) * 780 * 0.5
    y = -(s - 1) * 1520 * f
    js.append(f'tl.to("#cam",{{scale:{s},x:{x:.1f},y:{y:.1f},duration:1.6,ease:"power2.inOut"}},{S[k] + 0.2:.3f});')

js.append(f'tl.to("#phone3d",{{scale:.72,duration:1.2,ease:"power2.inOut"}},{S["aovivo"] + 0.1:.3f});')
js.append(f'tl.to("#phone3d",{{scale:.86,duration:1.2,ease:"power2.inOut"}},{S["painel"] + 0.1:.3f});')
# ── 3D phone choreography: gentle continuous float + per-scene orbit ──
orbit = [(-7, 3), (6, -2), (-5, -3), (7, 2), (-6, 2), (5, -3)]
for i, k in enumerate(rec):
    ry, rx = orbit[i % len(orbit)]
    js.append(f'tl.to("#phone3d",{{rotationY:{ry},rotationX:{rx},duration:{max(2.0, slot[k] * 0.8):.2f},ease:"sine.inOut"}},{S[k]:.3f});')

# ── bokeh / particles (depth layers) ──
bok = []
for i in range(34):
    depth = rnd.random()
    size = int(8 + depth * 70)
    blur = round(1 + depth * 14, 1)
    x = rnd.randint(-40, W)
    y = rnd.randint(0, H)
    op = round(0.12 + (1 - depth) * 0.35, 2)
    col = rnd.choice(['#E07B39', '#D9A441', '#F2A65A', '#A24A32'])
    bok.append(f'<div id="bk{i}" class="bk" data-layout-allow-overflow style="left:{x}px;top:{y}px;width:{size}px;height:{size}px;background:{col};filter:blur({blur}px);opacity:{op}"></div>')
    drift = int(120 + depth * 420)
    js.append(f'tl.fromTo("#bk{i}",{{y:0,x:0}},{{y:{-drift},x:{rnd.randint(-80, 80)},duration:TOTAL,ease:"none"}},0);')

whoosh_at = [S['como'] - 0.3, S['acessar'] - 0.3, S['conta'] - 1.2] + [S[k] - 0.15 for k in ['regras', 'moderador', 'final']]
audio = [f'<audio id="vo-{k}" src="assets/vo/{k}.wav" data-start="{S[k] + LEAD:.3f}" data-duration="{T[k]["duration"]:.3f}" data-track-index="5" data-volume="1"></audio>' for k in order]
audio.append(f'<audio id="bgm" src="assets/bgm_long.mp3" data-start="0" data-duration="{TOTAL:.3f}" data-track-index="6" data-volume="0.16"></audio>')
audio += [f'<audio id="wh{i}" src="assets/whoosh.mp3" data-start="{a:.3f}" data-duration="1.0" data-track-index="7" data-volume="0.35"></audio>' for i, a in enumerate(whoosh_at)]
audio += [f'<audio id="pp{i}" src="assets/pop.mp3" data-start="{a:.3f}" data-duration="0.25" data-track-index="8" data-volume="0.22"></audio>' for i, a in enumerate(sfx)]

check = '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="3"><path d="M5 12l5 5 9-10"/></svg>'
steps = ['Crie sua conta', 'Cadastre as palavras', 'Monte as mensagens', 'Conecte o robô', 'Coloque de moderador', 'Favorite a streamer']
PH_IN = S['acessar'] + slot['acessar'] - 1.3       # phone flies in
REC_LEN = 234.5

doc = f'''<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width={W}, height={H}" />
<title>Atila's Client — Tutorial cinematográfico (celular)</title>
<script src="assets/gsap.min.js"></script>
<style>
@font-face {{ font-family: "Inter"; src: url("assets/fonts/inter-latin-300-normal.woff2") format("woff2"); font-weight: 300; }}
@font-face {{ font-family: "Inter"; src: url("assets/fonts/inter-latin-500-normal.woff2") format("woff2"); font-weight: 500; }}
@font-face {{ font-family: "Inter"; src: url("assets/fonts/inter-latin-700-normal.woff2") format("woff2"); font-weight: 700; }}
@font-face {{ font-family: "Inter"; src: url("assets/fonts/inter-latin-800-normal.woff2") format("woff2"); font-weight: 800; }}
@font-face {{ font-family: "JetBrains Mono"; src: url("assets/fonts/jetbrains-mono-latin-600-normal.woff2") format("woff2"); font-weight: 600; }}
:root {{ --bg: #0b0806; --amber: #F2A65A; --orange: #E07B39; --gold: #D9A441; --rust: #A24A32; --cream: #F7EEE3; --text2: #C9B7A3; --glass: rgba(36,26,19,.72); --line: rgba(242,166,90,.28); --ok: #7FBF6A; --red: #E0563A; }}
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
html, body {{ width: {W}px; height: {H}px; overflow: hidden; background: var(--bg); }}
#root {{ position: relative; width: 100%; height: 100%; overflow: hidden; font-family: "Inter", sans-serif; color: var(--cream); background: var(--bg); }}
.layer {{ position: absolute; inset: 0; }}
#bg {{ background: radial-gradient(900px 1100px at 50% 38%, #24170f 0%, #120c09 55%, #070504 100%); }}
.beam {{ position: absolute; width: 520px; height: 2600px; top: -500px; filter: blur(46px); transform-origin: 50% 0%; }}
#beam1 {{ left: -180px; background: linear-gradient(180deg, rgba(242,166,90,.38), rgba(242,166,90,0) 70%); }}
#beam2 {{ left: 700px; background: linear-gradient(180deg, rgba(224,123,57,.30), rgba(224,123,57,0) 65%); }}
#beam3 {{ left: 300px; width: 380px; background: linear-gradient(180deg, rgba(217,164,65,.20), rgba(217,164,65,0) 60%); }}
#floor {{ position: absolute; left: -540px; top: 1180px; width: 2160px; height: 1100px; background-image: linear-gradient(rgba(242,166,90,.16) 2px, transparent 2px), linear-gradient(90deg, rgba(242,166,90,.16) 2px, transparent 2px); background-size: 90px 90px; -webkit-mask-image: linear-gradient(180deg, transparent, #000 30%, transparent 85%); mask-image: linear-gradient(180deg, transparent, #000 30%, transparent 85%); opacity: .55; }}
#floorwrap {{ position: absolute; inset: 0; perspective: 900px; perspective-origin: 50% 40%; }}
.bk {{ position: absolute; border-radius: 50%; }}
#vignette {{ background: radial-gradient(1000px 1500px at 50% 45%, transparent 55%, rgba(0,0,0,.75) 100%); }}
#grain {{ opacity: .05; background-image: repeating-radial-gradient(circle at 17% 32%, #fff 0 1px, transparent 1px 3px); }}

/* bands */
.chapter {{ position: absolute; left: 60px; top: 64px; width: 960px; height: 70px; z-index: 40; }}
.ch-in {{ display: flex; align-items: center; justify-content: center; gap: 16px; height: 70px; white-space: nowrap; }}
.ch-dot {{ width: 14px; height: 14px; border-radius: 50%; background: var(--amber); box-shadow: 0 0 18px 4px rgba(242,166,90,.8); }}
.ch-tag {{ font-size: 22px; font-weight: 800; letter-spacing: .18em; text-transform: uppercase; color: var(--amber); }}
.ch-title {{ font-size: 40px; font-weight: 800; letter-spacing: -0.01em; color: var(--cream); text-shadow: 0 0 30px rgba(242,166,90,.35); }}
.cap {{ position: absolute; left: 60px; top: 1640px; width: 960px; height: 200px; display: flex; justify-content: center; align-items: center; z-index: 70; }}
.cap-in {{ display: block; text-align: center; max-width: 960px; font-size: 42px; line-height: 1.28; font-weight: 700; color: #fff; padding: 14px 30px; border-radius: 22px; background: rgba(12,8,6,.82); border: 1px solid var(--line); box-shadow: 0 0 40px rgba(242,166,90,.12), inset 0 1px 0 rgba(255,255,255,.06); }}
.rail {{ position: absolute; left: 90px; top: 1526px; width: 900px; height: 96px; display: flex; justify-content: center; align-items: center; perspective: 800px; z-index: 30; }}
.chip-in {{ display: flex; align-items: center; gap: 16px; white-space: nowrap; font-size: 32px; font-weight: 700; padding: 18px 32px; border-radius: 999px; background: var(--glass); border: 1.5px solid var(--line); box-shadow: 0 10px 40px rgba(0,0,0,.5), 0 0 40px rgba(242,166,90,.18); }}
.sd {{ width: 16px; height: 16px; flex: none; border-radius: 50%; }}
.ok .sd {{ background: var(--ok); box-shadow: 0 0 16px 4px rgba(127,191,106,.85); }}
.amb .sd {{ background: var(--amber); box-shadow: 0 0 16px 4px rgba(242,166,90,.85); }}
.red .sd, .live .sd, .ban .sd {{ background: var(--red); box-shadow: 0 0 16px 4px rgba(224,86,58,.9); }}
.off .sd {{ background: #8C7968; box-shadow: 0 0 10px 2px rgba(140,121,104,.6); }}
.mute .sd {{ background: var(--gold); box-shadow: 0 0 16px 4px rgba(217,164,65,.9); }}
.live {{ border-color: rgba(224,86,58,.5); }}

/* phone */
#stage3d {{ position: absolute; left: 0; top: 0; width: {W}px; height: {H}px; perspective: 2200px; perspective-origin: 50% 45%; }}
#phone3d {{ position: absolute; left: 182px; top: 96px; width: 716px; height: 1509px; transform-style: preserve-3d; }}
#phone {{ position: absolute; left: 0; top: 0; width: 716px; height: 1509px; border-radius: 88px; background: linear-gradient(145deg, #2b211a, #0d0907 45%, #1c1511); border: 2px solid rgba(242,166,90,.35); box-shadow: 0 60px 140px rgba(0,0,0,.75), 0 0 90px rgba(242,166,90,.18), inset 0 0 0 6px #050403; }}
#pscreen {{ position: absolute; left: 16px; top: 16px; width: 682.5px; height: 1477px; border-radius: 72px; overflow: hidden; background: #1B140F; }}
#status {{ position: absolute; left: 0; top: 0; width: 682.5px; height: 77px; display: flex; align-items: center; justify-content: space-between; padding: 14px 58px 0 66px; font-size: 26px; font-weight: 700; color: var(--cream); }}
.sicons {{ display: flex; gap: 8px; }} .sicons i {{ display: block; width: 22px; height: 14px; border-radius: 3px; background: var(--cream); opacity: .85; }}
#urlbar {{ position: absolute; left: 24px; top: 82px; width: 634px; height: 58px; border-radius: 29px; background: #2a1f18; display: flex; align-items: center; gap: 12px; padding: 0 24px; }}
#urltxt {{ font-family: "JetBrains Mono", monospace; font-size: 25px; color: var(--cream); display: inline-block; overflow: hidden; white-space: nowrap; width: 0; }}
#viewport {{ position: absolute; left: 0; top: 147px; width: 682.5px; height: 1330px; overflow: hidden; }}
#scaler {{ position: absolute; left: 0; top: 0; width: 780px; height: 1520px; transform: scale(0.875); transform-origin: 0 0; }}
#cam, #screen, #poster {{ position: absolute; left: 0; top: 0; width: 780px; height: 1520px; }}
#cam {{ transform-origin: 0 0; }}
#blank {{ position: absolute; inset: 0; background: #1B140F; }}
#glare {{ position: absolute; left: -400px; top: 0; width: 300px; height: 1477px; background: linear-gradient(90deg, transparent, rgba(255,230,200,.10), transparent); }}
#dim {{ position: absolute; left: 16px; top: 163px; width: 682.5px; height: 1330px; border-radius: 0 0 72px 72px; background: rgba(10,7,5,.82); opacity: 0; }}
#reflect {{ position: absolute; left: 182px; top: 1470px; width: 716px; height: 120px; border-radius: 50%; background: radial-gradient(closest-side, rgba(242,166,90,.35), transparent); filter: blur(20px); }}

/* side event cards */
.ev {{ position: absolute; width: 320px; height: 150px; perspective: 900px; z-index: 35; }}
.ev.left {{ left: 14px; }} .ev.right {{ left: 738px; }}
.ev-in {{ width: 320px; padding: 16px 18px; border-radius: 26px; background: rgba(28,20,15,.9); border: 1.5px solid var(--line); box-shadow: 0 30px 70px rgba(0,0,0,.6), 0 0 50px rgba(242,166,90,.2); display: flex; flex-direction: column; gap: 10px; }}
.ev-in.ban {{ border-color: rgba(224,86,58,.55); box-shadow: 0 30px 70px rgba(0,0,0,.6), 0 0 50px rgba(224,86,58,.25); }}
.ev-h {{ display: flex; align-items: center; gap: 10px; font-size: 25px; white-space: nowrap; }}
.ev-v {{ margin-left: auto; font-size: 17px; font-weight: 800; letter-spacing: .1em; text-transform: uppercase; padding: 6px 14px; border-radius: 10px; }}
.mute .ev-v {{ color: #1b140f; background: var(--gold); }}
.ban .ev-v {{ color: #fff; background: var(--red); }}
.ev-q {{ font-size: 20px; overflow: hidden; text-overflow: ellipsis; color: var(--text2); white-space: nowrap; }}

/* hero scenes */
.hero {{ position: absolute; inset: 0; perspective: 1400px; }}
#intro-box {{ position: absolute; left: 60px; top: 360px; width: 960px; height: 1150px; display: flex; flex-direction: column; align-items: center; gap: 34px; }}
#intro-fox {{ width: 620px; height: 413px; object-fit: contain; filter: drop-shadow(0 0 60px rgba(242,166,90,.35)); }}
#intro-title {{ font-size: 118px; font-weight: 800; letter-spacing: -0.04em; white-space: nowrap; text-shadow: 0 0 60px rgba(242,166,90,.35); }}
#intro-title span {{ color: var(--amber); }}
#intro-sub {{ font-size: 38px; font-weight: 300; color: var(--text2); text-align: center; width: 860px; line-height: 1.35; }}
#intro-line {{ width: 520px; height: 2px; background: linear-gradient(90deg, transparent, var(--amber), transparent); }}
#flare {{ position: absolute; left: -600px; top: 760px; width: 500px; height: 260px; background: radial-gradient(closest-side, rgba(255,214,160,.55), transparent); filter: blur(10px); }}
#como-box {{ position: absolute; left: 90px; top: 250px; width: 900px; height: 1300px; display: flex; flex-direction: column; align-items: center; gap: 26px; transform-style: preserve-3d; }}
.gcard {{ width: 900px; height: 210px; display: flex; align-items: center; gap: 34px; padding: 0 44px; border-radius: 32px; background: var(--glass); border: 1.5px solid var(--line); box-shadow: 0 30px 80px rgba(0,0,0,.55), 0 0 60px rgba(242,166,90,.12); }}
.gcard .ic {{ width: 112px; height: 112px; flex: none; border-radius: 30px; background: rgba(242,166,90,.10); border: 1px solid var(--line); display: flex; align-items: center; justify-content: center; }}
.gcard .ic img {{ width: 92px; height: 92px; object-fit: contain; }}
.gcard .tx {{ display: flex; flex-direction: column; gap: 10px; }}
.gcard h3 {{ font-size: 42px; font-weight: 800; }}
.gcard p {{ font-size: 28px; font-weight: 300; color: var(--text2); }}
.conn {{ width: 4px; height: 40px; border-radius: 2px; background: linear-gradient(180deg, var(--amber), var(--rust)); box-shadow: 0 0 16px rgba(242,166,90,.8); }}
.pills {{ display: flex; flex-wrap: wrap; justify-content: center; gap: 18px; width: 900px; margin-top: 18px; }}
.pill {{ display: flex; align-items: center; gap: 14px; white-space: nowrap; font-size: 30px; font-weight: 700; padding: 16px 28px; border-radius: 999px; background: var(--glass); border: 1.5px solid var(--line); }}
#close-tab {{ width: 900px; text-align: center; font-size: 30px; font-weight: 700; line-height: 1.3; padding: 22px 30px; border-radius: 24px; background: rgba(127,191,106,.12); border: 1.5px solid rgba(127,191,106,.6); color: #d8efcf; margin-top: 10px; }}
#ac-box {{ position: absolute; left: 90px; top: 420px; width: 900px; height: 1100px; display: flex; flex-direction: column; align-items: center; gap: 46px; transform-style: preserve-3d; }}
#ac-url {{ width: 900px; height: 124px; border-radius: 62px; display: flex; align-items: center; gap: 24px; padding: 0 46px; background: rgba(36,26,19,.85); border: 2px solid rgba(242,166,90,.5); box-shadow: 0 30px 90px rgba(0,0,0,.6), 0 0 80px rgba(242,166,90,.25); }}
#ac-ty {{ font-family: "JetBrains Mono", monospace; font-size: 52px; font-weight: 600; color: var(--cream); display: inline-block; overflow: hidden; white-space: nowrap; width: 0; }}
.devs {{ display: flex; gap: 34px; }}
.dev {{ width: 300px; height: 250px; border-radius: 30px; background: var(--glass); border: 1.5px solid var(--line); display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 20px; font-size: 32px; font-weight: 800; box-shadow: 0 20px 60px rgba(0,0,0,.5); }}
#ac-pwa {{ width: 900px; text-align: center; font-size: 30px; font-weight: 700; line-height: 1.3; padding: 22px 30px; border-radius: 24px; background: rgba(217,164,65,.10); border: 1.5px solid rgba(217,164,65,.55); color: #f3dfb2; }}

/* overlay cards */
.ocard {{ position: absolute; left: 80px; width: 920px; border-radius: 34px; background: rgba(24,17,13,.92); border: 1.5px solid var(--line); box-shadow: 0 40px 120px rgba(0,0,0,.75), 0 0 80px rgba(242,166,90,.18); padding: 46px 48px; display: flex; flex-direction: column; gap: 16px; }}
.ocard h2 {{ font-size: 46px; font-weight: 800; letter-spacing: -0.02em; line-height: 1.15; margin-bottom: 8px; }}
.rule {{ display: flex; align-items: center; gap: 18px; min-height: 80px; padding: 14px 24px; border-radius: 18px; background: rgba(242,166,90,.06); border: 1px solid rgba(242,166,90,.14); font-size: 30px; font-weight: 500; }}
.rule .ex {{ flex: 1; white-space: nowrap; }}
.kw {{ flex: none; font-family: "JetBrains Mono", monospace; font-weight: 600; color: var(--amber); font-size: 27px; padding: 4px 14px; border-radius: 10px; background: rgba(0,0,0,.35); white-space: nowrap; }}
.res {{ flex: none; white-space: nowrap; font-weight: 800; font-size: 22px; letter-spacing: .08em; text-transform: uppercase; padding: 7px 14px; border-radius: 10px; }}
.yes {{ color: #dff2d6; background: rgba(127,191,106,.25); }}
.no {{ color: #f6cdc2; background: rgba(224,86,58,.25); }}
#rg-card {{ top: 520px; }}
#md-card {{ top: 600px; align-items: center; text-align: center; gap: 26px; border-color: rgba(217,164,65,.6); box-shadow: 0 40px 120px rgba(0,0,0,.75), 0 0 90px rgba(217,164,65,.28); }}
#md-card h2 {{ color: var(--gold); }}
#md-card p {{ font-size: 34px; font-weight: 500; line-height: 1.4; color: var(--cream); }}
#rc-card {{ top: 360px; }}
.step {{ display: flex; align-items: center; gap: 22px; min-height: 88px; padding: 0 26px; border-radius: 20px; background: rgba(242,166,90,.06); border: 1px solid rgba(242,166,90,.14); font-size: 34px; font-weight: 700; }}
.num {{ width: 52px; height: 52px; flex: none; border-radius: 50%; background: var(--orange); color: #1B140F; font-weight: 800; font-size: 26px; display: flex; align-items: center; justify-content: center; box-shadow: 0 0 20px rgba(224,123,57,.6); }}
.tick {{ margin-left: auto; width: 46px; height: 46px; flex: none; border-radius: 50%; background: var(--ok); display: flex; align-items: center; justify-content: center; box-shadow: 0 0 18px rgba(127,191,106,.7); }}
#outro {{ position: absolute; inset: 0; background: radial-gradient(900px 1200px at 50% 45%, #24170f, #070504 75%); z-index: 50; }}
#outro-box {{ position: absolute; left: 60px; top: 480px; width: 960px; height: 980px; display: flex; flex-direction: column; align-items: center; gap: 34px; }}
#outro-fox {{ width: 440px; height: 440px; object-fit: contain; filter: drop-shadow(0 0 70px rgba(242,166,90,.45)); }}
#outro-title {{ font-size: 108px; font-weight: 800; letter-spacing: -0.04em; white-space: nowrap; text-shadow: 0 0 60px rgba(242,166,90,.35); }}
#outro-title span {{ color: var(--amber); }}
#outro-sub {{ font-size: 38px; font-weight: 300; color: var(--text2); }}
#outro-url {{ font-family: "JetBrains Mono", monospace; font-size: 40px; font-weight: 600; color: var(--amber); padding: 18px 40px; border-radius: 999px; border: 2px solid rgba(242,166,90,.6); box-shadow: 0 0 50px rgba(242,166,90,.3); white-space: nowrap; }}
#progress {{ position: absolute; left: 0; top: 0; height: 6px; width: {W}px; background: linear-gradient(90deg, var(--rust), var(--orange), var(--amber)); box-shadow: 0 0 14px rgba(242,166,90,.8); transform-origin: 0 50%; z-index: 80; }}
</style>
</head>
<body>
<div id="root" data-composition-id="main" data-start="0" data-duration="{TOTAL:.3f}" data-width="{W}" data-height="{H}">
  <div id="bg" class="layer"></div>
  <div id="beams" class="layer" data-layout-allow-overflow><div id="beam1" class="beam"></div><div id="beam2" class="beam"></div><div id="beam3" class="beam"></div></div>
  <div id="floorwrap" data-layout-allow-overflow><div id="floor" data-layout-allow-overflow></div></div>
  <div id="vignette" class="layer"></div>
  <div id="grain" class="layer"></div>
  <div id="bokeh" class="layer" data-layout-allow-overflow>{''.join(bok)}</div>

  <div id="intro" class="clip hero" data-start="0" data-duration="{slot['intro']:.3f}" data-track-index="1">
    <div id="intro-box">
      <img id="intro-fox" src="assets/img/fox_hero.webp" alt="" />
      <div id="intro-title">Atila's <span>Client</span></div>
      <div id="intro-line"></div>
      <div id="intro-sub">O robô que modera as suas lives no SuperLive</div>
    </div>
    <div id="flare" data-layout-allow-overflow></div>
  </div>

  <div id="como" class="clip hero" data-start="{S['como']:.3f}" data-duration="{slot['como']:.3f}" data-track-index="1">
    <div id="como-box">
      <div id="g1" class="gcard"><div class="ic"><svg width="62" height="62" viewBox="0 0 24 24" fill="none" stroke="#F2A65A" stroke-width="1.8"><rect x="6" y="2" width="12" height="20" rx="2"/><path d="M11 18h2"/></svg></div><div class="tx"><h3>Site</h3><p>Você configura tudo pelo navegador</p></div></div>
      <div id="k1" class="conn"></div>
      <div id="g2" class="gcard"><div class="ic"><svg width="62" height="62" viewBox="0 0 24 24" fill="none" stroke="#D9A441" stroke-width="1.8"><rect x="3" y="3" width="18" height="7" rx="2"/><rect x="3" y="14" width="18" height="7" rx="2"/><path d="M7 6.5h.01M7 17.5h.01"/></svg></div><div class="tx"><h3>Servidor</h3><p>Guarda as regras e controla o robô</p></div></div>
      <div id="k2" class="conn"></div>
      <div id="g3" class="gcard"><div class="ic"><img src="assets/img/fox_avatar.png" alt="" /></div><div class="tx"><h3>Robô na live</h3><p>De olho no chat, 24 horas</p></div></div>
      <div class="pills">
        <div id="p1" class="pill mute"><span class="sd"></span>Silencia</div>
        <div id="p2" class="pill ban"><span class="sd"></span>Expulsa</div>
        <div id="p3" class="pill ok"><span class="sd"></span>Manda mensagens</div>
      </div>
      <div id="close-tab">Pode fechar o navegador: a moderação continua</div>
    </div>
  </div>

  <div id="acessar" class="clip hero" data-start="{S['acessar']:.3f}" data-duration="{slot['acessar']:.3f}" data-track-index="1">
    <div id="ac-box">
      <div id="ac-url"><svg width="44" height="44" viewBox="0 0 24 24" fill="none" stroke="#F2A65A" stroke-width="2.2"><rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></svg><span id="ac-ty">atilaclient.tech</span></div>
      <div class="devs">
        <div id="d1" class="dev"><svg width="92" height="92" viewBox="0 0 24 24" fill="none" stroke="#F2A65A" stroke-width="1.6"><rect x="3" y="4" width="18" height="12" rx="2"/><path d="M1 20h22"/></svg>Computador</div>
        <div id="d2" class="dev"><svg width="92" height="92" viewBox="0 0 24 24" fill="none" stroke="#F2A65A" stroke-width="1.6"><rect x="6" y="2" width="12" height="20" rx="2"/><path d="M11 18h2"/></svg>Celular</div>
      </div>
      <div id="ac-pwa">Dá pra instalar como app em Configurações</div>
    </div>
  </div>

  <div id="reflect"></div>
  <div id="stage3d">
    <div id="phone3d">
      <div id="phone">
        <div id="pscreen">
          <div id="status"><span>9:41</span><span class="sicons"><i></i><i></i><i></i></span></div>
          <div id="urlbar"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#C9B7A3" stroke-width="2"><rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></svg><span id="urltxt">atilaclient.tech</span></div>
          <div id="viewport"><div id="scaler"><div id="cam">
            <img id="poster" src="assets/img/first.jpg" alt="" />
            <video id="screen" src="assets/rec/screen.mp4" muted playsinline data-start="{T_REC:.3f}" data-duration="{min(REC_LEN, TOTAL - T_REC):.3f}" data-track-index="0"></video>
          </div></div><div id="blank"></div></div>
          <div id="glare" data-layout-allow-overflow></div>
        </div>
        <div id="dim"></div>
      </div>
    </div>
  </div>

  {''.join(side)}

  <div id="regras" class="clip hero" data-start="{S['regras'] + 0.3:.3f}" data-duration="{slot['regras'] - 0.5:.3f}" data-track-index="2">
    <div id="rg-card" class="ocard">
      <h2>O robô lê a palavra inteira</h2>
      <div id="r1" class="rule"><span class="kw">passa zap</span><span class="ex">“me PASSA ZÁP”</span><span class="res yes">pega</span></div>
      <div id="r2" class="rule"><span class="kw">zap</span><span class="ex">“zapzap”</span><span class="res no">não pega</span></div>
      <div id="r3" class="rule"><span class="kw">divulg*</span><span class="ex">“divulguem”</span><span class="res yes">pega</span></div>
      <div id="r4" class="rule"><span class="kw">divulg*</span><span class="ex">“divulgação”</span><span class="res yes">pega</span></div>
    </div>
  </div>

  <div id="moderador" class="clip hero" data-start="{S['moderador'] + 0.3:.3f}" data-duration="{slot['moderador'] - 0.6:.3f}" data-track-index="2">
    <div id="md-card" class="ocard">
      <svg width="110" height="110" viewBox="0 0 24 24" fill="none" stroke="#D9A441" stroke-width="1.8"><path d="M12 2l8 4v6c0 5-3.5 8.5-8 10-4.5-1.5-8-5-8-10V6z"/><path d="M12 8v5M12 16h.01"/></svg>
      <h2>Coloque o robô como moderador</h2>
      <p>Sem isso, o SuperLive não deixa o robô silenciar nem banir ninguém.</p>
    </div>
  </div>

  <div id="recap" class="clip hero" data-start="{S['final'] + 4.0:.3f}" data-duration="{cap('final', 2) - S['final'] - 4.0:.3f}" data-track-index="2">
    <div id="rc-card" class="ocard">
      <h2>Checklist</h2>
      {''.join(f'<div id="st{i}" class="step"><span class="num">{i + 1}</span><span>{E(s)}</span><span class="tick">{check}</span></div>' for i, s in enumerate(steps))}
    </div>
  </div>

  {''.join(chip_html)}

  <div id="outro" class="clip" data-start="{cap('final', 2):.3f}" data-duration="{TOTAL - cap('final', 2):.3f}" data-track-index="2">
    <div id="outro-box">
      <img id="outro-fox" src="assets/img/fox_avatar.png" alt="" />
      <div id="outro-title">Atila's <span>Client</span></div>
      <div id="outro-sub">Suas lives no piloto automático</div>
      <div id="outro-url">atilaclient.tech</div>
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

// volumetric light: slow sway + breathing
tl.fromTo("#beam1", {{ rotation: 18 }}, {{ rotation: 8, duration: TOTAL / 2, ease: "sine.inOut", yoyo: true, repeat: 1 }}, 0);
tl.fromTo("#beam2", {{ rotation: -20 }}, {{ rotation: -9, duration: TOTAL / 3, ease: "sine.inOut", yoyo: true, repeat: 2 }}, 0);
tl.fromTo("#beam3", {{ rotation: 4, opacity: .5 }}, {{ rotation: -6, opacity: 1, duration: TOTAL / 4, ease: "sine.inOut", yoyo: true, repeat: 3 }}, 0);
tl.fromTo("#floor", {{ rotationX: 72, y: 0 }}, {{ rotationX: 72, y: 180, duration: TOTAL, ease: "none" }}, 0);

// INTRO: light sweep reveals the logo
tl.fromTo("#intro-fox", {{ opacity: 0, scale: .82, y: 60, filter: "blur(18px)" }}, {{ opacity: 1, scale: 1, y: 0, filter: "blur(0px)", duration: 1.6, ease: "power3.out" }}, 0.2);
tl.fromTo("#intro-title", {{ opacity: 0, scale: 1.18, filter: "blur(12px)" }}, {{ opacity: 1, scale: 1, filter: "blur(0px)", duration: 1.4, ease: "power3.out" }}, 0.9);
tl.fromTo("#intro-line", {{ scaleX: 0 }}, {{ scaleX: 1, duration: 1.1, ease: "power2.inOut" }}, 1.6);
tl.fromTo("#intro-sub", {{ opacity: 0, y: 20 }}, {{ opacity: 1, y: 0, duration: .9, ease: "power2.out" }}, 2.0);
tl.fromTo("#flare", {{ x: 0 }}, {{ x: 2200, duration: 2.4, ease: "power2.inOut" }}, 0.8);
tl.to("#intro-fox", {{ y: -16, duration: 2.6, ease: "sine.inOut", yoyo: true, repeat: 2 }}, 1.8);
tl.to("#intro-box", {{ scale: 1.35, opacity: 0, filter: "blur(16px)", duration: .9, ease: "power2.in" }}, {slot['intro'] - 1.0:.3f});

// COMO: glass cards float in from depth
const cc = {cc('como')};
tl.fromTo("#g1", {{ opacity: 0, z: -500, rotationX: 40 }}, {{ opacity: 1, z: 0, rotationX: 0, duration: .9, ease: "power3.out" }}, cc[1]);
tl.fromTo("#k1", {{ scaleY: 0 }}, {{ scaleY: 1, duration: .4 }}, cc[1] + 1.5);
tl.fromTo("#g2", {{ opacity: 0, z: -500, rotationX: 40 }}, {{ opacity: 1, z: 0, rotationX: 0, duration: .9, ease: "power3.out" }}, cc[1] + 1.8);
tl.fromTo("#k2", {{ scaleY: 0 }}, {{ scaleY: 1, duration: .4 }}, cc[1] + 3.3);
tl.fromTo("#g3", {{ opacity: 0, z: -500, rotationX: 40 }}, {{ opacity: 1, z: 0, rotationX: 0, duration: .9, ease: "power3.out" }}, cc[2]);
tl.fromTo("#p1", {{ opacity: 0, y: 30, scale: .9 }}, {{ opacity: 1, y: 0, scale: 1, duration: .5, ease: "back.out(2)" }}, cc[2] + 4.0);
tl.fromTo("#p2", {{ opacity: 0, y: 30, scale: .9 }}, {{ opacity: 1, y: 0, scale: 1, duration: .5, ease: "back.out(2)" }}, cc[2] + 5.0);
tl.fromTo("#p3", {{ opacity: 0, y: 30, scale: .9 }}, {{ opacity: 1, y: 0, scale: 1, duration: .5, ease: "back.out(2)" }}, cc[2] + 8.0);
tl.fromTo("#close-tab", {{ opacity: 0, scale: .92 }}, {{ opacity: 1, scale: 1, duration: .5, ease: "back.out(2)" }}, cc[3] + 1.3);
tl.fromTo("#como-box", {{ rotationY: -8, rotationX: 4 }}, {{ rotationY: 8, rotationX: -3, duration: {slot['como']:.2f}, ease: "sine.inOut" }}, {S['como']:.3f});
tl.to("#como-box", {{ scale: 1.3, opacity: 0, filter: "blur(16px)", duration: .8, ease: "power2.in" }}, {S['como'] + slot['como'] - 0.85:.3f});

// ACESSAR: glowing URL bar types, devices float
const ac = {cc('acessar')};
tl.fromTo("#ac-url", {{ opacity: 0, z: -600, rotationX: 30 }}, {{ opacity: 1, z: 0, rotationX: 0, duration: 1, ease: "power3.out" }}, {S['acessar'] + 0.3:.3f});
tl.fromTo("#ac-ty", {{ width: 0 }}, {{ width: "16ch", duration: 1.2, ease: "steps(16)" }}, ac[1] + 2.6);
tl.fromTo("#d1", {{ opacity: 0, y: 50, rotationY: -30 }}, {{ opacity: 1, y: 0, rotationY: 0, duration: .7, ease: "power3.out" }}, ac[2] + 0.5);
tl.fromTo("#d2", {{ opacity: 0, y: 50, rotationY: 30 }}, {{ opacity: 1, y: 0, rotationY: 0, duration: .7, ease: "power3.out" }}, ac[2] + 1.1);
tl.fromTo("#ac-pwa", {{ opacity: 0, y: 24 }}, {{ opacity: 1, y: 0, duration: .5 }}, ac[2] + 4.8);
tl.to("#ac-box", {{ scale: 1.3, opacity: 0, filter: "blur(16px)", duration: .7, ease: "power2.in" }}, {PH_IN - 0.9:.3f});

// PHONE flies in from depth, then floats
tl.fromTo("#phone3d", {{ opacity: 0, z: -1600, rotationY: 38, rotationX: 12, scale: .86 }}, {{ opacity: 1, z: 0, rotationY: -6, rotationX: 3, scale: .86, duration: 1.6, ease: "power3.out" }}, {PH_IN:.3f});
tl.fromTo("#reflect", {{ opacity: 0 }}, {{ opacity: 1, duration: 1.2 }}, {PH_IN + 0.4:.3f});
tl.fromTo("#phone3d", {{ y: 0 }}, {{ y: -18, duration: 3.2, ease: "sine.inOut", yoyo: true, repeat: {int((TOTAL - PH_IN) / 3.2):d} }}, {PH_IN + 1.6:.3f});
tl.fromTo("#urltxt", {{ width: 0 }}, {{ width: "16ch", duration: .6, ease: "steps(16)" }}, {PH_IN + 0.6:.3f});
tl.to("#blank", {{ opacity: 0, duration: .4 }}, {PH_IN + 1.1:.3f});
tl.set("#poster", {{ opacity: 0 }}, {T_REC + 0.2:.3f});
for (let g = 0; g < 9; g++) tl.fromTo("#glare", {{ x: 0 }}, {{ x: 1400, duration: 1.6, ease: "power2.inOut" }}, {T_REC:.3f} + g * 21);

// overlays: dim the screen, cards float in front
const dim = (a, b) => {{ tl.to("#dim", {{ opacity: 1, duration: .4 }}, a); if (b) tl.to("#dim", {{ opacity: 0, duration: .4 }}, b); }};
dim({S['regras'] + 0.3:.3f}, {S['regras'] + slot['regras'] - 0.5:.3f});
dim({S['moderador'] + 0.3:.3f}, {S['moderador'] + slot['moderador'] - 0.6:.3f});
dim({S['final'] + 4.0:.3f}, 0);
const rc = {cc('regras')};
tl.fromTo("#rg-card", {{ opacity: 0, z: -400, rotationX: 25 }}, {{ opacity: 1, z: 0, rotationX: 0, duration: .8, ease: "power3.out" }}, {S['regras'] + 0.4:.3f});
tl.fromTo("#r1", {{ opacity: 0, x: -30 }}, {{ opacity: 1, x: 0, duration: .4 }}, rc[1] + 0.8);
tl.fromTo("#r2", {{ opacity: 0, x: -30 }}, {{ opacity: 1, x: 0, duration: .4 }}, rc[1] + 2.6);
tl.fromTo("#r3", {{ opacity: 0, x: -30 }}, {{ opacity: 1, x: 0, duration: .4 }}, rc[2] + 6.2);
tl.fromTo("#r4", {{ opacity: 0, x: -30 }}, {{ opacity: 1, x: 0, duration: .4 }}, rc[2] + 7.4);
tl.to("#rg-card", {{ opacity: 0, scale: 1.08, filter: "blur(10px)", duration: .45 }}, {S['regras'] + slot['regras'] - 0.9:.3f});
tl.fromTo("#md-card", {{ opacity: 0, z: -400, rotationX: 25 }}, {{ opacity: 1, z: 0, rotationX: 0, duration: .8, ease: "power3.out" }}, {S['moderador'] + 0.4:.3f});
tl.to("#md-card svg", {{ scale: 1.12, duration: .5, yoyo: true, repeat: 5, ease: "sine.inOut" }}, {S['moderador'] + 1.0:.3f});
tl.to("#md-card", {{ opacity: 0, scale: 1.08, filter: "blur(10px)", duration: .45 }}, {S['moderador'] + slot['moderador'] - 1.0:.3f});
const fc = {cc('final')};
tl.fromTo("#rc-card", {{ opacity: 0, z: -400, rotationX: 25 }}, {{ opacity: 1, z: 0, rotationX: 0, duration: .8, ease: "power3.out" }}, {S['final'] + 4.1:.3f});
[1.0, 2.2, 3.6, 5.0, 6.4, 8.3].forEach((d, i) => {{
  tl.fromTo("#st" + i, {{ opacity: 0, x: -30 }}, {{ opacity: 1, x: 0, duration: .35, ease: "power2.out" }}, fc[1] + d);
  tl.fromTo("#st" + i + " .tick", {{ scale: 0 }}, {{ scale: 1, duration: .35, ease: "back.out(3)" }}, fc[1] + d + 0.4);
}});
tl.fromTo("#outro-fox", {{ opacity: 0, scale: .7, filter: "blur(16px)" }}, {{ opacity: 1, scale: 1, filter: "blur(0px)", duration: 1.1, ease: "power3.out" }}, fc[2] + 0.1);
tl.fromTo("#outro-title", {{ opacity: 0, scale: 1.18, filter: "blur(12px)" }}, {{ opacity: 1, scale: 1, filter: "blur(0px)", duration: 1.0, ease: "power3.out" }}, fc[2] + 0.5);
tl.fromTo("#outro-sub", {{ opacity: 0, y: 18 }}, {{ opacity: 1, y: 0, duration: .6 }}, fc[2] + 1.0);
tl.fromTo("#outro-url", {{ opacity: 0, scale: .85 }}, {{ opacity: 1, scale: 1, duration: .6, ease: "back.out(2)" }}, fc[2] + 1.4);

{chr(10).join(js)}

window.__timelines["main"] = tl;
</script>
</body>
</html>
'''
open('/tmp/claude-0/hf/eleven/index.html', 'w').write(doc)
print('total', TOTAL, 'captions', ci, 'chips', len(chip_html))
