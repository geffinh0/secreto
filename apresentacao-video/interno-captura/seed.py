import json, urllib.request
A="http://127.0.0.1:8000"
def api(m,p,b=None,t=None):
    r=urllib.request.Request(A+p,data=json.dumps(b).encode() if b is not None else None,method=m)
    r.add_header("Content-Type","application/json")
    if t: r.add_header("Authorization","Bearer "+t)
    try:
        with urllib.request.urlopen(r,timeout=20) as x: return json.loads(x.read() or "null")
    except urllib.error.HTTPError as e: print(e.code,e.read().decode()); return None
code=open("agency.txt").read().strip()
r=api("POST","/auth/register",{"username":"aurora","password":"Senha-Demo-123","display_name":"Aurora","agency_code":code})
t=r["access_token"]; uid=r["user"]["id"]; print(uid)
for k,a in [("mal educada","mute"),("chata","mute"),("spam","kick")]:
    api("POST","/moderation/rules",{"user_id":uid,"keyword":k,"action":a},t)
for m in ["Obrigada por acompanharem a live.","Sigam o perfil para não perder as próximas lives.","Respeito em primeiro lugar no chat.","Bem-vindos! Fiquem à vontade."]:
    api("POST","/messages",{"user_id":uid,"content":m},t)
print(api("PUT",f"/settings/{uid}",{"auto_messages_enabled":True,"message_interval_seconds":120},t))
print(api("POST","/robot/connect",{"email":"robot@x.com","password":"good"},t))
open("token.txt","w").write(t)

import sqlite3, random, re
dbp=re.search(r"Banco de dados: (.*)",open("server.log").read()).group(1).strip()
random.seed(11)
con=sqlite3.connect(dbp)
lives=[("live-a1",19),("live-b2",15),("live-c3",12),("live-d4",8),("live-e5",5),("live-f6",2)]
kw=[("chata","mute",9),("spam","kick",7),("mal educada","mute",5),("feia","mute",4),("passa zap","mute",3)]
names=["Lucas","Marina","Bruno","Ana","Davi","bot77","Clara","Rafa","Duda","Téo"]
for lid,ago in lives:
    n=random.randint(6,14)
    for i in range(n):
        k,a,w=random.choices(kw,weights=[x[2] for x in kw])[0]
        ts=f"datetime('now','-{ago} days','-{random.randint(0,180)} minutes')"
        con.execute(f"INSERT INTO moderation_log (user_id,livestream_id,target_user_id,target_name,action,keyword,message_text,ok,created_at) VALUES (?,?,?,?,?,?,?,?,{ts})",(uid,lid,f"u{random.randint(10,99)}",random.choice(names),a,k,k,1))
con.commit(); con.close(); print("history ok")
