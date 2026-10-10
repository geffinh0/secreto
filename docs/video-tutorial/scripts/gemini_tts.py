"""Gemini TTS -> wav. usage: gtts.py VOICE OUT.wav 'texto' [model]"""
import sys, json, base64, wave, urllib.request, os, time
voice, out, text = sys.argv[1], sys.argv[2], sys.argv[3]
if text.startswith("@"): text = open(text[1:]).read()
model = sys.argv[4] if len(sys.argv) > 4 else "gemini-3.8-flash-tts"
key = os.environ["GEMINI_API_KEY"]
STYLE = ("Leia em português do Brasil, com sotaque brasileiro natural (paulista), no tom de uma criadora de conteúdo "
         "simpática explicando um app pra um amigo: animada, leve, sorrindo, ritmo de conversa, sem soar robótica. Texto: ")
PROMPT = """# AUDIO PROFILE: Ana, criadora de conteúdo brasileira de São Paulo
## THE SCENE: gravando a narração de um tutorial curto de app para o Instagram, num estúdio caseiro.
### DIRECTOR'S NOTES
Idioma: português do Brasil, sotaque paulista natural.
Estilo: simpática, animada e leve, sorrindo, como quem explica um app para um amigo. Nada robótico.
Ritmo: conversa natural, com pequenas pausas entre as frases e uma pausa maior entre os parágrafos.
#### TRANSCRIPT
"""
body = {"contents": [{"parts": [{"text": PROMPT + text}]}],
        "generationConfig": {"responseModalities": ["AUDIO"],
                             "speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": voice}}}}}
req = urllib.request.Request(f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
                             data=json.dumps(body).encode(), headers={"Content-Type": "application/json", "x-goog-api-key": key})
for attempt in range(3):
    try:
        d = json.load(urllib.request.urlopen(req, timeout=180)); break
    except urllib.error.HTTPError as e:
        msg = e.read().decode()[:300]; print("HTTP", e.code, msg, file=sys.stderr)
        if e.code in (429, 500, 503): time.sleep(30); continue
        sys.exit(1)
part = d["candidates"][0]["content"]["parts"][0]["inlineData"]
pcm = base64.b64decode(part["data"])
if pcm[:4] == b"RIFF":
    open(out, "wb").write(pcm)
else:
    rate = 24000
    if "rate=" in part.get("mimeType", ""): rate = int(part["mimeType"].split("rate=")[1].split(";")[0])
    with wave.open(out, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate); w.writeframes(pcm)
with wave.open(out) as w: print(out, round(w.getnframes() / w.getframerate(), 2), "s", w.getframerate(), part.get("mimeType"))
