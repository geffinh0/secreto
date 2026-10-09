"""Runs the repo's MockSuperLive persistently + a tiny control API to inject chat."""
import json, sys, time
from http.server import BaseHTTPRequestHandler, HTTPServer
sys.path.insert(0, "/home/user/secreto/backend")
from tests.mock_superlive import MockSuperLive

mock = MockSuperLive()
mock.heartbeat_seconds = 20
mock.start(9100)

class H(BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("content-length", 0))) or b"{}")
        kind = self.path.strip("/")
        if kind == "chat":
            mock.chat(body["user_id"], body["name"], body["text"], body.get("live", "live1"))
        elif kind == "gift":
            mock.emit("livestream_gift_sent", {"livestream_id": body.get("live", "live1"),
                      "user_id": str(body["user_id"]), "name": body.get("name", ""),
                      "gift": {"cost": body["cost"]}})
        self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
    def log_message(self, *a): pass

print("mock ready", flush=True)
HTTPServer(("127.0.0.1", 9101), H).serve_forever()
