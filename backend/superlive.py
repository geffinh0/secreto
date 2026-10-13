"""Client for the (unofficial) SuperLive API.

Endpoint paths and field names come from the decompiled app (SuperLive 2.31.0):
  * HTTP bodies use ``livestream_id`` / ``user_id`` / ``text`` / ``guid`` / ``permanent``.
  * The real-time channel is a plain WebSocket: URL from ``user/settings`` ->
    ``websocket.url`` + ``?device=<device id>&auth=<token>``. The server pushes
    ``{"id", "type", "data"}`` frames; the client sends ``{"id", "action", "data"}``.

Nothing here tries to defeat bot protection (App Check / reCAPTCHA). If the server
asks for it, the login simply fails with the server's own message.
"""
import asyncio
import itertools
import json
import logging
import os
import time
import uuid

import requests

# The app's Retrofit base is ".../api/v1/". Without that prefix the server answers
# HTTP 400 {"error": {"code": 77, "message": "unknown urd"}} to every call.
DEFAULT_BASE_URL = "https://api.sprlv-api.com/api/v1/"
BASE_URL = os.getenv("SUPERLIVE_BASE_URL", DEFAULT_BASE_URL)
USER_AGENT = os.getenv(
    "SUPERLIVE_USER_AGENT", "SuperLive/2.31.0 (samsung SM-G998B; Android 13; Scale/3.0)"
)
HTTP_TIMEOUT = float(os.getenv("SUPERLIVE_HTTP_TIMEOUT", "20"))
# Short connect timeout: requests are serial (see _dispatcher), so a dead
# proxy/tunnel must fail fast instead of holding every robot's queue for 20s.
HTTP_CONNECT_TIMEOUT = float(os.getenv("SUPERLIVE_HTTP_CONNECT_TIMEOUT", "6"))

# One pooled session reused across calls: without it every request paid a new
# TCP + SOCKS + TLS handshake through the tunnel. Only the dispatcher thread
# uses it, one request at a time.
_http_sessions: dict = {}


def _http_for(proxy: str) -> "requests.Session":
    sess = _http_sessions.get(proxy)
    if sess is None:
        sess = _http_sessions[proxy] = requests.Session()
    return sess


def _retry_after_seconds(value) -> float:
    try:
        return max(0.0, float(value))
    except (TypeError, ValueError):
        return 0.0  # absent, or an HTTP-date we don't bother parsing

def get_proxy_url() -> str:
    """Return the proxy URL configured via SUPERLIVE_PROXY_URL or environment variables."""
    return (
        os.getenv("SUPERLIVE_PROXY_URL")
        or os.getenv("HTTPS_PROXY")
        or os.getenv("HTTP_PROXY")
        or os.getenv("ALL_PROXY")
        or ""
    ).strip()


PROXY_URL = get_proxy_url()


def _redact_proxy(proxy: str) -> str:
    """host:port only - proxy URLs may carry credentials, which never get logged."""
    if not proxy:
        return "direct"
    host = proxy.split("@")[-1]
    return host.split("://")[-1]


def get_proxy_pool() -> list:
    """Every egress the robots may leave through: ``SUPERLIVE_PROXY_URLS``
    (comma-separated) when set, else the single legacy proxy (or ``""`` =
    direct). The FIRST entry must stay the original egress: accounts that
    connected before the pool existed live on slot 0 and keep their IP."""
    raw = os.getenv("SUPERLIVE_PROXY_URLS", "")
    pool = [p.strip() for p in raw.split(",") if p.strip()]
    return pool or [get_proxy_url()]


def proxy_for_slot(slot) -> str:
    """The proxy URL for a user's stored egress slot (a slot beyond a pool
    that has since shrunk wraps around instead of failing)."""
    pool = get_proxy_pool()
    return pool[(slot or 0) % len(pool)]

log = logging.getLogger("super_moderator.superlive")

# All of this process' robot accounts share one egress IP (the VPS's own, or
# the residential proxy behind it). SuperLive appears to reject two actions
# that land at the exact same instant from the same IP - confirmed directly:
# a message sent from a personal account's phone collided with the robot's
# own message sent that same moment and was refused. So every outbound call
# to SuperLive, from every account/session in this process, funnels through
# one global priority queue (see SuperLiveClient.post / _dispatcher below)
# instead of firing independently - never per-account, since the collision
# is per-IP, not per-account.
#
# Two tiers, so a pile-up of low-stakes traffic (auto-messages, periodic
# live-status polls) never makes an urgent mute/kick wait behind it: a mute
# or kick jumps straight to the front of the line. Chat messages additionally
# get their own, more generous cooldown (SUPERLIVE_MESSAGE_SPACING_SECONDS)
# on top of the base anti-collision spacing every request respects - being
# slow to re-send a promo message costs nothing; being slow to mute/kick does.
PRIORITY_URGENT = 0   # mute, kick
PRIORITY_NORMAL = 5   # everything else (chat messages, retrieve, settings, ...)
PRIORITY_LOW = 9      # background "is she live yet?" polling: shed first when the line is long

# The collision rule above is per IP, so there is one queue per egress, not one
# per process: with a pool of N proxies the robots get N times the throughput.

_MESSAGE_PATH = "livestream/chat/send_text_message"
# Keyed by the running event loop's id, not a single module-level singleton:
# the app itself only ever has one loop for its whole lifetime, but a couple
# of tests (and any one-off script) call `asyncio.run(...)`, which spins up
# and tears down its own loop - an asyncio.Queue/Task is only ever safe to
# use from the loop that created it, so reusing one across loops hangs.
_dispatchers: "dict[tuple, tuple[asyncio.PriorityQueue, asyncio.Task]]" = {}
_seq = itertools.count()


def _request_spacing_seconds() -> float:
    # Read live (not frozen at import time): whichever test module a combined
    # run imports first would otherwise permanently bake in the default
    # before a later module's env override had a chance to apply.
    return float(os.getenv("SUPERLIVE_REQUEST_SPACING", "0.35"))


def _low_queue_max() -> int:
    return int(os.getenv("SUPERLIVE_LOW_QUEUE_MAX", "40"))


def _message_spacing_seconds() -> float:
    return float(os.getenv("SUPERLIVE_MESSAGE_SPACING_SECONDS", "3"))


async def _dispatcher(queue: "asyncio.PriorityQueue") -> None:
    """The only coroutine that actually sends anything to SuperLive for a
    given event loop - every request, from every session, passes through
    here one at a time, in priority order. Keeping it as a single
    long-running consumer (rather than N callers racing for a lock) is
    what makes "urgent jumps the queue" possible: asyncio.Lock wakes
    waiters FIFO with no concept of priority; a PriorityQueue does.
    """
    last_any = 0.0
    last_message = 0.0
    # A 429 is about the shared egress IP, not the one account that got it, so
    # the whole queue backs off (urgent requests included - sending them anyway
    # would only extend the penalty). Never retried here: a repeated chat
    # message or kick is worse than a failed one the caller can see.
    cooldown_until = 0.0
    backoff_429 = 0.0
    while True:
        _priority, _seq, fut, client, path, body, auth = await queue.get()
        if fut.cancelled():
            continue
        now = time.monotonic()
        wait = _request_spacing_seconds() - (now - last_any)
        if path == _MESSAGE_PATH:
            wait = max(wait, _message_spacing_seconds() - (now - last_message))
        wait = max(wait, cooldown_until - now)
        if wait > 0:
            await asyncio.sleep(wait)
        try:
            result = await asyncio.to_thread(client._post_sync, path, body or {}, auth)
        except Exception as exc:  # noqa: BLE001 - relayed to the caller via the future
            if isinstance(exc, SuperLiveError) and exc.status == 429:
                backoff_429 = min(max(backoff_429 * 2, 2.0), 60.0)
                pause = min(exc.retry_after or backoff_429, 120.0)
                cooldown_until = time.monotonic() + pause
                log.warning("SuperLive HTTP 429 em %s: fila global pausada por %.0fs", path, pause)
            if not fut.cancelled():
                fut.set_exception(exc)
        else:
            backoff_429 = 0.0
            if not fut.cancelled():
                fut.set_result(result)
        finally:
            finished = time.monotonic()
            last_any = finished
            if path == _MESSAGE_PATH:
                last_message = finished


def queue_depths() -> dict:
    """egress proxy URL -> requests waiting in its queue (admin capacity view)."""
    try:
        loop_id = id(asyncio.get_running_loop())
    except RuntimeError:
        return {}
    return {proxy: entry[0].qsize() for (lid, proxy), entry in _dispatchers.items()
            if lid == loop_id}


def _ensure_dispatcher(proxy: str = "") -> asyncio.PriorityQueue:
    """Lazily creates (or reuses) the queue/dispatcher for the CURRENT
    running loop and egress. Module import happens before any loop exists, so
    this can't be module-level setup."""
    loop = asyncio.get_running_loop()
    key = (id(loop), proxy)
    entry = _dispatchers.get(key)
    if entry is None or entry[1].done():
        queue: asyncio.PriorityQueue = asyncio.PriorityQueue()
        task = loop.create_task(_dispatcher(queue), name="superlive-dispatcher")
        log.info("superlive dispatcher started for egress %s", _redact_proxy(proxy))
        _dispatchers[key] = (queue, task)
        return queue
    return entry[0]


class SuperLiveError(Exception):
    """Any failure talking to SuperLive. ``status`` is 0 for network-level errors."""

    def __init__(self, message: str, status: int = 0, body=None, retry_after: float = 0.0):
        super().__init__(message)
        self.message = message
        self.status = status
        self.body = body
        self.retry_after = retry_after  # seconds, from a 429's Retry-After header

    @property
    def is_auth_error(self) -> bool:
        return self.status == 401

    @property
    def is_forbidden(self) -> bool:
        return self.status == 403


def _server_message(body):
    if isinstance(body, dict):
        for key in ("message", "detail", "error", "error_message", "msg"):
            value = body.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
            if isinstance(value, dict):
                inner = _server_message(value)
                if inner:
                    return inner
    return None


def unwrap(body):
    """Some responses nest the payload under ``data``; tolerate both shapes."""
    if isinstance(body, dict) and isinstance(body.get("data"), dict):
        return body["data"]
    return body if isinstance(body, dict) else {}


def _log_unexpected_200(path: str, body) -> None:
    """SuperLive answered HTTP 200 but without the field we expected (no token /
    no verification id). Not an HTTPError, so _post_sync never logs it — do it here,
    visible in the backend window, so the real response shape can be diagnosed.
    """
    log.warning("SuperLive %s -> HTTP 200 without the expected field: %s",
                path, json.dumps(body)[:500])


# public shared_id -> internal user_id (it never changes), so the periodic
# "is she live?" poll costs one request instead of two.
_shared_id_cache: dict = {}


class SuperLiveClient:
    """``device_id`` must be a *server-issued* id (see :meth:`register_device`): the
    real app registers the device first and sends the returned ``guid`` as the
    ``Device-ID`` header on every call. A made-up id is rejected by the server
    ("unknown urd")."""

    def __init__(self, token=None, device_id=None, base_url=None, proxy_url=None):
        self.token = token
        self.device_id = device_id
        # None = the legacy single proxy; "" = direct; else this user's egress
        self.proxy_url = proxy_url
        self.base_url = (base_url or BASE_URL).rstrip("/") + "/"

    # ── transport ──────────────────────────────────────────────────────────
    def _headers(self, auth: bool) -> dict:
        headers = {
            "Content-Type": "application/json; charset=UTF-8",
            "Accept": "application/json",
            "User-Agent": USER_AGENT,
        }
        if self.device_id:  # like the app: no header until the device is registered
            headers["Device-ID"] = self.device_id
        if auth and self.token:
            headers["Authorization"] = f"Token {self.token}"
        return headers

    def _proxy(self) -> str:
        return get_proxy_url() if self.proxy_url is None else self.proxy_url

    def _post_sync(self, path: str, body: dict, auth: bool) -> dict:
        proxy = self._proxy()
        proxies = {"http": proxy, "https": proxy} if proxy else None
        try:
            resp = _http_for(proxy).post(
                self.base_url + path.lstrip("/"),
                json=body if body is not None else {},
                headers=self._headers(auth),
                timeout=(HTTP_CONNECT_TIMEOUT, HTTP_TIMEOUT),
                proxies=proxies,
            )
        except requests.exceptions.RequestException as exc:
            raise SuperLiveError(f"Falha de rede: {exc}") from None

        raw = resp.content
        if resp.status_code >= 400:
            parsed = _parse_json(raw)
            # visible in the backend window; the request body (passwords) is never logged
            log.warning("SuperLive %s -> HTTP %s: %s", path, resp.status_code,
                        raw.decode("utf-8", errors="replace")[:300])
            raise SuperLiveError(
                _server_message(parsed) or f"HTTP {resp.status_code}", resp.status_code, parsed,
                retry_after=_retry_after_seconds(resp.headers.get("Retry-After")),
            )

        parsed = _parse_json(raw)
        if isinstance(parsed, dict) and parsed.get("success") is False:
            raise SuperLiveError(
                _server_message(parsed) or "Operação recusada pelo SuperLive",
                resp.status_code, parsed,
            )
        return parsed if isinstance(parsed, dict) else {}

    async def post(self, path: str, body=None, auth: bool = True,
                    priority: int = PRIORITY_NORMAL) -> dict:
        queue = _ensure_dispatcher(self._proxy())
        if priority >= PRIORITY_LOW and queue.qsize() >= _low_queue_max():
            # Shed background polling instead of letting it pile up behind (and
            # delay) real work; the watcher just tries again next cycle.
            raise SuperLiveError("Fila de saída do SuperLive ocupada; tentando de novo em breve.", 0)
        loop = asyncio.get_running_loop()
        fut = loop.create_future()
        await queue.put((priority, next(_seq), fut, self, path, body, auth))
        try:
            return await fut
        except asyncio.CancelledError:
            fut.cancel()
            raise

    # ── account ────────────────────────────────────────────────────────────
    async def register_device(self) -> str:
        """Ask SuperLive for a device id (``device/register`` -> ``guid``), exactly
        like the app does on first launch, and use it from now on."""
        previous, self.device_id = self.device_id, None  # registration is sent without a Device-ID
        try:
            data = unwrap(await self.post("device/register", {}, auth=False))
        except SuperLiveError:
            self.device_id = previous
            raise
        guid = data.get("guid") or data.get("device_id")
        if not guid:
            self.device_id = previous
            raise SuperLiveError("O SuperLive não devolveu um identificador de aparelho", 200, data)
        self.device_id = str(guid)
        return self.device_id

    async def send_phone_code(self, phone_number: str, is_retry: bool = False) -> dict:
        """Step 1 of phone login: ask SuperLive to text a code to ``phone_number``
        (E.164, e.g. ``+5511999999999``). Returns ``{verification_id, retry_timeout_seconds}``.

        Like the real app, we send only ``phone_number``/``is_retry`` — never a forged
        ``app_check_token``/``re_token``/``recaptcha_token``. The app itself gates this
        call behind the same App Check/reCAPTCHA pre-check used for e-mail login, so the
        server may well reject this; if it does, the error is surfaced as-is.
        """
        body = await self.post(
            "user/signup/send_phone_verification_code",
            {"phone_number": phone_number, "is_retry": is_retry}, auth=False,
        )
        data = unwrap(body)
        verification_id = data.get("phone_verification_id")
        if not verification_id:
            _log_unexpected_200("user/signup/send_phone_verification_code", body)
            raise SuperLiveError(
                _server_message(body) or "O SuperLive não devolveu o identificador da verificação",
                200, body,
            )
        return {
            "verification_id": str(verification_id),
            "retry_timeout_seconds": int(data.get("retry_timeout_seconds") or 60),
        }

    async def verify_phone_code(self, verification_id: str, phone_number: str, code: str) -> str:
        """Step 2 of phone login: confirm the SMS code and obtain the session token."""
        body = await self.post(
            "user/signup/auth_phone",
            {"phone_verification_id": verification_id, "phone_number": phone_number, "code": code},
            auth=False,
        )
        # NOTE: the response also carries `logged_in`/`existed` (onboarding context, e.g.
        # "is this a brand-new account") but the real app's own repository
        # (UserSignUpRepositoryImpl.verifyPhoneWithSmsCode) saves the token unconditionally
        # once present, ignoring both flags. We do the same: `logged_in: false` with a
        # token is not a failure.
        data = unwrap(body)
        token = data.get("token")
        if not token:
            _log_unexpected_200("user/signup/auth_phone", body)
            raise SuperLiveError(
                _server_message(body) or "Código inválido ou expirado", 200, body
            )
        self.token = str(token)
        return self.token

    async def send_email_otp_code(self, email: str, force_new: bool = False) -> int:
        """Step 1 of e-mail-code login: ask SuperLive to e-mail a one-time code to
        ``email``. Returns the ``email_otp_code_id`` needed for step 2.

        Not the same thing as ``login()`` (``user/signup/email_signin``, password):
        this is the flow the real app falls back to for an account that has no
        password set on its e-mail (e.g. created via phone or Google/Apple login,
        with the e-mail only linked afterwards) - confirmed in
        ``SendEmailOtpCodeUseCase``/``UserSignUpApiService`` in the decompiled app.
        Like the phone flow, we send only ``email``/``force_new`` - never a forged
        ``app_check_token``/``re_token``/``recaptcha_token``; if SuperLive insists
        on one, the error is surfaced as-is.
        """
        body = await self.post(
            "user/signup/send_email_otp_code",
            {"email": email, "force_new": force_new}, auth=False,
        )
        data = unwrap(body)
        otp_code_id = data.get("email_otp_code_id")
        if otp_code_id is None:
            _log_unexpected_200("user/signup/send_email_otp_code", body)
            raise SuperLiveError(
                _server_message(body) or "O SuperLive não devolveu o identificador do código",
                200, body,
            )
        return int(otp_code_id)

    async def verify_email_otp_code(self, email_otp_code_id: int, code: str) -> str:
        """Step 2 of e-mail-code login: confirm the code and obtain the session token."""
        try:
            code_int = int(str(code).strip())
        except ValueError:
            raise SuperLiveError("O código deve conter só números.", 0) from None
        body = await self.post(
            "user/signup/otp",
            {"email_otp_code_id": email_otp_code_id, "code": code_int}, auth=False,
        )
        data = unwrap(body)
        token = data.get("token")
        if not token:
            _log_unexpected_200("user/signup/otp", body)
            raise SuperLiveError(
                _server_message(body) or "Código inválido ou expirado", 200, body
            )
        self.token = str(token)
        return self.token

    async def login(self, email: str, password: str) -> str:
        body = await self.post(
            "user/signup/email_signin", {"email": email, "password": password}, auth=False
        )
        # Same note as verify_phone_code: the app's UserSignUpRepositoryImpl.emailLogin
        # saves `token` unconditionally, regardless of `logged_in`/`existed`.
        data = unwrap(body)
        token = data.get("token") or data.get("access_token")
        if not token:
            _log_unexpected_200("user/signup/email_signin", body)
            raise SuperLiveError(
                _server_message(body) or "O SuperLive não devolveu uma sessão válida",
                200, body,
            )
        self.token = str(token)
        return self.token

    async def own_profile(self) -> dict:
        data = unwrap(await self.post("users/own_profile", {}))
        user = data.get("user") if isinstance(data.get("user"), dict) else data
        return user if isinstance(user, dict) else {}

    async def other_profile(self, user_id: str, priority: int = PRIORITY_NORMAL) -> dict:
        """Public profile by the *internal* ``user_id`` — NOT the "ID: ..." number shown
        on the profile screen in the app (that one is ``shared_id``; see
        :meth:`find_live_by_shared_id`). Mixing the two up returns a *different,
        unrelated account* instead of an error, which is easy to miss.
        """
        data = unwrap(await self.post("users/profile", {"user_id": user_id}, priority=priority))
        user = data.get("user") if isinstance(data.get("user"), dict) else data
        return user if isinstance(user, dict) else {}

    async def search_users(self, query: str, priority: int = PRIORITY_NORMAL) -> list:
        data = unwrap(await self.post("users/search", {"search_query": query}, priority=priority))
        items = data.get("items")
        return items if isinstance(items, list) else []

    def _profile_result(self, profile: dict) -> dict:
        images = profile.get("profile_images")
        avatar = images[0].get("url") if isinstance(images, list) and images else None
        if avatar is None and isinstance(profile.get("profile_image"), dict):
            avatar = profile["profile_image"].get("url")
        livestream_id = profile.get("livestream_id")
        return {
            "nickname": profile.get("name") or "Streamer",
            "avatar": avatar,
            "live": bool(livestream_id),
            "livestream_id": str(livestream_id) if livestream_id else None,
        }

    async def find_live_by_user_id(self, user_id: str, priority: int = PRIORITY_NORMAL) -> dict:
        """Resolve a streamer's *internal* account id to her current livestream_id, if
        she is live right now — the same lookup the app's profile screen uses to enable
        its "watch live" button (``OtherProfileViewModel``: the button only works when
        ``profile.livestream_id != null``).
        """
        profile = await self.other_profile(user_id, priority)
        if not profile or not (profile.get("user_id") or profile.get("id")):
            raise SuperLiveError("Não encontramos nenhuma conta com esse ID.", 200, profile)
        return self._profile_result(profile)

    async def find_live_by_shared_id(self, shared_id: str, priority: int = PRIORITY_NORMAL) -> dict:
        """Resolve the **public** "ID: ..." shown on a SuperLive profile (``shared_id``)
        to her current livestream_id. ``shared_id`` is a different field from the
        internal ``user_id`` that :meth:`other_profile` actually keys on — confirmed by
        a real lookup: searching ``users/profile`` by the displayed id silently returned
        a *different, unrelated account* instead of an error. So we resolve it properly:
        search for the id (``users/search``, the same endpoint behind the app's search
        bar), match the account whose own ``shared_id`` equals it, then read her current
        livestream_id from her real profile via the resolved internal ``user_id``.
        """
        cached = _shared_id_cache.get(str(shared_id))
        if cached:
            try:
                return await self.find_live_by_user_id(cached, priority)
            except SuperLiveError as exc:
                if exc.status == 0 or exc.status >= 500:
                    raise  # transient (network, SuperLive down): the id is still good
                _shared_id_cache.pop(str(shared_id), None)  # stale: resolve again below
        results = await self.search_users(shared_id, priority)
        match = next(
            (u for u in results if str(u.get("shared_id") or "") == str(shared_id)), None
        )
        if match is None:
            raise SuperLiveError("Não encontramos nenhuma conta com esse ID.", 200,
                                 {"query": shared_id, "results_count": len(results)})
        user_id = match.get("user_id")
        if not user_id:
            # the search result itself still carries name/livestream_id; fall back to it
            # rather than failing outright if, for some reason, it has no user_id.
            return self._profile_result(match)
        _shared_id_cache[str(shared_id)] = str(user_id)
        return await self.find_live_by_user_id(str(user_id), priority)

    async def get_settings(self) -> dict:
        return unwrap(await self.post("user/settings", {}))

    async def logout(self) -> None:
        await self.post("user/logout", {})

    # ── livestream ─────────────────────────────────────────────────────────
    async def retrieve_livestream(self, livestream_id: str) -> dict:
        return unwrap(await self.post("livestream/retrieve", {"livestream_id": livestream_id}))

    async def send_text(self, livestream_id: str, text: str) -> dict:
        return await self.post(
            "livestream/chat/send_text_message",
            {"livestream_id": livestream_id, "text": text, "guid": str(uuid.uuid4())},
        )

    async def mute(self, livestream_id: str, user_id: str) -> dict:
        return await self.post(
            "livestream/chat/mute", {"livestream_id": livestream_id, "user_id": user_id},
            priority=PRIORITY_URGENT,
        )

    async def kick(self, livestream_id: str, user_id: str, permanent: bool = False) -> dict:
        return await self.post(
            "livestream/kick",
            {"livestream_id": livestream_id, "user_id": user_id, "permanent": bool(permanent)},
            priority=PRIORITY_URGENT,
        )


def _parse_json(raw: bytes):
    if not raw:
        return {}
    try:
        return json.loads(raw.decode("utf-8", errors="replace"))
    except ValueError:
        return {"message": raw.decode("utf-8", errors="replace")[:200]}


# ── real-time channel helpers ──────────────────────────────────────────────
def build_ws_url(base_url: str, device_id: str, token: str) -> str:
    sep = "&" if "?" in base_url else "?"
    return f"{base_url}{sep}device={device_id}&auth={token}"


def client_message(action: str, data: dict) -> str:
    return json.dumps({"id": str(uuid.uuid4()), "action": action, "data": data})


def enter_message(livestream_id: str) -> str:
    return client_message("enter_livestream", {"livestream_id": livestream_id})


def leave_message(livestream_id: str) -> str:
    return client_message("leave_livestream", {"livestream_id": livestream_id})


def heartbeat_message(livestream_id: str) -> str:
    return client_message("heartbeat", {"state": f"livestream:{livestream_id}"})
