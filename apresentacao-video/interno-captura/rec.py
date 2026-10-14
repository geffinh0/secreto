import asyncio, base64, os, json, subprocess, shutil, time
from playwright.async_api import async_playwright
ROOT="/tmp/claude-0/-home-user-secreto/5a577aff-184f-5ecc-81ef-0546d19cec6e/scratchpad"
OUT=ROOT+"/cap"; CL=OUT+"/clips"
CHROME="/opt/pw-browsers/chromium-1194/chrome-linux/chrome"
K=0.4235
async def new_ctx(p, state=True):
    b=await p.chromium.launch(executable_path=CHROME,args=["--no-sandbox","--proxy-bypass-list=<-loopback>","--force-device-scale-factor="+os.environ.get("DSF","3"),"--hide-scrollbars"])
    ctx=await b.new_context(storage_state=(OUT+"/state.json") if state else None,no_viewport=True,locale="pt-BR",has_touch=True)
    pg=await ctx.new_page()
    await pg.route("**/fonts.gstatic.com/**",lambda r:r.abort())
    return b,ctx,pg
async def mobile(pg):
    cdp=await pg.context.new_cdp_session(pg)
    await cdp.send("Emulation.setDeviceMetricsOverride",{"width":390,"height":844,"deviceScaleFactor":int(os.environ.get("DSF","3")),"mobile":True})
    await pg.wait_for_timeout(1000)
class Rec:
    def __init__(s,pg,name): s.pg=pg; s.name=name; s.frames=[]; s.t0=None
    async def start(s):
        s.cdp=await s.pg.context.new_cdp_session(s.pg)
        async def on(ev):
            s.frames.append((ev["metadata"]["timestamp"],ev["data"]))
            try: await s.cdp.send("Page.screencastFrameAck",{"sessionId":ev["sessionId"]})
            except Exception: pass
        s.cdp.on("Page.screencastFrame",lambda ev: asyncio.ensure_future(on(ev)))
        await s.cdp.send("Page.startScreencast",{"format":"jpeg","quality":92,"maxWidth":390*int(os.environ.get("DSF","3")),"maxHeight":844*int(os.environ.get("DSF","3")),"everyNthFrame":1})
    async def stop(s):
        await s.cdp.send("Page.stopScreencast"); await asyncio.sleep(0.3)
        d=f"{CL}/{s.name}_frames"; shutil.rmtree(d,ignore_errors=True); os.makedirs(d)
        lst=[]
        for i,(t,data) in enumerate(s.frames):
            open(f"{d}/{i:05d}.jpg","wb").write(base64.b64decode(data))
        for i,(t,_) in enumerate(s.frames):
            dur=(s.frames[i+1][0]-t) if i+1<len(s.frames) else 0.1
            lst.append(f"file '{d}/{i:05d}.jpg'\nduration {max(dur,0.001):.4f}")
        lst.append(f"file '{d}/{len(s.frames)-1:05d}.jpg'")
        open(f"{d}/list.txt","w").write("\n".join(lst))
        out=f"{CL}/{s.name}.mp4"
        subprocess.run(["ffmpeg","-v","error","-y","-f","concat","-safe","0","-i",f"{d}/list.txt","-vf","fps=30,format=yuv420p","-c:v","libx264","-crf","14","-preset","fast",out],check=True)
        dur=s.frames[-1][0]-s.frames[0][0]
        print(s.name,len(s.frames),"frames",round(dur,2),"s",round(len(s.frames)/max(dur,0.01),1),"fps")
        shutil.rmtree(d,ignore_errors=True)
async def tap(pg,x,y,wait=500): await pg.mouse.click(x,y); await pg.wait_for_timeout(wait)
async def boot(pg):
    await pg.goto("http://localhost:3000",wait_until="networkidle"); await pg.wait_for_timeout(5000)
    await mobile(pg); await pg.wait_for_timeout(1200)
