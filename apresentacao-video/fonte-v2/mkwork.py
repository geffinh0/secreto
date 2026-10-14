import sys, os, json, shutil
SC=sys.argv[1]
R="/tmp/claude-0/-home-user-secreto/5a577aff-184f-5ecc-81ef-0546d19cec6e/scratchpad/video2"
T=json.load(open(R+"/timing.json"))[SC]
W=f"{R}/work/{SC}"
shutil.rmtree(W,ignore_errors=True); os.makedirs(W+"/compositions")
os.symlink(R+"/atila2/assets",W+"/assets")
open(W+"/hyperframes.json","w").write(open(R+"/atila2/hyperframes.json").read())
open(W+"/meta.json","w").write(open(R+"/atila2/meta.json").read())
open(W+"/package.json","w").write(open(R+"/atila2/package.json").read())
os.symlink(f"{R}/atila2/compositions/{SC}.html",f"{W}/compositions/{SC}.html") if os.path.exists(f"{R}/atila2/compositions/{SC}.html") else None
d=T["dur"]
open(W+"/index.html","w").write(f'''<!doctype html><html lang="pt-BR"><head><meta charset="UTF-8"/><meta name="viewport" content="width=1080, height=1920"/>
<link rel="stylesheet" href="assets/base.css"/><script src="assets/gsap.min.js"></script><script src="assets/lib.js"></script>
<style>*{{margin:0;padding:0;box-sizing:border-box}}html,body{{width:1080px;height:1920px;overflow:hidden;background:#F4ECDC}}#root{{position:absolute;inset:0}}</style></head><body>
<div id="root" data-composition-id="main" data-start="0" data-duration="{d}" data-width="1080" data-height="1920">
<div id="{SC}" data-composition-id="{SC}" data-composition-src="compositions/{SC}.html" data-start="0" data-duration="{d}" data-track-index="1" data-width="1080" data-height="1920"></div>
<audio id="vo" data-start="{T['voiceOffset']}" data-duration="{T['voiceLen']}" data-track-index="9" src="assets/vo/{SC}.wav"></audio>
</div><script>window.__timelines=window.__timelines||{{}};const tl=gsap.timeline({{paused:true}});window.__timelines["main"]=tl;</script></body></html>''')
print("work ready:",W,"dur",d)
