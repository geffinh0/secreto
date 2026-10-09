import sys, sherpa_onnx, soundfile as sf
voice, text, out = sys.argv[1], sys.argv[2], sys.argv[3]
speed = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0
d = f"/tmp/claude-0/tts/vits-piper-pt_BR-{voice}-medium"
import glob
cfg = sherpa_onnx.OfflineTtsConfig(model=sherpa_onnx.OfflineTtsModelConfig(
    vits=sherpa_onnx.OfflineTtsVitsModelConfig(model=glob.glob(f"{d}/*.onnx")[0], tokens=f"{d}/tokens.txt", data_dir=f"{d}/espeak-ng-data",
                                               noise_scale=0.7, noise_scale_w=0.9, length_scale=1.0), num_threads=4))
tts = sherpa_onnx.OfflineTts(cfg)
a = tts.generate(text, sid=0, speed=speed)
sf.write(out, a.samples, a.sample_rate)
print(round(len(a.samples) / a.sample_rate, 2), a.sample_rate)
