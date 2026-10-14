import asyncio, os
from rec2 import *
async def fclick(pg):
    bp=await pos(pg,'Testar frase'); await pg.mouse.move(195,bp[1]-40,steps=6); await pg.mouse.click(195,bp[1]-40); await pg.wait_for_timeout(500)
S=OUT+"/stills/"
async def shot3(pg,name): await pg.wait_for_timeout(700); await pg.screenshot(path=S+name+".png")
async def main():
    os.environ["DSF"]="2"
    async with async_playwright() as p:
        b,ctx,pg=await new_ctx(p,state=True); await boot2(pg)
        await tapt(pg,"Moderação","exact",wait=1800); await prep(pg)
        await scroll_by(pg,1700,26); await idle(pg,1800); await prep(pg)
        await tapt(pg,"Testar uma frase",wait=1600); await prep(pg)
        for txt,name in (("SP4M gratis aqui","teste_ban"),("ch4t4","teste_mute"),("chatas","teste_none")):
            if name!="teste_ban":
                await fclick(pg); await pg.keyboard.press("Control+a")
            await pg.keyboard.type(txt,delay=40); await pg.wait_for_timeout(900); await prep(pg)
            await tapt(pg,"Testar frase",wait=1800); await shot3(pg,name); await prep(pg)
        await pg.keyboard.press("Escape"); await pg.wait_for_timeout(900); await prep(pg)
        await tapt(pg,"Como as regras funcionam",wait=1500); await shot3(pg,"como_regras")
        await scroll_by(pg,420,10,y=600); await shot3(pg,"como_regras2")
        await pg.keyboard.press("Escape"); await pg.wait_for_timeout(800); await prep(pg)
        await tapt(pg,"Mais","exact",wait=1300); await shot3(pg,"mais")
        await prep(pg); await tapt(pg,"Configurações",wait=2200); await prep(pg)
        for i in range(3): await scroll_by(pg,520,16); await idle(pg,400)
        await scroll_by(pg,700,20); await idle(pg,600); await shot3(pg,"atividade")
        await b.close()
asyncio.run(main())
