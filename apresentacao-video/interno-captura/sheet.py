import sys, subprocess, glob, os
from PIL import Image
clip=sys.argv[1]; n=int(sys.argv[2]) if len(sys.argv)>2 else 10
d=subprocess.check_output(["ffprobe","-v","error","-show_entries","format=duration","-of","csv=p=0",clip]).decode().strip(); d=float(d)
out=f"/tmp/sh_{os.path.basename(clip)}"; os.makedirs(out,exist_ok=True)
ims=[]
for i in range(n):
    t=d*(i+0.5)/n; f=f"{out}/{i}.png"
    subprocess.run(["ffmpeg","-v","error","-y","-ss",f"{t:.2f}","-i",clip,"-frames:v","1","-vf","scale=260:-1",f],check=True); ims.append(Image.open(f))
w,h=ims[0].size; cols=min(n,8); rows=(n+cols-1)//cols
s=Image.new("RGB",(w*cols,h*rows),"white")
for i,im in enumerate(ims): s.paste(im,((i%cols)*w,(i//cols)*h))
p=out+".jpg"; s.save(p,quality=82); print(p,round(d,1))
