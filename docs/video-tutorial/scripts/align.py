"""Align script lines to the 3 Gemini narration blocks (silence chunks + Whisper + DP), cut per-scene wavs."""
import json, re, subprocess, os, difflib, unicodedata
import numpy as np, soundfile as sf, sherpa_onnx
B = '/tmp/claude-0/hf/build'; G = '/tmp/claude-0/gem'; OUT = '/tmp/claude-0/hf/gem/assets/vo'; os.makedirs(OUT, exist_ok=True)
script = json.load(open(f'{B}/script2.json'))
MOB = [(r"\bclica\b", "toca"), (r"\bclico\b", "toco"), (r"\bclicar\b", "tocar"), (r"aqui do lado", "aqui embaixo"), (r"\bClica\b", "Toca")]
def mob(t):
    for a, b in MOB: t = re.sub(a, b, t)
    return t
def norm(t):
    t = unicodedata.normalize('NFD', t.lower()); t = ''.join(c for c in t if unicodedata.category(c) != 'Mn')
    return re.sub(r'[^a-z0-9 ]', ' ', t).split()
d = '/tmp/claude-0/asr/m/sherpa-onnx-whisper-small'
rec = sherpa_onnx.OfflineRecognizer.from_whisper(encoder=f'{d}/small-encoder.int8.onnx', decoder=f'{d}/small-decoder.int8.onnx', tokens=f'{d}/small-tokens.txt', language='pt', task='transcribe', num_threads=4)
blocks = [script[0:5], script[5:10], script[10:15]]
timing = {}
for bi, scenes in enumerate(blocks):
    src = f'{G}/block{bi}.wav'
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', src, '-ar', '16000', '-ac', '1', f'{G}/b16.wav'], check=True)
    y, sr = sf.read(f'{G}/b16.wav', dtype='float32'); dur = len(y) / sr
    o = subprocess.run(['ffmpeg', '-i', src, '-af', 'silencedetect=noise=-38dB:d=0.11', '-f', 'null', '-'], capture_output=True, text=True).stderr
    ss = [float(x) for x in re.findall(r'silence_start: ([0-9.]+)', o)]; se = [float(x) for x in re.findall(r'silence_end: ([0-9.]+)', o)]
    chunks, prev = [], 0.0
    for s, e in zip(ss, se):
        if s - prev > 0.12: chunks.append([prev, s])
        prev = e
    if dur - prev > 0.12: chunks.append([prev, dur])
    texts = []
    for a, b in chunks:
        st = rec.create_stream(); st.accept_waveform(sr, y[int(max(0, a - .05) * sr):int(min(dur, b + .05) * sr)]); rec.decode_stream(st)
        texts.append(st.result.text)
    lines = [(sc['id'], mob(c)) for sc in scenes for _, c in sc['lines']]
    L, C = len(lines), len(chunks)
    def sim(li, a, b):
        x, yv = norm(lines[li][1]), norm(' '.join(texts[a:b]))
        return difflib.SequenceMatcher(None, x, yv).ratio() * (len(x) + len(yv)) / 2
    INF = -1e9; dp = [[INF] * (C + 1) for _ in range(L + 1)]; bk = [[0] * (C + 1) for _ in range(L + 1)]; dp[0][0] = 0
    for i in range(1, L + 1):
        for j in range(1, C + 1):
            for k in range(max(0, j - 14), j):
                if dp[i - 1][k] == INF: continue
                v = dp[i - 1][k] + sim(i - 1, k, j)
                if v > dp[i][j]: dp[i][j], bk[i][j] = v, k
    j = C; spans = []
    for i in range(L, 0, -1):
        k = bk[i][j]; spans.append((chunks[k][0], chunks[j - 1][1], ' '.join(texts[k:j]))); j = k
    spans.reverse()
    li = 0
    for sc in scenes:
        n = len(sc['lines']); sp = spans[li:li + n]; li += n
        a, b = max(0, sp[0][0] - 0.08), min(dur, sp[-1][1] + 0.3)
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-ss', f'{a:.3f}', '-t', f'{b - a:.3f}', '-i', src, '-af',
                        'afade=t=in:d=0.02,areverse,afade=t=in:d=0.06,areverse,highpass=f=60,acompressor=threshold=-20dB:ratio=2.5:attack=5:release=120:makeup=2,loudnorm=I=-16:TP=-1.5:LRA=9',
                        '-ar', '48000', '-ac', '1', f"{OUT}/{sc['id']}.wav"], check=True)
        caps = [{'text': mob(c), 'start': round(s - a, 3), 'end': round(e - a, 3)} for (s, e, _), (_, c) in zip(sp, sc['lines'])]
        timing[sc['id']] = {'duration': round(b - a, 3), 'captions': caps}
        for (s, e, t), (_, c) in zip(sp, sc['lines']):
            print(f"{sc['id']:10s} {s:6.2f}-{e:6.2f} | {mob(c)[:45]:45s} | {t[:60]}")
json.dump(timing, open(f'{B}/timing_gem.json', 'w'), ensure_ascii=False, indent=1)
print({k: v['duration'] for k, v in timing.items()}, round(sum(v['duration'] for v in timing.values()), 1))
