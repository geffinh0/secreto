import os, sys, json, base64, urllib.request, wave
KEY=os.environ["GEMINI_API_KEY"]
VOICE=sys.argv[1]; MODEL=sys.argv[2]; out=sys.argv[3]; text=sys.argv[4]
body={"contents":[{"parts":[{"text":text}]}],"generationConfig":{"responseModalities":["AUDIO"],"speechConfig":{"voiceConfig":{"prebuiltVoiceConfig":{"voiceName":VOICE}}}}}
req=urllib.request.Request(f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent",data=json.dumps(body).encode(),headers={"Content-Type":"application/json","x-goog-api-key":KEY})
try:
    r=json.load(urllib.request.urlopen(req,timeout=120))
except urllib.error.HTTPError as e:
    print(e.code,e.read().decode()[:400]); sys.exit(1)
pcm=base64.b64decode(r["candidates"][0]["content"]["parts"][0]["inlineData"]["data"])
w=wave.open(out,"wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(24000); w.writeframes(pcm); w.close()
print(out,len(pcm)/48000,"s")
