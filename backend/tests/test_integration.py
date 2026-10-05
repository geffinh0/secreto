"""End-to-end tests: real FastAPI app + real engine + a fake SuperLive.

Run from backend/:  python -m unittest discover -s tests -v
"""
import hashlib
import json
import os
import shutil
import sqlite3
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request

import uvicorn

import db
import engine
import main
import superlive
import tests.mock_superlive as mock_superlive
from tests.mock_superlive import ROBOT_ID, STREAMER_ID, MockSuperLive

API_PORT, MOCK_PORT = 18765, 18766
API = f"http://127.0.0.1:{API_PORT}"

mock = MockSuperLive()
_api_server = None
_tmp = None


def setUpModule():
    global _api_server, _tmp
    _tmp = tempfile.mkdtemp(prefix="sm-test-")
    db.DB_PATH = os.path.join(_tmp, "test.db")  # never touch the real database
    engine.CONFIG_TTL_SECONDS = 0.1
    engine.MIN_INTERVAL_SECONDS = 1
    engine.ACTION_SPACING_SECONDS = 0.05
    mock.start(MOCK_PORT)
    superlive.BASE_URL = mock.base_url
    config = uvicorn.Config(main.app, host="127.0.0.1", port=API_PORT, log_level="error")
    _api_server = uvicorn.Server(config)
    threading.Thread(target=_api_server.run, daemon=True).start()
    wait_for(lambda: _api_server.started, 10, "API server did not start")


def tearDownModule():
    _api_server.should_exit = True
    mock.stop()
    time.sleep(0.3)
    shutil.rmtree(_tmp, ignore_errors=True)


# ── helpers ──────────────────────────────────────────────────────────────────
def wait_for(predicate, timeout=6.0, message="condition not met in time"):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.05)
    raise AssertionError(message)


def api(method, path, body=None, token=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            text = resp.read().decode()
            return resp.status, (json.loads(text) if text else None)
    except urllib.error.HTTPError as exc:
        text = exc.read().decode()
        try:
            return exc.code, json.loads(text)
        except ValueError:
            return exc.code, text


_counter = [0]


def new_user(prefix="user"):
    _counter[0] += 1
    name = f"{prefix}{_counter[0]}"
    status, body = api("POST", "/auth/register", {
        "username": name, "email": f"{name}@example.com", "password": "senha-forte-1",
    })
    assert status == 200, body
    return name, body["access_token"], body["user"]["id"]


def sql(query, params=()):
    conn = sqlite3.connect(db.DB_PATH)
    try:
        conn.execute(query, params)
        conn.commit()
    finally:
        conn.close()


# ── auth, validation and ownership ───────────────────────────────────────────
class AuthAndApiTests(unittest.TestCase):
    def test_register_validation_returns_plain_string_detail(self):
        status, body = api("POST", "/auth/register",
                           {"username": "ab", "email": "nope", "password": "123"})
        self.assertEqual(status, 422)
        self.assertIsInstance(body["detail"], str)  # the Flutter app reads this as a String

    def test_register_duplicate_is_case_insensitive(self):
        name, _, _ = new_user("dup")
        status, _ = api("POST", "/auth/register", {
            "username": name.upper(), "email": "other@example.com", "password": "senha-forte-1"})
        self.assertEqual(status, 400)

    def test_login_me_and_logout(self):
        name, _, _ = new_user("login")
        status, bad = api("POST", "/auth/login", {"username": name, "password": "errada"})
        self.assertEqual(status, 401)
        status, ok = api("POST", "/auth/login", {"username": name, "password": "senha-forte-1"})
        self.assertEqual(status, 200)
        self.assertIs(ok["user"]["is_admin"], False)
        status, me = api("GET", "/auth/me", token=ok["access_token"])
        self.assertEqual(status, 200)
        self.assertIs(me["is_admin"], False)  # was an int before -> broke the Flutter model
        self.assertNotIn("password_hash", me)
        self.assertEqual(api("POST", "/auth/logout", token=ok["access_token"])[0], 200)
        self.assertEqual(api("GET", "/auth/me", token=ok["access_token"])[0], 401)

    def test_missing_and_expired_tokens_are_rejected(self):
        self.assertEqual(api("GET", "/auth/me")[0], 401)
        _, token, _ = new_user("exp")
        sql("UPDATE sessions SET expires_at = datetime('now', '-1 day') WHERE token = ?", (token,))
        self.assertEqual(api("GET", "/auth/me", token=token)[0], 401)

    def test_login_throttle(self):
        name, _, _ = new_user("thr")
        try:
            for _ in range(8):
                api("POST", "/auth/login", {"username": name, "password": "x"})
            self.assertEqual(api("POST", "/auth/login", {"username": name, "password": "senha-forte-1"})[0], 429)
        finally:
            main.throttle._failures.clear()

    def test_legacy_sha256_password_still_logs_in_and_is_upgraded(self):
        legacy = hashlib.sha256(b"antiga-senha1").hexdigest()
        sql("INSERT INTO users (username, email, display_name, password_hash) VALUES (?,?,?,?)",
            ("legacyuser", "legacy@example.com", "legacy", legacy))
        status, body = api("POST", "/auth/login", {"username": "legacyuser", "password": "antiga-senha1"})
        self.assertEqual(status, 200)
        conn = sqlite3.connect(db.DB_PATH)
        stored = conn.execute("SELECT password_hash FROM users WHERE username='legacyuser'").fetchone()[0]
        conn.close()
        self.assertTrue(stored.startswith("pbkdf2_sha256$"))

    def test_users_cannot_touch_each_others_data(self):
        _, alice, alice_id = new_user("alice")
        _, bob, bob_id = new_user("bob")
        _, rule = api("POST", "/moderation/rules",
                      {"user_id": alice_id, "keyword": "segredo", "action": "mute"}, alice)
        _, msg = api("POST", "/messages", {"user_id": alice_id, "content": "oi"}, alice)

        self.assertEqual(api("GET", f"/moderation/rules?user_id={alice_id}", token=bob)[0], 403)
        self.assertEqual(api("POST", "/moderation/rules",
                             {"user_id": alice_id, "keyword": "x", "action": "kick"}, bob)[0], 403)
        self.assertEqual(api("PUT", f"/moderation/rules/{rule['id']}", {"is_active": False}, bob)[0], 404)
        self.assertEqual(api("DELETE", f"/moderation/rules/{rule['id']}", token=bob)[0], 404)
        self.assertEqual(api("PUT", f"/messages/{msg['id']}", {"content": "hack"}, bob)[0], 404)
        self.assertEqual(api("DELETE", f"/messages/{msg['id']}", token=bob)[0], 404)
        self.assertEqual(api("GET", f"/settings?user_id={alice_id}", token=bob)[0], 403)
        self.assertEqual(api("PUT", f"/settings/{alice_id}", {"moderation_enabled": False}, bob)[0], 403)
        self.assertEqual(api("GET", "/robot/status", token=bob)[1]["connected"], False)
        # alice's data is intact
        self.assertEqual(len(api("GET", f"/moderation/rules?user_id={alice_id}", token=alice)[1]), 1)
        self.assertEqual(api("GET", f"/settings?user_id={alice_id}", token=alice)[1]["moderation_enabled"], True)

    def test_rule_validation(self):
        _, token, uid = new_user("rules")
        post = lambda kw, action="mute": api(
            "POST", "/moderation/rules", {"user_id": uid, "keyword": kw, "action": action}, token)

        status, rule = post("  Passa   ZAP ")
        self.assertEqual(status, 200)
        self.assertEqual(rule["keyword"], "passa zap")
        self.assertIs(rule["is_active"], True)
        self.assertEqual(post("   ")[0], 422)                      # empty keyword
        self.assertEqual(post("x", "ban")[0], 422)                  # invalid action
        self.assertIsInstance(post("x", "ban")[1]["detail"], str)
        self.assertEqual(post("PASSA zap")[0], 409)                 # duplicate
        self.assertEqual(post("Pássa Zap")[0], 409)                 # duplicate ignoring accents
        _, other = post("outra")
        self.assertEqual(api("PUT", f"/moderation/rules/{other['id']}", {"keyword": "passa zap"}, token)[0], 409)
        self.assertEqual(api("PUT", f"/moderation/rules/{other['id']}", {"action": "ban"}, token)[0], 422)
        status, toggled = api("PUT", f"/moderation/rules/{other['id']}", {"is_active": False}, token)
        self.assertEqual((status, toggled["is_active"]), (200, False))
        self.assertEqual(api("PUT", "/moderation/rules/99999", {"is_active": True}, token)[0], 404)

    def test_settings_partial_update_and_validation(self):
        _, token, uid = new_user("settings")
        status, s = api("GET", f"/settings?user_id={uid}", token=token)
        self.assertEqual((s["message_interval_seconds"], s["moderation_enabled"], s["kick_permanent"]),
                         (120, True, False))
        self.assertNotIn("end_message_enabled", s)   # discontinued feature, not in the API anymore
        self.assertNotIn("end_message_template", s)
        status, s = api("PUT", f"/settings/{uid}", {"kick_permanent": True}, token)
        self.assertEqual((status, s["kick_permanent"], s["moderation_enabled"]), (200, True, True))
        status, s = api("PUT", f"/settings/{uid}", {
            "auto_messages_enabled": True, "message_interval_seconds": 45}, token)
        self.assertEqual((s["message_interval_seconds"], s["kick_permanent"]), (45, True))
        self.assertEqual(api("PUT", f"/settings/{uid}", {"message_interval_seconds": 3}, token)[0], 422)
        self.assertEqual(api("PUT", f"/settings/{uid}", {"message_interval_seconds": 0}, token)[0], 422)
        # a stale client sending the old fields is simply ignored, not an error
        status, s = api("PUT", f"/settings/{uid}",
                        {"end_message_enabled": True, "end_message_template": "oi"}, token)
        self.assertEqual(status, 200)
        self.assertNotIn("end_message_template", s)

    def test_cors_only_allows_localhost(self):
        def preflight(origin):
            req = urllib.request.Request(API + "/auth/login", method="OPTIONS", headers={
                "Origin": origin, "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "content-type"})
            with urllib.request.urlopen(req) as resp:
                return resp.headers.get("access-control-allow-origin")
            return None
        self.assertEqual(preflight("http://localhost:3000"), "http://localhost:3000")
        try:
            self.assertIsNone(preflight("https://evil.example"))
        except urllib.error.HTTPError as exc:  # Starlette answers 400 to disallowed origins
            self.assertEqual(exc.code, 400)


# ── robot: SuperLive connection + live session ───────────────────────────────
class RobotTestBase(unittest.TestCase):
    def setUp(self):
        mock.calls.clear()
        mock.frames.clear()
        mock.fail.clear()
        mock.require_captcha = False
        mock.ws_auth_ok = True
        self.name, self.token, self.uid = new_user("robot")

    def tearDown(self):
        api("POST", "/robot/stop", token=self.token)
        api("POST", "/robot/disconnect", token=self.token)
        wait_for(lambda: not mock.clients, 5, "websocket client still connected after cleanup")

    # shortcuts
    def connect_robot(self):
        status, body = api("POST", "/robot/connect", {"email": "robot@x.com", "password": "good"}, self.token)
        self.assertEqual(status, 200, body)
        return body

    def add_rule(self, keyword, action):
        status, body = api("POST", "/moderation/rules",
                           {"user_id": self.uid, "keyword": keyword, "action": action}, self.token)
        self.assertEqual(status, 200, body)
        return body

    def settings(self, **fields):
        status, body = api("PUT", f"/settings/{self.uid}", fields, self.token)
        self.assertEqual(status, 200, body)

    def start_live(self, livestream_id="live1"):
        status, body = api("POST", "/robot/start", {"livestream_id": livestream_id}, self.token)
        self.assertEqual(status, 200, body)
        wait_for(lambda: self.status()["session"]["ws_state"] == "connected", 6, "ws never connected")
        return body

    def status(self):
        return api("GET", "/robot/status", token=self.token)[1]

    def settle(self, seconds=0.5):
        time.sleep(seconds)


class RobotConnectionTests(RobotTestBase):
    def test_wrong_password_gives_actionable_error_and_stores_nothing(self):
        status, body = api("POST", "/robot/connect", {"email": "robot@x.com", "password": "bad"}, self.token)
        self.assertEqual(status, 400)
        self.assertIn("Colar token", body["detail"])
        self.assertFalse(self.status()["connected"])

    def test_server_side_bot_protection_is_reported_not_bypassed(self):
        mock.require_captcha = True
        status, body = api("POST", "/robot/connect", {"email": "robot@x.com", "password": "good"}, self.token)
        self.assertEqual(status, 400)
        self.assertIn("recaptcha required", body["detail"])
        self.assertEqual(len(mock.calls_to("user/signup/email_signin")), 1)  # no retries / tricks

    def test_missing_credentials(self):
        self.assertEqual(api("POST", "/robot/connect", {}, self.token)[0], 400)
        self.assertEqual(api("POST", "/robot/connect", {"email": "robot@x.com"}, self.token)[0], 400)

    def test_connect_with_password_never_leaks_or_stores_the_password(self):
        body = self.connect_robot()
        self.assertTrue(body["connected"])
        self.assertEqual(body["robot"]["nickname"], "RoboMod")
        self.assertEqual(body["robot"]["auth_mode"], "password")
        self.assertNotIn("tok-robot", json.dumps(body))            # token never sent to the browser
        conn = sqlite3.connect(db.DB_PATH)
        row = conn.execute("SELECT token, device_id FROM robot_accounts WHERE user_id=?", (self.uid,)).fetchone()
        dump = " ".join(str(v) for r in conn.execute("SELECT * FROM robot_accounts") for v in r)
        conn.close()
        self.assertEqual(row[0], "tok-robot")
        self.assertNotIn("good", dump.split())                      # password not persisted
        profile_call = mock.calls_to("users/own_profile")[0]
        self.assertEqual(profile_call["headers"]["authorization"], "Token tok-robot")
        self.assertEqual(profile_call["headers"]["device-id"], row[1])

    def test_a_token_is_accepted_even_when_logged_in_is_false(self):
        # Real SuperLive behaviour, seen in production: an existing account can get a
        # valid token back with "logged_in": false. The app's own repository
        # (UserSignUpRepositoryImpl) saves the token unconditionally once present —
        # we must do the same instead of treating this as a failed login.
        status, body = api("POST", "/robot/connect",
                           {"email": mock_superlive.LOGGED_IN_FALSE_EMAIL, "password": "good"},
                           self.token)
        self.assertEqual(status, 200, body)
        self.assertTrue(body["connected"])
        self.assertEqual(body["robot"]["auth_mode"], "password")

    def test_connect_with_pasted_token(self):
        status, body = api("POST", "/robot/connect", {"token": "tok-robot"}, self.token)
        self.assertEqual(status, 200, body)
        self.assertEqual(body["robot"]["auth_mode"], "token")
        status, body = api("POST", "/robot/connect", {"token": "tok-invalid"}, self.token)
        self.assertEqual(status, 400)
        self.assertIn("bad token", body["detail"])

    def test_device_id_is_stable_across_reconnects(self):
        self.connect_robot()
        first = mock.calls_to("users/own_profile")[-1]["headers"]["device-id"]
        self.connect_robot()
        self.assertEqual(mock.calls_to("users/own_profile")[-1]["headers"]["device-id"], first)

    def test_device_is_registered_with_superlive_before_logging_in(self):
        # The real service answers "unknown urd" (HTTP 400) to a Device-ID it never issued.
        self.connect_robot()
        calls = [c["path"] for c in mock.calls]
        self.assertEqual(calls[:3], ["device/register", "user/signup/email_signin", "users/own_profile"])
        register = mock.calls_to("device/register")[0]
        self.assertNotIn("device-id", register["headers"])           # sent before any id exists
        guid = mock.calls_to("user/signup/email_signin")[0]["headers"]["device-id"]
        self.assertIn(guid, mock.known_devices)                      # the id SuperLive issued
        conn = sqlite3.connect(db.DB_PATH)
        stored = conn.execute("SELECT device_id FROM robot_accounts WHERE user_id=?", (self.uid,)).fetchone()[0]
        conn.close()
        self.assertEqual(stored, guid)

    def test_a_made_up_device_id_is_rejected_by_the_service(self):
        import asyncio
        client = superlive.SuperLiveClient(device_id="11111111-2222-3333-4444-555555555555")
        with self.assertRaises(superlive.SuperLiveError) as ctx:
            asyncio.run(client.login("robot@x.com", "good"))
        self.assertEqual((ctx.exception.status, ctx.exception.message), (400, "unknown urd"))

    def test_requests_without_the_api_v1_prefix_get_the_real_error(self):
        # What the first version did: base URL without "/api/v1/" -> "unknown urd" on every call.
        import asyncio
        client = superlive.SuperLiveClient(base_url=mock.base_url.replace("/api/v1/", "/"))
        with self.assertRaises(superlive.SuperLiveError) as ctx:
            asyncio.run(client.register_device())
        self.assertEqual((ctx.exception.status, ctx.exception.message), (400, "unknown urd"))
        self.assertEqual(ctx.exception.body["error"]["code"], 77)

    def test_token_login_registers_a_device_too(self):
        status, body = api("POST", "/robot/connect", {"token": "tok-robot"}, self.token)
        self.assertEqual(status, 200, body)
        self.assertEqual(len(mock.calls_to("device/register")), 1)

    def test_reconnecting_reuses_the_registered_device(self):
        self.connect_robot()
        self.connect_robot()
        self.assertEqual(len(mock.calls_to("device/register")), 1)

    def test_device_registration_failure_is_reported(self):
        mock.fail["device/register"] = (500, {"message": "boom"})
        status, body = api("POST", "/robot/connect", {"email": "robot@x.com", "password": "good"}, self.token)
        self.assertEqual(status, 400)
        self.assertIn("boom", body["detail"])
        self.assertFalse(self.status()["connected"])
        self.assertEqual(len(mock.calls_to("user/signup/email_signin")), 0)   # never got to the password

    def test_disconnect_logs_out_only_for_password_sessions(self):
        self.connect_robot()
        status, body = api("POST", "/robot/disconnect", token=self.token)
        self.assertFalse(body["connected"])
        self.assertEqual(len(mock.calls_to("user/logout")), 1)

        mock.calls.clear()
        api("POST", "/robot/connect", {"token": "tok-robot"}, self.token)
        api("POST", "/robot/disconnect", token=self.token)
        self.assertEqual(len(mock.calls_to("user/logout")), 0)     # a pasted token is never killed

    def test_start_requires_robot_and_valid_id(self):
        self.assertEqual(api("POST", "/robot/start", {"livestream_id": "live1"}, self.token)[0], 400)
        self.connect_robot()
        self.assertEqual(api("POST", "/robot/start", {"livestream_id": "bad id!"}, self.token)[0], 422)
        status, body = api("POST", "/robot/start", {"livestream_id": "unknown-live"}, self.token)
        self.assertEqual(status, 400)
        self.assertIn("livestream not found", body["detail"])
        self.assertFalse(self.status()["session"]["running"])

    def test_cannot_start_twice_or_swap_robot_while_running(self):
        self.connect_robot()
        self.start_live()
        self.assertEqual(api("POST", "/robot/start", {"livestream_id": "live1"}, self.token)[0], 409)
        self.assertEqual(api("POST", "/robot/connect", {"token": "tok-robot"}, self.token)[0], 409)


class PhoneLoginTests(RobotTestBase):
    """Phone login mirrors the real app: send_phone_verification_code + auth_phone,
    with no forged app_check/recaptcha tokens (see superlive.send_phone_code)."""

    def send_code(self, phone=mock_superlive.GOOD_PHONE, resend=False):
        return api("POST", "/robot/connect/phone/send_code",
                   {"phone_number": phone, "resend": resend}, self.token)

    def verify_code(self, phone=mock_superlive.GOOD_PHONE, code=mock_superlive.GOOD_SMS_CODE):
        return api("POST", "/robot/connect/phone/verify", {"phone_number": phone, "code": code}, self.token)

    def test_send_then_verify_connects_the_robot(self):
        status, body = self.send_code()
        self.assertEqual(status, 200, body)
        self.assertEqual(body["retry_timeout_seconds"], 60)
        self.assertEqual(len(mock.calls_to("device/register")), 1)

        status, body = self.verify_code()
        self.assertEqual(status, 200, body)
        self.assertTrue(body["connected"])
        self.assertEqual(body["robot"]["auth_mode"], "phone")
        self.assertNotIn("tok-robot", json.dumps(body))

    def test_invalid_phone_format_is_rejected(self):
        self.assertEqual(self.send_code(phone="011999999999")[0], 422)   # missing '+'
        self.assertEqual(self.send_code(phone="+55")[0], 422)            # too short

    def test_phone_the_server_does_not_recognize_fails_cleanly(self):
        status, body = self.send_code(phone="+5511000000000")
        self.assertEqual(status, 400)
        self.assertIn("invalid phone number", body["detail"])

    def test_verify_without_sending_code_first_fails(self):
        status, body = self.verify_code()
        self.assertEqual(status, 400)
        self.assertIn("Peça um novo código", body["detail"])

    def test_wrong_code_can_be_retried_without_a_new_sms(self):
        self.send_code()
        status, body = self.verify_code(code="000000")
        self.assertEqual(status, 400)
        self.assertIn("invalid code", body["detail"])
        self.assertFalse(self.status()["connected"])

        status, body = self.verify_code()  # same verification_id, now the right code
        self.assertEqual(status, 200, body)
        self.assertTrue(body["connected"])

    def test_verifying_a_different_number_than_the_one_texted_is_rejected(self):
        self.send_code(phone=mock_superlive.GOOD_PHONE)
        status, body = self.verify_code(phone="+5521988888888", code=mock_superlive.GOOD_SMS_CODE)
        self.assertEqual(status, 400)
        self.assertIn("Peça um novo código", body["detail"])

    def test_resend_marks_is_retry(self):
        self.send_code()
        self.send_code(resend=True)
        calls = mock.calls_to("user/signup/send_phone_verification_code")
        self.assertEqual([c["body"]["is_retry"] for c in calls], [False, True])

    def test_same_anti_bot_gate_as_email_blocks_phone_too(self):
        mock.require_captcha = True
        status, body = self.send_code()
        self.assertEqual(status, 400)
        self.assertIn("recaptcha required", body["detail"])

    def test_device_is_reused_between_send_and_verify(self):
        self.send_code()
        self.verify_code()
        conn = sqlite3.connect(db.DB_PATH)
        device_id = conn.execute(
            "SELECT device_id FROM robot_accounts WHERE user_id=?", (self.uid,)
        ).fetchone()[0]
        conn.close()
        register_call = mock.calls_to("device/register")[0]
        verify_call = mock.calls_to("user/signup/auth_phone")[0]
        self.assertEqual(verify_call["headers"]["device-id"], device_id)
        self.assertNotIn("device-id", register_call["headers"])

    def test_cannot_start_a_phone_login_while_a_session_is_running(self):
        self.connect_robot()
        self.start_live()
        self.assertEqual(self.send_code()[0], 409)

    def test_disconnect_logs_out_a_phone_session_and_clears_pending_login(self):
        self.send_code()
        self.verify_code()
        status, body = api("POST", "/robot/disconnect", token=self.token)
        self.assertEqual(status, 200)
        self.assertFalse(body["connected"])
        self.assertEqual(len(mock.calls_to("user/logout")), 1)


class LookupStreamerTests(RobotTestBase):
    """Resolve the public "ID: ..." shown on a creator's SuperLive profile (her
    `shared_id`) to her current livestream_id, the way the app's own profile screen
    enables its "watch live" button — but starting from the id a *human* actually has
    (the one visible on screen), not the internal user_id some endpoints expect.
    """

    def lookup(self, shared_id):
        return api("POST", "/robot/lookup_streamer", {"shared_id": shared_id}, self.token)

    def test_requires_a_connected_robot(self):
        self.assertEqual(self.lookup(mock_superlive.STREAMER_SHARED_ID)[0], 400)

    def test_finds_the_live_id_of_a_streamer_who_is_live(self):
        self.connect_robot()
        status, body = self.lookup(mock_superlive.STREAMER_SHARED_ID)
        self.assertEqual(status, 200, body)
        self.assertEqual(body, {
            "nickname": "Streamer", "avatar": "http://x/streamer.png",
            "live": True, "livestream_id": "live1",
        })
        search_call = mock.calls_to("users/search")[0]
        self.assertEqual(search_call["body"], {"search_query": mock_superlive.STREAMER_SHARED_ID})
        profile_call = mock.calls_to("users/profile")[0]
        # resolved to the REAL internal user_id, not the shared_id that was searched
        self.assertEqual(profile_call["body"], {"user_id": mock_superlive.STREAMER_ID})
        self.assertEqual(profile_call["headers"]["authorization"], "Token tok-robot")

    def test_never_confuses_the_shared_id_with_an_unrelated_accounts_internal_user_id(self):
        # Regression for the real bug: STREAMER_SHARED_ID and DECOY_USER_ID are the same
        # number on purpose. Calling users/profile directly with the shared_id (the old,
        # wrong behaviour) would silently return DecoyWrongAccount instead of Streamer.
        self.connect_robot()
        _, body = self.lookup(mock_superlive.STREAMER_SHARED_ID)
        self.assertEqual(body["nickname"], "Streamer")
        self.assertNotEqual(body["nickname"], "DecoyWrongAccount")

    def test_reports_offline_without_an_error(self):
        self.connect_robot()
        status, body = self.lookup(mock_superlive.OFFLINE_STREAMER_SHARED_ID)
        self.assertEqual(status, 200, body)
        self.assertEqual(body["nickname"], "Offline")
        self.assertFalse(body["live"])
        self.assertIsNone(body["livestream_id"])

    def test_unknown_id_gives_a_clear_error_instead_of_the_wrong_account(self):
        self.connect_robot()
        status, body = self.lookup("999999999")
        self.assertEqual(status, 400)
        self.assertIn("Não encontramos nenhuma conta", body["detail"])

    def test_non_numeric_id_is_rejected(self):
        self.connect_robot()
        self.assertEqual(self.lookup("not-an-id")[0], 422)
        self.assertEqual(self.lookup("")[0], 422)

    def test_the_livestream_id_it_finds_can_be_used_to_start_moderating(self):
        self.connect_robot()
        _, found = self.lookup(mock_superlive.STREAMER_SHARED_ID)
        self.start_live(found["livestream_id"])
        self.assertTrue(self.status()["session"]["running"])


class ModerationFlowTests(RobotTestBase):
    def test_rules_are_applied_to_the_live_chat(self):
        self.add_rule("passa zap", "mute")
        self.add_rule("feia", "kick")
        spam = self.add_rule("spam", "mute")
        api("PUT", f"/moderation/rules/{spam['id']}", {"is_active": False}, self.token)
        self.connect_robot()
        self.start_live()

        # the app-style handshake: enter + heartbeats carrying "livestream:<id>"
        enter = wait_for(lambda: next((f for f in list(mock.frames) if f.get("action") == "enter_livestream"), None))
        self.assertEqual(enter["data"], {"livestream_id": "live1"})
        beat = wait_for(lambda: next((f for f in list(mock.frames) if f.get("action") == "heartbeat"), None))
        self.assertEqual(beat["data"], {"state": "livestream:live1"})

        mock.chat(1, "Ana", "oi gente, tudo bem?")                 # clean
        mock.chat(2, "Bia", "Me PASSA ZAP pfv")                    # mute (case-insensitive)
        mock.chat(2, "Bia", "passa zap de novo")                   # same user again -> deduped
        mock.chat(3, "Caio", "você é feia")                         # kick
        mock.chat(3, "Caio", "feia feia")                           # deduped
        mock.chat(2, "Bia", "feia")                                 # escalation mute -> kick is allowed
        mock.chat(STREAMER_ID, "Streamer", "passa zap")             # the streamer is never moderated
        mock.chat(ROBOT_ID, "RoboMod", "feia")                      # neither is the robot
        mock.chat(4, "Dani", "spam")                                # inactive rule
        mock.chat(5, "Edu", "mensagem de outra live", livestream_id="other-live")  # other stream ignored
        wait_for(lambda: len(mock.calls_to("livestream/kick")) >= 2, 6, "kicks not sent")
        self.settle()

        mutes, kicks = mock.calls_to("livestream/chat/mute"), mock.calls_to("livestream/kick")
        self.assertEqual([c["body"] for c in mutes], [{"livestream_id": "live1", "user_id": "2"}])
        self.assertEqual([c["body"]["user_id"] for c in kicks], ["3", "2"])
        self.assertEqual(kicks[0]["body"], {"livestream_id": "live1", "user_id": "3", "permanent": False})
        for call in mutes + kicks:
            self.assertEqual(call["headers"]["authorization"], "Token tok-robot")

        session = self.status()["session"]
        self.assertEqual(session["counters"]["actions_ok"], 3)
        self.assertEqual(len(session["recent_actions"]), 3)
        tagged = {c["text"]: c["action"] for c in session["recent_chat"] if c["action"]}
        self.assertEqual(tagged["Me PASSA ZAP pfv"], "mute")
        self.assertEqual(tagged["você é feia"], "kick")
        self.assertNotIn("mensagem de outra live", [c["text"] for c in session["recent_chat"]])

        log = api("GET", "/robot/log", token=self.token)[1]
        self.assertEqual(len(log), 3)
        self.assertTrue(all(row["ok"] is True for row in log))
        self.assertEqual({row["keyword"] for row in log}, {"passa zap", "feia"})
        self.assertEqual(self.status()["totals"]["actions_ok"], 3)

    def test_settings_and_rule_changes_apply_during_a_live(self):
        self.add_rule("feia", "kick")
        self.connect_robot()
        self.start_live()

        self.settings(moderation_enabled=False)
        self.settle(0.4)
        mock.chat(1, "Ana", "feia")
        self.settle()
        self.assertEqual(len(mock.calls_to("livestream/kick")), 0)   # moderation switched off

        self.settings(moderation_enabled=True, kick_permanent=True)
        self.settle(0.4)
        mock.chat(2, "Bia", "feia")
        wait_for(lambda: len(mock.calls_to("livestream/kick")) == 1)
        self.assertIs(mock.calls_to("livestream/kick")[0]["body"]["permanent"], True)

        self.add_rule("golpe", "kick")                               # added while live
        self.settle(0.4)
        mock.chat(3, "Caio", "isso é golpe")
        wait_for(lambda: len(mock.calls_to("livestream/kick")) == 2, 6, "new rule was not picked up")

    def test_permission_denied_is_logged_and_explained(self):
        self.add_rule("feia", "kick")
        self.add_rule("zap", "mute")
        self.connect_robot()
        mock.fail["livestream/chat/mute"] = (403, {"message": "not a moderator"})
        self.start_live()
        mock.chat(1, "Ana", "manda zap")
        row = wait_for(lambda: next(iter(api("GET", "/robot/log", token=self.token)[1]), None))
        self.assertIs(row["ok"], False)
        self.assertEqual(row["detail"], "not a moderator")
        session = self.status()["session"]
        self.assertTrue(session["running"])
        self.assertIn("moderador", session["last_error"])
        self.assertEqual(session["counters"]["actions_failed"], 1)
        # a failed mute must not block a later retry for the same user
        mock.fail.clear()
        mock.chat(1, "Ana", "manda zap de novo")
        wait_for(lambda: len(mock.calls_to("livestream/chat/mute")) == 2)

    def test_expired_robot_token_stops_the_session_with_a_clear_message(self):
        self.add_rule("feia", "kick")
        self.connect_robot()
        mock.fail["livestream/kick"] = (401, {"message": "token expired"})
        self.start_live()
        mock.chat(1, "Ana", "feia")
        wait_for(lambda: self.status()["session"]["state"] == "error", 6, "session did not stop on 401")
        self.assertIn("token do robô expirou", self.status()["session"]["last_error"])

    def test_websocket_rejection_is_reported(self):
        self.connect_robot()
        mock.ws_auth_ok = False
        status, _ = api("POST", "/robot/start", {"livestream_id": "live1"}, self.token)
        self.assertEqual(status, 200)
        wait_for(lambda: self.status()["session"]["state"] == "error", 8, "ws rejection not reported")
        self.assertIn("recusou a conexão", self.status()["session"]["last_error"])

    def test_reconnects_after_the_connection_drops(self):
        self.add_rule("feia", "kick")
        self.connect_robot()
        self.start_live()
        before = mock.ws_connects
        mock.drop_clients()
        wait_for(lambda: mock.ws_connects > before and self.status()["session"]["ws_state"] == "connected",
                 8, "did not reconnect")
        enters = [f for f in list(mock.frames) if f.get("action") == "enter_livestream"]
        self.assertGreaterEqual(len(enters), 2)                      # re-entered the live
        mock.chat(1, "Ana", "feia")
        wait_for(lambda: len(mock.calls_to("livestream/kick")) == 1)


class MessagesFlowTests(RobotTestBase):
    def prepare_messages(self):
        for text, active in (("Siga a live!", True), ("Mensagem oculta", False), ("Obrigada por estar aqui", True)):
            _, msg = api("POST", "/messages", {"user_id": self.uid, "content": text, "sort_order": 0}, self.token)
            if not active:
                api("PUT", f"/messages/{msg['id']}", {"is_active": False}, self.token)
        # the API enforces >= 10 s; the engine floor is lowered in tests, so write the DB directly
        sql("UPDATE bot_settings SET auto_messages_enabled = 1, message_interval_seconds = 1 WHERE user_id = ?",
            (self.uid,))

    def test_auto_messages_rotate_through_active_messages_only(self):
        self.prepare_messages()
        self.connect_robot()
        self.start_live()
        wait_for(lambda: len(mock.calls_to("livestream/chat/send_text_message")) >= 3, 8, "no auto messages")
        calls = mock.calls_to("livestream/chat/send_text_message")
        texts = [c["body"]["text"] for c in calls[:3]]
        self.assertEqual(texts, ["Siga a live!", "Obrigada por estar aqui", "Siga a live!"])
        for call in calls:
            self.assertEqual(call["body"]["livestream_id"], "live1")
            self.assertTrue(call["body"]["guid"])
        self.assertGreaterEqual(self.status()["session"]["counters"]["messages_sent"], 3)

    def test_auto_messages_respect_the_toggle(self):
        self.prepare_messages()
        self.settings(auto_messages_enabled=False)
        self.connect_robot()
        self.start_live()
        self.settle(2.5)
        self.assertEqual(len(mock.calls_to("livestream/chat/send_text_message")), 0)

    def test_interval_below_the_floor_is_clamped_by_the_engine(self):
        old = engine.MIN_INTERVAL_SECONDS
        engine.MIN_INTERVAL_SECONDS = 10
        try:
            self.assertEqual(engine.BotSession._interval({"settings": {"message_interval_seconds": 0}}), 120)  # unset -> default
            self.assertEqual(engine.BotSession._interval({"settings": {"message_interval_seconds": None}}), 120)
            self.assertEqual(engine.BotSession._interval({"settings": {"message_interval_seconds": -5}}), 10)
            self.assertEqual(engine.BotSession._interval({"settings": {"message_interval_seconds": 3}}), 10)
            self.assertEqual(engine.BotSession._interval({"settings": {"message_interval_seconds": 90}}), 90)
        finally:
            engine.MIN_INTERVAL_SECONDS = old

    def test_stop_leaves_the_livestream_cleanly(self):
        self.connect_robot()
        self.start_live()
        status, body = api("POST", "/robot/stop", token=self.token)
        self.assertEqual(status, 200)
        self.assertEqual(body["session"]["state"], "stopped")
        # the end-of-live message was discontinued: stopping never posts a chat message
        self.assertEqual(len(mock.calls_to("livestream/chat/send_text_message")), 0)
        leave = wait_for(lambda: [f for f in list(mock.frames) if f.get("action") == "leave_livestream"],
                         5, "leave_livestream frame never arrived")
        self.assertEqual(leave[0]["data"], {"livestream_id": "live1"})

    def test_livestream_ended_event_closes_the_session(self):
        self.connect_robot()
        self.start_live()
        mock.emit("livestream_ended", {"livestream_id": "another-live"})   # not ours: ignored
        self.settle(0.5)
        self.assertTrue(self.status()["session"]["running"])
        mock.emit("livestream_ended", {"livestream_id": "live1"})
        wait_for(lambda: self.status()["session"]["state"] == "stopped", 8, "session did not close")
        self.assertEqual(self.status()["session"]["stop_reason"], "A live foi encerrada")
        wait_for(lambda: not mock.clients, 5, "websocket not closed")

    def test_can_start_a_new_session_after_one_ended(self):
        self.connect_robot()
        self.start_live()
        api("POST", "/robot/stop", token=self.token)
        self.start_live()
        self.assertTrue(self.status()["session"]["running"])


# ── upgrading a database created by the previous version ─────────────────────
class MigrationTests(unittest.TestCase):
    def test_existing_database_is_upgraded_without_losing_data(self):
        real = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "super_moderator.db")
        copy = os.path.join(_tmp, "migrate.db")
        if os.path.exists(real):
            shutil.copy(real, copy)
        else:  # build an "old" schema by hand
            conn = sqlite3.connect(copy)
            conn.executescript("""
                CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT UNIQUE NOT NULL,
                    email TEXT UNIQUE NOT NULL, display_name TEXT, password_hash TEXT NOT NULL,
                    is_admin INTEGER DEFAULT 0, created_at TEXT DEFAULT (datetime('now')));
                CREATE TABLE sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER NOT NULL,
                    token TEXT UNIQUE NOT NULL, created_at TEXT DEFAULT (datetime('now')));
                CREATE TABLE bot_settings (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER UNIQUE NOT NULL,
                    auto_messages_enabled INTEGER DEFAULT 0, message_interval_seconds INTEGER DEFAULT 120,
                    end_message_enabled INTEGER DEFAULT 0, end_message_template TEXT, moderation_enabled INTEGER DEFAULT 1);
                INSERT INTO users (username, email, password_hash) VALUES ('old', 'old@x.com', 'abc');
                INSERT INTO sessions (user_id, token) VALUES (1, 'old-token');
            """)
            conn.commit()
            conn.close()

        def counts():
            conn = sqlite3.connect(copy)
            try:
                tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
                return {t: conn.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
                        for t in ("users", "sessions", "bot_settings", "moderation_rules", "auto_messages")
                        if t in tables}
            finally:
                conn.close()

        before = counts()
        saved = db.DB_PATH
        db.DB_PATH = copy
        try:
            db.init_db()
            db.init_db()  # idempotent
        finally:
            db.DB_PATH = saved
        after = counts()
        for table, n in before.items():
            self.assertEqual(after[table], n, table)

        conn = sqlite3.connect(copy)
        names = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        self.assertTrue({"robot_accounts", "moderation_log"} <= names)
        self.assertIn("expires_at", [r[1] for r in conn.execute("PRAGMA table_info(sessions)")])
        self.assertIn("kick_permanent", [r[1] for r in conn.execute("PRAGMA table_info(bot_settings)")])
        conn.close()


if __name__ == "__main__":
    unittest.main()
