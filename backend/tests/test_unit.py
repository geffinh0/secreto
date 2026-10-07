import unittest

import security
from engine import RuleMatcher, normalize
from superlive import DEFAULT_BASE_URL, SuperLiveClient, build_ws_url, heartbeat_message, enter_message
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


if __name__ == "__main__":
    unittest.main()
