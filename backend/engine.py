"""Live-chat moderation engine.

One ``BotSession`` per portal user: it joins a SuperLive livestream over the
real-time WebSocket, applies the user's keyword rules to every chat message
(mute / kick through the robot account) and sends the recurring auto messages.
"""
import asyncio
import json
import logging
import re
import time
import unicodedata
import uuid
from collections import deque
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from typing import Optional

import websockets
from websockets.exceptions import InvalidStatus

import db
from superlive import (
    USER_AGENT, SuperLiveClient, SuperLiveError, build_ws_url, enter_message,
    heartbeat_message, leave_message,
)

log = logging.getLogger("super_moderator.engine")

MIN_INTERVAL_SECONDS = 10      # never spam the chat faster than this
ACTION_SPACING_SECONDS = 0.5   # pause between moderation calls (API courtesy)
CONFIG_TTL_SECONDS = 5         # how often rules/settings are re-read from the DB
MAX_QUEUED_ACTIONS = 200
MAX_WS_FAILURES = 12
ACTION_LEVEL = {"mute": 1, "kick": 2}
LIVE_POLL_INTERVAL_SECONDS = 20  # how often to check whether the streamer went live again


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


# ─── Keyword matching ──────────────────────────────────────────────────────────
def normalize(text: str) -> str:
    """Lowercase, strip accents, collapse whitespace ("Zap  ZÁP" -> "zap zap")."""
    text = unicodedata.normalize("NFKD", text or "")
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    return re.sub(r"\s+", " ", text.casefold()).strip()


class RuleMatcher:
    """Whole-word / whole-phrase matching on normalized text.

    A trailing ``*`` turns a keyword into a prefix match (``puta*`` also catches
    ``putaria``). Kick rules win over mute rules when both match.
    """

    def __init__(self, rules):
        compiled = []
        for rule in rules:
            keyword = normalize(rule["keyword"])
            prefix = keyword.endswith("*")
            keyword = keyword.rstrip("*").strip()
            if not keyword:
                continue
            pattern = r"(?<!\w)" + re.escape(keyword) + ("" if prefix else r"(?!\w)")
            compiled.append((rule["action"], rule["keyword"], re.compile(pattern)))
        compiled.sort(key=lambda item: -ACTION_LEVEL.get(item[0], 0))
        self._rules = compiled

    def match(self, text: str):
        """Return ``(action, keyword)`` of the strongest matching rule, or None."""
        haystack = normalize(text)
        for action, keyword, pattern in self._rules:
            if pattern.search(haystack):
                return action, keyword
        return None


# ─── Session ───────────────────────────────────────────────────────────────────
@dataclass
class ChatEntry:
    id: str
    user_id: str
    name: str
    text: str
    ts: str
    action: Optional[str] = None  # set when a rule was applied to this message


@dataclass
class ActionEntry:
    id: str
    ts: str
    action: str
    target_user_id: str
    target_name: str
    keyword: str
    message_text: str
    ok: bool
    detail: Optional[str] = None


class BotSession:
    def __init__(self, user_id: int, client: SuperLiveClient, robot_sl_id: Optional[str],
                 livestream_id: str, ws_url_override: Optional[str] = None):
        self.user_id = user_id
        self.client = client
        self.robot_sl_id = str(robot_sl_id) if robot_sl_id else None
        self.livestream_id = livestream_id
        self.ws_url_override = ws_url_override

        self.state = "starting"          # starting|running|waiting_for_live|stopping|stopped|error
        self.ws_state = "disconnected"   # disconnected|connecting|connected
        self.started_at = None
        self.stop_reason = None
        self.last_error = None           # moderation / message / auth problems
        self.ws_error = None             # transient connection problems (cleared on reconnect)
        self.streamer_id: Optional[str] = None

        self.messages_sent = 0
        self.chat_seen = 0
        self.actions_ok = 0
        self.actions_failed = 0
        self.recent_chat = deque(maxlen=60)
        self.recent_actions = deque(maxlen=60)

        self._ws = None
        self._ws_url = None
        self._heartbeat_seconds = 5
        self._tasks = []
        self._bg = set()
        self._queue = asyncio.Queue(maxsize=MAX_QUEUED_ACTIONS)
        self._pending = set()
        self._acted = {}                 # user_id -> highest action level applied
        self._diamonds = {}              # user_id -> diamonds sent in the CURRENT live
        self._cfg = None
        self._cfg_at = 0.0
        self._forbidden_hits = 0
        self._stop_lock = asyncio.Lock()
        self._finalized = False

    # ---- lifecycle ---------------------------------------------------------
    @property
    def is_active(self) -> bool:
        return self.state in ("starting", "running", "waiting_for_live")

    async def start(self) -> None:
        """Validate the livestream, resolve the WebSocket URL and start the workers.

        Raises SuperLiveError (with a user-facing message) if it cannot start.
        """
        details = await self.client.retrieve_livestream(self.livestream_id)
        streamer = details.get("user") if isinstance(details.get("user"), dict) else {}
        streamer_id = streamer.get("id") or streamer.get("user_id")
        self.streamer_id = str(streamer_id) if streamer_id else None

        if self.ws_url_override:
            base_url = self.ws_url_override
        else:
            settings = await self.client.get_settings()
            ws = settings.get("websocket") if isinstance(settings.get("websocket"), dict) else {}
            base_url = ws.get("url")
            if ws.get("heartbeat"):
                self._heartbeat_seconds = max(2, min(60, int(ws["heartbeat"])))
        if not base_url:
            raise SuperLiveError("O SuperLive não informou a URL do canal em tempo real (WebSocket)")
        self._ws_url = build_ws_url(base_url, self.client.device_id, self.client.token)

        self.state = "running"
        self.started_at = now_iso()
        self._tasks = [
            asyncio.create_task(self._ws_loop(), name=f"ws-{self.user_id}"),
            asyncio.create_task(self._action_worker(), name=f"actions-{self.user_id}"),
            asyncio.create_task(self._auto_message_loop(), name=f"auto-{self.user_id}"),
        ]

    async def stop(self, reason: str = "Parado pelo usuário",
                   final_state: str = "stopped") -> None:
        async with self._stop_lock:
            if self._finalized:
                return
            self.state = "stopping"
            if self._ws is not None:
                try:
                    await asyncio.wait_for(self._ws.send(leave_message(self.livestream_id)), 3)
                except Exception:  # noqa: BLE001
                    pass
            current = asyncio.current_task()
            tasks = [t for t in self._tasks if t is not current]
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
            self.ws_state = "disconnected"
            self.state = final_state
            self.stop_reason = reason
            self._finalized = True

    def _spawn(self, coro) -> None:
        task = asyncio.create_task(coro)
        self._bg.add(task)
        task.add_done_callback(self._bg.discard)

    def _fail(self, message: str) -> None:
        if self._finalized or self.state in ("stopping", "error"):
            return
        self.last_error = message
        log.warning("session %s failed: %s", self.user_id, message)
        self._spawn(self.stop(reason=message, final_state="error"))

    # ---- config ------------------------------------------------------------
    def _config(self, force: bool = False) -> dict:
        now = time.monotonic()
        if force or self._cfg is None or now - self._cfg_at > CONFIG_TTL_SECONDS:
            try:
                cfg = db.load_engine_config(self.user_id)
                cfg["matcher"] = RuleMatcher(cfg["rules"])
                self._cfg, self._cfg_at = cfg, now
            except Exception:  # noqa: BLE001 - keep working with the last snapshot
                log.exception("could not reload config")
                if self._cfg is None:
                    raise
        return self._cfg

    # ---- real-time channel -------------------------------------------------
    async def _ws_loop(self) -> None:
        backoff, failures = 1, 0
        while self.is_active:
            if self.livestream_id is None:
                # The live we were in ended; wait here until the streamer goes live
                # again (or the session is stopped) instead of tearing everything down.
                if not await self._wait_for_next_live():
                    return
                backoff, failures = 1, 0

            connected_at = time.monotonic()
            try:
                self.ws_state = "connecting"
                async with websockets.connect(
                    self._ws_url, user_agent_header=USER_AGENT, open_timeout=15,
                    ping_interval=60, ping_timeout=30, close_timeout=3, max_size=2 ** 22,
                ) as ws:
                    self._ws = ws
                    self.ws_state = "connected"
                    self.ws_error = None
                    await ws.send(enter_message(self.livestream_id))
                    heartbeat = asyncio.create_task(self._heartbeat(ws))
                    try:
                        async for raw in ws:
                            await self._on_frame(raw)
                    finally:
                        heartbeat.cancel()
            except asyncio.CancelledError:
                raise
            except InvalidStatus as exc:
                status = exc.response.status_code
                if status in (401, 403):
                    self._fail(
                        f"O SuperLive recusou a conexão em tempo real (HTTP {status}): "
                        "o token do robô é inválido ou expirou. Reconecte o robô."
                    )
                    return
                self.ws_error = f"WebSocket recusado (HTTP {status})"
            except Exception as exc:  # noqa: BLE001
                self.ws_error = f"WebSocket: {exc}"
            finally:
                self._ws = None
                self.ws_state = "disconnected"

            if not self.is_active:
                return
            if self.livestream_id is None:
                continue  # the live ended again (or ended mid-connect); go back to waiting
            failures = 0 if time.monotonic() - connected_at > 30 else failures + 1
            if failures >= MAX_WS_FAILURES:
                self._fail("Não foi possível manter a conexão em tempo real com o SuperLive.")
                return
            await asyncio.sleep(backoff)
            backoff = 1 if failures == 0 else min(backoff * 2, 30)

    async def _wait_for_next_live(self) -> bool:
        """Polls SuperLive for the streamer's next broadcast while the moderator
        stays "on" with nothing to connect to. Returns False if the session was
        stopped (or the robot's token failed) while waiting."""
        self.state = "waiting_for_live"
        self.ws_state = "disconnected"
        self.stop_reason = None
        log.info("session %s: live %s ended, watching for the next one",
                  self.user_id, self.livestream_id or "?")
        while self.is_active and self.livestream_id is None:
            try:
                result = await self.client.find_live_by_user_id(self.streamer_id)
            except SuperLiveError as exc:
                if exc.is_auth_error:
                    self._fail("O token do robô expirou. Reconecte o robô na aba Robô.")
                    return False
                result = None
            if result and result.get("live") and result.get("livestream_id"):
                self.livestream_id = str(result["livestream_id"])
                self._diamonds.clear()  # diamond immunity is per-live, not cumulative
                log.info("session %s: streamer is live again on %s",
                         self.user_id, self.livestream_id)
            else:
                await asyncio.sleep(LIVE_POLL_INTERVAL_SECONDS)
        if not self.is_active:
            return False
        self.state = "running"
        self.last_error = None
        return True

    async def _heartbeat(self, ws) -> None:
        while True:
            await ws.send(heartbeat_message(self.livestream_id))
            await asyncio.sleep(self._heartbeat_seconds)

    async def _on_frame(self, raw) -> None:
        try:
            if isinstance(raw, bytes):
                raw = raw.decode("utf-8", errors="replace")
            frame = json.loads(raw)
            if not isinstance(frame, dict):
                return
            kind, data = frame.get("type"), frame.get("data")
            data = data if isinstance(data, dict) else {}
            frame_stream = data.get("livestream_id")
            if frame_stream and str(frame_stream) != self.livestream_id:
                return
            if kind == "livestream_message_sent":
                self._on_chat(data)
            elif kind == "livestream_gift_sent":
                self._on_gift(data)
            elif kind == "livestream_ended":
                await self._on_live_ended()
        except Exception:  # noqa: BLE001 - one bad frame must not kill the loop
            log.exception("could not handle frame")

    async def _on_live_ended(self) -> None:
        if not self.streamer_id:
            # We don't know who the streamer is (e.g. the session was started
            # straight from a livestream_id, not resolved from her profile), so
            # there's nothing to poll for. Fall back to the old behaviour.
            self._spawn(self.stop(reason="A live foi encerrada"))
            return
        self.livestream_id = None  # makes _ws_loop switch into "wait for the next live"
        if self._ws is not None:
            try:
                await self._ws.close()
            except Exception:  # noqa: BLE001
                pass

    # ---- chat handling -----------------------------------------------------
    def _on_chat(self, data: dict) -> None:
        user_id = str(data.get("user_id") or "")
        text = data.get("text") or ""
        if not user_id or not text:
            return
        entry = ChatEntry(
            id=str(data.get("message_id") or uuid.uuid4()),
            user_id=user_id,
            name=str(data.get("name") or user_id),
            text=text,
            ts=now_iso(),
        )
        self.chat_seen += 1
        self.recent_chat.append(entry)

        if user_id in (self.robot_sl_id, self.streamer_id):
            return  # never moderate ourselves or the streamer
        cfg = self._config()
        if not cfg["settings"].get("moderation_enabled", True):
            return
        if cfg["settings"].get("diamond_immunity_enabled") and self._is_diamond_immune(user_id, cfg):
            return
        hit = cfg["matcher"].match(text)
        if not hit:
            return
        action, keyword = hit
        if self._acted.get(user_id, 0) >= ACTION_LEVEL[action] or (user_id, action) in self._pending:
            return
        try:
            self._queue.put_nowait((entry, action, keyword))
        except asyncio.QueueFull:
            log.warning("action queue full - dropping %s on %s", action, user_id)
            return
        self._pending.add((user_id, action))
        entry.action = action

    def _is_diamond_immune(self, user_id: str, cfg: dict) -> bool:
        threshold = cfg["settings"].get("diamond_immunity_threshold") or db.MIN_DIAMOND_IMMUNITY_THRESHOLD
        return self._diamonds.get(user_id, 0) >= threshold

    # ---- gifts / diamonds ---------------------------------------------------
    def _on_gift(self, data: dict) -> None:
        """Accumulates diamonds sent by each user during the current live, so
        ``diamond_immunity_enabled`` can exempt generous gifters from mute/kick
        rules. Field names come from the decompiled app (``GiftStreamEventData`` /
        ``APIGift`` / ``APIGiftComboDetail``): a gift's value is ``gift.cost``,
        multiplied by the combo count when the gift was sent as part of a combo
        (``gift_combo_detail.gift_combo_count``), falling back to
        ``gift_batch_size`` for batched sends, or 1 for a single gift.
        """
        user_id = str(data.get("user_id") or "")
        gift = data.get("gift") if isinstance(data.get("gift"), dict) else {}
        cost = gift.get("cost")
        if not user_id or not isinstance(cost, (int, float)) or cost <= 0:
            return
        combo = data.get("gift_combo_detail") if isinstance(data.get("gift_combo_detail"), dict) else {}
        multiplier = combo.get("gift_combo_count") or data.get("gift_batch_size") or 1
        try:
            multiplier = int(multiplier)
        except (TypeError, ValueError):
            multiplier = 1
        self._diamonds[user_id] = self._diamonds.get(user_id, 0) + int(cost) * max(1, multiplier)

    async def _action_worker(self) -> None:
        while True:
            entry, action, keyword = await self._queue.get()
            try:
                await self._execute(entry, action, keyword)
            finally:
                self._pending.discard((entry.user_id, action))
            await asyncio.sleep(ACTION_SPACING_SECONDS)

    async def _execute(self, entry: ChatEntry, action: str, keyword: str) -> None:
        detail, ok = None, True
        try:
            if action == "mute":
                await self.client.mute(self.livestream_id, entry.user_id)
            else:
                permanent = bool(self._config()["settings"].get("kick_permanent"))
                await self.client.kick(self.livestream_id, entry.user_id, permanent)
            self._acted[entry.user_id] = max(self._acted.get(entry.user_id, 0), ACTION_LEVEL[action])
            self.actions_ok += 1
        except SuperLiveError as exc:
            ok, detail = False, exc.message
            self.actions_failed += 1
            if exc.is_auth_error:
                self._fail("O token do robô expirou. Reconecte o robô na aba Robô.")
            elif exc.is_forbidden:
                self._forbidden_hits += 1
                self.last_error = (
                    "O SuperLive recusou a ação (403). O robô precisa ser moderador desta live."
                )
        except Exception as exc:  # noqa: BLE001 - never let the worker die silently
            log.exception("unexpected error while moderating")
            ok, detail = False, str(exc)
            self.actions_failed += 1
        try:
            db.log_action(self.user_id, self.livestream_id, entry.user_id, entry.name, action,
                          keyword, entry.text, ok, detail)
        except Exception:  # noqa: BLE001
            log.exception("could not write moderation log")
        self.recent_actions.append(ActionEntry(
            id=str(uuid.uuid4()), ts=now_iso(), action=action, target_user_id=entry.user_id,
            target_name=entry.name, keyword=keyword, message_text=entry.text[:300], ok=ok,
            detail=detail,
        ))

    # ---- recurring messages ------------------------------------------------
    async def _auto_message_loop(self) -> None:
        index = 0
        while True:
            try:
                await asyncio.sleep(self._interval(self._config(force=True)))
                cfg = self._config(force=True)
                if self.livestream_id is None:
                    continue  # waiting for the streamer's next live; nowhere to send to
                if not cfg["settings"].get("auto_messages_enabled") or not cfg["messages"]:
                    continue
                text = cfg["messages"][index % len(cfg["messages"])]
                index += 1
                await self.client.send_text(self.livestream_id, text)
                self.messages_sent += 1
            except asyncio.CancelledError:
                raise
            except SuperLiveError as exc:
                if exc.is_auth_error:
                    self._fail("O token do robô expirou. Reconecte o robô na aba Robô.")
                    return
                self.last_error = f"Mensagem automática não enviada: {exc.message}"
            except Exception:  # noqa: BLE001
                log.exception("auto message loop error")
                await asyncio.sleep(MIN_INTERVAL_SECONDS)

    @staticmethod
    def _interval(cfg: dict) -> int:
        try:
            value = int(cfg["settings"].get("message_interval_seconds") or 120)
        except (TypeError, ValueError):
            value = 120
        return max(MIN_INTERVAL_SECONDS, value)

    # ---- reporting ---------------------------------------------------------
    def snapshot(self) -> dict:
        return {
            "running": self.is_active,
            "state": self.state,
            "ws_state": self.ws_state,
            "livestream_id": self.livestream_id,
            "started_at": self.started_at,
            "stop_reason": self.stop_reason,
            "last_error": self.last_error or (self.ws_error if self.ws_state != "connected" else None),
            "counters": {
                "messages_sent": self.messages_sent,
                "chat_seen": self.chat_seen,
                "actions_ok": self.actions_ok,
                "actions_failed": self.actions_failed,
            },
            "recent_chat": [asdict(c) for c in self.recent_chat],
            "recent_actions": [asdict(a) for a in self.recent_actions],
        }


IDLE_SNAPSHOT = {
    "running": False, "state": "idle", "ws_state": "disconnected", "livestream_id": None,
    "started_at": None, "stop_reason": None, "last_error": None,
    "counters": {"messages_sent": 0, "chat_seen": 0, "actions_ok": 0, "actions_failed": 0},
    "recent_chat": [], "recent_actions": [],
}


class SessionManager:
    """Keeps at most one live session per portal user."""

    def __init__(self):
        self._sessions = {}

    def get(self, user_id: int) -> Optional[BotSession]:
        return self._sessions.get(user_id)

    async def start(self, user_id: int, client: SuperLiveClient, robot_sl_id,
                    livestream_id: str, ws_url_override: Optional[str] = None) -> BotSession:
        current = self._sessions.get(user_id)
        if current is not None and current.state in ("starting", "running", "stopping"):
            raise RuntimeError("Já existe uma sessão do robô em andamento")
        session = BotSession(user_id, client, robot_sl_id, livestream_id, ws_url_override)
        await session.start()  # may raise SuperLiveError; nothing is registered then
        self._sessions[user_id] = session
        return session

    async def stop(self, user_id: int) -> Optional[BotSession]:
        session = self._sessions.get(user_id)
        if session is not None:
            await session.stop()
        return session

    async def shutdown(self) -> None:
        await asyncio.gather(
            *(s.stop(reason="Servidor encerrado") for s in self._sessions.values()),
            return_exceptions=True,
        )
        self._sessions.clear()
