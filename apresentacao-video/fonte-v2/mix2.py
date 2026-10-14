import numpy as np, wave, json, subprocess, os, glob, sys
R="/tmp/claude-0/-home-user-secreto/5a577aff-184f-5ecc-81ef-0546d19cec6e/scratchpad"
V2=R+"/video2"; SR=44100
T=json.load(open(V2+"/timing.json")); total=T["_total"]; N=int(SR*total)
VO=sys.argv[1] if len(sys.argv)>1 else R+"/audio2/b"
rng=np.random.default_rng(7)
def rdw(p):
    tmp="/tmp/_v.wav"; subprocess.run(["ffmpeg","-v","error","-y","-i",p,"-ar",str(SR),"-ac","1",tmp],check=True)
    w=wave.open(tmp); a=np.frombuffer(w.readframes(w.getnframes()),dtype=np.int16).astype(np.float32)/32768; return a
def add(buf,sig,t,g=1.0):
    i=int(t*SR)
    if i<0 or i>=N: return
    j=min(N,i+len(sig)); buf[i:j]+=sig[:j-i]*g
def env_ad(n,a,d): t=np.arange(n)/SR; return np.minimum(1,t/max(a,1e-4))*np.exp(-t/d)
def lp(x,fc):
    a=np.exp(-2*np.pi*fc/SR); y=np.zeros_like(x); s=0.0
    for i in range(len(x)): s=(1-a)*x[i]+a*s; y[i]=s
    return y
note=lambda m:440*2**((m-69)/12)
# voice
voice=np.zeros(N,np.float32)
for k,s in T.items():
    if k=="_total": continue
    v=rdw(f"{VO}/{k}.wav"); v=v/max(np.abs(v).max(),1e-6)*0.9
    add(voice,v,s["start"]+s["voiceOffset"])
win=int(SR*0.05); act=np.convolve(np.abs(voice),np.ones(win)/win,'same')>0.02
duck=np.clip(np.convolve(act.astype(np.float32),np.ones(int(SR*0.4))/int(SR*0.4),'same')*1.6,0,1)
# music
bpm=76; beat=60/bpm
chords=[(62,[62,66,69]),(59,[59,62,66]),(55,[55,59,62]),(57,[57,61,64])]
def pluck(f,dur=1.4):
    n=int(SR*dur); t=np.arange(n)/SR
    return (np.sin(2*np.pi*f*t)+0.4*np.sin(2*np.pi*2*f*t)*np.exp(-t*6)+0.15*np.sin(2*np.pi*3*f*t)*np.exp(-t*9))*env_ad(n,0.004,0.35)
def pad(f,dur):
    n=int(SR*dur); t=np.arange(n)/SR; s=sum(np.sin(2*np.pi*f*d*t) for d in (1,1.003,0.997))/3
    return s*np.minimum(1,t/1.2)*np.minimum(1,(dur-t)/1.5)
def bell(f,dur=2.5):
    n=int(SR*dur); t=np.arange(n)/SR
    return (np.sin(2*np.pi*f*t)+0.5*np.sin(2*np.pi*f*2.76*t)*np.exp(-t*3))*env_ad(n,0.002,0.9)
level={}  # music level per scene
for k,s in T.items():
    if k=="_total": continue
    level[k]=(s["start"],s["start"]+s["dur"],{"s01":0.4,"s03":0.65,"s07":0.45,"s15":0.35,"s16":0.55}.get(k,0.5))
def lvl(t):
    for a,b,l in level.values():
        if a<=t<b: return l
    return 0.4
mus=np.zeros(N,np.float32); penta=[74,76,78,81,83,86]
bars=int(total/(beat*4))+1
for b in range(bars):
    t0=b*beat*4; root,ch=chords[b%4]; L=lvl(t0)
    for m in ch: add(mus,pad(note(m-12),beat*4+1.2),t0,0.10*L/0.5)
    add(mus,pluck(note(root-24),1.2),t0,0.22*L/0.5)
    seq=[ch[0]+12,ch[1]+12,ch[2]+12,ch[1]+12,ch[2]+12,ch[1]+12,ch[0]+24,ch[2]+12]
    for k,m in enumerate(seq):
        if L<0.45 and k%2: continue
        add(mus,pluck(note(m),1.1),t0+k*beat/2,0.10*L/0.5*(1.0 if k%2==0 else 0.8))
    if b%2==1 and t0>10: add(mus,bell(note(penta[(b*3)%6]),2.2),t0+beat*2.5,0.04)
fin=T["s16"]["start"]+0.3
for m in (50,57,62,66,69): add(mus,bell(note(m),6.0),fin,0.05)
mus*=(1-0.6*duck)
fade=np.ones(N,np.float32); fi=int(SR*1.2); fade[:fi]=np.linspace(0,1,fi); fo=int(SR*2.5); fade[-fo:]=np.linspace(1,0,fo); mus*=fade
# sfx
def whoosh(dur=0.9):
    n=int(SR*dur); x=rng.standard_normal(n).astype(np.float32)
    y=lp(x,900)*0.6+lp(x,3500)*0.4*np.linspace(0,1,n); return y*(np.sin(np.pi*np.linspace(0,1,n))**2)*3.0
def swoosh(): return whoosh(0.5)*0.8
def tick(): n=int(SR*0.05); t=np.arange(n)/SR; return np.sin(2*np.pi*2300*t)*np.exp(-t*90)*0.6
def pop(): n=int(SR*0.12); t=np.arange(n)/SR; f=520+700*t/0.12; return np.sin(2*np.pi*np.cumsum(f)/SR)*np.exp(-t*30)*0.8
def stamp():
    n=int(SR*0.35); t=np.arange(n)/SR; x=rng.standard_normal(n).astype(np.float32)
    return np.sin(2*np.pi*85*t)*np.exp(-t*16)*1.2+lp(x,1200)*np.exp(-t*40)*0.8
def chime(): return bell(988,1.6)*0.5+bell(1318,1.6)*0.3
def click(): n=int(SR*0.03); t=np.arange(n)/SR; return np.sin(2*np.pi*3200*t)*np.exp(-t*160)*0.7
def typek(): n=int(SR*0.03); t=np.arange(n)/SR; return (np.sin(2*np.pi*1800*t)+0.4*rng.standard_normal(n))*np.exp(-t*140)*0.35
def toggle(): return np.concatenate([click(),np.zeros(int(SR*0.04)),pop()*0.6])
FN={"whoosh":whoosh,"swoosh":swoosh,"tick":tick,"pop":pop,"stamp":stamp,"chime":chime,"click":click,"type":typek,"toggle":toggle}
sfx=np.zeros(N,np.float32); cnt=0
for k,s in T.items():
    if k=="_total": continue
    p=f"{V2}/atila2/compositions/{k}.sfx.json"
    if os.path.exists(p):
        for c in json.load(open(p)):
            f=FN.get(c["type"]); 
            if f: add(sfx,f(),s["start"]+c["t"],c.get("gain",0.3)); cnt+=1
bounds=[T[k]["start"] for k in T if k not in("_total","s01")]
for b in bounds: add(sfx,whoosh(),b-0.55,0.3)
print("sfx cues",cnt,"+",len(bounds),"whooshes")
mix=voice*0.95+mus*0.95+sfx*0.55
st=np.stack([mix,mix],1); st[:,0]+=mus*0.04; st[:,1]-=mus*0.04
st=np.clip(st,-1,1)
w=wave.open("/tmp/mix_raw2.wav","wb"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes((st*32767).astype(np.int16).tobytes()); w.close()
subprocess.run(["ffmpeg","-v","error","-y","-i","/tmp/mix_raw2.wav","-af","loudnorm=I=-14:TP=-1.5:LRA=9","-ar","48000",V2+"/atila2/assets/mix.wav"],check=True)
print("mix ok")
