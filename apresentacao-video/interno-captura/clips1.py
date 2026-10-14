import asyncio, sys
from rec2 import *
async def fclick(pg):
    bp=await pos(pg,'Testar frase'); await pg.mouse.move(195,bp[1]-40,steps=6); await pg.mouse.click(195,bp[1]-40); await pg.wait_for_timeout(500)


async def k01(pg,r,ctx):
    await pg.wait_for_timeout(600); await r.start(); await pg.wait_for_timeout(900)
    await pg.mouse.click(195,449); await pg.wait_for_timeout(500); await typ(pg,"aurora",110)
    await pg.mouse.click(195,540); await pg.wait_for_timeout(500); await typ(pg,"Senha-Demo-123",90)
    await pg.wait_for_timeout(500); await pg.mouse.click(195,611); await pg.wait_for_timeout(4200)
    await pg.wait_for_timeout(4500)
async def k02(pg,r,ctx):
    await pg.wait_for_timeout(500); await r.start(); await pg.wait_for_timeout(1500)
    await scroll_by(pg,420,14); await pg.wait_for_timeout(1400)
    await scroll_by(pg,420,14); await pg.wait_for_timeout(1400)
    await scroll_by(pg,-840,18); await pg.wait_for_timeout(1000)
async def k03(pg,r,ctx):
    await tapt(pg,"Moderação","exact",wait=1800); await prep(pg)
    await r.start(); await pg.wait_for_timeout(1200)
    await field(pg,"Palavra para silenciar"); await typ(pg,"feia",130); await pg.wait_for_timeout(500)
    await tapt(pg,"Adicionar palavra",wait=1500)
    await scroll_by(pg,520,12); await pg.wait_for_timeout(1200)
    await prep(pg)
    await tapt(pg,"Ativar chata",wait=900); await pg.wait_for_timeout(600); await tapt(pg,"Ativar chata",wait=900)
    await scroll_by(pg,-520,12); await pg.wait_for_timeout(500); await prep(pg)
    await tapt(pg,"Banir (",wait=1100); await prep(pg)
    await field(pg,"Palavra para banir"); await typ(pg,"passa zap",110); await pg.wait_for_timeout(500)
    await tapt(pg,"Adicionar palavra",wait=1600)
    await tapt(pg,"Silenciar (",wait=1200); await pg.wait_for_timeout(800)
async def k04(pg,r,ctx):
    await tapt(pg,"Moderação","exact",wait=1800); await prep(pg)
    await scroll_by(pg,1500,26); await pg.wait_for_timeout(900); await prep(pg)
    await r.start(); await pg.wait_for_timeout(900)
    await tapt(pg,"Testar uma frase",wait=1400); await prep(pg)
    await pg.keyboard.type("SP4M gratis aqui",delay=95); await pg.wait_for_timeout(600)
    await tapt(pg,"Testar frase",wait=1800)
    await fclick(pg)
    await pg.keyboard.press("Control+a"); await pg.keyboard.type("ch4t4",delay=120); await pg.wait_for_timeout(500)
    await tapt(pg,"Testar frase",wait=1800)
    await fclick(pg)
    await pg.keyboard.press("Control+a"); await pg.keyboard.type("chatas",delay=120); await pg.wait_for_timeout(500)
    await tapt(pg,"Testar frase",wait=1800)
    await pg.keyboard.press("Escape"); await pg.wait_for_timeout(900); await prep(pg)
    await tapt(pg,"Como as regras funcionam",wait=1500)
    await scroll_by(pg,300,10,y=600); await pg.wait_for_timeout(1000)
    await scroll_by(pg,300,10,y=600); await pg.wait_for_timeout(1000)
async def k05(pg,r,ctx):
    await tapt(pg,"Moderação","exact",wait=1800); await prep(pg)
    await scroll_by(pg,1200,22); await pg.wait_for_timeout(500); await prep(pg)
    print(await pg.evaluate("[...document.querySelectorAll('flt-semantics')].filter(e=>e.getAttribute('role')=='switch').map(e=>e.getAttribute('aria-label')+' '+Math.round(e.getBoundingClientRect().top))"))
    await r.start(); await pg.wait_for_timeout(1200)
    await scroll_by(pg,300,10); await pg.wait_for_timeout(900)
    await prep(pg)
    await tapt(pg,"Banimento permanente",wait=1400); await pg.wait_for_timeout(900)
    await tapt(pg,"Banimento permanente",wait=1400); await pg.wait_for_timeout(900)


async def k07(pg,r,ctx):
    api("POST","/robot/disconnect")
    await pg.reload(wait_until="networkidle"); await pg.wait_for_timeout(5000); await prep(pg)
    await tapt(pg,"Robô","exact",wait=2000); await prep(pg)
    await r.start(); await pg.wait_for_timeout(1500)
    await tapt(pg,"Celular",wait=1100); await prep(pg)
    await pg.mouse.click(195,492); await pg.wait_for_timeout(500); await typ(pg,"11999999999",90); await pg.wait_for_timeout(900)
    await tapt(pg,"Código por e-mail",wait=1300); await prep(pg); await pg.wait_for_timeout(900)
    await tapt(pg,"E-mail e senha",wait=1200); await prep(pg)
    await pg.mouse.click(195,512); await pg.wait_for_timeout(500); await typ(pg,"robot@x.com",80); await pg.wait_for_timeout(500)
    await pg.mouse.click(180,602); await pg.wait_for_timeout(500); await typ(pg,"good",120); await pg.wait_for_timeout(700)
    await tapt(pg,"Mostrar senha",wait=1200); await tapt(pg,"Ocultar senha",wait=700)
    await tapt(pg,"Conectar robô",wait=300); await idle(pg,7500)

which=sys.argv[1:]
M={"k01":(k01,False),"k02":(k02,True),"k03":(k03,True),"k04":(k04,True),"k05":(k05,True),"k07":(k07,True)}
async def main():
    for k in which:
        fn,st=M[k]; print("==",k); await clip(k,fn,state=st)
asyncio.run(main())
