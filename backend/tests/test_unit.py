import asyncio
import os
import shutil
import tempfile
import threading
import time
import unittest
from unittest import mock

import security
from engine import BotSession, RuleMatcher, SessionManager, normalize
from superlive import DEFAULT_BASE_URL, PRIORITY_LOW, PRIORITY_URGENT, SuperLiveClient, SuperLiveError, build_ws_url, heartbeat_message, enter_message
import json


def rules(*pairs):
    return [{"keyword": k, "action": a} for k, a in pairs]


class NormalizeTests(unittest.TestCase):
    def test_strips_accents_case_and_spaces(self):
        self.assertEqual(normalize("  PaSSa   ZÁP  "), "passa zap")
        self.assertEqual(normalize("Não é"), "nao e")
        self.assertEqual(normalize(None), "")


class MatcherTests(unittest.TestCase):
    def test_whole_word_only(self):
        m = RuleMatcher(rules(("ass", "mute")))
        self.assertIsNone(m.match("vou passar la"))       # no Scunthorpe problem
        self.assertIsNotNone(m.match("que ass chato"))

    def test_case_and_accent_insensitive(self):
        m = RuleMatcher(rules(("palavrão", "mute")))
        self.assertEqual(m.match("Que PALAVRAO feio"), ("mute", "palavrão"))
        m = RuleMatcher(rules(("palavrao", "mute")))
        self.assertIsNotNone(m.match("PalavrÃo!"))

    def test_phrase_and_punctuation(self):
        m = RuleMatcher(rules(("passa zap", "mute")))
        self.assertIsNotNone(m.match("ei, passa   zap?"))
        self.assertIsNone(m.match("passa o zap"))

    def test_prefix_wildcard(self):
        m = RuleMatcher(rules(("puta*", "kick")))
        self.assertIsNotNone(m.match("que putaria"))
        self.assertIsNotNone(m.match("puta"))
        self.assertIsNone(m.match("computador"))

    def test_kick_has_priority_over_mute(self):
        m = RuleMatcher(rules(("zap", "mute"), ("feia", "kick")))
        self.assertEqual(m.match("zap sua feia"), ("kick", "feia"))
        self.assertEqual(m.match("manda zap"), ("mute", "zap"))

    def test_blank_and_empty_rules_are_ignored(self):
        m = RuleMatcher(rules(("", "mute"), ("   ", "kick"), ("*", "kick")))
        self.assertIsNone(m.match("qualquer coisa"))

    def test_no_match(self):
        self.assertIsNone(RuleMatcher(rules(("spam", "kick"))).match("oi gente, tudo bem?"))


class SecurityTests(unittest.TestCase):
    def test_hash_roundtrip_and_salting(self):
        h1, h2 = security.hash_password("segredo123"), security.hash_password("segredo123")
        self.assertNotEqual(h1, h2)
        self.assertEqual(security.verify_password("segredo123", h1), (True, False))
        self.assertEqual(security.verify_password("errada", h1), (False, False))

    def test_legacy_sha256_is_accepted_and_flagged_for_upgrade(self):
        import hashlib
        legacy = hashlib.sha256(b"antiga123").hexdigest()
        self.assertEqual(security.verify_password("antiga123", legacy), (True, True))
        self.assertEqual(security.verify_password("x", legacy), (False, False))

    def test_ip_keys_have_their_own_higher_budget(self):
        t = security.LoginThrottle(max_failures=3, window_seconds=60, ip_max_failures=10)
        for _ in range(5):
            t.record_failure("ip:1.2.3.4", "user:a")
        self.assertTrue(t.is_blocked("user:a"))           # 5 >= 3
        self.assertFalse(t.is_blocked("ip:1.2.3.4"))      # 5 < 10: one bucket must not lock everybody
        for _ in range(5):
            t.record_failure("ip:1.2.3.4")
        self.assertTrue(t.is_blocked("ip:1.2.3.4"))
        t.clear()
        self.assertFalse(t.is_blocked("ip:1.2.3.4", "user:a"))

    def test_hash_token_is_stable_and_not_the_token(self):
        tok = security.generate_token()
        self.assertEqual(security.hash_token(tok), security.hash_token(tok))
        self.assertNotEqual(security.hash_token(tok), tok)
        self.assertEqual(len(security.hash_token(tok)), 64)

    def test_robot_token_encryption_roundtrip_and_fail_closed(self):
        import os, tempfile
        from cryptography.fernet import Fernet
        saved = os.environ.get("SM_TOKEN_KEY_FILE")
        try:
            os.environ.pop("SM_TOKEN_KEY_FILE", None)
            with self.assertRaises(security.RobotKeyUnavailable):   # no key: never stored in clear
                security.encrypt_robot_token("tok")
            self.assertEqual(security.decrypt_robot_token("legacy-clear"), "legacy-clear")
            with tempfile.TemporaryDirectory() as d:
                good, other = os.path.join(d, "a"), os.path.join(d, "b")
                for path in (good, other):
                    with open(path, "wb") as fh:
                        fh.write(Fernet.generate_key())
                os.environ["SM_TOKEN_KEY_FILE"] = good
                blob = security.encrypt_robot_token("tok-secret")
                self.assertTrue(security.is_encrypted_token(blob))
                self.assertNotIn("tok-secret", blob)
                self.assertEqual(security.decrypt_robot_token(blob), "tok-secret")
                os.environ["SM_TOKEN_KEY_FILE"] = other
                with self.assertRaises(security.RobotKeyUnavailable):  # wrong key
                    security.decrypt_robot_token(blob)
        finally:
            if saved is None:
                os.environ.pop("SM_TOKEN_KEY_FILE", None)
            else:
                os.environ["SM_TOKEN_KEY_FILE"] = saved

    def test_throttle_blocks_after_max_failures(self):
        t = security.LoginThrottle(max_failures=3, window_seconds=60)
        for _ in range(3):
            t.record_failure("u")
        self.assertTrue(t.is_blocked("u"))
        self.assertFalse(t.is_blocked("other"))
        t.reset("u")
        self.assertFalse(t.is_blocked("u"))


class ProtocolTests(unittest.TestCase):
    def test_default_base_url_is_the_apps_api_v1_root(self):
        self.assertEqual(DEFAULT_BASE_URL, "https://api.sprlv-api.com/api/v1/")
        client = SuperLiveClient(base_url=DEFAULT_BASE_URL)
        self.assertEqual(client.base_url + "device/register".lstrip("/"),
                         "https://api.sprlv-api.com/api/v1/device/register")

    def test_device_header_only_once_a_device_id_exists(self):
        self.assertNotIn("Device-ID", SuperLiveClient()._headers(auth=False))
        headers = SuperLiveClient(token="t", device_id="dev-1")._headers(auth=True)
        self.assertEqual((headers["Device-ID"], headers["Authorization"]), ("dev-1", "Token t"))

    def test_ws_url(self):
        self.assertEqual(build_ws_url("wss://x/ws", "dev", "tok"), "wss://x/ws?device=dev&auth=tok")
        self.assertEqual(build_ws_url("wss://x/ws?a=1", "dev", "tok"), "wss://x/ws?a=1&device=dev&auth=tok")

    def test_client_frames_match_the_app_format(self):
        enter = json.loads(enter_message("L1"))
        self.assertEqual((enter["action"], enter["data"]), ("enter_livestream", {"livestream_id": "L1"}))
        hb = json.loads(heartbeat_message("L1"))
        self.assertEqual((hb["action"], hb["data"]), ("heartbeat", {"state": "livestream:L1"}))
        self.assertTrue(enter["id"])


class LeetspeakAndStretchedLettersTests(unittest.TestCase):
    def test_leetspeak_substitutions(self):
        m = RuleMatcher(rules(("goza", "kick")))
        self.assertIsNotNone(m.match("g0z4"))
        self.assertIsNotNone(m.match("g0za"))
        self.assertIsNotNone(m.match("goz4"))
        self.assertIsNotNone(m.match("g0z@"))
        self.assertIsNone(m.match("gozar fora disso"))  # different word still rejected

    def test_leetspeak_on_multiword_rule(self):
        m = RuleMatcher(rules(("passa zap", "mute")))
        self.assertIsNotNone(m.match("p4ss4 z4p"))
        self.assertIsNotNone(m.match("p4ss4z4p"))  # leetspeak + connected words together

    def test_stretched_letters_are_collapsed(self):
        m = RuleMatcher(rules(("goza", "kick")))
        self.assertIsNotNone(m.match("gozzzaaa"))
        self.assertIsNotNone(m.match("goooza"))
        # a real legitimate double letter must still not falsely match an
        # unrelated rule just because collapsing kicks in
        m2 = RuleMatcher(rules(("feia", "kick")))
        self.assertIsNone(m2.match("carro assado"))

    def test_trailing_punctuation_does_not_break_word_boundary(self):
        # Regression: "!" must not be treated as leetspeak for "i" - that
        # turned every sentence ending in "!" into one that no longer ends
        # with the banned word at all ("palavrao!" -> "palavraoi").
        m = RuleMatcher(rules(("palavrao", "kick")))
        self.assertIsNotNone(m.match("que PALAVRAO!"))
        self.assertIsNotNone(m.match("palavrao!!!"))

    def test_normalize_helper_directly(self):
        self.assertEqual(normalize("g0z4"), "goza")
        self.assertEqual(normalize("P4SS4 Z4P"), "passa zap")  # "ss" is only 2 - stays (3+ needed to collapse)
        self.assertEqual(normalize("gozzzaaa"), "goza")

    def test_digit_keyword_matches_only_the_literal_digit_spelling(self):
        # Regra escrita com numero ("d4") significa a grafia literal com
        # numero, nao a traducao letra-a-letra ("da") - senao toda mensagem
        # com a palavra comum "da" seria pega.
        m = RuleMatcher(rules(("d4", "kick")))
        self.assertIsNotNone(m.match("d4"))
        self.assertIsNotNone(m.match("quero d4 com ela"))
        self.assertIsNone(m.match("gostei da live"))
        self.assertIsNone(m.match("amei da hora"))

    def test_digit_keyword_still_collapses_stretching_and_case(self):
        m = RuleMatcher(rules(("d4", "kick")))
        self.assertIsNotNone(m.match("D4"))
        self.assertIsNotNone(m.match("d444"))


class AntiEvasionAndNewRulesTests(unittest.TestCase):
    def test_banned_username_w(self):
        from engine import is_banned_username
        self.assertTrue(is_banned_username("w"))
        self.assertTrue(is_banned_username("W"))
        self.assertTrue(is_banned_username(" w "))
        self.assertTrue(is_banned_username("w\u200b"))
        self.assertTrue(is_banned_username("  W\t\n "))
        self.assertFalse(is_banned_username("william"))
        self.assertFalse(is_banned_username("ww"))
        self.assertFalse(is_banned_username("a"))
        self.assertFalse(is_banned_username(""))
        self.assertFalse(is_banned_username(None))

    def test_connected_words_anti_evasion(self):
        # Regra com palavras compostas
        m = RuleMatcher(rules(("passa zap", "mute")))
        self.assertIsNotNone(m.match("passa zap"))
        self.assertIsNotNone(m.match("passazap"))        # Conectadas diretamente
        self.assertIsNotNone(m.match("passa-zap"))       # Conectadas com hífen
        self.assertIsNotNone(m.match("passa_zap"))       # Conectadas com underline
        self.assertIsNotNone(m.match("passa.zap"))       # Conectadas com ponto
        self.assertIsNotNone(m.match("p.a.s.s.a z.a.p")) # Letras separadas por pontos
        self.assertIsNone(m.match("passar"))
        self.assertIsNone(m.match("passar o cafe"))

    def test_single_word_delimiters_and_intra_word(self):
        m = RuleMatcher(rules(("zap", "mute")))
        self.assertIsNotNone(m.match("manda no _zap_"))   # Delimitador com _
        self.assertIsNotNone(m.match("manda no -zap-"))   # Delimitador com -
        self.assertIsNotNone(m.match("chama no z.a.p"))   # Letras conectadas por .
        self.assertIsNone(m.match("zapato"))              # Palavra diferente

    def test_live_summary_emission(self):
        from engine import BotSession
        import time

        class DummyClient:
            device_id = "dev"
            token = "tok"

        session = BotSession(user_id=1, client=DummyClient(), robot_sl_id="bot1", livestream_id="live999")
        session._live_start_time = time.monotonic() - 65  # 1m 5s atrás
        session._live_chat_seen = 42
        session._live_messages_sent = 3
        session._live_mutes_count = 2
        session._live_kicks_count = 1
        session._diamonds["user_a"] = 100
        session._diamonds["user_b"] = 50

        summary = session._emit_live_summary("live999")
        self.assertIsNotNone(summary)
        self.assertEqual(summary["livestream_id"], "live999")
        self.assertEqual(summary["chat_seen"], 42)
        self.assertEqual(summary["messages_sent"], 3)
        self.assertEqual(summary["mutes"], 2)
        self.assertEqual(summary["kicks"], 1)
        self.assertEqual(summary["actions_ok"], 3)
        self.assertEqual(summary["diamonds"], 150)
        self.assertIn("Resumo da Live live999", summary["summary_text"])
        self.assertEqual(session.last_live_summary, summary)
        self.assertTrue(len(session.alerts) > 0)


class RealClientIpTests(unittest.IsolatedAsyncioTestCase):
    """The chain is cata-pobre nginx -> web nginx -> backend. Each nginx *appends*
    to X-Forwarded-For, so the backend sees "<whatever the client sent>, <real ip>,
    <cata nginx ip>" from the web container. uvicorn must take the right-most
    address that is not a trusted proxy, and ignore the header from anyone else."""
    WEB, CATA = "172.28.0.10", "172.18.0.5"

    async def seen_client(self, trusted, peer, xff):
        from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware
        got = {}

        async def app(scope, receive, send):
            got["client"] = scope["client"][0]

        mw = ProxyHeadersMiddleware(app, trusted_hosts=trusted)
        scope = {"type": "http", "client": (peer, 40000), "headers": [(b"x-forwarded-for", xff.encode())]}
        await mw(scope, None, None)
        return got["client"]

    async def test_real_ip_is_taken_when_both_proxies_are_trusted(self):
        ip = await self.seen_client(f"{self.WEB},{self.CATA}", self.WEB, f"203.0.113.9, {self.CATA}")
        self.assertEqual(ip, "203.0.113.9")

    async def test_a_forged_header_from_the_client_cannot_win(self):
        ip = await self.seen_client(f"{self.WEB},{self.CATA}", self.WEB,
                                    f"6.6.6.6, 203.0.113.9, {self.CATA}")   # client prepended 6.6.6.6
        self.assertEqual(ip, "203.0.113.9")

    async def test_header_from_an_untrusted_peer_is_ignored(self):
        # a neighbour container talking straight to the backend / web
        ip = await self.seen_client(f"{self.WEB},{self.CATA}", "172.28.0.77", "1.2.3.4")
        self.assertEqual(ip, "172.28.0.77")

    async def test_unpinned_cata_ip_fails_closed_to_the_proxy_address(self):
        # cata not in the trusted list (its IP changed): everybody looks like the
        # proxy - the old shared-bucket behaviour, never an attacker-chosen address.
        ip = await self.seen_client(self.WEB, self.WEB, f"6.6.6.6, 203.0.113.9, {self.CATA}")
        self.assertEqual(ip, self.CATA)

    async def test_default_trusts_nobody_but_loopback(self):
        ip = await self.seen_client("127.0.0.1", self.WEB, "1.2.3.4")
        self.assertEqual(ip, self.WEB)


class _FakeClient:
    device_id = "dev"
    token = "tok"

    def __init__(self):
        self.calls = []

    async def mute(self, live_id, user_id):
        self.calls.append(("mute", live_id, user_id))

    async def kick(self, live_id, user_id, permanent=False):
        self.calls.append(("kick", live_id, user_id))


class StaleActionAndEndDebounceTests(unittest.IsolatedAsyncioTestCase):
    """The action queue used to run with whatever livestream_id the session had
    when the action was *executed*, and was never emptied when a live ended or
    switched. Also: one "not live" lookup used to end the session."""

    def make(self, live="live1"):
        from engine import BotSession
        client = _FakeClient()
        session = BotSession(user_id=1, client=client, robot_sl_id="bot", livestream_id=live)
        session.state = "running"
        return session, client

    def entry(self, uid="u1"):
        from engine import ChatEntry
        return ChatEntry(id="1", user_id=uid, name="N", text="passa zap", ts="t")

    async def test_action_runs_against_the_live_it_was_queued_for(self):
        from unittest import mock
        session, client = self.make("live1")
        with mock.patch("engine.db.log_action") as log_action:
            await session._execute(self.entry(), "mute", "zap", "live1")
        self.assertEqual(client.calls, [("mute", "live1", "u1")])
        self.assertEqual(log_action.call_args.args[1], "live1")

    async def test_stale_action_is_dropped_after_the_live_switched(self):
        from unittest import mock
        session, client = self.make("live2")           # session moved on to live2
        with mock.patch("engine.db.log_action") as log_action:
            await session._execute(self.entry(), "kick", "zap", "live1")    # decided in live1
            await session._execute(self.entry(), "kick", "zap", None)       # no live at queue time
        self.assertEqual(client.calls, [])
        log_action.assert_not_called()

    async def test_drain_queue_empties_it_and_releases_pending(self):
        session, _ = self.make("live1")
        for uid in ("a", "b"):
            session._queue.put_nowait((self.entry(uid), "mute", "k", "live1"))
            session._pending.add((uid, "mute"))
        session._drain_queue()
        self.assertTrue(session._queue.empty())
        self.assertEqual(session._pending, set())

    async def test_on_live_ended_and_switch_drain_the_queue(self):
        session, _ = self.make("live1")
        session.streamer_id = "streamer"               # has a target -> goes to waiting_for_live
        session._queue.put_nowait((self.entry(), "mute", "k", "live1"))
        session._pending.add(("u1", "mute"))
        await session.on_live_ended()
        self.assertEqual(session.state, "waiting_for_live")
        self.assertTrue(session._queue.empty())
        self.assertEqual(session._pending, set())

    async def _confirm(self, statuses, live_changes_to=None, **kw):
        import engine
        session, _ = self.make("live1")
        seq = list(statuses)

        async def fake_status():
            if live_changes_to:
                session.livestream_id = live_changes_to
            return seq.pop(0)

        session._check_live_status = fake_status
        old = engine.LIVE_END_RECHECK_SECONDS
        engine.LIVE_END_RECHECK_SECONDS = 0
        try:
            return await session._confirm_live_ended(**kw)
        finally:
            engine.LIVE_END_RECHECK_SECONDS = old

    async def test_end_is_confirmed_only_if_the_recheck_agrees(self):
        self.assertTrue(await self._confirm([False]))

    async def test_a_single_flaky_lookup_does_not_end_the_live(self):
        self.assertFalse(await self._confirm([True]))          # it is still live
        self.assertFalse(await self._confirm(["live9"]))       # moved to another broadcast
        self.assertFalse(await self._confirm([None]))          # could not tell -> not an end

    async def test_unknown_counts_only_on_the_error_path(self):
        self.assertTrue(await self._confirm([None], accept_unknown=True))

    async def test_confirmation_is_cancelled_if_the_session_already_moved_on(self):
        self.assertFalse(await self._confirm([False], live_changes_to="live2"))


class SessionManagerRaceTests(unittest.IsolatedAsyncioTestCase):
    """Regression: two concurrent /robot/start calls for the same user used to
    both pass the "no active session" check (nothing was registered until
    after BotSession.start() awaited), so both could end up believing they
    own the session. Now the session is registered before that await,
    closing the window."""

    async def test_concurrent_start_calls_do_not_both_succeed(self):
        sessions = SessionManager()
        release = asyncio.Event()

        async def slow_start(self):
            await release.wait()
            self.state = "running"

        with mock.patch.object(BotSession, "start", slow_start):
            t1 = asyncio.create_task(sessions.start(1, None, None, "live1"))
            t2 = asyncio.create_task(sessions.start(1, None, None, "live1"))
            await asyncio.sleep(0)  # let both tasks reach the patched await
            release.set()
            results = await asyncio.gather(t1, t2, return_exceptions=True)

        successes = [r for r in results if not isinstance(r, Exception)]
        errors = [r for r in results if isinstance(r, Exception)]
        self.assertEqual(len(successes), 1, results)
        self.assertEqual(len(errors), 1, results)
        self.assertIsInstance(errors[0], RuntimeError)
        self.assertIs(sessions.get(1), successes[0])

    async def test_failed_start_restores_the_previous_stopped_session(self):
        """The watch loop's "stopped on this exact live, wait for a genuinely
        new one" guard depends on finding the old session object after a
        failed restart attempt - not an empty slot (see WatchManager)."""
        sessions = SessionManager()
        previous = BotSession(1, None, None, "live_old")
        previous.state = "stopped"
        sessions._sessions[1] = previous

        async def failing_start(self):
            raise RuntimeError("boom")

        with mock.patch.object(BotSession, "start", failing_start):
            with self.assertRaises(RuntimeError):
                await sessions.start(1, None, None, "live_new")

        self.assertIs(sessions.get(1), previous)

    async def test_cancelled_start_frees_the_slot(self):
        """A CancelledError (client disconnect, shutdown) is not an Exception;
        it used to leave the slot stuck in "starting" until a restart."""
        sessions = SessionManager()

        async def hanging_start(self):
            await asyncio.Event().wait()

        with mock.patch.object(BotSession, "start", hanging_start):
            task = asyncio.create_task(sessions.start(1, None, None, "live1"))
            await asyncio.sleep(0)
            task.cancel()
            with self.assertRaises(asyncio.CancelledError):
                await task

        self.assertIsNone(sessions.get(1))

    async def test_global_session_cap(self):
        sessions = SessionManager()

        async def ok_start(self):
            self.state = "running"

        with mock.patch.object(BotSession, "start", ok_start),                 mock.patch.dict("os.environ", {"SM_MAX_SESSIONS": "2"}):
            await sessions.start(1, None, None, "a")
            await sessions.start(2, None, None, "b")
            with self.assertRaises(RuntimeError):
                await sessions.start(3, None, None, "c")
        self.assertIsNone(sessions.get(3))


class Dispatcher429Tests(unittest.IsolatedAsyncioTestCase):
    async def test_429_pauses_the_whole_queue_without_retrying(self):
        calls = []

        def fake_post(self, path, body, auth):
            calls.append((path, time.monotonic()))
            if len(calls) == 1:
                raise SuperLiveError("slow down", 429, None, retry_after=0.3)
            return {}

        with mock.patch.object(SuperLiveClient, "_post_sync", fake_post),                 mock.patch.dict("os.environ", {"SUPERLIVE_REQUEST_SPACING": "0"}):
            client = SuperLiveClient("tok", "dev")
            with self.assertRaises(SuperLiveError):
                await client.post("a", {})
            await client.post("b", {}, priority=PRIORITY_URGENT)

        self.assertEqual([c[0] for c in calls], ["a", "b"])  # "a" not retried
        self.assertGreaterEqual(calls[1][1] - calls[0][1], 0.28)


class ThrottleAwarePollingTests(unittest.IsolatedAsyncioTestCase):
    async def test_a_429_marks_the_egress_and_halves_its_polling_budget(self):
        import superlive
        from engine import WatchManager

        def fake_post(self, path, body, auth):
            raise SuperLiveError("slow down", 429, None, retry_after=0.01)

        proxy = "socks5h://throttled-egress:1080"
        superlive._last_429.pop(proxy, None)
        self.assertFalse(superlive.recently_throttled(proxy))
        with mock.patch.object(SuperLiveClient, "_post_sync", fake_post), \
                mock.patch.dict("os.environ", {"SUPERLIVE_REQUEST_SPACING": "0"}):
            with self.assertRaises(SuperLiveError):
                await SuperLiveClient("t", "d", proxy_url=proxy).post("a", {})
        self.assertTrue(superlive.recently_throttled(proxy))
        self.assertFalse(superlive.recently_throttled("socks5h://other:1080"))

        mgr = WatchManager.__new__(WatchManager)
        mgr._mult = {i: 1.0 for i in range(150)}
        mgr._egress = {i: proxy for i in range(150)}
        throttled = mgr._poll_interval(proxy, 0)
        superlive._last_429.pop(proxy, None)
        normal = mgr._poll_interval(proxy, 0)
        self.assertGreater(throttled, normal * 1.6)


class PasswordRulesTests(unittest.TestCase):
    def test_accepts_a_long_password_with_letters_and_digits(self):
        self.assertEqual(security.password_problems("Bolo-de-cenoura-42", "maria", "Maria Souza"), [])

    def test_each_rule_reports_its_own_reason(self):
        self.assertTrue(any("pelo menos" in p for p in security.password_problems("abc123")))
        self.assertTrue(any("letras e números" in p for p in security.password_problems("abcdefghijkl")))
        self.assertTrue(any("nome de usuário" in p for p in security.password_problems("xx-Maria.Souza-91", "maria.souza")))
        self.assertTrue(any("nome de exibição" in p for p in security.password_problems("Fulana_de_Tal-77", "u1", "Fulana de Tal")))
        self.assertTrue(any("comum" in p for p in security.password_problems("Senha@123456")))
        self.assertTrue(any("sequências" in p for p in security.password_problems("1234567890")))

    def test_temporary_passwords_are_random_and_unambiguous(self):
        seen = {security.generate_temp_password() for _ in range(50)}
        self.assertEqual(len(seen), 50)
        for pw in seen:
            self.assertRegex(pw, r"^[A-Za-z2-9]{4}-[A-Za-z2-9]{4}-[A-Za-z2-9]{4}$")
            self.assertFalse(set(pw) & set("0O1lI"))


class UsernameMigrationTests(unittest.TestCase):
    def test_startup_with_names_that_differ_only_by_case_does_not_crash_or_delete_anything(self):
        import sqlite3
        import tempfile
        import db as dbmod
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "old.db")
            old = sqlite3.connect(path)
            old.execute("CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT UNIQUE NOT NULL, "
                        "email TEXT UNIQUE NOT NULL, display_name TEXT, password_hash TEXT NOT NULL, "
                        "is_admin INTEGER DEFAULT 0, created_at TEXT DEFAULT (datetime('now')))")
            old.executemany("INSERT INTO users (username, email, password_hash) VALUES (?,?,?)",
                            [("Nyx", "a@x.com", "h"), ("nyx", "b@x.com", "h")])
            old.commit()
            old.close()
            with mock.patch.object(dbmod, "DB_PATH", path):
                with self.assertLogs("super_moderator.db", level="ERROR") as cm:
                    dbmod.init_db()
                conn = sqlite3.connect(path)
                names = [r[0] for r in conn.execute("SELECT username FROM users ORDER BY id")]
                cols = [r[1] for r in conn.execute("PRAGMA table_info(users)")]
                conn.close()
            self.assertEqual(names, ["Nyx", "nyx"])          # nothing renamed or removed
            self.assertIn("must_change_password", cols)      # the rest of the migration still ran
            self.assertIn("differ only by case", "\n".join(cm.output))


class OrphanSweepTests(unittest.IsolatedAsyncioTestCase):
    async def test_sessions_and_watches_of_deleted_users_are_stopped_and_dropped(self):
        import sqlite3
        import tempfile
        import db as dbmod
        import main as mainmod

        class FakeSessions:
            def __init__(self):
                self.held, self.dropped = {1: object(), 2: object()}, []

            def all_sessions(self):
                return dict(self.held)

            async def drop(self, user_id, reason):
                self.dropped.append((user_id, reason))

        class FakeWatchers:
            def __init__(self):
                self.stopped = []

            def watching_ids(self):
                return [2, 3]

            async def stop(self, user_id):
                self.stopped.append(user_id)

        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "t.db")
            with mock.patch.object(dbmod, "DB_PATH", path):
                dbmod.init_db()
                conn = sqlite3.connect(path)
                conn.execute("INSERT INTO users (id, username, email, password_hash) VALUES (1, 'viva', 'v@x.invalid', 'h')")
                conn.commit()
                conn.close()
                fake_sessions, fake_watchers = FakeSessions(), FakeWatchers()
                with mock.patch.object(mainmod, "sessions", fake_sessions), \
                        mock.patch.object(mainmod, "watchers", fake_watchers), \
                        self.assertLogs("super_moderator.main", level="WARNING"):
                    gone = await mainmod.reap_deleted_users()
        self.assertEqual(gone, [2, 3])                       # user 1 still exists: untouched
        self.assertEqual(fake_watchers.stopped, [2, 3])
        self.assertEqual([uid for uid, _ in fake_sessions.dropped], [2, 3])

    async def test_nothing_held_means_no_database_work(self):
        import main as mainmod

        class Empty:
            def all_sessions(self): return {}
            def watching_ids(self): return []

        with mock.patch.object(mainmod, "sessions", Empty()), mock.patch.object(mainmod, "watchers", Empty()):
            self.assertEqual(await mainmod.reap_deleted_users(), [])


class WatchLookupLoggingTests(unittest.TestCase):
    def _mgr(self):
        from engine import WatchManager
        mgr = WatchManager.__new__(WatchManager)
        mgr._last_lookup = {}
        mgr._diverge_warned = {}
        return mgr

    def test_logs_only_changes_and_warns_when_two_robots_disagree(self):
        mgr = self._mgr()
        with self.assertLogs("super_moderator.engine", level="INFO") as cm:
            mgr._note_lookup(1, "69", 0, True, "L1")      # first answer: logged
            mgr._note_lookup(1, "69", 0, True, "L1")      # unchanged: silent
            mgr._note_lookup(2, "69", 0, False, None)     # first answer + disagrees with robot 1
        text = "\n".join(cm.output)
        self.assertEqual(text.count("lookup of 69"), 2)
        self.assertIn("watch divergence on 69", text)

    def test_a_persistent_disagreement_is_reported_once_not_every_poll(self):
        mgr = self._mgr()
        with self.assertLogs("super_moderator.engine", level="WARNING") as cm:
            mgr._note_lookup(1, "69", 0, True, "L1")
            for _ in range(5):
                mgr._note_lookup(2, "69", 0, False, None)
                mgr._note_lookup(1, "69", 0, True, "L1")
        self.assertEqual("\n".join(cm.output).count("watch divergence"), 1)

    def test_agreeing_robots_do_not_warn(self):
        mgr = self._mgr()
        with self.assertLogs("super_moderator.engine", level="INFO") as cm:
            mgr._note_lookup(1, "69", 0, True, "L1")
            mgr._note_lookup(2, "69", 0, True, "L1")
        self.assertNotIn("divergence", "\n".join(cm.output))


class EgressPoolTests(unittest.IsolatedAsyncioTestCase):
    """Scale: one serial queue PER egress IP (the SuperLive collision rule is per IP),
    background polling shed first, and a fixed least-loaded egress per user."""

    async def test_each_egress_has_its_own_queue(self):
        def slow_post(self, path, body, auth):
            time.sleep(0.05)
            return {}

        with mock.patch.object(SuperLiveClient, "_post_sync", slow_post), \
                mock.patch.dict("os.environ", {"SUPERLIVE_REQUEST_SPACING": "0.3"}):
            a = SuperLiveClient("t", "d", proxy_url="socks5h://egress-a:1080")
            b = SuperLiveClient("t", "d", proxy_url="socks5h://egress-b:1080")
            await a.post("warmup", {})
            await b.post("warmup", {})
            await asyncio.sleep(0.35)   # let every egress's spacing window expire
            start = time.monotonic()
            await asyncio.gather(a.post("x", {}), b.post("x", {}))      # different IPs: in parallel
            parallel = time.monotonic() - start
            await asyncio.sleep(0.35)
            start = time.monotonic()
            await asyncio.gather(a.post("x", {}), a.post("y", {}))      # same IP: one after the other
            serial = time.monotonic() - start
        self.assertLess(parallel, 0.25)
        self.assertGreaterEqual(serial, 0.3)

    async def test_background_polling_is_shed_when_the_line_is_long(self):
        release = threading.Event()

        def blocking_post(self, path, body, auth):
            release.wait(5)
            return {}

        with mock.patch.object(SuperLiveClient, "_post_sync", blocking_post), \
                mock.patch.dict("os.environ", {"SUPERLIVE_REQUEST_SPACING": "0",
                                               "SUPERLIVE_LOW_QUEUE_MAX": "2"}):
            c = SuperLiveClient("t", "d", proxy_url="socks5h://egress-shed:1080")
            busy = [asyncio.create_task(c.post("a", {})) for _ in range(4)]
            await asyncio.sleep(0.1)  # 1 in flight, 3 waiting
            with self.assertRaises(SuperLiveError):
                await c.post("poll", {}, priority=PRIORITY_LOW)
            urgent = asyncio.create_task(c.post("mute", {}, priority=PRIORITY_URGENT))  # never shed
            release.set()
            await asyncio.gather(*busy, urgent)

    async def test_shared_id_is_resolved_once_then_polled_with_one_request(self):
        import superlive
        superlive._shared_id_cache.clear()
        seen = []

        def fake_post(self, path, body, auth):
            seen.append(path)
            if path == "users/search":
                return {"items": [{"shared_id": "123", "user_id": "u9", "name": "S"}]}
            return {"user": {"user_id": "u9", "name": "S", "livestream_id": "live7"}}

        with mock.patch.object(SuperLiveClient, "_post_sync", fake_post), \
                mock.patch.dict("os.environ", {"SUPERLIVE_REQUEST_SPACING": "0"}):
            c = SuperLiveClient("t", "d", proxy_url="")
            first = await c.find_live_by_shared_id("123")
            second = await c.find_live_by_shared_id("123")
        self.assertEqual(seen, ["users/search", "users/profile", "users/profile"])
        self.assertEqual(first["livestream_id"], second["livestream_id"])

    def test_pool_parsing_and_wraparound(self):
        import superlive
        with mock.patch.dict("os.environ", {"SUPERLIVE_PROXY_URLS": " socks5h://a:1 , socks5h://b:1 ,"}):
            self.assertEqual(superlive.get_proxy_pool(), ["socks5h://a:1", "socks5h://b:1"])
            self.assertEqual(superlive.proxy_for_slot(1), "socks5h://b:1")
            self.assertEqual(superlive.proxy_for_slot(5), "socks5h://b:1")   # pool shrank: wraps
            self.assertEqual(superlive.proxy_for_slot(None), "socks5h://a:1")
        with mock.patch.dict("os.environ", {"SUPERLIVE_PROXY_URLS": "", "SUPERLIVE_PROXY_URL": "socks5h://old:1"}):
            self.assertEqual(superlive.get_proxy_pool(), ["socks5h://old:1"])

    def test_poll_interval_grows_with_watchers_per_egress(self):
        from engine import watch_poll_interval
        with mock.patch.dict("os.environ", {"SM_POLL_BUDGET_RPS": "1.5"}):
            self.assertEqual(watch_poll_interval(0), 30)
            self.assertEqual(watch_poll_interval(20), 30)            # small: stays at the floor
            self.assertAlmostEqual(watch_poll_interval(150), 100)    # 150 / 1.5
            self.assertAlmostEqual(watch_poll_interval(500), 500 / 1.5)
        with mock.patch.dict("os.environ", {"SM_POLL_BUDGET_RPS": "junk"}):
            self.assertGreaterEqual(watch_poll_interval(10), 30)


class EgressSlotAssignmentTests(unittest.TestCase):
    def setUp(self):
        import db
        self.db = db
        self.old_path = db.DB_PATH
        self.tmp = tempfile.mkdtemp(prefix="sm-slot-")
        db.DB_PATH = os.path.join(self.tmp, "t.db")
        db.init_db()
        self.conn = db.connect()
        for i in range(1, 10):
            self.conn.execute("INSERT INTO users (username, email, password_hash) VALUES (?, ?, 'x')",
                              (f"u{i}", f"u{i}@x.com"))
        self.conn.commit()

    def tearDown(self):
        self.conn.close()
        self.db.DB_PATH = self.old_path
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_spreads_evenly_and_never_moves_a_user(self):
        slots = [self.db.get_or_assign_egress_slot(self.conn, uid, 3) for uid in range(1, 10)]
        self.assertEqual(sorted(slots), [0, 0, 0, 1, 1, 1, 2, 2, 2])
        again = [self.db.get_or_assign_egress_slot(self.conn, uid, 3) for uid in range(1, 10)]
        self.assertEqual(slots, again)

    def test_single_egress_keeps_everyone_on_slot_zero(self):
        self.assertEqual({self.db.get_or_assign_egress_slot(self.conn, uid, 1) for uid in range(1, 10)}, {0})

    def test_new_proxy_added_later_gets_the_next_users_only(self):
        for uid in range(1, 5):
            self.db.get_or_assign_egress_slot(self.conn, uid, 1)          # 4 users on the only IP
        later = [self.db.get_or_assign_egress_slot(self.conn, uid, 2) for uid in range(5, 9)]
        self.assertEqual(later, [1, 1, 1, 1])                              # the empty IP fills first
        self.assertEqual([self.db.get_or_assign_egress_slot(self.conn, uid, 2) for uid in range(1, 5)],
                         [0, 0, 0, 0])                                     # existing users keep their IP

    def test_existing_robot_owners_are_migrated_to_slot_zero(self):
        self.conn.execute("DELETE FROM users WHERE id > 2")
        self.conn.execute("INSERT INTO robot_accounts (user_id, sl_user_id, token, device_id) "
                          "VALUES (1, '555', 't', 'd')")
        self.conn.execute("UPDATE users SET egress_slot = NULL")
        self.conn.execute("ALTER TABLE users DROP COLUMN egress_slot")
        self.conn.commit()
        self.db.init_db()
        row = {r["id"]: r["egress_slot"] for r in self.conn.execute("SELECT id, egress_slot FROM users")}
        self.assertEqual(row[1], 0)       # had a robot: stays on the original IP
        self.assertIsNone(row[2])         # no robot yet: assigned on first use


class ProxyOutageTests(unittest.IsolatedAsyncioTestCase):
    async def test_a_dead_proxy_does_not_burn_the_websocket_failure_budget(self):
        import engine
        client = _FakeClient()
        client.proxy_url = "socks5h://dead:1080"
        session = BotSession(1, client, "r1", "live1")
        session.state = "running"
        session._ws_url = "wss://unused"
        calls = []
        real_sleep = asyncio.sleep

        async def dead_proxy(url, proxy_url=None, **kwargs):
            calls.append(proxy_url)
            raise ConnectionRefusedError("socks proxy down")

        async def fast_sleep(_seconds):
            await real_sleep(0)

        with mock.patch.object(engine, "_ws_connect", dead_proxy), \
                mock.patch("engine.asyncio.sleep", fast_sleep):
            task = asyncio.create_task(session._ws_loop())
            for _ in range(500):
                if len(calls) > engine.MAX_WS_FAILURES + 5:
                    break
                await real_sleep(0.001)
            self.assertGreater(len(calls), engine.MAX_WS_FAILURES + 5)
            self.assertTrue(session.is_active)                  # a dead proxy is not a dead session
            self.assertIn("proxy", session.ws_error)
            self.assertEqual(calls[0], "socks5h://dead:1080")   # the user's own egress, not a global one
            task.cancel()
            with self.assertRaises(asyncio.CancelledError):
                await task


class AdaptiveWatchTests(unittest.IsolatedAsyncioTestCase):
    """Fewer requests per creator: hot/cold polling weights, no duplicate polling
    by the session while the watcher covers her."""

    NOW = __import__("datetime").datetime(2026, 10, 13, 21, 0, 0)

    def days_ago(self, days, hour=21):
        import datetime as dt
        d = self.NOW - dt.timedelta(days=days)
        return d.replace(hour=hour, minute=10)

    def mult(self, starts=(), last_end=None, created=None, state=None):
        from engine import watch_multiplier
        created = created or self.NOW.replace(year=2026, month=1)
        return watch_multiplier(list(starts), last_end, self.NOW, created, state)

    def test_creator_who_usually_goes_live_at_this_hour_is_polled_twice_as_often(self):
        self.assertEqual(self.mult([self.days_ago(1), self.days_ago(3), self.days_ago(8)]), 0.5)
        # +-1 hour counts, 4 hours away does not
        self.assertEqual(self.mult([self.days_ago(1, 22), self.days_ago(2, 20), self.days_ago(3, 21)]), 0.5)
        self.assertEqual(self.mult([self.days_ago(1, 17), self.days_ago(2, 17), self.days_ago(3, 17)]), 1.0)

    def test_two_lives_on_the_same_day_are_one_day_not_two(self):
        d = self.days_ago(1)
        self.assertEqual(self.mult([d, d.replace(hour=22), self.days_ago(2)]), 1.0)

    def test_no_lives_for_two_weeks_means_polled_four_times_less(self):
        self.assertEqual(self.mult([self.days_ago(16, 3)]), 4.0)
        self.assertEqual(self.mult([]), 4.0)

    def test_a_brand_new_account_is_not_cold_yet(self):
        import datetime as dt
        self.assertEqual(self.mult([], created=self.NOW - dt.timedelta(days=3)), 1.0)

    def test_just_ended_live_and_session_state_override_history(self):
        import datetime as dt
        self.assertEqual(self.mult([], last_end=self.NOW - dt.timedelta(minutes=5)), 0.5)
        self.assertEqual(self.mult([], last_end=self.NOW - dt.timedelta(minutes=45)), 4.0)
        self.assertEqual(self.mult([], state="waiting_for_live"), 0.5)
        self.assertEqual(self.mult([self.days_ago(1), self.days_ago(2), self.days_ago(3)], state="running"), 2.0)

    def test_intervals_share_the_budget_and_hot_creators_wait_less(self):
        import engine
        wm = engine.WatchManager(SessionManager())
        # 500 creators on one egress: 50 hot (0.5), 450 cold (4)
        for uid in range(500):
            wm._egress[uid] = "px"
            wm._mult[uid] = 0.5 if uid < 50 else 4.0
        with mock.patch.dict("os.environ", {"SM_POLL_BUDGET_RPS": "1.5"}), \
                mock.patch("engine.random.uniform", lambda a, b: 1.0):
            hot, cold = wm._poll_interval("px", 0), wm._poll_interval("px", 499)
            self.assertLess(hot, 90)                                  # was 333 s for everyone
            self.assertLessEqual(cold, engine.WATCH_COLD_MAX_INTERVAL_SECONDS)
            rate = sum(1 / wm._poll_interval("px", u) for u in range(500))
            self.assertLessEqual(rate, 1.5 * 1.15)                   # the egress budget still holds

    async def test_session_does_not_poll_while_the_watcher_covers_her(self):
        import engine
        client = _FakeClient()
        session = BotSession(1, client, "r1", "live1")
        session.state = "running"
        asked = []

        async def fake_check():
            asked.append(1)
            return True

        session._check_live_status = fake_check
        with mock.patch.object(engine, "LIVE_POLL_INTERVAL_SECONDS", 0.02):
            task = asyncio.create_task(session._live_monitor_loop())
            session.watch_covers_until = time.monotonic() + 60
            await asyncio.sleep(0.15)
            self.assertEqual(asked, [])                               # covered: zero requests
            session.watch_covers_until = 0.0                           # watcher gone: back to self-polling
            await asyncio.sleep(0.15)
            self.assertGreater(len(asked), 0)
            task.cancel()
            with self.assertRaises(asyncio.CancelledError):
                await task


class LivePatternDbTests(unittest.TestCase):
    def test_reads_starts_and_last_end_from_the_activity_log(self):
        import db
        old = db.DB_PATH
        tmp = tempfile.mkdtemp(prefix="sm-pattern-")
        db.DB_PATH = os.path.join(tmp, "p.db")
        try:
            db.init_db()
            conn = db.connect()
            conn.execute("INSERT INTO users (username, email, password_hash) VALUES ('a', 'a@x.com', 'x')")
            rows = [("session_auto_started", "-1 days"), ("session_started", "-2 days"),
                    ("favorite_live_connected", "-3 days"), ("live_ended", "-2 days"),
                    ("login", "-1 days"), ("session_auto_started", "-40 days")]
            for action, delta in rows:
                conn.execute("INSERT INTO user_activity_log (user_id, action, created_at) "
                             "VALUES (1, ?, datetime('now', ?))", (action, delta))
            conn.commit()
            starts, last_end, created = db.get_live_pattern(conn, 1)
            self.assertEqual(len(starts), 3)          # login ignored, the 40-day-old start is outside 21 days
            self.assertIsNotNone(last_end)
            self.assertIsNotNone(created)
            conn.close()
        finally:
            db.DB_PATH = old
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
