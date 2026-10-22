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


class _EgressClient:
    device_id = "d"
    token = "t"

    def __init__(self, proxy):
        self.proxy_url = proxy


class PerEgressCapTests(unittest.IsolatedAsyncioTestCase):
    """14 robots per egress IP (SM_SESSIONS_PER_EGRESS), counting the ones waiting for the
    streamer's next live; another IP has its own allowance."""

    def patched(self, **env):
        async def ok_start(self):
            self.state = "running"

        base = {"SM_SESSIONS_PER_EGRESS": "3", "SM_MAX_SESSIONS": "0"}
        base.update({k: str(v) for k, v in env.items()})
        return mock.patch.object(BotSession, "start", ok_start), mock.patch.dict("os.environ", base)

    async def test_the_robot_past_the_cap_on_one_ip_is_refused_but_another_ip_is_free(self):
        sessions = SessionManager()
        p1, p2 = self.patched()
        with p1, p2:
            for uid in (1, 2, 3):
                await sessions.start(uid, _EgressClient("socks5h://ip-a:1"), "bot", "L")
            with self.assertRaises(RuntimeError) as cm:
                await sessions.start(4, _EgressClient("socks5h://ip-a:1"), "bot", "L")
            self.assertIn("Capacidade", str(cm.exception))
            self.assertIsNone(sessions.get(4))                       # nothing was left registered
            await sessions.start(5, _EgressClient("socks5h://ip-b:1"), "bot", "L")   # other IP: free
            self.assertIsNotNone(sessions.get(5))

    async def test_robots_waiting_for_the_next_live_still_hold_a_slot(self):
        sessions = SessionManager()
        p1, p2 = self.patched()
        with p1, p2:
            for uid in (1, 2, 3):
                await sessions.start(uid, _EgressClient("socks5h://ip-a:1"), "bot", "L")
            sessions.get(1).state = "waiting_for_live"
            with self.assertRaises(RuntimeError):
                await sessions.start(4, _EgressClient("socks5h://ip-a:1"), "bot", "L")

    async def test_a_stopped_robot_frees_its_slot(self):
        sessions = SessionManager()
        p1, p2 = self.patched()
        with p1, p2:
            for uid in (1, 2, 3):
                await sessions.start(uid, _EgressClient("socks5h://ip-a:1"), "bot", "L")
            sessions.get(2).state = "stopped"
            await sessions.start(4, _EgressClient("socks5h://ip-a:1"), "bot", "L")

    async def test_restarting_your_own_waiting_robot_does_not_count_against_you(self):
        sessions = SessionManager()
        p1, p2 = self.patched()
        with p1, p2:
            for uid in (1, 2, 3):
                await sessions.start(uid, _EgressClient("socks5h://ip-a:1"), "bot", "L")
            sessions.get(3).state = "waiting_for_live"
            await sessions.start(3, _EgressClient("socks5h://ip-a:1"), "bot", "L2")   # her own slot

    async def test_zero_turns_the_per_ip_cap_off_and_the_global_cap_still_works(self):
        sessions = SessionManager()
        p1, p2 = self.patched(SM_SESSIONS_PER_EGRESS=0)
        with p1, p2:
            for uid in range(1, 8):
                await sessions.start(uid, _EgressClient("socks5h://ip-a:1"), "bot", "L")
        sessions2 = SessionManager()
        q1, q2 = self.patched(SM_SESSIONS_PER_EGRESS=0, SM_MAX_SESSIONS=2)
        with q1, q2:
            await sessions2.start(1, _EgressClient("a"), "bot", "L")
            await sessions2.start(2, _EgressClient("b"), "bot", "L")
            with self.assertRaises(RuntimeError):
                await sessions2.start(3, _EgressClient("c"), "bot", "L")

    def test_the_default_is_seven_per_ip(self):
        from engine import _sessions_per_egress
        with mock.patch.dict("os.environ", {}, clear=False):
            os.environ.pop("SM_SESSIONS_PER_EGRESS", None)
            self.assertEqual(_sessions_per_egress(), 7)


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
    def test_accepts_exactly_the_required_shape(self):
        # 8+ characters, one uppercase, one special
        self.assertEqual(security.password_problems("Bolo!cen", "maria", "Maria Souza"), [])
        self.assertEqual(security.password_problems("Bolo-de-cenoura", "maria", "Maria Souza"), [])
        self.assertEqual(security.password_problems("Pa$$w0rdx", "x"), [])      # digits are optional, not required

    def test_each_rule_reports_its_own_reason(self):
        self.assertTrue(any("pelo menos 8" in p for p in security.password_problems("Ab!defg")))
        self.assertTrue(any("maiúscula" in p for p in security.password_problems("abcdefg!1")))
        self.assertTrue(any("especial" in p for p in security.password_problems("Abcdefgh1")))
        self.assertTrue(any("especial" in p for p in security.password_problems("Abcdefg h")))  # a space is not "special"
        self.assertTrue(any("nome de usuário" in p for p in security.password_problems("xx-Maria.Souza-91!", "maria.souza")))
        self.assertTrue(any("nome de exibição" in p for p in security.password_problems("Fulana_de_Tal-77", "u1", "Fulana de Tal")))
        self.assertTrue(any("comum" in p for p in security.password_problems("Senha@123456")))

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


class DispatcherPacingTests(unittest.IsolatedAsyncioTestCase):
    """The queue must never make a mute/kick wait behind a chat message that is only
    waiting out its own 3 s spacing, must keep one request in flight at a time, and
    must keep the spacing rules otherwise unchanged."""

    async def test_urgent_does_not_wait_for_a_message_spacing(self):
        import superlive
        order = []

        def fake_post(self, path, body, auth):
            order.append(path)
            return {}

        env = {"SUPERLIVE_REQUEST_SPACING": "0", "SUPERLIVE_MESSAGE_SPACING_SECONDS": "1.0"}
        with mock.patch.object(SuperLiveClient, "_post_sync", fake_post), mock.patch.dict("os.environ", env):
            c = SuperLiveClient("t", "d", proxy_url="socks5h://egress-urgent-first:1080")
            await c.post(superlive._MESSAGE_PATH, {})            # starts the 1 s message window
            waiting = asyncio.create_task(c.post(superlive._MESSAGE_PATH, {}))   # must wait ~1 s
            await asyncio.sleep(0.1)
            start = time.monotonic()
            await c.post("mute", {}, priority=PRIORITY_URGENT)
            urgent_took = time.monotonic() - start
            await waiting
        self.assertLess(urgent_took, 0.4)        # not held for the ~0.9 s left of the message window
        self.assertEqual(order, [superlive._MESSAGE_PATH, "mute", superlive._MESSAGE_PATH])

    async def test_messages_still_respect_their_own_spacing(self):
        import superlive
        starts = []

        def fake_post(self, path, body, auth):
            starts.append(time.monotonic())
            return {}

        env = {"SUPERLIVE_REQUEST_SPACING": "0", "SUPERLIVE_MESSAGE_SPACING_SECONDS": "0.4"}
        with mock.patch.object(SuperLiveClient, "_post_sync", fake_post), mock.patch.dict("os.environ", env):
            c = SuperLiveClient("t", "d", proxy_url="socks5h://egress-msg-spacing:1080")
            await asyncio.gather(c.post(superlive._MESSAGE_PATH, {}), c.post(superlive._MESSAGE_PATH, {}))
        self.assertGreaterEqual(starts[1] - starts[0], 0.35)

    async def test_urgent_still_respects_the_base_spacing_and_a_waiting_message_keeps_its_place(self):
        import superlive
        order = []

        def fake_post(self, path, body, auth):
            order.append(path)
            return {}

        env = {"SUPERLIVE_REQUEST_SPACING": "0.3", "SUPERLIVE_MESSAGE_SPACING_SECONDS": "1.0"}
        with mock.patch.object(SuperLiveClient, "_post_sync", fake_post), mock.patch.dict("os.environ", env):
            c = SuperLiveClient("t", "d", proxy_url="socks5h://egress-base-spacing:1080")
            first = time.monotonic()
            await c.post("mute", {}, priority=PRIORITY_URGENT)
            await c.post("kick", {}, priority=PRIORITY_URGENT)
            gap = time.monotonic() - first
        self.assertGreaterEqual(gap, 0.28)       # base spacing still applies to urgent calls
        self.assertEqual(order, ["mute", "kick"])

    async def test_only_one_request_is_ever_in_flight(self):
        in_flight = 0
        peak = 0

        def slow_post(self, path, body, auth):
            nonlocal in_flight, peak
            in_flight += 1
            peak = max(peak, in_flight)
            time.sleep(0.05)
            in_flight -= 1
            return {}

        env = {"SUPERLIVE_REQUEST_SPACING": "0", "SUPERLIVE_PACING_FROM_START": "1"}
        with mock.patch.object(SuperLiveClient, "_post_sync", slow_post), mock.patch.dict("os.environ", env):
            c = SuperLiveClient("t", "d", proxy_url="socks5h://egress-one-inflight:1080")
            await asyncio.gather(*[c.post("x", {}) for _ in range(6)])
        self.assertEqual(peak, 1)

    async def test_spacing_from_start_makes_the_cycle_max_of_call_and_spacing(self):
        def slow_post(self, path, body, auth):
            time.sleep(0.2)
            return {}

        async def run(flag: str, proxy: str) -> float:
            env = {"SUPERLIVE_REQUEST_SPACING": "0.3", "SUPERLIVE_PACING_FROM_START": flag}
            with mock.patch.dict("os.environ", env):
                c = SuperLiveClient("t", "d", proxy_url=proxy)
                await c.post("warmup", {})
                await asyncio.sleep(0.35)
                start = time.monotonic()
                await asyncio.gather(c.post("a", {}), c.post("b", {}), c.post("c", {}))
                return time.monotonic() - start

        with mock.patch.object(SuperLiveClient, "_post_sync", slow_post):
            legacy = await run("0", "socks5h://egress-legacy-cycle:1080")        # 3 calls: 0.2 + 2 x (0.3 + 0.2)
            from_start = await run("1", "socks5h://egress-start-cycle:1080")     # 3 calls: 0.2 + 2 x 0.3
        self.assertGreaterEqual(legacy, 1.1)
        self.assertLess(from_start, legacy - 0.15)

    async def test_each_urgent_action_and_message_logs_wait_and_call_time(self):
        import superlive

        def fake_post(self, path, body, auth):
            return {}

        env = {"SUPERLIVE_REQUEST_SPACING": "0", "SUPERLIVE_MESSAGE_SPACING_SECONDS": "0"}
        with mock.patch.object(SuperLiveClient, "_post_sync", fake_post), mock.patch.dict("os.environ", env):
            c = SuperLiveClient("t", "d", proxy_url="socks5h://egress-log-line:1080")
            with self.assertLogs("super_moderator.superlive", level="INFO") as cm:
                await c.post("mute", {}, priority=PRIORITY_URGENT)
                await c.post(superlive._MESSAGE_PATH, {})
                await c.post("users/profile", {})        # background traffic: not one line per call
        lines = [m for m in cm.output if "pacing acao" in m]
        self.assertEqual(len(lines), 2)
        self.assertIn("tipo=urgente", lines[0])
        self.assertIn("tipo=mensagem", lines[1])
        self.assertIn("resultado=ok", lines[0])

    async def test_trace_file_gets_one_json_line_per_call(self):
        import superlive
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp, True)
        trace = os.path.join(tmp, "sub", "pacing.jsonl")

        def fake_post(self, path, body, auth):
            if path == "boom":
                raise SuperLiveError("limite", 429, None, retry_after=0.01)
            return {}

        env = {"SUPERLIVE_REQUEST_SPACING": "0", "SUPERLIVE_PACING_LOG_FILE": trace}
        with mock.patch.object(SuperLiveClient, "_post_sync", fake_post), mock.patch.dict("os.environ", env):
            c = SuperLiveClient("t", "d", proxy_url="socks5h://egress-trace:1080")
            await c.post("users/profile", {}, priority=PRIORITY_LOW)
            await c.post("mute", {}, priority=PRIORITY_URGENT)
            with self.assertRaises(SuperLiveError):
                await c.post("boom", {})
            # close the rotating handler so the file can be read/removed on every OS
            for h in list(superlive._trace_logger.handlers):
                h.flush()
        rows = [json.loads(line) for line in open(trace, encoding="utf-8").read().splitlines()]
        calls = [r for r in rows if "ev" not in r]
        self.assertEqual([r["path"] for r in calls], ["users/profile", "mute", "boom"])
        self.assertEqual([r["prio"] for r in calls], [PRIORITY_LOW, PRIORITY_URGENT, 5])
        self.assertEqual(calls[2]["out"], "429")
        for key in ("t", "te", "egress", "wait", "L", "qd_in", "qd_out"):
            self.assertIn(key, calls[0])
        self.assertTrue(any(r.get("ev") == "cooldown" for r in rows))
        for h in list(superlive._trace_logger.handlers):
            h.close()
        superlive._trace_logger = None

    async def test_trace_failure_never_breaks_a_call(self):
        import superlive
        env = {"SUPERLIVE_REQUEST_SPACING": "0", "SUPERLIVE_PACING_LOG_FILE": os.path.join(os.devnull, "x", "y.jsonl")}
        with mock.patch.object(SuperLiveClient, "_post_sync", lambda self, p, b, a: {"ok": 1}),                 mock.patch.dict("os.environ", env):
            superlive._trace_logger = None
            c = SuperLiveClient("t", "d", proxy_url="socks5h://egress-trace-bad:1080")
            self.assertEqual(await c.post("x", {}), {"ok": 1})
            self.assertEqual(os.environ.get("SUPERLIVE_PACING_LOG_FILE"), "")   # disabled itself

    async def test_pacing_stats_record_wait_per_priority_and_call_time(self):
        import superlive

        def fake_post(self, path, body, auth):
            time.sleep(0.02)
            return {}

        with mock.patch.object(SuperLiveClient, "_post_sync", fake_post), \
                mock.patch.dict("os.environ", {"SUPERLIVE_REQUEST_SPACING": "0"}):
            c = SuperLiveClient("t", "d", proxy_url="socks5h://egress-stats:1080")
            await c.post("x", {})
            await c.post("mute", {}, priority=PRIORITY_URGENT)
        stats = superlive.pacing_stats()
        entry = next(v for k, v in stats.items() if "egress-stats" in k)
        self.assertEqual(entry["sent"], 2)
        self.assertEqual(entry["urgent_wait"]["n"], 1)
        self.assertEqual(entry["normal_wait"]["n"], 1)
        self.assertGreaterEqual(entry["call"]["p50"], 0.02)


class NetworkPauseAndFlagsTests(unittest.IsolatedAsyncioTestCase):
    """Network pause for background lookups, message gap from start, shed counter."""

    async def test_background_lookups_pause_after_three_network_failures_but_not_actions(self):
        import superlive
        calls = []

        def fake_post(self, path, body, auth):
            calls.append(path)
            if path == "users/profile":
                raise SuperLiveError("Falha de rede: boom", 0)
            return {}

        env = {"SUPERLIVE_REQUEST_SPACING": "0", "SUPERLIVE_NETWORK_PAUSE_MIN_SECONDS": "0.4",
               "SUPERLIVE_NETWORK_COOLDOWN": "1"}
        with mock.patch.object(SuperLiveClient, "_post_sync", fake_post), mock.patch.dict("os.environ", env):
            c = SuperLiveClient("t", "d", proxy_url="socks5h://egress-net-pause:1080")
            for _ in range(3):
                with self.assertRaises(SuperLiveError):
                    await c.post("users/profile", {})
            self.assertEqual(calls.count("users/profile"), 3)
            with self.assertRaises(SuperLiveError) as cm:           # 4th: skipped, never sent
                await c.post("users/profile", {})
            self.assertEqual(cm.exception.kind, "pausa")
            self.assertEqual(calls.count("users/profile"), 3)
            with self.assertRaises(SuperLiveError):                 # low priority is skipped too
                await c.post("anything", {}, priority=PRIORITY_LOW)
            await c.post("mute", {}, priority=PRIORITY_URGENT)       # actions go through
            await c.post(superlive._MESSAGE_PATH, {})
            self.assertIn("mute", calls)
            self.assertIn(superlive._MESSAGE_PATH, calls)
            await asyncio.sleep(0.5)                                # the pause ends
            with self.assertRaises(SuperLiveError) as again:
                await c.post("users/profile", {})                   # reaches the network again
            self.assertNotEqual(again.exception.kind, "pausa")
            self.assertEqual(calls.count("users/profile"), 4)
        entry = next(v for k, v in superlive.pacing_stats().items() if "egress-net-pause" in k)
        self.assertGreaterEqual(entry["skipped_network_pause"], 2)

    async def test_a_success_clears_the_network_pause(self):
        results = iter([SuperLiveError("x", 0), SuperLiveError("x", 0), None, SuperLiveError("x", 0)])

        def fake_post(self, path, body, auth):
            r = next(results)
            if r is not None:
                raise r
            return {}

        env = {"SUPERLIVE_REQUEST_SPACING": "0", "SUPERLIVE_NETWORK_COOLDOWN": "1"}
        with mock.patch.object(SuperLiveClient, "_post_sync", fake_post), mock.patch.dict("os.environ", env):
            c = SuperLiveClient("t", "d", proxy_url="socks5h://egress-net-reset:1080")
            for _ in range(2):
                with self.assertRaises(SuperLiveError):
                    await c.post("users/profile", {})
            await c.post("users/profile", {})                       # success resets the count
            with self.assertRaises(SuperLiveError) as cm:           # 1st failure again: still sent
                await c.post("users/profile", {})
            self.assertNotEqual(cm.exception.kind, "pausa")

    async def test_network_pause_can_be_turned_off(self):
        calls = []

        def fake_post(self, path, body, auth):
            calls.append(path)
            raise SuperLiveError("x", 0)

        env = {"SUPERLIVE_REQUEST_SPACING": "0", "SUPERLIVE_NETWORK_COOLDOWN": "0"}
        with mock.patch.object(SuperLiveClient, "_post_sync", fake_post), mock.patch.dict("os.environ", env):
            c = SuperLiveClient("t", "d", proxy_url="socks5h://egress-net-off:1080")
            for _ in range(6):
                with self.assertRaises(SuperLiveError):
                    await c.post("users/profile", {})
        self.assertEqual(len(calls), 6)

    async def test_message_gap_can_count_from_the_start_of_the_previous_message(self):
        import superlive

        def slow_post(self, path, body, auth):
            time.sleep(0.2)
            return {}

        async def gap(flag, proxy):
            env = {"SUPERLIVE_REQUEST_SPACING": "0", "SUPERLIVE_MESSAGE_SPACING_SECONDS": "0.5",
                   "SUPERLIVE_MESSAGE_FROM_START": flag}
            starts = []

            def timed(self, path, body, auth):
                starts.append(time.monotonic())
                time.sleep(0.2)
                return {}

            with mock.patch.object(SuperLiveClient, "_post_sync", timed), mock.patch.dict("os.environ", env):
                c = SuperLiveClient("t", "d", proxy_url=proxy)
                await asyncio.gather(c.post(superlive._MESSAGE_PATH, {}), c.post(superlive._MESSAGE_PATH, {}))
            return starts[1] - starts[0]

        legacy = await gap("0", "socks5h://egress-msg-legacy:1080")        # 0.2 call + 0.5 gap
        from_start = await gap("1", "socks5h://egress-msg-start:1080")     # 0.5 gap from the start
        self.assertGreaterEqual(legacy, 0.68)
        self.assertGreaterEqual(from_start, 0.48)
        self.assertLess(from_start, legacy - 0.1)

    async def test_shed_background_calls_are_counted(self):
        import superlive
        release = threading.Event()

        def blocking_post(self, path, body, auth):
            release.wait(5)
            return {}

        env = {"SUPERLIVE_REQUEST_SPACING": "0", "SUPERLIVE_LOW_QUEUE_MAX": "1"}
        with mock.patch.object(SuperLiveClient, "_post_sync", blocking_post), mock.patch.dict("os.environ", env):
            c = SuperLiveClient("t", "d", proxy_url="socks5h://egress-shed-count:1080")
            busy = [asyncio.create_task(c.post("a", {})) for _ in range(3)]
            await asyncio.sleep(0.1)
            with self.assertRaises(SuperLiveError):
                await c.post("poll", {}, priority=PRIORITY_LOW)
            release.set()
            await asyncio.gather(*busy)
        entry = next(v for k, v in superlive.pacing_stats().items() if "egress-shed-count" in k)
        self.assertEqual(entry["shed"], 1)

    def test_profile_result_exposes_the_account_id(self):
        c = SuperLiveClient("t", "d", proxy_url="")
        self.assertEqual(c._profile_result({"user_id": "u9", "name": "S"}, True)["user_id"], "u9")
        self.assertEqual(c._profile_result({"id": 7, "name": "S"}, True)["user_id"], "7")
        self.assertIsNone(c._profile_result({"name": "S"}, True)["user_id"])
        self.assertNotIn("user_id", c._profile_result({"user_id": "u9", "name": "S"}))   # API shape unchanged


class _LookupClient:
    device_id = "dev"
    token = "tok"

    def __init__(self, shared=None, shared_exc=None, by_user=None):
        self.shared = shared
        self.shared_exc = shared_exc
        self.by_user = by_user
        self.calls = []

    async def find_live_by_shared_id(self, shared_id, priority=5, include_user_id=False):
        self.calls.append("shared")
        if self.shared_exc:
            raise self.shared_exc
        return self.shared

    async def find_live_by_user_id(self, user_id, priority=5, include_user_id=False):
        self.calls.append("user")
        return self.by_user


class LiveLookupDedupeTests(unittest.IsolatedAsyncioTestCase):
    """The "is she live yet?" check used to read the same profile twice (public id, then
    internal id) every cycle. The second read is skipped only when it would be the same
    request; detection of a live that starts later is untouched."""

    OFFLINE = {"live": False, "livestream_id": None, "user_id": "U1"}

    def make(self, client):
        from engine import BotSession
        session = BotSession(user_id=1, client=client, robot_sl_id="bot", livestream_id=None)
        session.watch_shared_id = "S1"
        session.streamer_id = "U1"
        return session

    async def test_same_account_offline_is_one_call(self):
        c = _LookupClient(shared=dict(self.OFFLINE))
        self.assertIsNone(await self.make(c)._find_next_live())
        self.assertEqual(c.calls, ["shared"])

    async def test_different_account_still_checks_the_internal_id(self):
        c = _LookupClient(shared={"live": False, "livestream_id": None, "user_id": "OTHER"},
                          by_user={"live": True, "livestream_id": "L9", "user_id": "U1"})
        self.assertEqual(await self.make(c)._find_next_live(), "L9")
        self.assertEqual(c.calls, ["shared", "user"])

    async def test_profile_without_user_id_keeps_the_old_behaviour(self):
        c = _LookupClient(shared={"live": False, "livestream_id": None})
        await self.make(c)._find_next_live()
        self.assertEqual(c.calls, ["shared", "user"])

    async def test_failed_public_lookup_that_is_not_transient_still_falls_back(self):
        c = _LookupClient(shared_exc=SuperLiveError("Não encontramos nenhuma conta", 200),
                          by_user={"live": True, "livestream_id": "L3", "user_id": "U1"})
        self.assertEqual(await self.make(c)._find_next_live(), "L3")
        self.assertEqual(c.calls, ["shared", "user"])

    async def test_no_second_request_after_network_error_throttling_or_5xx(self):
        for exc in (SuperLiveError("rede", 0), SuperLiveError("limite", 429), SuperLiveError("fora", 503)):
            c = _LookupClient(shared_exc=exc, by_user={"live": True, "livestream_id": "L1", "user_id": "U1"})
            self.assertIsNone(await self.make(c)._find_next_live())
            self.assertEqual(c.calls, ["shared"])

    async def test_live_found_by_the_first_lookup_needs_no_second(self):
        c = _LookupClient(shared={"live": True, "livestream_id": "L5", "user_id": "U1"})
        self.assertEqual(await self.make(c)._find_next_live(), "L5")
        self.assertEqual(c.calls, ["shared"])

    async def test_a_live_that_starts_later_is_still_detected(self):
        c = _LookupClient(shared=dict(self.OFFLINE))
        session = self.make(c)
        self.assertIsNone(await session._find_next_live())            # cycle 1: offline, one call
        self.assertEqual(c.calls, ["shared"])
        c.shared = {"live": True, "livestream_id": "L7", "user_id": "U1"}
        self.assertEqual(await session._find_next_live(), "L7")        # cycle 2: found
        self.assertEqual(c.calls, ["shared", "shared"])

    async def test_switch_off_restores_the_second_request(self):
        c = _LookupClient(shared=dict(self.OFFLINE))
        with mock.patch.dict("os.environ", {"SUPERLIVE_DEDUPE_LOOKUP": "0"}):
            await self.make(c)._find_next_live()
        self.assertEqual(c.calls, ["shared", "user"])

    async def test_counters_say_what_the_second_lookup_did(self):
        import engine
        before = engine.lookup_stats()
        c = _LookupClient(shared=dict(self.OFFLINE))
        await self.make(c)._find_next_live()
        after = engine.lookup_stats()
        self.assertEqual(after["skipped_same_id"], before["skipped_same_id"] + 1)


class GiftLedgerTests(unittest.TestCase):
    """How many diamonds each sender gave in ONE live: plain gifts, batches, combos, repeats."""

    def make(self):
        from engine import BotSession
        return BotSession(user_id=1, client=_FakeClient(), robot_sl_id="bot", livestream_id="L1")

    @staticmethod
    def gift(user="9", cost=10, name="Ana", combo=None, count=None, batch=None, **extra):
        data = {"livestream_id": "L1", "user_id": user, "name": name, "gift": {"cost": cost}}
        if combo is not None:
            data["gift_combo_detail"] = {"gift_combo_id": combo}
            if count is not None:
                data["gift_combo_detail"]["gift_combo_count"] = count
        if batch is not None:
            data["gift_batch_size"] = batch
        data.update(extra)
        return data

    def test_a_plain_gift_is_worth_its_cost(self):
        s = self.make()
        s._on_gift(self.gift(cost=30))
        self.assertEqual(s._diamonds, {"9": 30})

    def test_diamonds_are_counted_not_the_coins_the_viewer_paid(self):
        s = self.make()
        s._on_gift({"livestream_id": "L1", "user_id": "9", "name": "Ana", "gift": {"cost": 100, "diamond": 30}})
        self.assertEqual(s._diamonds["9"], 30)               # 100 coins paid, 30 diamonds received

    def test_diamonds_times_combo_count(self):
        s = self.make()
        for step in range(1, 4):
            s._on_gift({"livestream_id": "L1", "user_id": "9", "gift": {"cost": 10, "diamond": 4},
                        "gift_combo_detail": {"gift_combo_id": "c1", "gift_combo_count": step}})
        self.assertEqual(s._diamonds["9"], 12)               # 3 gifts x 4 diamonds

    def test_a_present_with_zero_or_missing_diamond_value_counts_nothing_when_the_field_exists(self):
        s = self.make()
        for bad in (0, None, -1, "5"):
            s._on_gift({"livestream_id": "L1", "user_id": "9", "gift": {"cost": 50, "diamond": bad}})
        self.assertEqual(s._diamonds, {})                    # the coins are NOT used instead

    def test_a_batch_is_cost_times_batch_size(self):
        s = self.make()
        s._on_gift(self.gift(cost=10, batch=5))
        self.assertEqual(s._diamonds["9"], 50)

    def test_a_combo_is_counted_once_not_as_1_plus_2_plus_n(self):
        s = self.make()
        for step in range(1, 6):                       # frames of one combo: running total 1..5
            s._on_gift(self.gift(cost=10, combo="c1", count=step))
        self.assertEqual(s._diamonds["9"], 50)         # 5 gifts x 10, NOT 10x(1+2+3+4+5)=150

    def test_a_repeated_or_late_combo_frame_adds_nothing(self):
        s = self.make()
        for step in (1, 3, 3, 2, 3):                   # a gap, a repeat and an out-of-order frame
            s._on_gift(self.gift(cost=10, combo="c1", count=step))
        self.assertEqual(s._diamonds["9"], 30)

    def test_two_combos_and_two_senders_do_not_mix(self):
        s = self.make()
        s._on_gift(self.gift(cost=10, combo="c1", count=4))
        s._on_gift(self.gift(cost=20, combo="c2", count=2))                  # same sender, another combo
        s._on_gift(self.gift(user="7", name="Bia", cost=10, combo="c1", count=2))   # same id, other sender
        self.assertEqual(s._diamonds, {"9": 80, "7": 20})

    def test_a_combo_frame_without_a_running_total_counts_one_step(self):
        s = self.make()
        s._on_gift(self.gift(cost=10, combo="c1"))
        s._on_gift(self.gift(cost=10, combo="c1"))
        self.assertEqual(s._diamonds["9"], 20)

    def test_a_replayed_frame_is_not_counted_twice(self):
        s = self.make()
        s._on_gift(self.gift(cost=40), "frame-aaaa-0001")
        s._on_gift(self.gift(cost=40), "frame-aaaa-0001")       # same frame again
        s._on_gift(self.gift(cost=40), "frame-aaaa-0002")       # a different one
        self.assertEqual(s._diamonds["9"], 80)

    def test_short_or_missing_frame_ids_never_hide_a_gift(self):
        s = self.make()
        for _ in range(3):
            s._on_gift(self.gift(cost=10), "srv-1")             # constant short id: cannot be trusted
            s._on_gift(self.gift(cost=10), None)
        self.assertEqual(s._diamonds["9"], 60)

    def test_values_that_are_not_a_positive_cost_are_ignored(self):
        s = self.make()
        for bad in (0, -5, True, "10", None, float("nan")):
            s._on_gift(self.gift(cost=bad))
        s._on_gift({"livestream_id": "L1", "user_id": "9"})                 # no gift at all
        s._on_gift({"gift": "x", "user_id": "9"})
        self.assertEqual(s._diamonds, {})

    def test_hostile_batch_and_combo_values_cannot_break_it(self):
        s = self.make()
        s._on_gift(self.gift(cost=10, batch="abc"))
        s._on_gift(self.gift(cost=10, batch=-3))
        s._on_gift(self.gift(cost=10, combo="c9", count="x"))
        s._on_gift(self.gift(cost=10, combo="c9", count=-2))
        self.assertEqual(s._diamonds["9"], 40)                   # each fell back to one unit

    def test_a_sender_without_id_goes_to_one_anonymous_line(self):
        s = self.make()
        s._on_gift(self.gift(user="", cost=10, name="Fulano", is_incognito=True))
        s._on_gift(self.gift(user=None, cost=5))
        s._on_gift(self.gift(user="9", cost=20))
        ranking = s.live_ranking()
        self.assertEqual([(r["name"], r["diamonds"]) for r in ranking], [("Ana", 20), ("Anônimos", 15)])
        self.assertEqual(sum(s._diamonds.values()), 35)          # the total still includes them

    def test_an_incognito_gifter_keeps_her_id_but_not_her_name(self):
        s = self.make()
        s._on_gift(self.gift(user="9", cost=10, name="Ana Secreta", is_incognito=True))
        self.assertEqual(s.live_ranking()[0]["name"], "Usuário 9")

    def test_ranking_is_biggest_first_and_ties_go_to_whoever_gave_first(self):
        s = self.make()
        s._on_gift(self.gift(user="1", name="Primeiro", cost=50))
        s._on_gift(self.gift(user="2", name="Segundo", cost=50))
        s._on_gift(self.gift(user="3", name="Maior", cost=70))
        s._on_gift(self.gift(user="4", name="Pequeno", cost=5))
        self.assertEqual([r["name"] for r in s.live_ranking()], ["Maior", "Primeiro", "Segundo", "Pequeno"])

    def test_the_latest_name_wins(self):
        s = self.make()
        s._on_gift(self.gift(name="Ana"))
        s._on_gift(self.gift(name="Ana Maria"))
        self.assertEqual(s.live_ranking()[0]["name"], "Ana Maria")

    def test_the_ledger_is_per_live(self):
        s = self.make()
        s._on_gift(self.gift(cost=100, combo="c1", count=1))
        s._reset_gift_ledger()                                   # the robot moved to another live
        self.assertEqual(s.live_ranking(), [])
        s._on_gift(self.gift(cost=10, combo="c1", count=1))      # the same combo id again counts afresh
        self.assertEqual(s._diamonds["9"], 10)

    def test_text_format(self):
        from engine import ranking_text
        entries = [{"name": "usuario x", "diamonds": 1234}, {"name": "usuario  q\nzz", "diamonds": 1}]
        self.assertEqual(ranking_text(entries, 1235),
                         "usuario x: enviou 1.234 diamantes\nusuario q zz: enviou 1 diamante\nTotal: 1.235 diamantes")


class _DMClient:
    """Fake SuperLive client for the ranking DM: records what would be sent."""

    def __init__(self, cost=0, blocked=False, conv_id="conv-1", fail=None):
        self.cost, self.blocked, self.conv_id, self.fail = cost, blocked, conv_id, fail
        self.info_calls, self.sent = [], []

    async def conversation_info(self, user_id):
        self.info_calls.append(user_id)
        return {"conversation_id": self.conv_id, "initial_coin_cost": self.cost, "is_blocked": self.blocked}

    async def send_private_text(self, conversation_id, text):
        if self.fail:
            raise self.fail
        self.sent.append((conversation_id, text))
        return {"success": True}


class RankingDMTests(unittest.IsolatedAsyncioTestCase):
    """The end-of-live ranking sent to the streamer by private message (inbox, not live chat)."""

    def setUp(self):
        import db
        import engine
        self.db, self.engine = db, engine
        self.old_path, self.old_delay = db.DB_PATH, engine.RANKING_DM_DELAY_SECONDS
        engine.RANKING_DM_DELAY_SECONDS = 0
        self.tmp = tempfile.mkdtemp(prefix="sm-dm-")
        db.DB_PATH = os.path.join(self.tmp, "t.db")
        db.init_db()
        conn = db.connect()
        conn.execute("INSERT INTO users (id, username, email, password_hash) VALUES (1, 'u1', 'u1@x', 'x')")
        conn.commit()
        db.save_live_ranking(conn, 1, "L1", 80, [{"user_id": "9", "name": "Ana", "diamonds": 50},
                                                {"user_id": "7", "name": "Bia", "diamonds": 30}])
        conn.execute("UPDATE live_rankings SET ended_at = '2026-10-21 01:30:00'")
        conn.commit()
        conn.close()

    def tearDown(self):
        self.db.DB_PATH = self.old_path
        self.engine.RANKING_DM_DELAY_SECONDS = self.old_delay
        shutil.rmtree(self.tmp, ignore_errors=True)

    def session(self, client, streamer="100", robot="bot"):
        s = self.engine.BotSession(user_id=1, client=client, robot_sl_id=robot, livestream_id=None)
        s.streamer_id = streamer
        return s

    def status(self):
        conn = self.db.connect()
        try:
            return self.db.get_live_ranking(conn, 1, "L1")["dm_status"]
        finally:
            conn.close()

    async def test_sends_the_ranking_to_the_streamer_once_and_never_with_coins(self):
        client = _DMClient()
        s = self.session(client)
        await s._send_ranking_dm("L1")
        self.assertEqual(client.info_calls, ["100"])                      # the streamer of that live
        self.assertEqual(len(client.sent), 1)
        conv, text = client.sent[0]
        self.assertEqual(conv, "conv-1")
        self.assertEqual(text, "Ranking de diamantes da live de 20/10 às 22:30 (horário de Brasília)\n\n"
                               "Ana: enviou 50 diamantes\nBia: enviou 30 diamantes\nTotal: 80 diamantes")
        self.assertTrue(self.status().startswith("Enviado"))
        await s._send_ranking_dm("L1")                                    # the same live again
        self.assertEqual(len(client.sent), 1)

    async def test_a_conversation_whose_first_message_costs_coins_is_not_used(self):
        client = _DMClient(cost=50)
        await self.session(client)._send_ranking_dm("L1")
        self.assertEqual(client.sent, [])
        self.assertIn("custa 50 moedas", self.status())
        self.assertIn("nunca gasta moedas", self.status())

    async def test_a_blocked_conversation_is_not_used(self):
        client = _DMClient(blocked=True)
        await self.session(client)._send_ranking_dm("L1")
        self.assertEqual(client.sent, [])
        self.assertIn("bloqueada", self.status())

    async def test_a_refusal_from_superlive_is_recorded(self):
        from superlive import SuperLiveError
        client = _DMClient(fail=SuperLiveError("Message not allowed", 400))
        await self.session(client)._send_ranking_dm("L1")
        self.assertIn("recusou", self.status())
        self.assertIn("Message not allowed", self.status())

    async def test_unknown_streamer_or_robot_is_the_streamer(self):
        client = _DMClient()
        await self.session(client, streamer=None)._send_ranking_dm("L1")
        self.assertIn("não sei qual é a conta", self.status())
        await self.session(client, streamer="bot", robot="bot")._send_ranking_dm("L1")
        self.assertIn("própria conta", self.status())
        self.assertEqual(client.info_calls, [])

    async def test_back_in_the_same_live_means_it_was_not_over(self):
        client = _DMClient()
        s = self.session(client)
        s.livestream_id, s.state = "L1", "running"
        await s._send_ranking_dm("L1")
        self.assertEqual(client.sent, [])
        self.assertIsNone(self.status())

    async def test_a_live_without_a_saved_ranking_sends_nothing(self):
        client = _DMClient()
        await self.session(client)._send_ranking_dm("OUTRA")
        self.assertEqual(client.info_calls, [])

    def live_session(self, client):
        s = self.session(client)
        cfg = {"settings": {"live_ranking_enabled": True, "live_ranking_dm_enabled": True,
                            "moderation_enabled": True}, "messages": [], "matcher": None}
        s._config = lambda force=False: cfg
        s.livestream_id, s.state = "L2", "running"
        s._on_gift({"livestream_id": "L2", "user_id": "9", "name": "Ana", "gift": {"cost": 40}})
        return s

    def saved(self, live):
        conn = self.db.connect()
        try:
            return self.db.get_live_ranking(conn, 1, live)
        finally:
            conn.close()

    async def test_stopping_the_robot_mid_live_saves_the_ranking_but_sends_nothing(self):
        client = _DMClient()
        s = self.live_session(client)
        await s.stop()                                   # she stopped the robot; the live goes on
        await asyncio.sleep(0.05)
        self.assertEqual(self.saved("L2")["total_diamonds"], 40)
        self.assertEqual(client.info_calls, [])
        self.assertEqual(client.sent, [])

    async def test_a_live_that_really_ended_sends_the_dm_even_if_the_robot_stops(self):
        client = _DMClient()
        s = self.live_session(client)
        await s.stop(reason="A live foi encerrada", live_ended=True)   # no favourite: stops at the end
        await asyncio.sleep(0.05)
        self.assertEqual(len(client.sent), 1)
        self.assertIn("Ana: enviou 40 diamantes", client.sent[0][1])
        self.assertTrue(self.saved("L2")["dm_status"].startswith("Enviado"))

    def test_long_rankings_are_cut_and_split_under_the_message_limit(self):
        from engine import DM_CHUNK_CHARS, ranking_dm_messages
        entries = [{"name": f"Pessoa numero {i:03d} com nome comprido", "diamonds": 1000 - i} for i in range(45)]
        total = sum(e["diamonds"] for e in entries)
        chunks = ranking_dm_messages(entries, total, "2026-10-21 01:30:00")
        self.assertGreater(len(chunks), 1)
        self.assertTrue(all(len(c) <= DM_CHUNK_CHARS for c in chunks))
        joined = "\n".join(chunks)
        self.assertEqual(joined.count(": enviou "), 30)                       # top 30 by name
        rest = sum(e["diamonds"] for e in entries[30:])
        self.assertIn("e mais 15 pessoas: " + f"{rest:,}".replace(",", ".") + " diamantes", joined)
        self.assertTrue(joined.endswith(f"Total: {total:,} diamantes".replace(",", ".")))


class PassiveTelemetryTests(unittest.IsolatedAsyncioTestCase):
    """Counters only: they must never change what a session does."""

    def make(self, client=None):
        from engine import BotSession
        session = BotSession(user_id=1, client=client or _FakeClient(), robot_sl_id="bot", livestream_id="L1")
        session.state = "running"
        return session

    async def test_frame_types_are_counted_without_touching_any_handler_or_the_queue(self):
        session = self.make()
        for kind in ("livestream_viewers_update", "livestream_viewers_update", "something_new"):
            await session._on_frame(json.dumps({"type": kind, "data": {"livestream_id": "L1"}}))
        await session._on_frame("not json at all")
        counts = session.telemetry()["frame_types"]
        self.assertEqual(counts["livestream_viewers_update"], 2)
        self.assertEqual(counts["something_new"], 1)
        self.assertEqual(session._queue.qsize(), 0)          # no action was decided from them
        self.assertEqual(session.chat_seen, 0)

    async def test_frame_type_labels_are_bounded(self):
        session = self.make()
        for i in range(200):
            await session._on_frame(json.dumps({"type": f"t{i}", "data": {}}))
        self.assertLessEqual(len(session._frame_counts), 81)
        self.assertIn("(outros)", session._frame_counts)

    async def test_status_checks_are_counted_and_the_result_is_unchanged(self):
        client = _LookupClient(shared={"live": False, "livestream_id": None, "user_id": "U1"})
        session = self.make(client)
        session.watch_shared_id = "S1"
        self.assertIs(await session._check_live_status(), False)
        self.assertEqual(session.telemetry()["status_checks"], 1)

    def test_snapshot_exposes_the_telemetry(self):
        snap = self.make().snapshot()
        self.assertEqual(snap["telemetry"], {"frame_types": {}, "ws_drops": 0, "status_checks": 0})

    async def test_pacing_stats_count_calls_by_path(self):
        import superlive

        with mock.patch.object(SuperLiveClient, "_post_sync", lambda self, p, b, a: {}), \
                mock.patch.dict("os.environ", {"SUPERLIVE_REQUEST_SPACING": "0"}):
            c = SuperLiveClient("t", "d", proxy_url="socks5h://egress-by-path:1080")
            for path in ("users/profile", "users/profile", "livestream/kick"):
                await c.post(path, {})
        entry = next(v for k, v in superlive.pacing_stats().items() if "egress-by-path" in k)
        self.assertEqual(entry["by_path"], {"users/profile": 2, "livestream/kick": 1})

    def test_verification_requests_are_recognised_but_ordinary_errors_are_not(self):
        import superlive
        ask = superlive._asks_for_verification
        self.assertTrue(ask(403, "Please complete the Turnstile challenge"))
        self.assertTrue(ask(400, "You need to verify your identity to go live"))
        self.assertTrue(ask(428, "captcha required"))
        self.assertFalse(ask(400, "Invalid verification code"))     # normal sign-in error
        self.assertFalse(ask(500, "captcha"))
        self.assertFalse(ask(403, "Forbidden"))
        self.assertFalse(ask(200, "turnstile"))


class PermanentMessageRefusalTests(unittest.TestCase):
    PREMIUM = SuperLiveError("\U0001F512This is a PREMIUM stream. To enter, send a gift worth 99 or more.", 400,
                             {"error": {"code": 10, "message": "This is a PREMIUM stream"}})
    GONE = SuperLiveError("There is not any active livestream with given livestream_id", 404,
                          {"error": {"code": 3, "message": "There is not any active livestream"}})

    def test_only_the_two_known_refusals_are_permanent(self):
        from engine import BotSession
        self.assertIn("exige presente", BotSession._permanent_message_refusal(self.PREMIUM))
        self.assertIn("não está mais ativa", BotSession._permanent_message_refusal(self.GONE))
        for exc in (SuperLiveError("HTTP 400", 400, {"error": {"code": 10, "message": "other"}}),
                    SuperLiveError("rate", 429), SuperLiveError("net", 0), SuperLiveError("x", 500),
                    SuperLiveError("HTTP 400", 400, None),
                    SuperLiveError("PREMIUM", 400, {"error": {"code": 99}})):
            self.assertIsNone(BotSession._permanent_message_refusal(exc), exc.message)


class AutoMessageStopsOnRefusedLiveTests(unittest.IsolatedAsyncioTestCase):
    async def test_a_premium_refusal_stops_the_messages_for_that_live_only(self):
        from engine import BotSession
        sent = []

        class Client:
            device_id = "d"
            token = "t"

            async def send_text(self, live_id, text):
                sent.append(live_id)
                if live_id == "L1":
                    raise PermanentMessageRefusalTests.PREMIUM

        session = BotSession(user_id=1, client=Client(), robot_sl_id="bot", livestream_id="L1")
        session.state = "running"
        cfg = {"settings": {"auto_messages_enabled": True, "message_interval_seconds": 10},
               "messages": ["oi"]}
        session._config = lambda force=False: cfg
        with mock.patch("engine.MIN_INTERVAL_SECONDS", 0), \
                mock.patch.object(BotSession, "_interval", staticmethod(lambda c: 0.01)), \
                mock.patch.object(BotSession, "_handle_live_error_or_change", mock.AsyncMock()):
            task = asyncio.create_task(session._auto_message_loop())
            await asyncio.sleep(0.15)
            self.assertEqual(sent, ["L1"])                                  # tried once, then stopped
            self.assertIn("exige presente", session.last_error)
            session.livestream_id = "L2"                                    # next live: tries again
            await asyncio.sleep(0.1)
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass
        self.assertIn("L2", sent)
        self.assertEqual(sent.count("L1"), 1)


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
