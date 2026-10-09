# usage: master.sh MODE  -> builds master_MODE.mp4 from screencast frames
M=$1; cd /tmp/claude-0/demo
python3 - $M <<'PY'
import json,sys
M=sys.argv[1]; d=json.load(open(f'frames_{M}.json')); f=d['frames']
with open(f'concat_{M}.txt','w') as o:
    for i,fr in enumerate(f):
        dur=(f[i+1]['t']-fr['t']) if i+1<len(f) else 2.0
        o.write(f"file '{fr['file']}'\nduration {max(dur,0.001):.4f}\n")
    o.write(f"file '{f[-1]['file']}'\n")
print('t0', f[0]['t'])
PY
ffmpeg -y -loglevel error -f concat -safe 0 -i concat_$M.txt -vf "fps=30,scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p" -c:v libx264 -preset medium -crf 16 -g 30 master_$M.mp4
ffprobe -v error -show_entries format=duration -of csv=p=0 master_$M.mp4
