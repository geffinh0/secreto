import json, os, sys
R="/tmp/claude-0/-home-user-secreto/5a577aff-184f-5ecc-81ef-0546d19cec6e/scratchpad/video2"
T=json.load(open(R+"/timing.json")); total=T["_total"]
scenes=[k for k in T if k!="_total"]
only=set(sys.argv[1:]) if len(sys.argv)>1 else None
slots=[]; 
for i,k in enumerate(scenes):
    s=T[k]
    if os.path.exists(f"{R}/atila2/compositions/{k}.html"):
        slots.append(f'<div id="{k}" data-composition-id="{k}" data-composition-src="compositions/{k}.html" data-start="{s["start"]}" data-duration="{s["dur"]}" data-track-index="{1+i%2}" data-width="1080" data-height="1920"></div>')
    else:
        slots.append(f'<div id="{k}" class="clip" data-start="{s["start"]}" data-duration="{s["dur"]}" data-track-index="{1+i%2}" style="position:absolute;inset:0;background:#E3E8D6;display:flex;align-items:center;justify-content:center;font:700 120px Fraunces,serif;color:#1F3A2E">{k}</div>')
bounds=[T[k]["start"] for k in scenes[1:]]
wipes="\n".join(f"tl.fromTo(\"#wipe\",{{yPercent:{100 if i%2==0 else -100}}},{{yPercent:{-100 if i%2==0 else 100},duration:0.9,ease:E.press,immediateRender:false}},{b-0.45});" for i,b in enumerate(bounds))
audio = f'<audio id="mix" data-start="0" data-duration="{total}" data-track-index="9" src="assets/mix.wav" data-volume="1"></audio>' if os.path.exists(R+"/atila2/assets/mix.wav") else ""
html=f'''<!doctype html>
<html lang="pt-BR"><head><meta charset="UTF-8"/><meta name="viewport" content="width=1080, height=1920"/><title>Atila's Client</title>
<link rel="stylesheet" href="assets/base.css"/><link rel="stylesheet" href="assets/base.css"/><script src="assets/gsap.min.js"></script><script src="assets/lib.js"></script>
<style>
@font-face{{font-family:'Fraunces';src:url('assets/Fraunces72ptSoft-SemiBold.ttf');font-weight:600}} @font-face{{font-family:'Fraunces';src:url('assets/Fraunces72ptSoft-Bold.ttf');font-weight:700}} @font-face{{font-family:'Source Sans 3';src:url('assets/SourceSans3VF-Upright.ttf');font-weight:200 900}}
*{{margin:0;padding:0;box-sizing:border-box}} html,body{{width:1080px;height:1920px;overflow:hidden;background:#F4ECDC}}
#root{{position:absolute;inset:0;width:100%;height:100%;overflow:hidden}}
#grain{{position:absolute;inset:0;z-index:60;pointer-events:none;mix-blend-mode:multiply;opacity:.2;background-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='300' height='300'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='2' seed='4'/><feColorMatrix values='0 0 0 0 0.55  0 0 0 0 0.45  0 0 0 0 0.3  0 0 0 0.55 0'/></filter><rect width='300' height='300' filter='url(%23n)'/></svg>")}}
#wipe{{position:absolute;left:0;top:0;width:1080px;height:2100px;background:#1F3A2E;z-index:50;border-top:14px solid #D2B568;border-bottom:14px solid #D2B568}}
</style></head><body>
<div id="root" data-composition-id="main" data-start="0" data-duration="{total}" data-width="1080" data-height="1920">
{chr(10).join(slots)}
<div id="wipe"></div><div id="grain"></div>
{audio}
</div>
<script>
const E={{press:"power2.inOut"}}; const tl=gsap.timeline({{paused:true}});
tl.set("#wipe",{{yPercent:100}},0);
{wipes}
window.__timelines=window.__timelines||{{}}; window.__timelines["main"]=tl;
</script></body></html>'''
open(R+"/atila2/index.html","w").write(html); print("index.html written; scenes with files:",[k for k in scenes if os.path.exists(f"{R}/atila2/compositions/{k}.html")])
