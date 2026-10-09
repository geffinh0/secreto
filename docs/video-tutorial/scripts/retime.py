# Cut master_MODE.mp4 per scene; scenes whose actions overran the narration are sped up to fit.
import json, sys, subprocess, os
M = sys.argv[1]
d = json.load(open(f'/tmp/claude-0/demo/frames_{M}.json')); t0 = d['frames'][0]['t']; m = d['marks']; ks = list(m)
src = f'/tmp/claude-0/demo/master_{M}.mp4'
total = float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0',src]))
segs = []; slots = {}
os.makedirs('/tmp/claude-0/demo/seg', exist_ok=True)
for i, k in enumerate(ks):
    a = m[k]['page'] - t0
    b = (m[ks[i + 1]]['page'] - t0) if i + 1 < len(ks) else min(total, a + m[k]['dur'] + 1.5)
    act = b - a; want = m[k]['dur']
    slot = want if act > want + 0.3 else act
    if k == ks[-1]: slot = act
    f = act / slot
    out = f'/tmp/claude-0/demo/seg/{M}_{i:02d}.mp4'
    subprocess.run(['ffmpeg','-y','-loglevel','error','-ss',f'{a:.3f}','-i',src,'-t',f'{act:.3f}','-vf',f'setpts=PTS/{f:.5f},fps=30'+(',tpad=stop_mode=clone:stop_duration=5' if k==ks[-1] else ''),'-t',f'{slot + (5 if k==ks[-1] else 0):.3f}','-c:v','libx264','-preset','medium','-crf','16','-g','30','-pix_fmt','yuv420p','-an',out], check=True)
    segs.append(out); slots[k] = round(slot, 3)
    print(k, round(act, 2), '->', round(slot, 2), f'x{f:.2f}')
with open(f'/tmp/claude-0/demo/seg/{M}.txt', 'w') as o:
    for s in segs: o.write(f"file '{s}'\n")
dst = f'/tmp/claude-0/hf/{"cine" if M=="cine" else M}/assets/rec/screen.mp4'
subprocess.run(['ffmpeg','-y','-loglevel','error','-f','concat','-safe','0','-i',f'/tmp/claude-0/demo/seg/{M}.txt','-c','copy',dst], check=True)
# real per-segment durations after encode
real = {}
for k, s in zip(ks, segs):
    real[k] = float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0',s]))
json.dump(real, open(f'/tmp/claude-0/hf/build/slots_{M}.json', 'w'), indent=1)
subprocess.run(['ffmpeg','-y','-loglevel','error','-i',dst,'-frames:v','1','-q:v','2',f'/tmp/claude-0/hf/{M}/assets/img/first.jpg'], check=True)
print('screen', subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0',dst]).decode().strip())
