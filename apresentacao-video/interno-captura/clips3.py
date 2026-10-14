import asyncio, sys
from rec2 import *
def C(u,n,t): return lambda: chat(u,n,t)
async def k02b(pg,r,ctx):
    await tapt(pg,"Painel","exact",wait=1500); await prep(pg)
    await r.start(); await idle(pg,1200)
    ev=[(1500,C("u21","Lia","SP4M gratis aqui")),(4200,C("u22","Gabi","que live chata"))]
    await play(pg,ev,6500)
    await scroll_by(pg,520,14); await idle(pg,2000)
    await scroll_by(pg,-520,14); await idle(pg,1500)
async def k06(pg,r,ctx):
    await tapt(pg,"Mais","exact",wait=1300); await prep(pg)
    await r.start(); await idle(pg,900)
    await tapt(pg,"Mensagens automáticas",wait=1800); await prep(pg)
    await idle(pg,1000)
    for t in ("30 s","1 min","5 min","2 min"):
        await tapt(pg,t,"exact",wait=900); await prep(pg)
    await scroll_by(pg,520,14); await idle(pg,700); await prep(pg)
    bp=await pos(pg,"Adicionar à fila")
    await pg.mouse.move(195,bp[1]-50,steps=8); await pg.mouse.click(195,bp[1]-50); await pg.wait_for_timeout(500)
    await typ(pg,"Respeito sempre, combinado?",85); await pg.wait_for_timeout(700)
    await tapt(pg,"Adicionar à fila",wait=1800); await prep(pg)
    await scroll_by(pg,380,12); await idle(pg,900); await prep(pg)
    p=await pos(pg,"Respeito sempre")
    print("new msg row",p)
    await scroll_by(pg,0,1)
    r2=await pos(pg,"Bem-vindos")
    print("last row",r2)
    if r2:
        y=r2[1]; await pg.mouse.move(56,y,steps=6); await pg.mouse.down(); await pg.wait_for_timeout(300)
        await pg.mouse.move(56,y-90,steps=14); await pg.wait_for_timeout(300); await pg.mouse.move(56,y-180,steps=14); await pg.wait_for_timeout(400); await pg.mouse.up(); await idle(pg,1800)
async def k10(pg,r,ctx):
    await tapt(pg,"Mais","exact",wait=1300); await prep(pg)
    await tapt(pg,"Estatísticas",wait=2500); await prep(pg)
    await r.start(); await idle(pg,2200)
    await scroll_by(pg,420,14); await idle(pg,1500); await scroll_by(pg,420,14); await idle(pg,1500)
    await scroll_by(pg,-840,18); await idle(pg,800); await prep(pg)
    await tapt(pg,"7 dias",wait=2200); await prep(pg); await tapt(pg,"90 dias",wait=2200); await prep(pg); await tapt(pg,"30 dias",wait=2000)
async def k11(pg,r,ctx):
    await tapt(pg,"Mais","exact",wait=1300); await prep(pg)
    await tapt(pg,"Configurações",wait=2200); await prep(pg)
    await r.start(); await idle(pg,1800)
    for i in range(4):
        await scroll_by(pg,520,16); await idle(pg,1300)
    await scroll_by(pg,-2080,30); await idle(pg,800)
async def k12(pg,r,ctx):
    await r.start(); await idle(pg,700)
    await tapt(pg,"Mais","exact",wait=1800); await idle(pg,1500)
which=sys.argv[1:]
M={"k02b":k02b,"k06":k06,"k10":k10,"k11":k11,"k12":k12}
async def main():
    for k in which:
        print("==",k); await clip(k,M[k],state=True)
asyncio.run(main())
