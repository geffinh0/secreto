import asyncio, sys
from rec2 import *
def C(u,n,t): return lambda: chat(u,n,t)
async def k08(pg,r,ctx):
    api("POST","/robot/connect",{"email":"robot@x.com","password":"good"})
    await pg.reload(wait_until="networkidle"); await pg.wait_for_timeout(5000); await prep(pg)
    await tapt(pg,"Robô","exact",wait=2000); await prep(pg)
    await r.start(); await pg.wait_for_timeout(1500)
    await pg.mouse.click(195,548); await pg.wait_for_timeout(500); await typ(pg,"live1",120); await pg.wait_for_timeout(700)
    await tapt(pg,"Iniciar moderação",wait=300); await idle(pg,2500)
    ev=[(0,C("u1","Lucas","Boa noite, Aurora!")),(1500,C("u2","Marina","que live chata")),(3300,C("u5","Ana","oi oi oi"))]
    await play(pg,ev[:3],4500)
    await scroll_by(pg,1700,30); await idle(pg,600)
    await play(pg,[(300,C("u4","Bruno","amei a live de hoje")),(2000,C("u3","bot77","SP4M compre seguidores aqui")),(4200,C("u6","Clara","ch4t4 demais")),(6200,C("u8","Rafa","SPAM spam spam"))],8500)
    await scroll_by(pg,520,14); await idle(pg,3500)
    await scroll_by(pg,-2300,34); await idle(pg,1000)

async def k09(pg,r,ctx):
    await tapt(pg,"Robô","exact",wait=2000); await prep(pg)
    await r.start(); await pg.wait_for_timeout(1200)
    if await pos(pg,"Parar moderação"):
        await tapt(pg,"Parar moderação",wait=300); await idle(pg,2200); await prep(pg)
    await scroll_by(pg,380,12); await idle(pg,500); await prep(pg)
    bp=await pos(pg,"Buscar streamer"); await pg.mouse.move(195,bp[1]-32,steps=8); await pg.mouse.click(195,bp[1]-32); await pg.wait_for_timeout(500)
    await typ(pg,"555200",130); await pg.wait_for_timeout(700)
    await tapt(pg,"Buscar streamer",wait=300); await idle(pg,2600)
    await scroll_by(pg,250,10); await idle(pg,900); await prep(pg)
    print(await pg.evaluate("[...document.querySelectorAll('flt-semantics')].filter(e=>e.getAttribute('role')=='button').map(e=>(e.textContent||'').slice(0,30)+' '+Math.round(e.getBoundingClientRect().top))"))
    await tapt(pg,"Favoritar",wait=300); await idle(pg,2800)
    await scroll_by(pg,-1000,16); await idle(pg,1500); await prep(pg)
    demo("/__demo/live",op="start",uid="200",lid="live3")
    await scroll_by(pg,300,10); await idle(pg,800); await prep(pg)
    await tapt(pg,"Avisar que entrei ao vivo",wait=300); await idle(pg,5500)
    await scroll_by(pg,-1000,16); await idle(pg,2500)
which=sys.argv[1:]
M={"k08":(k08,True),"k09":(k09,True)}
async def main():
    for k in which:
        fn,st=M[k]; print("==",k); await clip(k,fn,state=st)
asyncio.run(main())
