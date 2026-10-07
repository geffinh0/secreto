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
import json
import logging
import os
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

log = logging.getLogger("super_moderator.superlive")


class SuperLiveError(Exception):
    """Any failure talking to SuperLive. ``status`` is 0 for network-level errors."""

    def __init__(self, message: str, status: int = 0, body=None):
        super().__init__(message)
        self.message = message
        self.status = status
        self.body = body

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


class SuperLiveClient:
    """``device_id`` must be a *server-issued* id (see :meth:`register_device`): the
    real app registers the device first and sends the returned ``guid`` as the
    ``Device-ID`` header on every call. A made-up id is rejected by the server
    ("unknown urd")."""

    def __init__(self, token=None, device_id=None, base_url=None):
        self.token = token
        self.device_id = device_id
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

    def _post_sync(self, path: str, body: dict, auth: bool) -> dict:
        proxy = get_proxy_url()
        proxies = {"http": proxy, "https": proxy} if proxy else None
        try:
            resp = requests.post(
                self.base_url + path.lstrip("/"),
                json=body if body is not None else {},
                headers=self._headers(auth),
                timeout=HTTP_TIMEOUT,
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
                _server_message(parsed) or f"HTTP {resp.status_code}", resp.status_code, parsed
            )

        parsed = _parse_json(raw)
        if isinstance(parsed, dict) and parsed.get("success") is False:
            raise SuperLiveError(
                _server_message(parsed) or "Operação recusada pelo SuperLive",
                resp.status_code, parsed,
            )
        return parsed if isinstance(parsed, dict) else {}

    async def post(self, path: str, body=None, auth: bool = True) -> dict:
        return await asyncio.to_thread(self._post_sync, path, body or {}, auth)

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

    async def other_profile(self, user_id: str) -> dict:
        """Public profile by the *internal* ``user_id`` — NOT the "ID: ..." number shown
        on the profile screen in the app (that one is ``shared_id``; see
        :meth:`find_live_by_shared_id`). Mixing the two up returns a *different,
        unrelated account* instead of an error, which is easy to miss.
        """
        data = unwrap(await self.post("users/profile", {"user_id": user_id}))
        user = data.get("user") if isinstance(data.get("user"), dict) else data
        return user if isinstance(user, dict) else {}

    async def search_users(self, query: str) -> list:
        data = unwrap(await self.post("users/search", {"search_query": query}))
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

    async def find_live_by_user_id(self, user_id: str) -> dict:
        """Resolve a streamer's *internal* account id to her current livestream_id, if
        she is live right now — the same lookup the app's profile screen uses to enable
        its "watch live" button (``OtherProfileViewModel``: the button only works when
        ``profile.livestream_id != null``).
        """
        profile = await self.other_profile(user_id)
        if not profile or not (profile.get("user_id") or profile.get("id")):
            raise SuperLiveError("Não encontramos nenhuma conta com esse ID.", 200, profile)
        return self._profile_result(profile)

    async def find_live_by_shared_id(self, shared_id: str) -> dict:
        """Resolve the **public** "ID: ..." shown on a SuperLive profile (``shared_id``)
        to her current livestream_id. ``shared_id`` is a different field from the
        internal ``user_id`` that :meth:`other_profile` actually keys on — confirmed by
        a real lookup: searching ``users/profile`` by the displayed id silently returned
        a *different, unrelated account* instead of an error. So we resolve it properly:
        search for the id (``users/search``, the same endpoint behind the app's search
        bar), match the account whose own ``shared_id`` equals it, then read her current
        livestream_id from her real profile via the resolved internal ``user_id``.
        """
        results = await self.search_users(shared_id)
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
        return await self.find_live_by_user_id(str(user_id))

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
            "livestream/chat/mute", {"livestream_id": livestream_id, "user_id": user_id}
        )

    async def kick(self, livestream_id: str, user_id: str, permanent: bool = False) -> dict:
        return await self.post(
            "livestream/kick",
            {"livestream_id": livestream_id, "user_id": user_id, "permanent": bool(permanent)},
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
