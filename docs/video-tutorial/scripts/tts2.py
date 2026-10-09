"""Narration for both versions. Mobile swaps 'clica' for 'toca' etc. Writes per-variant wavs + timing."""
import json, subprocess, os, re, sys
B = "/tmp/claude-0/hf/build"
script = json.load(open(f"{B}/script2.json"))
MOBILE = [(r"\bclica\b", "toca"), (r"\bclico\b", "toco"), (r"\bclicar\b", "tocar"),
          (r"aqui do lado", "aqui embaixo"), (r"\bClica\b", "Toca")]
GAP = 0.28
VOICE, SPEED = "pf_dora", "1.08"

def dur(p):
    return float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", p]).decode())

def variant(text, v):
    if v == "mobile":
        for a, b in MOBILE:
            text = re.sub(a, b, text)
    return text

def build(v):
    out_dir = f"/tmp/claude-0/hf/{v}/assets/vo"; os.makedirs(out_dir, exist_ok=True)
    os.makedirs(f"{B}/lines2", exist_ok=True)
    sil = f"{B}/lines2/sil.wav"
    if not os.path.exists(sil):
        subprocess.run(["ffmpeg", "-y", "-f", "lavfi", "-i", "anullsrc=r=24000:cl=mono", "-t", str(GAP), sil], check=True, capture_output=True)
    timing = {}
    for sc in script:
        t = 0.0; caps = []; parts = []
        for tts, cap in sc["lines"]:
            tts, cap = variant(tts, v), variant(cap, v)
            key = re.sub(r"[^a-z0-9]+", "_", tts.lower())[:60] + f"_{abs(hash(tts)) % 10**8}"
            p = f"{B}/lines2/{key}.wav"
            if not os.path.exists(p):
                subprocess.run(["npx", "hyperframes", "tts", tts, "--voice", VOICE, "--lang", "pt-br", "--speed", SPEED, "-o", p], check=True, capture_output=True, cwd=B)
            d = dur(p); caps.append({"text": cap, "start": round(t, 3), "end": round(t + d, 3)}); parts.append(p); t += d + GAP
        lst = f"{B}/lines2/{v}_{sc['id']}.txt"
        with open(lst, "w") as f:
            for p in parts: f.write(f"file '{p}'\nfile '{sil}'\n")
        out = f"{out_dir}/{sc['id']}.wav"
        subprocess.run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", lst, "-ar", "48000", "-ac", "1", out], check=True, capture_output=True)
        timing[sc["id"]] = {"duration": round(dur(out), 3), "captions": caps}
    json.dump(timing, open(f"{B}/timing_{v}.json", "w"), ensure_ascii=False, indent=1)
    print(v, round(sum(x["duration"] for x in timing.values()), 1))

for v in sys.argv[1:] or ["desktop", "mobile"]:
    build(v)
