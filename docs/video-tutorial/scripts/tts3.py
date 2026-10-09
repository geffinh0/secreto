"""Mobile/cinematic narration with the Piper pt_BR 'cadu' voice (sherpa-onnx), studio-processed."""
import json, subprocess, os, re, glob
import sherpa_onnx, soundfile as sf
B = "/tmp/claude-0/hf/build"; OUT = "/tmp/claude-0/hf/cine/assets/vo"
script = json.load(open(f"{B}/script2.json"))
MOBILE = [(r"\bclica\b", "toca"), (r"\bclico\b", "toco"), (r"\bclicar\b", "tocar"), (r"aqui do lado", "aqui embaixo"), (r"\bClica\b", "Toca")]
GAP, SPEED = 0.32, 1.06
d = "/tmp/claude-0/tts/vits-piper-pt_BR-cadu-medium"
tts = sherpa_onnx.OfflineTts(sherpa_onnx.OfflineTtsConfig(model=sherpa_onnx.OfflineTtsModelConfig(
    vits=sherpa_onnx.OfflineTtsVitsModelConfig(model=glob.glob(f"{d}/*.onnx")[0], tokens=f"{d}/tokens.txt", data_dir=f"{d}/espeak-ng-data",
                                               noise_scale=0.72, noise_scale_w=0.9, length_scale=1.0), num_threads=4)))
os.makedirs(f"{B}/lines3", exist_ok=True)
def dur(p): return float(subprocess.check_output(["ffprobe","-v","error","-show_entries","format=duration","-of","csv=p=0",p]).decode())
def mob(t):
    for a, b in MOBILE: t = re.sub(a, b, t)
    return t
sil = f"{B}/lines3/sil.wav"
subprocess.run(["ffmpeg","-y","-loglevel","error","-f","lavfi","-i","anullsrc=r=48000:cl=mono","-t",str(GAP),sil], check=True)
timing = {}
for sc in script:
    t = 0.0; caps = []; parts = []
    for i, (spoken, cap) in enumerate(sc["lines"]):
        spoken, cap = mob(spoken), mob(cap)
        raw = f"{B}/lines3/{sc['id']}_{i}_raw.wav"; p = f"{B}/lines3/{sc['id']}_{i}.wav"
        a = tts.generate(spoken, sid=0, speed=SPEED); sf.write(raw, a.samples, a.sample_rate)
        # studio chain: trim edges, warm EQ, gentle compression, 48k
        subprocess.run(["ffmpeg","-y","-loglevel","error","-i",raw,"-af",
            "silenceremove=start_periods=1:start_threshold=-45dB,areverse,silenceremove=start_periods=1:start_threshold=-45dB,areverse,"
            "highpass=f=70,equalizer=f=180:t=q:w=1:g=2,equalizer=f=3500:t=q:w=1.2:g=2.5,deesser=i=0.3,"
            "acompressor=threshold=-20dB:ratio=3:attack=5:release=120:makeup=3,aresample=48000","-ac","1",p], check=True)
        dd = dur(p); caps.append({"text": cap, "start": round(t, 3), "end": round(t + dd, 3)}); parts.append(p); t += dd + GAP
    lst = f"{B}/lines3/{sc['id']}.txt"
    with open(lst, "w") as f:
        for p in parts: f.write(f"file '{p}'\nfile '{sil}'\n")
    out = f"{OUT}/{sc['id']}.wav"
    subprocess.run(["ffmpeg","-y","-loglevel","error","-f","concat","-safe","0","-i",lst,"-af","loudnorm=I=-16:TP=-1.5:LRA=9","-ar","48000","-ac","1",out], check=True)
    timing[sc["id"]] = {"duration": round(dur(out), 3), "captions": caps}
json.dump(timing, open(f"{B}/timing_cine.json", "w"), ensure_ascii=False, indent=1)
print("total", round(sum(v["duration"] for v in timing.values()), 1))
