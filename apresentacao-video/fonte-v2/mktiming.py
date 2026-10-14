import json, subprocess, re, sys, os, wave
R="/tmp/claude-0/-home-user-secreto/5a577aff-184f-5ecc-81ef-0546d19cec6e/scratchpad"
VO=sys.argv[1] if len(sys.argv)>1 else R+"/audio2/b"
S=json.load(open(R+"/audio2/script.json"))
tail={"s01":2.2,"s03":2.4,"s04":2.0,"s07":1.8,"s15":2.0,"s16":3.5}
mindur={"s14":7.0}
LEAD=0.5
t=0.0; out={}
for sid,text in S:
    f=f"{VO}/{sid}.wav"
    w=wave.open(f); L=w.getnframes()/w.getframerate(); w.close()
    sil=subprocess.run(["ffmpeg","-hide_banner","-nostats","-i",f,"-af","silencedetect=n=-38dB:d=0.14","-f","null","-"],capture_output=True,text=True).stderr
    ends=[float(x) for x in re.findall(r"silence_end: ([0-9.]+)",sil)]
    starts=[float(x) for x in re.findall(r"silence_start: ([0-9.]+)",sil)]
    dur=max(LEAD+L+tail.get(sid,1.3),mindur.get(sid,0))
    dur=round(dur*30)/30
    out[sid]={"start":round(t,3),"dur":dur,"voiceOffset":LEAD,"voiceLen":round(L,3),"voiceStart":LEAD,"voiceEnd":round(LEAD+L,3),
              "phraseStarts":[round(LEAD+e,2) for e in ends if e<L-0.2],"phraseEnds":[round(LEAD+s,2) for s in starts if s>0.1],"text":text}
    t+=dur
out["_total"]=round(t,3)
json.dump(out,open(R+"/video2/timing.json","w"),indent=1,ensure_ascii=False)
print("total",round(t,1)); [print(k,v["start"],v["dur"],v["phraseStarts"]) for k,v in out.items() if k!="_total"]
