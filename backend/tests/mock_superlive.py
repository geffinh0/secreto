"""A tiny fake SuperLive (HTTP + WebSocket) that follows the protocol found in the
decompiled app. It lets the whole bot be exercised end-to-end without real
credentials. Frames/requests it receives are recorded for assertions."""
import asyncio
import json
import threading
import time

import uvicorn
from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse

ROBOT_TOKEN = "tok-robot"
ROBOT_ID = "777"
# Deliberately different from the internal ids: on the real service, the "ID: ..."
# shown on a profile screen (shared_id) is NOT the same field as the internal user_id
# some other endpoints key on (users/profile). STREAMER_SHARED_ID below is set equal to
# DECOY_USER_ID on purpose, to reproduce the real bug this mock catches: calling
# users/profile with the shared_id (instead of resolving it via users/search first)
# silently returns a different, unrelated account instead of an error.
STREAMER_ID = "100"
STREAMER_SHARED_ID = "555100"
OFFLINE_STREAMER_ID = "200"
OFFLINE_STREAMER_SHARED_ID = "555200"
DECOY_USER_ID = "555100"
GOOD_PHONE = "+5511999999999"
GOOD_SMS_CODE = "123456"
LOGGED_IN_FALSE_EMAIL = "existing@x.com"


class MockSuperLive:
    def __init__(self):
        self.calls = []        # every HTTP POST: {"path", "body", "headers"}
        self.frames = []       # every WS frame sent by the client
        self.fail = {}         # path -> (status, json) forced failure
        self.require_captcha = False
        self.known_devices = set()   # ids handed out by device/register
        self.phone_codes = {}        # verification_id -> {"phone_number", "code"}
        self._next_phone_verification_id = 1
        self.ws_auth_ok = True
        self.ws_connects = 0
        self.heartbeat_seconds = 1
        self.clients = set()
        self.loop = None
        self.port = None
        self.server = None
        self.app = self._build()

    # ── helpers for tests ──────────────────────────────────────────────────
    @property
    def base_url(self):
        return f"http://127.0.0.1:{self.port}/api/v1/"

    def calls_to(self, path):
        return [c for c in list(self.calls) if c["path"] == path]

    def emit(self, frame_type, data):
        frame = json.dumps({"id": "srv-1", "type": frame_type, "data": data})
        asyncio.run_coroutine_threadsafe(self._broadcast(frame), self.loop).result(5)

    def chat(self, user_id, name, text, livestream_id="live1"):
        self.emit("livestream_message_sent", {
            "message_id": f"m-{time.time_ns()}", "livestream_id": livestream_id,
            "user_id": str(user_id), "name": name, "text": text,
        })

    def drop_clients(self):
        async def _drop():
            for ws in list(self.clients):
                await ws.close(code=1011)
        asyncio.run_coroutine_threadsafe(_drop(), self.loop).result(5)

    async def _broadcast(self, frame):
        for ws in list(self.clients):
            await ws.send_text(frame)

    # ── server lifecycle ───────────────────────────────────────────────────
    def start(self, port):
        self.port = port
        config = uvicorn.Config(self.app, host="127.0.0.1", port=port, log_level="error")
        self.server = uvicorn.Server(config)
        threading.Thread(target=self.server.run, daemon=True).start()
        for _ in range(100):
            if self.server.started:
                return
            time.sleep(0.05)
        raise RuntimeError("mock SuperLive did not start")

    def stop(self):
        if self.server:
            self.server.should_exit = True

    # ── the fake API ───────────────────────────────────────────────────────
    def _build(self):
        app = FastAPI()
        mock = self

        @app.on_event("startup")
        async def _startup():
            mock.loop = asyncio.get_running_loop()

        @app.post("/{path:path}")
        async def handle(path: str, request: Request):
            raw = await request.body()
            body = json.loads(raw) if raw else {}
            # like the real server: everything lives under /api/v1/
            if not path.startswith("api/v1/"):
                return JSONResponse({"error": {"code": 77, "message": "unknown urd"}}, status_code=400)
            path = path[len("api/v1/"):]
            headers = {k.lower(): v for k, v in request.headers.items()}
            mock.calls.append({"path": path, "body": body, "headers": headers})

            if path in mock.fail:
                status, payload = mock.fail[path]
                return JSONResponse(payload, status_code=status)

            if path == "device/register":
                guid = f"dev-{len(mock.known_devices) + 1}-{time.time_ns()}"
                mock.known_devices.add(guid)
                return {"guid": guid}

            # every other call needs a Device-ID that device/register issued
            if headers.get("device-id") not in mock.known_devices:
                return JSONResponse({"error": {"code": 77, "message": "unknown urd"}}, status_code=400)

            if path == "user/signup/email_signin":
                if mock.require_captcha:
                    return JSONResponse({"message": "recaptcha required"}, status_code=403)
                if body.get("email") == "robot@x.com" and body.get("password") == "good":
                    return {"token": ROBOT_TOKEN, "logged_in": True, "existed": True}
                # Real-world case: an existing account can get a valid token back with
                # logged_in: false (the app's own repository saves the token regardless).
                if body.get("email") == LOGGED_IN_FALSE_EMAIL and body.get("password") == "good":
                    return {
                        "success": True, "user_id": "32037361", "token": ROBOT_TOKEN,
                        "logged_in": False, "existed": True, "extra_information_required": False,
                        "initial_free_coin_offer": None,
                    }
                return JSONResponse({"message": "Invalid credentials"}, status_code=401)

            # Same anti-bot gate as email (confirmed in the decompiled app: both call
            # the identical AuthPreCheckManager.execute("auth", ...) before this request).
            if path == "user/signup/send_phone_verification_code":
                if mock.require_captcha:
                    return JSONResponse({"message": "recaptcha required"}, status_code=403)
                if body.get("phone_number") != GOOD_PHONE:
                    return JSONResponse({"message": "invalid phone number"}, status_code=400)
                vid = f"pv-{mock._next_phone_verification_id}"
                mock._next_phone_verification_id += 1
                mock.phone_codes[vid] = {
                    "phone_number": body.get("phone_number"), "code": GOOD_SMS_CODE,
                }
                return {
                    "phone_verification_id": vid,
                    "retry_timeout_seconds": 15 if body.get("is_retry") else 60,
                }

            if path == "user/signup/auth_phone":
                entry = mock.phone_codes.get(body.get("phone_verification_id"))
                if entry is None or entry["phone_number"] != body.get("phone_number"):
                    return JSONResponse({"message": "invalid or expired verification"}, status_code=400)
                if body.get("code") != entry["code"]:
                    return JSONResponse({"message": "invalid code"}, status_code=400)
                del mock.phone_codes[body["phone_verification_id"]]
                return {"token": ROBOT_TOKEN, "logged_in": True, "existed": True}

            if headers.get("authorization") != f"Token {ROBOT_TOKEN}":
                return JSONResponse({"message": "bad token"}, status_code=401)
            if path == "users/own_profile":
                return {"user": {"id": int(ROBOT_ID), "nickname": "RoboMod", "avatar": "http://x/a.png"}}
            if path == "users/profile":
                # Keyed on the INTERNAL user_id only - never the public shared_id.
                target = body.get("user_id")
                if target == STREAMER_ID:
                    return {"user": {
                        "user_id": STREAMER_ID, "name": "Streamer", "livestream_id": "live1",
                        "profile_images": [{"url": "http://x/streamer.png"}],
                    }}
                if target == OFFLINE_STREAMER_ID:
                    return {"user": {
                        "user_id": OFFLINE_STREAMER_ID, "name": "Offline", "livestream_id": None,
                        "profile_images": [],
                    }}
                if target == DECOY_USER_ID:
                    # Same number as STREAMER_SHARED_ID, different (unrelated) account -
                    # exactly what the real server returned for the real bug report.
                    return {"user": {
                        "user_id": DECOY_USER_ID, "name": "DecoyWrongAccount",
                        "livestream_id": None, "profile_images": [],
                    }}
                return JSONResponse({"message": "user not found"}, status_code=404)

            if path == "users/search":
                query = (body.get("search_query") or "").strip()
                items = []
                if query == STREAMER_SHARED_ID:
                    items = [{
                        "user_id": STREAMER_ID, "shared_id": STREAMER_SHARED_ID,
                        "name": "Streamer", "livestream_id": "live1",
                        "profile_image": {"url": "http://x/streamer.png"},
                    }]
                elif query == OFFLINE_STREAMER_SHARED_ID:
                    items = [{
                        "user_id": OFFLINE_STREAMER_ID, "shared_id": OFFLINE_STREAMER_SHARED_ID,
                        "name": "Offline", "livestream_id": None, "profile_image": None,
                    }]
                return {"items": items}
            if path == "user/settings":
                return {"websocket": {"url": f"ws://127.0.0.1:{mock.port}/ws",
                                      "heartbeat": mock.heartbeat_seconds}}
            if path == "livestream/retrieve":
                if body.get("livestream_id") != "live1":
                    return JSONResponse({"message": "livestream not found"}, status_code=404)
                return {"user": {"id": int(STREAMER_ID), "nickname": "Streamer"}}
            if path in ("livestream/chat/mute", "livestream/kick",
                        "livestream/chat/send_text_message", "user/logout"):
                return {"success": True}
            return JSONResponse({"message": f"unknown endpoint {path}"}, status_code=404)

        @app.websocket("/ws")
        async def ws(websocket: WebSocket):
            query = websocket.query_params
            if (not mock.ws_auth_ok or query.get("auth") != ROBOT_TOKEN
                    or query.get("device") not in mock.known_devices):
                await websocket.close(code=4401)  # closed before accept -> HTTP 403 handshake
                return
            await websocket.accept()
            mock.clients.add(websocket)
            mock.ws_connects += 1
            try:
                while True:
                    mock.frames.append(json.loads(await websocket.receive_text()))
            except WebSocketDisconnect:
                pass
            finally:
                mock.clients.discard(websocket)

        return app
