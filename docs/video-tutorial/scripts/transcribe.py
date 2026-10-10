import sys, json, subprocess, re
import numpy as np, soundfile as sf, sherpa_onnx
src = sys.argv[1]
wav = '/tmp/claude-0/asr/work/full16k.wav'
subprocess.run(['ffmpeg','-y','-loglevel','error','-i',src,'-ar','16000','-ac','1',wav], check=True)
out = subprocess.run(['ffmpeg','-i',src,'-af','silencedetect=noise=-38dB:d=0.3','-f','null','-'], capture_output=True, text=True).stderr
starts = [float(x) for x in re.findall(r'silence_start: ([0-9.]+)', out)]
ends = [float(x) for x in re.findall(r'silence_end: ([0-9.]+)', out)]
sil = list(zip(starts, ends))
y, sr = sf.read(wav, dtype='float32')
dur = len(y) / sr
# speech chunks = gaps between silences
chunks, prev = [], 0.0
for s, e in sil:
    if s - prev > 0.15: chunks.append((prev, s))
    prev = e
if dur - prev > 0.15: chunks.append((prev, dur))
d = '/tmp/claude-0/asr/m/sherpa-onnx-whisper-small'
rec = sherpa_onnx.OfflineRecognizer.from_whisper(encoder=f'{d}/small-encoder.int8.onnx', decoder=f'{d}/small-decoder.int8.onnx', tokens=f'{d}/small-tokens.txt', language='pt', task='transcribe', num_threads=4)
res = []
for a, b in chunks:
    seg = y[int(max(0, a - 0.05) * sr): int(min(dur, b + 0.05) * sr)]
    st = rec.create_stream(); st.accept_waveform(sr, seg); rec.decode_stream(st)
    res.append({'start': round(a, 3), 'end': round(b, 3), 'text': st.result.text.strip()})
    print(f"{a:7.2f}-{b:7.2f}  {st.result.text.strip()}", flush=True)
json.dump({'duration': dur, 'chunks': res, 'silences': sil}, open('/tmp/claude-0/asr/work/chunks.json', 'w'), ensure_ascii=False, indent=1)
