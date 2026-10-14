import numpy as np, wave, subprocess
SR=44100; DUR=63.5; N=int(SR*DUR)
rng=np.random.default_rng(7)
def rd(p):
    w=wave.open(p); a=np.frombuffer(w.readframes(w.getnframes()),dtype=np.int16).astype(np.float32)/32768; return a
def add(buf,sig,t,g=1.0):
    i=int(t*SR); j=min(N,i+len(sig))
    if i<N and j>i: buf[i:j]+=sig[:j-i]*g
def env_ad(n,a,d):  # attack/decay exp
    t=np.arange(n)/SR; e=np.minimum(1,t/max(a,1e-4))*np.exp(-t/d); return e
def lp(x,fc):
    a=np.exp(-2*np.pi*fc/SR); y=np.zeros_like(x); s=0.0
    for i in range(len(x)): s=(1-a)*x[i]+a*s; y[i]=s
    return y
# ---------------- voice
vstarts=[0.15,4.05,9.05,20.05,29.25,38.25,52.05,57.05]
voice=np.zeros(N,np.float32)
for k,s in enumerate(vstarts):
    v=rd(f"r_v0{k+1}.wav"); v=v/max(np.abs(v).max(),1e-6)*0.9
    add(voice,v,s)
# voice activity for ducking
win=int(SR*0.05); act=np.convolve(np.abs(voice),np.ones(win)/win,'same')>0.02
duck=np.convolve(act.astype(np.float32),np.ones(int(SR*0.35))/int(SR*0.35),'same'); duck=np.clip(duck*1.6,0,1)
# ---------------- music
bpm=76; beat=60/bpm
note=lambda m:440*2**((m-69)/12)
chords=[(62,[62,66,69]),(59,[59,62,66]),(55,[55,59,62]),(57,[57,61,64])]  # D, Bm, G, A
mus=np.zeros(N,np.float32)
def pluck(f,dur=1.4):
    n=int(SR*dur); t=np.arange(n)/SR
    s=np.sin(2*np.pi*f*t)+0.4*np.sin(2*np.pi*2*f*t)*np.exp(-t*6)+0.15*np.sin(2*np.pi*3*f*t)*np.exp(-t*9)
    return s*env_ad(n,0.004,0.35)
def pad(f,dur):
    n=int(SR*dur); t=np.arange(n)/SR
    s=sum(np.sin(2*np.pi*f*d*t) for d in (1,1.003,0.997))/3
    e=np.minimum(1,t/1.2)*np.minimum(1,(dur-t)/1.5); return s*e
def bell(f,dur=2.5):
    n=int(SR*dur); t=np.arange(n)/SR
    return (np.sin(2*np.pi*f*t)+0.5*np.sin(2*np.pi*f*2.76*t)*np.exp(-t*3))*env_ad(n,0.002,0.9)
bars=int(DUR/(beat*4))+1
penta=[74,76,78,81,83,86]
for b in range(bars):
    t0=b*beat*4; root,ch=chords[b%4]
    lvl=0.35 if t0<9 else (0.55 if t0<57 else 0.5)
    for m in ch: add(mus,pad(note(m-12),beat*4+1.2),t0,0.09*lvl/0.55)
    add(mus,pluck(note(root-24),1.2),t0,0.22*lvl)
    seq=[ch[0]+12,ch[1]+12,ch[2]+12,ch[1]+12,ch[2]+12,ch[1]+12,ch[0]+24,ch[2]+12]
    for k,m in enumerate(seq):
        if t0<4 and k%2: continue
        add(mus,pluck(note(m),1.1),t0+k*beat/2,0.10*lvl/0.55*(1.0 if k%2==0 else 0.8))
    if b%2==1 and t0>12 and t0<57:
        add(mus,bell(note(penta[(b*3)%6]),2.2),t0+beat*2.5,0.045)
# final resolve: D major chord ring at 57
for m in (50,57,62,66,69): add(mus,bell(note(m),5.0),57.2,0.05)
mus*= (1-0.62*duck)
fade=np.ones(N,np.float32); fi=int(SR*1.0); fade[:fi]=np.linspace(0,1,fi); fo=int(SR*2.0); fade[-fo:]=np.linspace(1,0,fo)
mus*=fade
# ---------------- sfx
sfx=np.zeros(N,np.float32)
def whoosh(dur=0.55):
    n=int(SR*dur); x=rng.standard_normal(n).astype(np.float32)
    y=lp(x,900)*0.6+lp(x,3500)*0.4*np.linspace(0,1,n)
    e=np.sin(np.pi*np.linspace(0,1,n))**2; return y*e*3.0
def tick():
    n=int(SR*0.05); t=np.arange(n)/SR; return np.sin(2*np.pi*2300*t)*np.exp(-t*90)*0.6
def pop():
    n=int(SR*0.12); t=np.arange(n)/SR; f=520+700*t/0.12; return np.sin(2*np.pi*np.cumsum(f)/SR)*np.exp(-t*30)*0.8
def stamp():
    n=int(SR*0.35); t=np.arange(n)/SR; x=rng.standard_normal(n).astype(np.float32)
    return (np.sin(2*np.pi*85*t)*np.exp(-t*16)*1.2+lp(x,1200)*np.exp(-t*40)*0.8)
def chime(): return bell(988,1.6)*0.5+bell(1318,1.6)*0.3
def click():
    n=int(SR*0.03); t=np.arange(n)/SR; return np.sin(2*np.pi*3200*t)*np.exp(-t*160)*0.7
W=[3.85,8.85,19.85,29.05,38.05,51.85,56.85]
for t in W: add(sfx,whoosh(),t,0.35)
for i in range(8): add(sfx,tick(),0.55+i*0.28,0.18)
for t in (1.3,1.9,2.4,3.0,3.4): add(sfx,tick(),t+0.0,0.14)
for t in (4.3,4.9,5.4,5.8,6.3,6.6,7.1,7.4,7.8): add(sfx,tick(),t,0.2)
add(sfx,chime(),9.3,0.5)
for t in (12.7,14.0,15.4): add(sfx,pop(),t,0.35)
add(sfx,stamp(),16.6,0.5)
for t in (20.35,20.9,22.9,24.5,26.4): add(sfx,pop(),t,0.3)
add(sfx,stamp(),22.9+0.7,0.5); add(sfx,stamp(),21.9,0.4)
add(sfx,pop(),29.5,0.3)
for t in (32.6,33.3,34.0,34.7): add(sfx,tick(),t,0.4); add(sfx,pop(),t,0.15)
add(sfx,pop(),34.85,0.3); add(sfx,chime(),36.5,0.3)
for t in (38.5,40.4,42.1): add(sfx,pop(),t,0.3)
add(sfx,chime(),44.4,0.4); add(sfx,stamp(),45.9,0.45); add(sfx,pop(),46.8,0.3); add(sfx,pop(),48.45,0.35)
add(sfx,click(),53.4,0.7); add(sfx,pop(),53.9,0.3)
add(sfx,chime(),57.3,0.5); add(sfx,pop(),59.65,0.4)
mix=voice*0.95+mus*0.95+sfx*0.55
mix=np.stack([mix,mix],1)
# slight stereo width on music
mix[:,0]+=mus*0.04; mix[:,1]-=mus*0.04
mix=np.clip(mix,-1,1)
w=wave.open("mix_raw.wav","wb"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes((mix*32767).astype(np.int16).tobytes()); w.close()
print("ok")
