import os, re, json, urllib.parse, urllib.request
from rec import *
RIPPLE = """
(()=>{const mk=()=>{
 const s=document.createElement('style');s.textContent='@keyframes rp{0%{transform:translate(-50%,-50%) scale(.3);opacity:.75}100%{transform:translate(-50%,-50%) scale(1.5);opacity:0}}.rp{position:fixed;width:84px;height:84px;border-radius:50%;background:rgba(168,70,31,.35);border:3px solid rgba(168,70,31,.85);pointer-events:none;z-index:2147483647;animation:rp .55s ease-out forwards}';
 document.documentElement.appendChild(s);
 addEventListener('pointerdown',e=>{const d=document.createElement('div');d.className='rp';d.style.left=e.clientX+'px';d.style.top=e.clientY+'px';document.documentElement.appendChild(d);setTimeout(()=>d.remove(),700)},true)};
 if(document.documentElement)mk();else addEventListener('DOMContentLoaded',mk)})();
"""
FIND = """([txt,mode,nth])=>{
 const els=[...document.querySelectorAll('flt-semantics')].filter(e=>{const t=(e.getAttribute('aria-label')||e.textContent||'').trim();
   if(!t)return false; return mode==='exact'? t===txt : t.includes(txt)});
 const sized=els.map(e=>{const r=e.getBoundingClientRect();return {e,r,a:r.width*r.height}}).filter(o=>o.r.width>4&&o.r.height>4&&o.r.bottom>0&&o.r.top<innerHeight);
 sized.sort((a,b)=>a.a-b.a);
 const o=sized[nth||0]; if(!o) return null; return [o.r.left+o.r.width/2,o.r.top+o.r.height/2,o.r.width,o.r.height]}"""
async def prep(pg):
    await pg.evaluate("document.querySelector('flt-semantics-placeholder') && document.querySelector('flt-semantics-placeholder').click()")
    await pg.wait_for_timeout(800)
async def boot2(pg):
    await pg.add_init_script(RIPPLE)
    await boot(pg); await prep(pg)
async def pos(pg,txt,mode="in",nth=0):
    return await pg.evaluate(FIND,[txt,mode,nth])
async def tapt(pg,txt,mode="in",nth=0,wait=700,dy=0):
    p=await pos(pg,txt,mode,nth)
    if not p: raise RuntimeError("not found: "+txt)
    await pg.mouse.move(p[0],p[1]+dy,steps=6); await pg.wait_for_timeout(120)
    await pg.mouse.click(p[0],p[1]+dy); await pg.wait_for_timeout(wait)
async def typ(pg,text,delay=90):
    await pg.keyboard.type(text,delay=delay)
async def scroll_by(pg,dy,steps=8,x=195,y=520):
    await pg.mouse.move(x,y)
    for _ in range(steps):
        await pg.mouse.wheel(0,dy/steps); await pg.wait_for_timeout(45)
    await pg.wait_for_timeout(350)
def demo(path,**q):
    url="http://localhost:8000"+path+("?"+urllib.parse.urlencode(q) if q else "")
    return urllib.request.urlopen(urllib.request.Request(url),timeout=10).read()
def chat(uid,name,text): demo("/__demo/chat",uid=uid,name=name,text=text)
TOKEN=lambda: open(ROOT+"/demo/token.txt").read().strip()
def api(method,path,body=None):
    r=urllib.request.Request("http://localhost:8000"+path,data=json.dumps(body).encode() if body is not None else None,method=method)
    r.add_header("Content-Type","application/json"); r.add_header("Authorization","Bearer "+TOKEN())
    try:
        with urllib.request.urlopen(r,timeout=15) as x: return json.loads(x.read() or "null")
    except urllib.error.HTTPError as e: return {"error":e.code,"body":e.read().decode()[:200]}
async def field(pg,label,dy=67,wait=450):
    r=await pg.evaluate("""(l)=>{const e=[...document.querySelectorAll('flt-semantics')].filter(e=>(e.getAttribute('aria-label')||'').startsWith(l)).map(e=>e.getBoundingClientRect()).sort((a,b)=>a.width*a.height-b.width*b.height)[0]; return e?[e.left,e.top,e.width,e.height]:null}""",label)
    if not r: raise RuntimeError("field not found "+label)
    await pg.mouse.move(195,r[1]+dy,steps=6); await pg.wait_for_timeout(100)
    await pg.mouse.click(195,r[1]+dy); await pg.wait_for_timeout(wait)
async def clip(name,fn,state=True,dsf="2"):
    os.environ["DSF"]=dsf
    async with async_playwright() as p:
        b,ctx,pg=await new_ctx(p,state=state); await boot2(pg)
        r=Rec(pg,name)
        try:
            await fn(pg,r,ctx)
        finally:
            if r.frames: await r.stop()
        await b.close()
async def idle(pg,ms,x=195,y=420):
    t=0; await pg.mouse.move(x,y)
    while t<ms:
        await pg.mouse.move(x+(t//400%2)*2,y); await pg.wait_for_timeout(200); t+=200
async def play(pg,events,total_ms,x=195,y=420):
    """events: [(ms, fn)] ; keeps page repainting by nudging mouse"""
    t=0; ev=sorted(events,key=lambda e:e[0]); i=0
    await pg.mouse.move(x,y)
    while t<total_ms:
        while i<len(ev) and ev[i][0]<=t:
            r=ev[i][1]()
            if asyncio.iscoroutine(r): await r
            i+=1
        await pg.mouse.move(x+(t//400%2)*2,y); await pg.wait_for_timeout(200); t+=200
