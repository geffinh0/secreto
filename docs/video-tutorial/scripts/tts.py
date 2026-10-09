import json, subprocess, os, sys
B="/tmp/claude-0/hf/build"; OUT="/tmp/claude-0/hf/tutorial/assets/vo"
script=json.load(open(f"{B}/script.json"))
os.makedirs(f"{B}/lines", exist_ok=True)
GAP=0.30
timing={}
def dur(p): return float(subprocess.check_output(["ffprobe","-v","error","-show_entries","format=duration","-of","csv=p=0",p]).decode())
for sc in script:
    parts=[]; t=0.0; caps=[]
    for i,(tts,cap) in enumerate(sc["lines"]):
        p=f"{B}/lines/{sc['id']}_{i}.wav"
        if not os.path.exists(p):
            subprocess.run(["npx","hyperframes","tts",tts,"--voice","pf_dora","--lang","pt-br","--speed","1.05","-o",p],check=True,capture_output=True,cwd=B)
        d=dur(p); caps.append({"text":cap,"start":round(t,3),"end":round(t+d,3)}); parts.append(p); t+=d+GAP
    # concat with gaps
    lst=f"{B}/lines/{sc['id']}.txt"
    sil=f"{B}/lines/sil.wav"
    if not os.path.exists(sil):
        subprocess.run(["ffmpeg","-y","-f","lavfi","-i","anullsrc=r=24000:cl=mono","-t",str(GAP),sil],check=True,capture_output=True)
    with open(lst,"w") as f:
        for p in parts: f.write(f"file '{p}'\nfile '{sil}'\n")
    out=f"{OUT}/{sc['id']}.wav"
    subprocess.run(["ffmpeg","-y","-f","concat","-safe","0","-i",lst,"-ar","48000","-ac","1",out],check=True,capture_output=True)
    timing[sc["id"]]={"duration":round(dur(out),3),"captions":caps}
    print(sc["id"], timing[sc["id"]]["duration"], flush=True)
json.dump(timing,open(f"{B}/timing.json","w"),ensure_ascii=False,indent=1)
print("total", sum(v["duration"] for v in timing.values()))
