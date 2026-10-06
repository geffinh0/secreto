"""Live-chat moderation engine.

One ``BotSession`` per portal user: it joins a SuperLive livestream over the
real-time WebSocket, applies the user's keyword rules to every chat message
(mute / kick through the robot account) and sends the recurring auto messages.
"""
import asyncio
import json
import logging
import os
import re
import time
import unicodedata
import uuid
from collections import deque
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from typing import Optional
from urllib.parse import urlsplit

import requests
import websockets
from websockets.exceptions import InvalidStatus

import db
from superlive import (
    PROXY_URL, USER_AGENT, SuperLiveClient, SuperLiveError, build_ws_url, enter_message,
    heartbeat_message, leave_message,
)

if PROXY_URL:
    from python_socks.async_.asyncio import Proxy


async def _ws_connect(url: str, **kwargs):
    """Same as ``websockets.connect(url, **kwargs)``, but through ``PROXY_URL``
    (SOCKS5) when one is set - see superlive.PROXY_URL for why. The WebSocket
    handshake and TLS still happen in ``websockets`` itself; the proxy only
    supplies the raw TCP connection to the SuperLive host."""
    if not PROXY_URL:
        return websockets.connect(url, **kwargs)
    parts = urlsplit(url)
    port = parts.port or (443 if parts.scheme == "wss" else 80)
    sock = await Proxy.from_url(PROXY_URL).connect(dest_host=parts.hostname, dest_port=port)
    return websockets.connect(url, sock=sock, server_hostname=parts.hostname, **kwargs)

log = logging.getLogger("super_moderator.engine")

# Local LLM (llama.cpp's OpenAI-compatible server, shared with the other
# project on this VPS - see DEPLOY.md) used only to guess whether a viewer's
# display name reads as feminine. Never for chat/moderation text. Empty/unset
# = the AI name filter is simply off, same as before this existed.
AI_NAME_FILTER_URL = os.getenv("AI_NAME_FILTER_URL", "").strip()
AI_NAME_FILTER_TIMEOUT = float(os.getenv("AI_NAME_FILTER_TIMEOUT", "8"))


def _classify_feminine_name_sync(name: str) -> bool:
    if not AI_NAME_FILTER_URL:
        return False
    prompt = (
        'Responda só com SIM ou NAO (maiúsculo, sem acento, nada mais). '
        f'O nome ou apelido "{name}" parece pertencer a uma pessoa do gênero feminino? '
        'Considere nomes próprios em português e inglês, apelidos e emojis. '
        'Se o nome for ambíguo, neutro, só números/símbolos, ou você não tiver certeza, responda NAO.'
    )
    try:
        resp = requests.post(
            f"{AI_NAME_FILTER_URL}/v1/chat/completions",
            json={
                "messages": [{"role": "user", "content": prompt}],
                "temperature": 0,
                "max_tokens": 4,
            },
            timeout=AI_NAME_FILTER_TIMEOUT,
        )
        resp.raise_for_status()
        content = resp.json()["choices"][0]["message"]["content"]
        return content.strip().upper().startswith("SIM")
    except Exception:  # noqa: BLE001 - a flaky classifier must never block the live
        log.exception("falha ao classificar nome via IA: %r", name)
        return False


async def classify_feminine_name(name: str) -> bool:
    return await asyncio.to_thread(_classify_feminine_name_sync, name)

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
        self.streamer_shared_id: Optional[str] = None
        self.watch_shared_id: Optional[str] = None
        self._last_ended_livestream_id: Optional[str] = None
        self._live_found_event = asyncio.Event()

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
        self.streamer_shared_id = str(streamer.get("shared_id")) if streamer.get("shared_id") else None

        conn = db.connect()
        try:
            watch = db.get_watch(conn, self.user_id)
            if watch and watch.get("shared_id"):
                self.watch_shared_id = str(watch["shared_id"])
        finally:
            conn.close()

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
            asyncio.create_task(self._live_monitor_loop(), name=f"monitor-{self.user_id}"),
        ]

    async def stop(self, reason: str = "Parado pelo usuário",
                   final_state: str = "stopped") -> None:
        async with self._stop_lock:
            if self._finalized:
                return
            self.state = "stopping"
            ws = self._ws
            self._ws = None
            if ws is not None:
                try:
                    await asyncio.wait_for(ws.send(leave_message(self.livestream_id)), 3)
                except Exception:  # noqa: BLE001
                    pass
                try:
                    await ws.close()
                except Exception:  # noqa: BLE001
                    pass
            current = asyncio.current_task()
            all_tasks = [t for t in (list(self._tasks) + list(self._bg)) if t is not current]
            for task in all_tasks:
                task.cancel()
            await asyncio.gather(*all_tasks, return_exceptions=True)
            self._bg.clear()
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
                async with await _ws_connect(
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

            # Check if live ended or switched to a new ID before blindly reconnecting to the old one
            try:
                status_live = await self._check_live_status()
                if isinstance(status_live, str) and status_live != self.livestream_id:
                    log.info("session %s: live changed during reconnect to %s", self.user_id, status_live)
                    await self.switch_livestream(status_live)
                    failures, backoff = 0, 1
                    continue
                elif status_live is False:
                    log.info("session %s: live %s ended during disconnect, waiting for next",
                             self.user_id, self.livestream_id)
                    await self.on_live_ended()
                    continue
            except Exception:
                pass

            failures = 0 if time.monotonic() - connected_at > 30 else failures + 1
            if failures >= MAX_WS_FAILURES:
                self._fail("Não foi possível manter a conexão em tempo real com o SuperLive.")
                return
            await asyncio.sleep(backoff)
            backoff = 1 if failures == 0 else min(backoff * 2, 30)

    async def _check_live_status(self):
        """Checks if the current livestream is still live or if a new one started.
        Returns:
            str: new livestream_id if the streamer is live on another broadcast
            True: if the current live is still active
            False: if the live has ended
            None: if the status could not be verified
        """
        target_shared = None
        try:
            conn = db.connect()
            try:
                w = db.get_watch(conn, self.user_id)
                if w and w.get("shared_id"):
                    target_shared = str(w["shared_id"])
            finally:
                conn.close()
        except Exception:
            pass
        target_shared = target_shared or self.watch_shared_id or self.streamer_shared_id

        if target_shared:
            try:
                res = await self.client.find_live_by_shared_id(target_shared)
                if res is not None:
                    if res.get("live") and res.get("livestream_id"):
                        lid = str(res["livestream_id"])
                        return lid if lid != self.livestream_id else True
                    else:
                        return False
            except Exception:
                pass

        if self.streamer_id:
            try:
                res = await self.client.find_live_by_user_id(self.streamer_id)
                if res is not None:
                    if res.get("live") and res.get("livestream_id"):
                        lid = str(res["livestream_id"])
                        return lid if lid != self.livestream_id else True
                    else:
                        return False
            except Exception:
                pass

        if self.livestream_id:
            try:
                details = await self.client.retrieve_livestream(self.livestream_id)
                if details and isinstance(details.get("user"), dict):
                    streamer = details["user"]
                    s_id = streamer.get("id") or streamer.get("user_id")
                    if s_id and not self.streamer_id:
                        self.streamer_id = str(s_id)
                    return True
            except SuperLiveError as exc:
                if exc.status == 404 or any(w in (exc.message or "").lower() for w in ("not found", "ended", "encerrad", "closed", "live")):
                    return False
            except Exception:
                pass

        return None

    async def _handle_live_error_or_change(self, exc: Optional[SuperLiveError] = None) -> None:
        """When an action or message fails against the current livestream, verify if
        the live has changed to a new broadcast or ended."""
        if not self.is_active or self.state in ("stopping", "stopped", "error", "waiting_for_live"):
            return
        try:
            status = await self._check_live_status()
            if isinstance(status, str) and status != self.livestream_id:
                log.info("session %s: detected live switched to %s", self.user_id, status)
                await self.switch_livestream(status)
                self.last_error = None
            elif status is False:
                log.info("session %s: detected live ended", self.user_id)
                await self.on_live_ended()
            elif status is None and exc is not None:
                msg_lower = (exc.message or "").lower()
                if any(w in msg_lower for w in ("live", "not found", "ended", "closed", "encerrad", "inexistente", "inativ")) or exc.status == 404:
                    log.info("session %s: error '%s' indicates live %s ended", self.user_id, exc.message, self.livestream_id)
                    await self.on_live_ended()
        except Exception:
            log.exception("session %s: error during live status verification", self.user_id)

    async def _live_monitor_loop(self) -> None:
        """Periodically checks if the current live ended or changed, in case the WebSocket
        channel did not push a livestream_ended frame."""
        while True:
            await asyncio.sleep(LIVE_POLL_INTERVAL_SECONDS)
            if not self.is_active or self.state != "running" or not self.livestream_id:
                continue
            try:
                status = await self._check_live_status()
                if isinstance(status, str) and status != self.livestream_id:
                    log.info("session %s: monitor detected live switched to %s", self.user_id, status)
                    await self.switch_livestream(status)
                elif status is False:
                    log.info("session %s: monitor detected live ended", self.user_id)
                    await self.on_live_ended()
            except Exception:
                pass

    async def _find_next_live(self) -> Optional[str]:
        target_shared = None
        try:
            conn = db.connect()
            try:
                w = db.get_watch(conn, self.user_id)
                if w and w.get("shared_id"):
                    target_shared = str(w["shared_id"])
            finally:
                conn.close()
        except Exception:
            pass
        target_shared = target_shared or self.watch_shared_id or self.streamer_shared_id

        result = None
        if target_shared:
            try:
                result = await self.client.find_live_by_shared_id(target_shared)
            except SuperLiveError as exc:
                if exc.is_auth_error:
                    raise
                result = None

        if (not result or not result.get("live")) and self.streamer_id:
            try:
                result = await self.client.find_live_by_user_id(self.streamer_id)
            except SuperLiveError as exc:
                if exc.is_auth_error:
                    raise
                result = None

        if result and result.get("live") and result.get("livestream_id"):
            found_id = str(result["livestream_id"])
            # Never re-accept the broadcast that just ended (protect against API caching)
            if self._last_ended_livestream_id and found_id == str(self._last_ended_livestream_id):
                log.debug("session %s: found live %s but it is the one that just ended, ignoring",
                          self.user_id, found_id)
                return None
            return found_id
        return None

    async def _wait_for_next_live(self) -> bool:
        """Polls SuperLive for the streamer's next broadcast while the moderator
        stays 'on' with nothing to connect to. Returns False if the session was
        stopped (or the robot's token failed) while waiting."""
        self.state = "waiting_for_live"
        self.ws_state = "disconnected"
        self.stop_reason = None
        self._live_found_event.clear()
        log.info("session %s: waiting for the streamer's next live", self.user_id)
        while self.is_active and self.livestream_id is None:
            try:
                found_id = await self._find_next_live()
            except SuperLiveError as exc:
                if exc.is_auth_error:
                    self._fail("O token do robô expirou. Reconecte o robô na aba Robô.")
                    return False
                found_id = None
            if found_id:
                await self.switch_livestream(found_id)
                break
            else:
                try:
                    await asyncio.wait_for(
                        self._live_found_event.wait(), timeout=LIVE_POLL_INTERVAL_SECONDS
                    )
                except asyncio.TimeoutError:
                    pass
        if not self.is_active:
            return False
        self.state = "running"
        self.last_error = None
        return True

    async def switch_livestream(self, new_livestream_id: str) -> None:
        """Switch moderation cleanly to a new livestream_id."""
        async with self._stop_lock:
            if self._finalized or not self.is_active or self.state in ("stopping", "stopped", "error"):
                return
            new_livestream_id = str(new_livestream_id)
            if self.livestream_id == new_livestream_id and self.state == "running" and self.ws_state == "connected":
                return

            old_livestream_id = self.livestream_id
            log.info("session %s: switching livestream from %s to %s",
                     self.user_id, old_livestream_id or "?", new_livestream_id)

            self._last_ended_livestream_id = old_livestream_id
            self.livestream_id = new_livestream_id
            self.state = "running"
            self.last_error = None
            self._diamonds.clear()
            self._acted.clear()
            self._live_found_event.set()

            try:
                conn = db.connect()
                try:
                    conn.execute(
                        "UPDATE robot_accounts SET last_livestream_id = ? WHERE user_id = ?",
                        (new_livestream_id, self.user_id),
                    )
                    conn.commit()
                finally:
                    conn.close()
            except Exception:
                log.exception("could not update last_livestream_id in database")

            try:
                db.log_activity(
                    self.user_id, "session_switched_live",
                    f"live {new_livestream_id}" + (f" (anterior: {old_livestream_id})" if old_livestream_id else ""),
                )
            except Exception:
                pass

            ws = self._ws
            self._ws = None
            if ws is not None:
                if old_livestream_id:
                    try:
                        await ws.send(leave_message(old_livestream_id))
                    except Exception:
                        pass
                try:
                    await ws.close()
                except Exception:
                    pass

    async def on_live_ended(self) -> None:
        """Handles the current livestream ending, entering waiting_for_live state."""
        async with self._stop_lock:
            if self._finalized or not self.is_active or self.state in ("stopping", "stopped", "error", "waiting_for_live"):
                return

            has_target = bool(self.streamer_id or self.streamer_shared_id or self.watch_shared_id)
            if not has_target:
                try:
                    conn = db.connect()
                    try:
                        watch = db.get_watch(conn, self.user_id)
                        has_target = bool(watch and watch.get("shared_id"))
                    finally:
                        conn.close()
                except Exception:
                    pass

            if not has_target:
                self._spawn(self.stop(reason="A live foi encerrada"))
                return

            old_live = self.livestream_id
            self._last_ended_livestream_id = old_live
            self.livestream_id = None
            self.state = "waiting_for_live"
            self.last_error = None
            self.ws_state = "disconnected"
            self._live_found_event.clear()
            log.info("session %s: live %s ended, watching for the next one",
                     self.user_id, old_live or "?")
            try:
                db.log_activity(self.user_id, "live_ended", f"live {old_live}" if old_live else "live encerrada")
            except Exception:
                pass
            ws = self._ws
            self._ws = None
            if ws is not None:
                try:
                    await ws.close()
                except Exception:
                    pass

    _on_live_ended = on_live_ended  # backwards compatibility

    async def _heartbeat(self, ws) -> None:
        while True:
            if self.livestream_id:
                try:
                    await ws.send(heartbeat_message(self.livestream_id))
                except Exception:
                    break
            await asyncio.sleep(self._heartbeat_seconds)

    async def _on_frame(self, raw) -> None:
        if self._finalized or not self.is_active:
            return
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
            elif kind == "livestream_arrival_message":
                self._spawn(self._on_arrival(data))
            elif kind == "livestream_ended":
                await self.on_live_ended()
        except Exception:  # noqa: BLE001 - one bad frame must not kill the loop
            log.exception("could not handle frame")

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

    # ---- AI name filter -----------------------------------------------------
    async def _on_arrival(self, data: dict) -> None:
        """Screens each viewer as she enters the live: the literal name "w" is
        always flagged outright (no AI needed), anything else goes through the
        local classifier. ``ai_name_filter_mode`` decides what happens to a
        flagged viewer - same mute/kick plumbing as a chat rule hit, so it gets
        the same rate limiting, dedup and action log."""
        user_id = str(data.get("user_id") or "")
        name = str(data.get("name") or "").strip()
        if not user_id or not name:
            return
        if user_id in (self.robot_sl_id, self.streamer_id):
            return

        cfg = self._config()
        mode = cfg["settings"].get("ai_name_filter_mode") or "off"
        if mode not in ("mute", "ban"):
            return
        action = "mute" if mode == "mute" else "kick"
        if self._acted.get(user_id, 0) >= ACTION_LEVEL[action] or (user_id, action) in self._pending:
            return

        if name.lower() == "w":
            reason = 'nome é só a letra "w"'
        elif await classify_feminine_name(name):
            reason = "nome de aparência feminina (IA)"
        else:
            return

        entry = ChatEntry(
            id=str(uuid.uuid4()), user_id=user_id, name=name,
            text=f'Entrou na live como "{name}"', ts=now_iso(),
        )
        try:
            self._queue.put_nowait((entry, action, reason))
        except asyncio.QueueFull:
            log.warning("action queue full - dropping name-filter %s on %s", action, user_id)
            return
        self._pending.add((user_id, action))

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
            else:
                self._spawn(self._handle_live_error_or_change(exc))
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
                self.last_error = None
            except asyncio.CancelledError:
                raise
            except SuperLiveError as exc:
                if exc.is_auth_error:
                    self._fail("O token do robô expirou. Reconecte o robô na aba Robô.")
                    return
                self.last_error = f"Mensagem automática não enviada: {exc.message}"
                await self._handle_live_error_or_change(exc)
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


WATCH_POLL_INTERVAL_SECONDS = 30  # how often a favourited streamer is checked


class WatchManager:
    """Keeps one background task per user watching their favourited streamer
    (``streamer_watch`` in the DB). While the watch is active and the robot has
    no session running, it polls her profile and starts moderating the moment
    she goes live - no manual "Iniciar moderação" click needed. Once a session
    is running, the engine's own reconnect-on-new-live logic takes over; this
    task just keeps idling in the background so it can pick up again if that
    session ever ends.
    """

    def __init__(self, sessions: SessionManager):
        self._sessions = sessions
        self._tasks: dict[int, asyncio.Task] = {}

    def is_watching(self, user_id: int) -> bool:
        task = self._tasks.get(user_id)
        return task is not None and not task.done()

    def start(self, user_id: int) -> None:
        if self.is_watching(user_id):
            return
        self._tasks[user_id] = asyncio.create_task(
            self._watch_loop(user_id), name=f"watch-{user_id}")

    async def stop(self, user_id: int) -> None:
        task = self._tasks.pop(user_id, None)
        if task is not None:
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass

    async def shutdown(self) -> None:
        await asyncio.gather(
            *(self.stop(uid) for uid in list(self._tasks)), return_exceptions=True,
        )

    async def _watch_loop(self, user_id: int) -> None:
        while True:
            conn = db.connect()
            try:
                watch = db.get_watch(conn, user_id)
                robot = db.get_robot(conn, user_id)
            finally:
                conn.close()
            if watch is None or not watch["active"] or robot is None:
                self._tasks.pop(user_id, None)
                return

            client = SuperLiveClient(robot["token"], robot["device_id"])
            try:
                result = await client.find_live_by_shared_id(watch["shared_id"])
            except SuperLiveError:
                result = None

            session = self._sessions.get(user_id)
            is_live = bool(result and result.get("live") and result.get("livestream_id"))
            current_live_id = str(result["livestream_id"]) if is_live else None

            if is_live and current_live_id:
                if session is None or not session.is_active:
                    # If the session was stopped on this specific live, wait for a new live before auto-starting
                    if session is not None and session.state == "stopped" and session.livestream_id == current_live_id:
                        pass
                    else:
                        try:
                            await self._sessions.start(
                                user_id, client, robot["sl_user_id"], current_live_id,
                                ws_url_override=os.getenv("SUPERLIVE_WS_URL") or None,
                            )
                            try:
                                conn = db.connect()
                                try:
                                    conn.execute(
                                        "UPDATE robot_accounts SET last_livestream_id = ? WHERE user_id = ?",
                                        (current_live_id, user_id),
                                    )
                                    conn.commit()
                                finally:
                                    conn.close()
                            except Exception:
                                pass
                            log.info("session %s: auto-started on the favourited streamer's live %s",
                                     user_id, current_live_id)
                            db.log_activity(
                                user_id, "session_auto_started",
                                f'live {current_live_id} ({watch.get("nickname") or watch["shared_id"]})',
                            )
                        except (RuntimeError, SuperLiveError):
                            pass  # lost a race with a manual start, or a transient error; retry next cycle
                elif session.state == "waiting_for_live":
                    if current_live_id != session._last_ended_livestream_id:
                        log.info("session %s: watch found streamer live %s, switching", user_id, current_live_id)
                        await session.switch_livestream(current_live_id)
                elif session.state == "running":
                    if session.livestream_id != current_live_id:
                        log.info("session %s: watch detected streamer switched to new live %s (was %s)",
                                 user_id, current_live_id, session.livestream_id)
                        await session.switch_livestream(current_live_id)
            else:
                if result is not None and session is not None and session.state == "running":
                    log.info("session %s: watch detected streamer is offline, live ended", user_id)
                    await session.on_live_ended()

            await asyncio.sleep(WATCH_POLL_INTERVAL_SECONDS)
