"""Splits the user's single ElevenLabs narration into per-scene wavs + caption timing (timing_eleven.json)."""
import json, re, subprocess, os
SRC = "/root/.claude/uploads/f6cfd08d-13bd-5186-bd8d-0d98098f778f/412eb76e-ElevenLabs_2026-10-10T00_57_00_Ana_Alice_-_Friendly__Clear_pvc_sp100_s35_sb75_se6_b_m2.mp3"
OUT = "/tmp/claude-0/hf/eleven/assets/vo"; os.makedirs(OUT, exist_ok=True)
B = "/tmp/claude-0/hf/build"
script = json.load(open(f"{B}/script2.json"))
MOB = [(r"\bclica\b", "toca"), (r"\bclico\b", "toco"), (r"\bclicar\b", "tocar"), (r"aqui do lado", "aqui embaixo"), (r"\bClica\b", "Toca")]
# (start, end) of every spoken line, from the Whisper transcript of the narration
L = {
 'intro': [(0.00, 6.96), (7.50, 13.05)],
 'como': [(13.70, 15.06), (15.52, 21.14), (21.81, 32.08), (32.78, 39.36)],
 'acessar': [(40.12, 42.81), (43.34, 47.75), (48.37, 56.23)],
 'conta': [(56.66, 58.87), (59.60, 62.63), (63.24, 69.05)],
 'dash': [(69.57, 71.70), (72.29, 81.38), (82.06, 88.46)],
 'silenciar': [(89.14, 92.49), (93.32, 98.10), (98.94, 101.32), (101.86, 104.28)],
 'regras': [(104.80, 108.84), (109.51, 115.36), (116.04, 125.59)],
 'banir': [(126.54, 130.96), (131.56, 133.83), (134.46, 144.35)],
 'mensagens': [(144.84, 148.91), (149.24, 158.45), (159.22, 164.50)],
 'robo': [(165.11, 170.17), (171.03, 179.84), (180.47, 183.41), (183.92, 186.12)],
 'moderador': [(186.72, 190.36), (191.06, 200.14)],
 'favoritar': [(200.82, 203.95), (204.71, 208.81), (209.39, 213.34), (213.88, 220.57)],
 'aovivo': [(221.16, 225.78), (226.33, 231.43), (231.89, 236.17)],
 'painel': [(237.09, 240.18), (240.67, 246.58), (247.09, 251.39)],
 'final': [(252.26, 255.38), (256.33, 266.57), (267.21, 273.70)],
}
PRE, POST = 0.06, 0.25
timing = {}
for sc in script:
    k = sc['id']; lines = L[k]; assert len(lines) == len(sc['lines']), k
    a, b = lines[0][0] - PRE, lines[-1][1] + POST
    a = max(0, a)
    out = f"{OUT}/{k}.wav"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-ss", f"{a:.3f}", "-t", f"{b - a:.3f}", "-i", SRC,
                    "-af", "afade=t=in:d=0.02,areverse,afade=t=in:d=0.08,areverse,highpass=f=60", "-ar", "48000", "-ac", "1", out], check=True)
    caps = []
    for (s, e), (_, cap) in zip(lines, sc['lines']):
        for x, y in MOB: cap = re.sub(x, y, cap)
        caps.append({"text": cap, "start": round(s - a, 3), "end": round(e - a, 3)})
    timing[k] = {"duration": round(b - a, 3), "captions": caps}
json.dump(timing, open(f"{B}/timing_eleven.json", "w"), ensure_ascii=False, indent=1)
print({k: v['duration'] for k, v in timing.items()}, round(sum(v['duration'] for v in timing.values()), 1))
