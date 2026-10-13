import asyncio
import logging
import hmac
import os
import re
import secrets
import sqlite3
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
from dataclasses import dataclass
from typing import Literal, Optional

from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field, field_validator

import db
import security
from db import row_to_dict
from engine import (
    IDLE_SNAPSHOT, MIN_INTERVAL_SECONDS, RuleMatcher, SessionManager, WatchManager, normalize,
)
from engine import client_for_user, watch_poll_interval
from superlive import SuperLiveClient, SuperLiveError, get_proxy_pool, queue_depths

_log_handlers = [logging.StreamHandler()]
# Opt-in persistent log file (SM_LOG_FILE=path/to/file.log) - used for local
# multi-account test runs (see start_local_test.bat) and for a VPS test run
# pointed at /data (the backend's persisted volume), so the log survives a
# `docker compose up -d --build` recreating the container mid-test - plain
# `docker logs` does not. Unset: console-only logging, unchanged from before.
_log_file = os.getenv("SM_LOG_FILE")
if _log_file:
    log_dir = os.path.dirname(_log_file)
    if log_dir:
        os.makedirs(log_dir, exist_ok=True)
    _log_handlers.append(logging.FileHandler(_log_file, encoding="utf-8"))
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    handlers=_log_handlers,
)

sessions = SessionManager()
watchers = WatchManager(sessions)
# 8 failures lock one username; the per-IP budget is higher because until the
# real client IP is trusted (FORWARDED_ALLOW_IPS) it may be one bucket for everyone.
LOGIN_IP_MAX_FAILURES = int(os.getenv("SM_LOGIN_IP_MAX", "50"))
throttle = security.LoginThrottle(ip_max_failures=LOGIN_IP_MAX_FAILURES)
# Wrong agency codes per client IP (guessing a code = signing up for free):
# the code space is ~10^12 so this only has to stop scripted guessing.
REGISTER_IP_MAX_FAILURES = int(os.getenv("SM_REGISTER_IP_MAX", "20"))
register_throttle = security.LoginThrottle(
    ip_max_failures=REGISTER_IP_MAX_FAILURES, window_seconds=600)
# Resending a login code costs SuperLive an SMS/e-mail to a third party, so the
# server enforces what the app only hints at: a minimum gap and a daily cap.
CODE_SEND_MIN_GAP_SECONDS = int(os.getenv("SM_CODE_SEND_MIN_GAP", "60"))
CODE_SEND_DAILY_MAX = int(os.getenv("SM_CODE_SEND_DAILY_MAX", "10"))
_code_sends: dict = {}  # user_id -> [monotonic timestamps of sends in the last 24h]

USERNAME_RE = re.compile(r"^[A-Za-z0-9_.-]{3,32}$")
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
LIVESTREAM_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
PHONE_RE = re.compile(r"^\+[1-9]\d{7,14}$")  # E.164: '+', country code, 8-15 digits total

# Phone login is two steps (send SMS code, then verify it) with a real SMS in between,
# so the pending attempt is held here between the two calls. In-memory only: a backend
# restart simply makes the user ask for a new code.
PHONE_CODE_TTL_SECONDS = 600
# Caps brute-forcing the SMS/e-mail code itself (it has no attempt limit on
# our side otherwise, only the TTL above). Kept across a resend - a resend
# asks SuperLive for a fresh code, it is not a way to reset the attempt
# budget - and reserved before the verification call below, not after, so
# concurrent verify requests can't all read "attempts < MAX" before any of
# them writes.
MAX_OTP_ATTEMPTS = 5


@dataclass
class _PendingPhoneLogin:
    device_id: str
    phone_number: str
    verification_id: str
    expires_at: float
    attempts: int = 0


_pending_phone_logins: dict[int, _PendingPhoneLogin] = {}

# Same idea as phone login, but for an account whose e-mail has no password set
# (see SuperLiveClient.send_email_otp_code) - SuperLive mails a one-time code
# instead of asking for a password.
EMAIL_CODE_TTL_SECONDS = 600


@dataclass
class _PendingEmailLogin:
    device_id: str
    email: str
    otp_code_id: int
    expires_at: float
    attempts: int = 0


_pending_email_logins: dict[int, _PendingEmailLogin] = {}


# ─── App setup ───────────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(_app: FastAPI):
    # Default executor is cpu+4 threads; every SuperLive egress parks one thread
    # per in-flight request and SQLite calls from the engine share the same pool.
    asyncio.get_running_loop().set_default_executor(
        ThreadPoolExecutor(max_workers=int(os.getenv("SM_THREADS", "64")),
                           thread_name_prefix="sm"))
    db.init_db()
    conn = db.connect()
    try:
        for watch in db.all_active_watches(conn):
            # jitter: hundreds of watchers must not all poll in the same second
            watchers.start(watch["user_id"], jitter=True)
        _bootstrap_admin_account(conn)
    finally:
        conn.close()
    print("[OK] Atila's Client API iniciada!")
    print(f"[DB] Banco de dados: {db.DB_PATH}")
    print("[DOCS] Docs: http://localhost:8000/docs")
    yield
    await watchers.shutdown()
    await sessions.shutdown()


app = FastAPI(
    title="Atila's Client API",
    description="Backend portal para o robô moderador de lives SuperLive",
    version="2.0.0",
    lifespan=lifespan,
)

@app.exception_handler(security.RobotKeyUnavailable)
async def _robot_key_unavailable(_request: Request, exc: security.RobotKeyUnavailable):
    # Fail closed: without the encryption key the robot token can be neither
    # stored nor read, and it is never silently handled in clear.
    logging.getLogger("super_moderator").error("robot token key unavailable: %s", exc)
    return JSONResponse(status_code=503, content={
        "detail": "Armazenamento seguro do robô indisponível. Avise o administrador."})


# The portal is served from localhost (any port); extra origins via SM_CORS_ORIGINS.
_extra_origins = [o.strip() for o in os.getenv("SM_CORS_ORIGINS", "").split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=_extra_origins,
    allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_credentials=False,  # auth is a bearer header, never cookies
    allow_methods=["*"],
    allow_headers=["*"],
)

bearer = HTTPBearer(auto_error=False)

_FIELD_LABELS = {
    "username": "Usuário", "email": "E-mail", "password": "Senha", "keyword": "Palavra",
    "action": "Ação", "content": "Mensagem", "message_interval_seconds": "Intervalo",
    "livestream_id": "ID da live",
    "display_name": "Nome", "token": "Token", "user_id": "user_id",
    "phone_number": "Telefone", "code": "Código", "shared_id": "ID público",
    "agency_code": "Código da agência", "name": "Nome da agência",
}


def _describe_validation_error(err: dict) -> str:
    field = err["loc"][-1] if err.get("loc") else "corpo"
    label = _FIELD_LABELS.get(field, str(field))
    kind, ctx = err.get("type", ""), err.get("ctx") or {}
    if kind == "missing":
        return f"{label}: campo obrigatório"
    if kind == "string_too_short":
        return f"{label}: não pode ficar vazio" if ctx.get("min_length") == 1 \
            else f"{label}: mínimo de {ctx.get('min_length')} caracteres"
    if kind == "string_too_long":
        return f"{label}: máximo de {ctx.get('max_length')} caracteres"
    if kind in ("greater_than_equal", "less_than_equal"):
        bound = ctx.get("ge", ctx.get("le"))
        return f"{label}: deve ser {'no mínimo' if kind == 'greater_than_equal' else 'no máximo'} {bound}"
    if kind == "literal_error":
        return f"{label}: valor inválido"
    msg = str(err.get("msg", "valor inválido"))
    return f"{label}: {msg.removeprefix('Value error, ')}"


@app.exception_handler(RequestValidationError)
async def validation_error_handler(_request: Request, exc: RequestValidationError):
    # `detail` is always a plain string so every client can show it directly.
    message = "; ".join(_describe_validation_error(e) for e in exc.errors()[:3])
    return JSONResponse(status_code=422, content={"detail": message})


# ─── Dependencies ────────────────────────────────────────────────────────────
def get_db():
    conn = db.connect()
    try:
        yield conn
    finally:
        conn.close()


def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer),
    conn: sqlite3.Connection = Depends(get_db),
):
    if credentials is None:
        raise HTTPException(401, "Token ausente")
    row = conn.execute(
        "SELECT u.* FROM users u JOIN sessions s ON s.user_id = u.id "
        "WHERE s.token_hash = ? AND s.expires_at > datetime('now')",
        (security.hash_token(credentials.credentials),),
    ).fetchone()
    if not row:
        raise HTTPException(401, "Token inválido ou sessão expirada")
    return row_to_dict(row)


def require_owner(current_user: dict, user_id: int) -> None:
    if user_id != current_user["id"]:
        raise HTTPException(403, "Acesso negado a dados de outro usuário")


def get_owned(conn, table: str, row_id: int, current_user: dict, not_found: str):
    """Fetch a row by id, but only if it belongs to the caller (404 otherwise)."""
    row = conn.execute(f"SELECT * FROM {table} WHERE id = ?", (row_id,)).fetchone()  # table is a literal
    if row is None or row["user_id"] != current_user["id"]:
        raise HTTPException(404, not_found)
    return row


def create_session(conn, user_id: int) -> str:
    token = security.generate_token()
    hashed = security.hash_token(token)  # only the hash is stored (token column mirrors it)
    conn.execute(
        "INSERT INTO sessions (user_id, token, token_hash, expires_at) "
        "VALUES (?, ?, ?, datetime('now', ?))",
        (user_id, hashed, hashed, f"+{db.SESSION_DAYS} days"),
    )
    conn.commit()
    return token


def public_user(row) -> dict:
    user = row_to_dict(row) if not isinstance(row, dict) else dict(row)
    user.pop("password_hash", None)
    return user


# ─── Schemas ─────────────────────────────────────────────────────────────────
def _clean_keyword(value: str) -> str:
    cleaned = " ".join(value.lower().split())
    if not cleaned:
        raise ValueError("a palavra não pode ficar vazia")
    return cleaned


class RegisterRequest(BaseModel):
    username: str
    email: str
    password: str = Field(min_length=8, max_length=128)
    display_name: Optional[str] = Field(default=None, max_length=60)
    agency_code: str = Field(min_length=1, max_length=40)

    @field_validator("username")
    @classmethod
    def _username(cls, v: str) -> str:
        v = v.strip()
        if not USERNAME_RE.match(v):
            raise ValueError("use 3 a 32 caracteres: letras, números, ponto, hífen ou underline")
        return v

    @field_validator("email")
    @classmethod
    def _email(cls, v: str) -> str:
        v = v.strip().lower()
        if len(v) > 200 or not EMAIL_RE.match(v):
            raise ValueError("e-mail inválido")
        return v


class LoginRequest(BaseModel):
    username: str = Field(min_length=1, max_length=200)
    password: str = Field(min_length=1, max_length=128)


class ModerationRuleCreate(BaseModel):
    user_id: int
    keyword: str = Field(min_length=1, max_length=60)
    action: Literal["mute", "kick"]
    is_active: bool = True

    @field_validator("keyword")
    @classmethod
    def _keyword(cls, v: str) -> str:
        return _clean_keyword(v)


class ModerationTestRequest(BaseModel):
    user_id: int
    text: str = Field(min_length=1, max_length=500)


class ModerationBulkCreate(BaseModel):
    user_id: int
    action: Literal["mute", "kick"]
    keywords: list[str] = Field(min_length=1, max_length=200)


class ModerationRuleUpdate(BaseModel):
    keyword: Optional[str] = Field(default=None, min_length=1, max_length=60)
    action: Optional[Literal["mute", "kick"]] = None
    is_active: Optional[bool] = None

    @field_validator("keyword")
    @classmethod
    def _keyword(cls, v):
        return None if v is None else _clean_keyword(v)


class AutoMessageCreate(BaseModel):
    user_id: int
    content: str = Field(min_length=1, max_length=500)
    sort_order: int = Field(default=0, ge=0)
    is_active: bool = True

    @field_validator("content")
    @classmethod
    def _content(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("a mensagem não pode ficar vazia")
        return v


class AutoMessageUpdate(BaseModel):
    content: Optional[str] = Field(default=None, min_length=1, max_length=500)
    sort_order: Optional[int] = Field(default=None, ge=0)
    is_active: Optional[bool] = None

    @field_validator("content")
    @classmethod
    def _content(cls, v):
        if v is None:
            return None
        v = v.strip()
        if not v:
            raise ValueError("a mensagem não pode ficar vazia")
        return v


class BotSettingsUpdate(BaseModel):
    """Partial update: only the fields present in the request are changed."""
    user_id: Optional[int] = None
    auto_messages_enabled: Optional[bool] = None
    message_interval_seconds: Optional[int] = Field(default=None, ge=MIN_INTERVAL_SECONDS, le=3600)
    moderation_enabled: Optional[bool] = None
    kick_permanent: Optional[bool] = None
    diamond_immunity_enabled: Optional[bool] = None
    diamond_immunity_threshold: Optional[int] = Field(
        default=None, ge=db.MIN_DIAMOND_IMMUNITY_THRESHOLD, le=1_000_000)


class RobotConnectRequest(BaseModel):
    email: Optional[str] = Field(default=None, max_length=200)
    password: Optional[str] = Field(default=None, max_length=200)
    token: Optional[str] = Field(default=None, max_length=4000)


class RobotPhoneSendCodeRequest(BaseModel):
    phone_number: str = Field(max_length=20)
    resend: bool = False

    @field_validator("phone_number")
    @classmethod
    def _phone_number(cls, v: str) -> str:
        v = v.strip()
        if not PHONE_RE.match(v):
            raise ValueError("use o formato internacional, ex: +5511999999999")
        return v


class RobotPhoneVerifyRequest(BaseModel):
    phone_number: str = Field(max_length=20)
    code: str = Field(min_length=3, max_length=10)

    @field_validator("phone_number")
    @classmethod
    def _phone_number(cls, v: str) -> str:
        v = v.strip()
        if not PHONE_RE.match(v):
            raise ValueError("use o formato internacional, ex: +5511999999999")
        return v

    @field_validator("code")
    @classmethod
    def _code(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("informe o código recebido por SMS")
        return v


class RobotEmailCodeSendRequest(BaseModel):
    email: str = Field(max_length=200)
    resend: bool = False

    @field_validator("email")
    @classmethod
    def _email(cls, v: str) -> str:
        v = v.strip()
        if not EMAIL_RE.match(v):
            raise ValueError("e-mail inválido")
        return v


class RobotEmailCodeVerifyRequest(BaseModel):
    email: str = Field(max_length=200)
    code: str = Field(min_length=3, max_length=10)

    @field_validator("email")
    @classmethod
    def _email(cls, v: str) -> str:
        v = v.strip()
        if not EMAIL_RE.match(v):
            raise ValueError("e-mail inválido")
        return v

    @field_validator("code")
    @classmethod
    def _code(cls, v: str) -> str:
        v = v.strip()
        if not v.isdigit():
            raise ValueError("informe o código recebido por e-mail (só números)")
        return v


class RobotStartRequest(BaseModel):
    livestream_id: str

    @field_validator("livestream_id")
    @classmethod
    def _livestream_id(cls, v: str) -> str:
        v = v.strip()
        if not LIVESTREAM_ID_RE.match(v):
            raise ValueError("use apenas letras, números, hífen e underline (até 64)")
        return v


class RobotLookupStreamerRequest(BaseModel):
    """``shared_id``: the numeric "ID: ..." shown on a creator's SuperLive profile
    screen. Not the same as SuperLive's *internal* user_id (a different field on the
    same account) nor the livestream_id — see SuperLiveClient.find_live_by_shared_id.
    """
    shared_id: str = Field(min_length=1, max_length=40)

    @field_validator("shared_id")
    @classmethod
    def _shared_id(cls, v: str) -> str:
        v = v.strip()
        if not v.isdigit():
            raise ValueError("use o ID numérico público do perfil dela no SuperLive")
        return v


class RobotWatchRequest(BaseModel):
    """Favourite a streamer (by her public profile id) for the robot to
    auto-join the moment she goes live, with ``active`` toggling it off again."""
    shared_id: str = Field(min_length=1, max_length=40)
    active: bool = True

    @field_validator("shared_id")
    @classmethod
    def _shared_id(cls, v: str) -> str:
        v = v.strip()
        if not v.isdigit():
            raise ValueError("use o ID numérico público do perfil dela no SuperLive")
        return v


# ─── Auth ────────────────────────────────────────────────────────────────────
@app.post("/auth/register")
def register(req: RegisterRequest, request: Request, conn: sqlite3.Connection = Depends(get_db)):
    if os.getenv("SM_ALLOW_REGISTRATION", "1") != "1":
        raise HTTPException(403, "Cadastro de novas contas está temporariamente desativado.")
    ip_key = f"ip:{request.client.host if request.client else 'unknown'}"
    if register_throttle.is_blocked(ip_key):
        raise HTTPException(429, "Muitas tentativas de cadastro. Aguarde alguns minutos.")
    # Same answer for "no such code" and "agency switched off", so the message
    # can't be used to tell which codes exist.
    agency = db.get_agency_by_code(conn, req.agency_code)
    if agency is None or not agency["active"]:
        register_throttle.record_failure(ip_key)
        raise HTTPException(400, "Código de agência inválido. Peça o código à sua agência.")
    existing = conn.execute(
        "SELECT id FROM users WHERE lower(username) = lower(?) OR lower(email) = lower(?)",
        (req.username, req.email),
    ).fetchone()
    if existing:
        raise HTTPException(400, "Usuário ou e-mail já cadastrado")

    try:
        cursor = conn.execute(
            "INSERT INTO users (username, email, display_name, password_hash, agency_id) "
            "VALUES (?, ?, ?, ?, ?)",
            (req.username, req.email, req.display_name or req.username,
             security.hash_password(req.password), agency["id"]),
        )
        conn.commit()
    except sqlite3.IntegrityError:
        raise HTTPException(400, "Usuário ou e-mail já cadastrado") from None
    user_id = cursor.lastrowid
    db.get_settings(conn, user_id)  # creates the default settings row

    token = create_session(conn, user_id)
    user = public_user(conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone())
    db.log_activity(user_id, "account_created", f"usuário {req.username} (agência {agency['name']})")
    return {"access_token": token, "token_type": "bearer", "user": user}


@app.post("/auth/login")
def login(req: LoginRequest, request: Request, conn: sqlite3.Connection = Depends(get_db)):
    ip = request.client.host if request.client else "unknown"
    user_key, ip_key = f"user:{req.username.lower()}", f"ip:{ip}"
    if throttle.is_blocked(user_key, ip_key):
        raise HTTPException(429, "Muitas tentativas de login. Aguarde alguns minutos.")

    row = conn.execute(
        "SELECT * FROM users WHERE lower(username) = lower(?)", (req.username,)
    ).fetchone()
    if row is None:
        security.burn_password_check(req.password)
        valid, needs_rehash = False, False
    else:
        valid, needs_rehash = security.verify_password(req.password, row["password_hash"])
    if not valid:
        throttle.record_failure(user_key, ip_key)
        raise HTTPException(401, "Credenciais inválidas")

    throttle.reset(user_key)
    if needs_rehash:
        conn.execute("UPDATE users SET password_hash = ? WHERE id = ?",
                     (security.hash_password(req.password), row["id"]))
        conn.commit()
    token = create_session(conn, row["id"])
    db.log_activity(row["id"], "login")
    return {"access_token": token, "token_type": "bearer", "user": public_user(row)}


@app.get("/auth/me")
def get_me(current_user: dict = Depends(get_current_user)):
    return public_user(current_user)


@app.post("/auth/logout")
def logout(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer),
    conn: sqlite3.Connection = Depends(get_db),
):
    if credentials is not None:
        conn.execute("DELETE FROM sessions WHERE token_hash = ?", (security.hash_token(credentials.credentials),))
        conn.commit()
    return {"success": True}


# ─── Moderation rules ────────────────────────────────────────────────────────
def _keyword_taken(conn, user_id: int, keyword: str, action: str,
                    exclude_id: Optional[int] = None) -> bool:
    """Whether `keyword` is already registered for this user under this same
    `action`. Scoped per action so the same word can be a mute rule and a
    kick rule at once (e.g. escalating a muted word to a ban later)."""
    target = normalize(keyword)
    rows = conn.execute(
        "SELECT id, keyword FROM moderation_rules WHERE user_id = ? AND action = ?",
        (user_id, action),
    ).fetchall()
    return any(r["id"] != exclude_id and normalize(r["keyword"]) == target for r in rows)


@app.get("/moderation/rules")
def list_rules(user_id: int, current_user: dict = Depends(get_current_user),
               conn: sqlite3.Connection = Depends(get_db)):
    require_owner(current_user, user_id)
    rows = conn.execute(
        "SELECT * FROM moderation_rules WHERE user_id = ? ORDER BY created_at DESC, id DESC",
        (user_id,),
    ).fetchall()
    return [row_to_dict(r) for r in rows]


@app.post("/moderation/rules")
def create_rule(req: ModerationRuleCreate, current_user: dict = Depends(get_current_user),
                conn: sqlite3.Connection = Depends(get_db)):
    require_owner(current_user, req.user_id)
    if _keyword_taken(conn, req.user_id, req.keyword, req.action):
        raise HTTPException(409, "Essa palavra já está cadastrada nessa lista")
    cursor = conn.execute(
        "INSERT INTO moderation_rules (user_id, keyword, action, is_active) VALUES (?, ?, ?, ?)",
        (req.user_id, req.keyword, req.action, int(req.is_active)),
    )
    conn.commit()
    db.log_activity(req.user_id, "rule_created", f'{req.action}: "{req.keyword}"')
    return row_to_dict(conn.execute(
        "SELECT * FROM moderation_rules WHERE id = ?", (cursor.lastrowid,)).fetchone())


@app.post("/moderation/rules/bulk")
def create_rules_bulk(req: ModerationBulkCreate, current_user: dict = Depends(get_current_user),
                      conn: sqlite3.Connection = Depends(get_db)):
    """Adds many keywords to the same list in one call (paste a batch instead
    of one-by-one). Cleans each line, skips blanks, de-duplicates against
    what's already registered *and* within the pasted batch itself - partial
    success is fine, the response says exactly what landed and what didn't."""
    require_owner(current_user, req.user_id)
    created, skipped = [], []
    seen_this_batch = set()
    for raw in req.keywords:
        try:
            keyword = _clean_keyword(raw)
        except ValueError:
            skipped.append({"keyword": raw, "reason": "vazia"})
            continue
        target = normalize(keyword)
        if target in seen_this_batch:
            skipped.append({"keyword": keyword, "reason": "duplicada no lote colado"})
            continue
        if _keyword_taken(conn, req.user_id, keyword, req.action):
            skipped.append({"keyword": keyword, "reason": "já cadastrada"})
            continue
        seen_this_batch.add(target)
        cursor = conn.execute(
            "INSERT INTO moderation_rules (user_id, keyword, action, is_active) VALUES (?, ?, ?, 1)",
            (req.user_id, keyword, req.action),
        )
        created.append(row_to_dict(conn.execute(
            "SELECT * FROM moderation_rules WHERE id = ?", (cursor.lastrowid,)).fetchone()))
    conn.commit()
    if created:
        db.log_activity(req.user_id, "rule_created",
                         f"{len(created)} palavras adicionadas em lote ({req.action})")
    return {"created": created, "skipped": skipped}


@app.post("/moderation/test")
def test_phrase(req: ModerationTestRequest, current_user: dict = Depends(get_current_user),
                conn: sqlite3.Connection = Depends(get_db)):
    """Runs a sample message through the user's own active rules - lets her
    check whether a tricky spelling ("g0z4", "p4ss4zap") would actually be
    caught before relying on it live. Uses the exact same RuleMatcher the
    running robot uses, so the answer here is never out of sync with reality."""
    require_owner(current_user, req.user_id)
    rows = conn.execute(
        "SELECT id, keyword, action FROM moderation_rules WHERE user_id = ? AND is_active = 1",
        (req.user_id,),
    ).fetchall()
    matcher = RuleMatcher([row_to_dict(r) for r in rows])
    hit = matcher.match(req.text)
    if hit is None:
        return {"matched": False, "action": None, "keyword": None}
    action, keyword = hit
    return {"matched": True, "action": action, "keyword": keyword}


@app.put("/moderation/rules/{rule_id}")
def update_rule(rule_id: int, req: ModerationRuleUpdate,
                current_user: dict = Depends(get_current_user),
                conn: sqlite3.Connection = Depends(get_db)):
    row = get_owned(conn, "moderation_rules", rule_id, current_user, "Regra não encontrada")
    updates, values, changed_fields = [], [], []
    if req.keyword is not None:
        effective_action = req.action if req.action is not None else row["action"]
        if _keyword_taken(conn, current_user["id"], req.keyword, effective_action,
                           exclude_id=rule_id):
            raise HTTPException(409, "Essa palavra já está cadastrada nessa lista")
        updates.append("keyword = ?")
        values.append(req.keyword)
        changed_fields.append("keyword")
    if req.action is not None:
        updates.append("action = ?")
        values.append(req.action)
        changed_fields.append("action")
    if req.is_active is not None:
        updates.append("is_active = ?")
        values.append(int(req.is_active))
        changed_fields.append("is_active")
    if not updates:
        raise HTTPException(400, "Nenhum campo para atualizar")
    values.append(rule_id)
    conn.execute(f"UPDATE moderation_rules SET {', '.join(updates)} WHERE id = ?", values)
    conn.commit()
    db.log_activity(current_user["id"], "rule_updated",
                     f'regra #{rule_id}: {", ".join(changed_fields)}')
    return row_to_dict(conn.execute(
        "SELECT * FROM moderation_rules WHERE id = ?", (rule_id,)).fetchone())


@app.delete("/moderation/rules/{rule_id}")
def delete_rule(rule_id: int, current_user: dict = Depends(get_current_user),
                conn: sqlite3.Connection = Depends(get_db)):
    row = get_owned(conn, "moderation_rules", rule_id, current_user, "Regra não encontrada")
    conn.execute("DELETE FROM moderation_rules WHERE id = ?", (rule_id,))
    conn.commit()
    db.log_activity(current_user["id"], "rule_deleted", f'{row["action"]}: "{row["keyword"]}"')
    return {"success": True}


# ─── Auto messages ───────────────────────────────────────────────────────────
@app.get("/messages")
def list_messages(user_id: int, current_user: dict = Depends(get_current_user),
                  conn: sqlite3.Connection = Depends(get_db)):
    require_owner(current_user, user_id)
    rows = conn.execute(
        "SELECT * FROM auto_messages WHERE user_id = ? ORDER BY sort_order ASC, id ASC", (user_id,)
    ).fetchall()
    return [row_to_dict(r) for r in rows]


@app.post("/messages")
def create_message(req: AutoMessageCreate, current_user: dict = Depends(get_current_user),
                   conn: sqlite3.Connection = Depends(get_db)):
    require_owner(current_user, req.user_id)
    cursor = conn.execute(
        "INSERT INTO auto_messages (user_id, content, sort_order, is_active) VALUES (?, ?, ?, ?)",
        (req.user_id, req.content, req.sort_order, int(req.is_active)),
    )
    conn.commit()
    db.log_activity(req.user_id, "message_created", f'"{req.content[:80]}"')
    return row_to_dict(conn.execute(
        "SELECT * FROM auto_messages WHERE id = ?", (cursor.lastrowid,)).fetchone())


@app.put("/messages/{msg_id}")
def update_message(msg_id: int, req: AutoMessageUpdate,
                   current_user: dict = Depends(get_current_user),
                   conn: sqlite3.Connection = Depends(get_db)):
    get_owned(conn, "auto_messages", msg_id, current_user, "Mensagem não encontrada")
    updates, values = [], []
    if req.content is not None:
        updates.append("content = ?")
        values.append(req.content)
    if req.sort_order is not None:
        updates.append("sort_order = ?")
        values.append(req.sort_order)
    if req.is_active is not None:
        updates.append("is_active = ?")
        values.append(int(req.is_active))
    if not updates:
        raise HTTPException(400, "Nenhum campo para atualizar")
    values.append(msg_id)
    conn.execute(f"UPDATE auto_messages SET {', '.join(updates)} WHERE id = ?", values)
    conn.commit()
    if req.content is not None or req.is_active is not None:
        # sort_order-only updates happen on every drag-reorder - too noisy to log.
        db.log_activity(current_user["id"], "message_updated", f"mensagem #{msg_id}")
    return row_to_dict(conn.execute(
        "SELECT * FROM auto_messages WHERE id = ?", (msg_id,)).fetchone())


@app.delete("/messages/{msg_id}")
def delete_message(msg_id: int, current_user: dict = Depends(get_current_user),
                   conn: sqlite3.Connection = Depends(get_db)):
    get_owned(conn, "auto_messages", msg_id, current_user, "Mensagem não encontrada")
    conn.execute("DELETE FROM auto_messages WHERE id = ?", (msg_id,))
    conn.commit()
    db.log_activity(current_user["id"], "message_deleted", f"mensagem #{msg_id}")
    return {"success": True}


# ─── Bot settings ────────────────────────────────────────────────────────────
@app.get("/settings")
def get_settings(user_id: int, current_user: dict = Depends(get_current_user),
                 conn: sqlite3.Connection = Depends(get_db)):
    require_owner(current_user, user_id)
    return db.get_settings(conn, user_id)


_BOOL_SETTINGS = ("auto_messages_enabled", "moderation_enabled", "kick_permanent",
                  "diamond_immunity_enabled")


@app.put("/settings/{user_id}")
def update_settings(user_id: int, req: BotSettingsUpdate,
                    current_user: dict = Depends(get_current_user),
                    conn: sqlite3.Connection = Depends(get_db)):
    require_owner(current_user, user_id)
    db.get_settings(conn, user_id)  # make sure the row exists
    sent = req.model_dump(exclude_unset=True)
    updates, values = [], []
    for key in _BOOL_SETTINGS:
        if sent.get(key) is not None:
            updates.append(f"{key} = ?")
            values.append(int(sent[key]))
    if sent.get("message_interval_seconds") is not None:
        updates.append("message_interval_seconds = ?")
        values.append(sent["message_interval_seconds"])
    if sent.get("diamond_immunity_threshold") is not None:
        updates.append("diamond_immunity_threshold = ?")
        values.append(sent["diamond_immunity_threshold"])
    if updates:
        values.append(user_id)
        conn.execute(f"UPDATE bot_settings SET {', '.join(updates)} WHERE user_id = ?", values)
        conn.commit()
        db.log_activity(user_id, "settings_updated", ", ".join(sorted(sent.keys())))
    return db.get_settings(conn, user_id)


# ─── Robot (SuperLive account + live session) ────────────────────────────────
def _superlive_http_error(exc: SuperLiveError, action: str, login: bool = False) -> HTTPException:
    if exc.status == 0:
        return HTTPException(502, f"Não foi possível falar com o SuperLive ({exc.message}).")
    message = f"O SuperLive recusou {action} (HTTP {exc.status}): {exc.message}."
    if exc.is_auth_error and not login:
        message = "O token do robô expirou ou é inválido. Reconecte o robô na aba Robô."
    if login:
        message += (" Se a mensagem acima não for sobre e-mail/senha e o SuperLive estiver exigindo "
                    "verificação anti-robô (reCAPTCHA/App Check), use a opção \"Colar token\".")
    return HTTPException(400, message)


def _watch_payload(conn, user_id: int) -> dict:
    watch = db.get_watch(conn, user_id)
    if watch is None:
        return {"shared_id": None, "nickname": None, "avatar": None, "active": False}
    return {
        "shared_id": watch["shared_id"], "nickname": watch["nickname"],
        "avatar": watch["avatar"], "active": watch["active"],
    }


def _robot_payload(conn, user_id: int) -> dict:
    robot = db.get_robot(conn, user_id, with_token=False)
    session = sessions.get(user_id)
    return {
        "connected": robot is not None,
        "robot": None if robot is None else {
            "id": robot["sl_user_id"], "nickname": robot["nickname"],
            "avatar": robot["avatar"], "auth_mode": robot["auth_mode"],
            "last_livestream_id": robot["last_livestream_id"],
        },
        "session": session.snapshot() if session else IDLE_SNAPSHOT,
        "totals": db.action_totals(conn, user_id),
        "watch": _watch_payload(conn, user_id),
    }


def _save_robot_account(conn, user_id: int, client: SuperLiveClient, profile: dict, mode: str) -> None:
    sl_user_id = str(profile.get("id") or profile.get("user_id") or "") or None
    if sl_user_id and not db.shared_robot_allowed():
        taken = conn.execute(
            "SELECT user_id FROM robot_accounts WHERE sl_user_id = ? AND user_id != ?",
            (sl_user_id, user_id)).fetchone()
        if taken is not None:
            raise HTTPException(
                409, "Essa conta do SuperLive já está conectada a outra usuária do portal.")
    try:
        _write_robot_account(conn, user_id, client, profile, mode, sl_user_id)
    except sqlite3.IntegrityError:
        conn.rollback()  # lost a race with the unique index on sl_user_id
        raise HTTPException(
            409, "Essa conta do SuperLive já está conectada a outra usuária do portal.") from None


def _write_robot_account(conn, user_id: int, client: SuperLiveClient, profile: dict, mode: str,
                         sl_user_id) -> None:
    conn.execute(
        "INSERT INTO robot_accounts (user_id, sl_user_id, nickname, avatar, token, device_id, auth_mode) "
        "VALUES (?, ?, ?, ?, ?, ?, ?) "
        "ON CONFLICT(user_id) DO UPDATE SET sl_user_id = excluded.sl_user_id, "
        "nickname = excluded.nickname, avatar = excluded.avatar, token = excluded.token, "
        "device_id = excluded.device_id, auth_mode = excluded.auth_mode",
        (
            user_id,
            sl_user_id,
            profile.get("nickname") or profile.get("name") or profile.get("username")
            or "Atila's Client",
            profile.get("avatar") or profile.get("profile_picture") or profile.get("picture_url"),
            db.store_robot_token(client.token), client.device_id, mode,
        ),
    )
    conn.commit()


def _require_no_active_session(user_id: int) -> None:
    session = sessions.get(user_id)
    if session is not None and session.is_active:
        raise HTTPException(409, "Pare a sessão do robô antes de trocar a conta.")


def _client(conn, user_id: int, token=None, device_id=None) -> SuperLiveClient:
    """Every SuperLive call for a user leaves through that user's fixed egress."""
    return client_for_user(conn, user_id, token, device_id)


def _robot_device_client(conn, user_id: int) -> SuperLiveClient:
    """A client reusing the robot's already-registered device id, if any."""
    existing = db.get_robot(conn, user_id, with_token=False)
    return _client(conn, user_id, device_id=existing["device_id"] if existing else None)


def _check_code_send_allowed(user_id: int, min_gap: float) -> None:
    """429 unless the last code was sent at least ``min_gap`` seconds ago and
    fewer than CODE_SEND_DAILY_MAX were sent in the last 24h."""
    now = time.monotonic()
    sends = [t for t in _code_sends.get(user_id, ()) if now - t < 86400]
    _code_sends[user_id] = sends
    if sends and now - sends[-1] < min_gap:
        wait = int(min_gap - (now - sends[-1])) + 1
        raise HTTPException(429, f"Aguarde {wait}s para pedir um novo código.")
    if len(sends) >= CODE_SEND_DAILY_MAX:
        raise HTTPException(429, "Limite diário de códigos atingido. Tente amanhã.")


def _record_code_send(user_id: int) -> None:
    _code_sends.setdefault(user_id, []).append(time.monotonic())


@app.post("/robot/connect")
async def robot_connect(req: RobotConnectRequest, current_user: dict = Depends(get_current_user),
                        conn: sqlite3.Connection = Depends(get_db)):
    user_id = current_user["id"]
    _require_no_active_session(user_id)

    # Keep the robot's device id across reconnects; a first connection registers a new
    # device with SuperLive (the server rejects Device-IDs it did not issue).
    client = _robot_device_client(conn, user_id)
    token = (req.token or "").strip()
    email, password = (req.email or "").strip(), req.password or ""
    if not token and not (email and password):
        raise HTTPException(400, "Informe e-mail e senha do robô ou cole o token da sessão.")
    try:
        if not client.device_id:
            await client.register_device()
        if token:
            client.token, mode = token, "token"
        else:
            await client.login(email, password)
            mode = "password"
        profile = await client.own_profile()
    except SuperLiveError as exc:
        raise _superlive_http_error(exc, "o login do robô", login=True) from None

    _save_robot_account(conn, user_id, client, profile, mode)
    db.log_activity(user_id, "robot_connected", f"modo: {mode}")
    return _robot_payload(conn, user_id)


@app.post("/robot/connect/phone/send_code")
async def robot_connect_phone_send_code(
    req: RobotPhoneSendCodeRequest, current_user: dict = Depends(get_current_user),
    conn: sqlite3.Connection = Depends(get_db),
):
    """Step 1 of phone login: ask SuperLive to text a verification code.

    NOTE: in the real app this is gated by the same App Check/reCAPTCHA check as
    e-mail login (confirmed by decompiling ``LoginPhoneViewModel`` — it calls the
    identical pre-check before this request). We send the plain request, with no
    forged tokens, same as the app would if that check were unavailable; SuperLive
    may well refuse it, and its own message is shown as-is.
    """
    user_id = current_user["id"]
    _require_no_active_session(user_id)
    _check_code_send_allowed(user_id, CODE_SEND_MIN_GAP_SECONDS)

    client = _robot_device_client(conn, user_id)
    try:
        if not client.device_id:
            await client.register_device()
        result = await client.send_phone_code(req.phone_number, is_retry=req.resend)
    except SuperLiveError as exc:
        raise _superlive_http_error(exc, "o envio do código por SMS", login=True) from None
    _record_code_send(user_id)

    # A resend keeps whatever attempt budget was already spent - it is a new
    # code from SuperLive, not a way to reset how many guesses are left.
    previous_attempts = _pending_phone_logins.get(user_id)
    _pending_phone_logins[user_id] = _PendingPhoneLogin(
        device_id=client.device_id,
        phone_number=req.phone_number,
        verification_id=result["verification_id"],
        expires_at=time.monotonic() + PHONE_CODE_TTL_SECONDS,
        attempts=previous_attempts.attempts if previous_attempts else 0,
    )
    return {"retry_timeout_seconds": result["retry_timeout_seconds"]}


@app.post("/robot/connect/phone/verify")
async def robot_connect_phone_verify(
    req: RobotPhoneVerifyRequest, current_user: dict = Depends(get_current_user),
    conn: sqlite3.Connection = Depends(get_db),
):
    """Step 2 of phone login: confirm the SMS code."""
    user_id = current_user["id"]
    _require_no_active_session(user_id)

    pending = _pending_phone_logins.get(user_id)
    if pending is None or pending.expires_at < time.monotonic():
        _pending_phone_logins.pop(user_id, None)
        raise HTTPException(400, "O código expirou ou não foi solicitado. Peça um novo código.")
    if req.phone_number != pending.phone_number:
        raise HTTPException(400, "Esse número não é o que recebeu o código. Peça um novo código.")
    if pending.attempts >= MAX_OTP_ATTEMPTS:
        _pending_phone_logins.pop(user_id, None)
        raise HTTPException(400, "Número de tentativas excedido. Peça um novo código.")
    # Reserved before the network call below (not after), so two concurrent
    # verify requests can't both read "attempts < MAX" before either writes.
    pending.attempts += 1

    client = _client(conn, user_id, device_id=pending.device_id)
    try:
        await client.verify_phone_code(pending.verification_id, pending.phone_number, req.code)
        profile = await client.own_profile()
    except SuperLiveError as exc:
        raise _superlive_http_error(exc, "a confirmação do código", login=True) from None

    _pending_phone_logins.pop(user_id, None)
    _save_robot_account(conn, user_id, client, profile, "phone")
    db.log_activity(user_id, "robot_connected", "modo: phone")
    return _robot_payload(conn, user_id)


@app.post("/robot/connect/email-code/send")
async def robot_connect_email_code_send(
    req: RobotEmailCodeSendRequest, current_user: dict = Depends(get_current_user),
    conn: sqlite3.Connection = Depends(get_db),
):
    """Step 1 of e-mail-code login - for a robot account whose e-mail has no
    password set (SuperLive mails a one-time code instead); see
    SuperLiveClient.send_email_otp_code."""
    user_id = current_user["id"]
    _require_no_active_session(user_id)
    _check_code_send_allowed(user_id, CODE_SEND_MIN_GAP_SECONDS)

    client = _robot_device_client(conn, user_id)
    try:
        if not client.device_id:
            await client.register_device()
        otp_code_id = await client.send_email_otp_code(req.email, force_new=req.resend)
    except SuperLiveError as exc:
        raise _superlive_http_error(exc, "o envio do código por e-mail", login=True) from None
    _record_code_send(user_id)

    previous_attempts = _pending_email_logins.get(user_id)
    _pending_email_logins[user_id] = _PendingEmailLogin(
        device_id=client.device_id,
        email=req.email,
        otp_code_id=otp_code_id,
        expires_at=time.monotonic() + EMAIL_CODE_TTL_SECONDS,
        attempts=previous_attempts.attempts if previous_attempts else 0,
    )
    return {"ok": True}


@app.post("/robot/connect/email-code/verify")
async def robot_connect_email_code_verify(
    req: RobotEmailCodeVerifyRequest, current_user: dict = Depends(get_current_user),
    conn: sqlite3.Connection = Depends(get_db),
):
    """Step 2 of e-mail-code login: confirm the code."""
    user_id = current_user["id"]
    _require_no_active_session(user_id)

    pending = _pending_email_logins.get(user_id)
    if pending is None or pending.expires_at < time.monotonic():
        _pending_email_logins.pop(user_id, None)
        raise HTTPException(400, "O código expirou ou não foi solicitado. Peça um novo código.")
    if req.email != pending.email:
        raise HTTPException(400, "Esse e-mail não é o que recebeu o código. Peça um novo código.")
    if pending.attempts >= MAX_OTP_ATTEMPTS:
        _pending_email_logins.pop(user_id, None)
        raise HTTPException(400, "Número de tentativas excedido. Peça um novo código.")
    pending.attempts += 1

    client = _client(conn, user_id, device_id=pending.device_id)
    try:
        await client.verify_email_otp_code(pending.otp_code_id, req.code)
        profile = await client.own_profile()
    except SuperLiveError as exc:
        raise _superlive_http_error(exc, "a confirmação do código", login=True) from None

    _pending_email_logins.pop(user_id, None)
    _save_robot_account(conn, user_id, client, profile, "email_code")
    db.log_activity(user_id, "robot_connected", "modo: email_code")
    return _robot_payload(conn, user_id)


@app.post("/robot/disconnect")
async def robot_disconnect(current_user: dict = Depends(get_current_user),
                           conn: sqlite3.Connection = Depends(get_db)):
    user_id = current_user["id"]
    await watchers.stop(user_id)
    await sessions.stop(user_id)
    _pending_phone_logins.pop(user_id, None)
    _pending_email_logins.pop(user_id, None)
    # The token is only needed for the best-effort logout below; removing the
    # robot must work even when the encryption key is unavailable.
    robot = db.get_robot(conn, user_id, with_token=False)
    # Only end the SuperLive session if we created it (password/phone/email-code
    # login). A pasted token belongs to a session the user may still be using
    # elsewhere.
    if robot is not None and robot["auth_mode"] in ("password", "phone", "email_code"):
        try:
            token = db.get_robot(conn, user_id)["token"]
            await _client(conn, user_id, token, robot["device_id"]).logout()
        except (SuperLiveError, security.RobotKeyUnavailable):
            pass
    conn.execute("DELETE FROM robot_accounts WHERE user_id = ?", (user_id,))
    conn.commit()
    if robot is not None:
        db.log_activity(user_id, "robot_disconnected")
    return _robot_payload(conn, user_id)


@app.get("/robot/watch")
def robot_watch_status(current_user: dict = Depends(get_current_user),
                       conn: sqlite3.Connection = Depends(get_db)):
    return _watch_payload(conn, current_user["id"])


@app.put("/robot/watch")
async def robot_watch_set(req: RobotWatchRequest, current_user: dict = Depends(get_current_user),
                          conn: sqlite3.Connection = Depends(get_db)):
    """Favourite a streamer so the robot auto-joins her next live by itself.

    Resolves ``shared_id`` right away (same lookup as /robot/lookup_streamer) both
    to validate it and to grab her nickname/avatar for display, and - if she
    happens to already be live - starts moderating immediately instead of
    waiting for the first background poll.
    """
    user_id = current_user["id"]
    robot = db.get_robot(conn, user_id)
    if robot is None:
        raise HTTPException(400, "Conecte a conta do robô primeiro.")

    client = _client(conn, user_id, robot["token"], robot["device_id"])
    try:
        found = await client.find_live_by_shared_id(req.shared_id)
    except SuperLiveError as exc:
        raise _superlive_http_error(exc, "a busca pelo ID da streamer") from None

    db.set_watch(conn, user_id, req.shared_id, found.get("nickname"), found.get("avatar"), req.active)
    db.log_activity(
        user_id, "watch_updated",
        f'{found.get("nickname") or req.shared_id}: {"ativo" if req.active else "inativo"}',
    )

    if req.active:
        watchers.start(user_id)
        session = sessions.get(user_id)
        if found.get("live") and found.get("livestream_id"):
            found_live_id = str(found["livestream_id"])
            if session is None or not session.is_active:
                try:
                    await sessions.start(user_id, client, robot["sl_user_id"], found_live_id,
                                         ws_url_override=os.getenv("SUPERLIVE_WS_URL") or None)
                    conn.execute("UPDATE robot_accounts SET last_livestream_id = ? WHERE user_id = ?",
                                 (found_live_id, user_id))
                    conn.commit()
                except (RuntimeError, SuperLiveError):
                    pass  # the background watcher will retry
            elif session.livestream_id != found_live_id:
                try:
                    await session.switch_livestream(found_live_id)
                except Exception:
                    pass
    else:
        await watchers.stop(user_id)

    return _watch_payload(conn, user_id)


_last_watch_ping: dict = {}  # user_id -> monotonic time of the last accepted ping
WATCH_PING_MIN_GAP_SECONDS = int(os.getenv("SM_WATCH_PING_MIN_GAP", "30"))


@app.post("/robot/watch/ping")
async def robot_watch_ping(current_user: dict = Depends(get_current_user)):
    """"I just went live": the favourite-streamer watcher checks her right now
    instead of waiting for its next scheduled poll (which, with hundreds of
    creators on one IP, can be minutes). One accepted ping per creator per 30 s."""
    user_id = current_user["id"]
    now = time.monotonic()
    last = _last_watch_ping.get(user_id)
    if last is not None and now - last < WATCH_PING_MIN_GAP_SECONDS:
        raise HTTPException(
            429, f"Aguarde {int(WATCH_PING_MIN_GAP_SECONDS - (now - last)) + 1}s para chamar de novo.")
    if not watchers.ping(user_id):
        raise HTTPException(400, "Ligue a streamer favorita primeiro para o robô poder entrar sozinho.")
    _last_watch_ping[user_id] = now
    return {"queued": True}


@app.get("/robot/status")
def robot_status(current_user: dict = Depends(get_current_user),
                 conn: sqlite3.Connection = Depends(get_db)):
    return _robot_payload(conn, current_user["id"])


HEALTHBOT_API_KEY = os.getenv("HEALTHBOT_API_KEY", "").strip()
# Which portal user's robot the Telegram healthbot reports on. Optional: with
# it unset, the behaviour is unchanged from before this existed (one active
# watch picks itself, none falls back to user 1) - fine for the common case
# of a single active user. It only matters once more than one user has an
# active watch at the same time, which this endpoint now refuses to guess at
# (see robot_live_status) rather than silently handing out someone else's
# chat/activity to the bot.
_raw_healthbot_target = os.getenv("HEALTHBOT_TARGET_USER_ID", "").strip()
try:
    HEALTHBOT_TARGET_USER_ID = int(_raw_healthbot_target) if _raw_healthbot_target else None
except ValueError:
    print(f"[HEALTHBOT] HEALTHBOT_TARGET_USER_ID inválido ({_raw_healthbot_target!r}), ignorando")
    HEALTHBOT_TARGET_USER_ID = None


@app.get("/robot/live_status")
def robot_live_status(x_healthbot_key: str = Header(default=""),
                      conn: sqlite3.Connection = Depends(get_db)):
    """Summary of the active stream session and recent activity, for the
    Telegram bot's /live and /resumo commands - not a portal user, so it
    authenticates with a shared secret instead of a login token. Without
    HEALTHBOT_API_KEY set, this stays closed (never falls open)."""
    if not HEALTHBOT_API_KEY or not hmac.compare_digest(x_healthbot_key, HEALTHBOT_API_KEY):
        raise HTTPException(403, "Acesso negado")
    if HEALTHBOT_TARGET_USER_ID is not None:
        user_id = HEALTHBOT_TARGET_USER_ID
    else:
        watches = db.all_active_watches(conn)
        if len(watches) > 1:
            # More than one candidate and no explicit target: refuse rather
            # than hand one user's chat/activity to the bot by guessing.
            raise HTTPException(
                503,
                "Múltiplas usuárias com robô ativo - configure HEALTHBOT_TARGET_USER_ID.",
            )
        user_id = watches[0]["user_id"] if watches else 1
    payload = _robot_payload(conn, user_id)
    payload["recent_activities"] = db.list_activity(conn, user_id, limit=8)
    return payload


@app.get("/ops/active_sessions")
def ops_active_sessions(x_healthbot_key: str = Header(default="")):
    """How many moderation sessions are live in this process right now. Used by
    deploy/deploy.sh to refuse restarting the backend mid-show (a restart drops
    every session and its in-memory queue). Same shared secret and same
    never-open behaviour as /robot/live_status; carries no user data."""
    if not HEALTHBOT_API_KEY or not hmac.compare_digest(x_healthbot_key, HEALTHBOT_API_KEY):
        raise HTTPException(403, "Acesso negado")
    return {"active": sum(1 for sess in sessions.all_sessions().values() if sess.is_active)}


@app.post("/robot/lookup_streamer")
async def robot_lookup_streamer(
    req: RobotLookupStreamerRequest, current_user: dict = Depends(get_current_user),
    conn: sqlite3.Connection = Depends(get_db),
):
    """Resolve a creator's public profile id to her current livestream_id (if she's
    live right now). Not being live is a normal result, not an error."""
    user_id = current_user["id"]
    robot = db.get_robot(conn, user_id)
    if robot is None:
        raise HTTPException(400, "Conecte a conta do robô primeiro.")
    client = _client(conn, user_id, robot["token"], robot["device_id"])
    try:
        return await client.find_live_by_shared_id(req.shared_id)
    except SuperLiveError as exc:
        raise _superlive_http_error(exc, "a busca pelo ID da streamer") from None


@app.post("/robot/start")
async def robot_start(req: RobotStartRequest, current_user: dict = Depends(get_current_user),
                      conn: sqlite3.Connection = Depends(get_db)):
    user_id = current_user["id"]
    robot = db.get_robot(conn, user_id)
    if robot is None:
        raise HTTPException(400, "Conecte a conta do robô primeiro.")
    client = _client(conn, user_id, robot["token"], robot["device_id"])
    try:
        await sessions.start(user_id, client, robot["sl_user_id"], req.livestream_id,
                             ws_url_override=os.getenv("SUPERLIVE_WS_URL") or None)
    except RuntimeError as exc:
        raise HTTPException(409, str(exc)) from None
    except SuperLiveError as exc:
        raise _superlive_http_error(exc, "o acesso a essa live") from None
    conn.execute("UPDATE robot_accounts SET last_livestream_id = ? WHERE user_id = ?",
                 (req.livestream_id, user_id))
    conn.commit()
    db.log_activity(user_id, "session_started", f"live {req.livestream_id}")
    return _robot_payload(conn, user_id)


@app.post("/robot/stop")
async def robot_stop(current_user: dict = Depends(get_current_user),
                     conn: sqlite3.Connection = Depends(get_db)):
    user_id = current_user["id"]
    stopped = await sessions.stop(user_id)
    if stopped is not None:
        db.log_activity(user_id, "session_stopped")
    return _robot_payload(conn, user_id)


@app.get("/robot/log")
def robot_log(limit: int = 50, current_user: dict = Depends(get_current_user),
              conn: sqlite3.Connection = Depends(get_db)):
    limit = max(1, min(limit, 200))
    rows = conn.execute(
        "SELECT * FROM moderation_log WHERE user_id = ? ORDER BY id DESC LIMIT ?",
        (current_user["id"], limit),
    ).fetchall()
    return [row_to_dict(r) for r in rows]


# ─── Account activity (login, rule/message/settings/robot changes) ──────────
@app.get("/activity")
def list_activity(limit: int = 50, current_user: dict = Depends(get_current_user),
                  conn: sqlite3.Connection = Depends(get_db)):
    return db.list_activity(conn, current_user["id"], limit=max(1, min(limit, 200)))


# ─── Stats (moderation history, aggregated from moderation_log) ─────────────
@app.get("/stats")
def get_stats(user_id: int, days: int = 30, current_user: dict = Depends(get_current_user),
              conn: sqlite3.Connection = Depends(get_db)):
    require_owner(current_user, user_id)
    return db.get_stats(conn, user_id, days=max(1, min(days, 365)))


# ─── Admin (read-only oversight: users, robots, live sessions) ──────────────
# Its own login (admin_accounts/admin_sessions, see db.py) - deliberately NOT
# the portal's users/sessions with an is_admin flag. There is no public
# /admin/register; the first account is created from env vars at startup
# (see _bootstrap_admin_account), the same pattern HEALTHBOT_API_KEY already
# uses for a VPS-only secret never committed to git.
ADMIN_SESSION_DAYS = 7
ADMIN_BOOTSTRAP_USERNAME = os.getenv("ADMIN_BOOTSTRAP_USERNAME", "").strip()
ADMIN_BOOTSTRAP_PASSWORD = os.getenv("ADMIN_BOOTSTRAP_PASSWORD", "")
admin_throttle = security.LoginThrottle(ip_max_failures=LOGIN_IP_MAX_FAILURES)


def _bootstrap_admin_account(conn: sqlite3.Connection) -> None:
    """Creates the first admin_accounts row from env vars, if none exists yet -
    there is no public /admin/register. Idempotent: once ANY admin account
    exists, this is a no-op forever, even with the env vars still set (so
    they can stay in .env without recreating/overwriting on every restart -
    change the password from inside the panel instead, once that exists)."""
    if not ADMIN_BOOTSTRAP_USERNAME or not ADMIN_BOOTSTRAP_PASSWORD:
        return
    if conn.execute("SELECT 1 FROM admin_accounts LIMIT 1").fetchone():
        return
    conn.execute(
        "INSERT INTO admin_accounts (username, password_hash, display_name) VALUES (?, ?, ?)",
        (ADMIN_BOOTSTRAP_USERNAME, security.hash_password(ADMIN_BOOTSTRAP_PASSWORD), "Administrador"),
    )
    conn.commit()
    print(f"[ADMIN] Conta administrativa inicial criada: {ADMIN_BOOTSTRAP_USERNAME}")


class AdminLoginRequest(BaseModel):
    username: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=1, max_length=200)


def get_current_admin(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer),
    conn: sqlite3.Connection = Depends(get_db),
) -> dict:
    """Separate from get_current_user/require_owner/get_owned entirely - those
    are the portal's own auth; this checks admin_sessions, a completely
    different token namespace. A portal session token is never valid here,
    and vice versa."""
    if credentials is None:
        raise HTTPException(401, "Token ausente")
    row = conn.execute(
        "SELECT a.* FROM admin_accounts a JOIN admin_sessions s ON s.admin_id = a.id "
        "WHERE s.token_hash = ? AND s.expires_at > datetime('now')",
        (security.hash_token(credentials.credentials),),
    ).fetchone()
    if not row:
        raise HTTPException(401, "Token inválido ou sessão expirada")
    return row_to_dict(row)


@app.post("/admin/login")
def admin_login(req: AdminLoginRequest, request: Request, conn: sqlite3.Connection = Depends(get_db)):
    ip = request.client.host if request.client else "unknown"
    user_key, ip_key = f"admin:{req.username.lower()}", f"ip:{ip}"
    if admin_throttle.is_blocked(user_key, ip_key):
        raise HTTPException(429, "Muitas tentativas de login. Aguarde alguns minutos.")

    row = conn.execute(
        "SELECT * FROM admin_accounts WHERE lower(username) = lower(?)", (req.username,)
    ).fetchone()
    if row is None:
        security.burn_password_check(req.password)
        valid, needs_rehash = False, False
    else:
        valid, needs_rehash = security.verify_password(req.password, row["password_hash"])
    if not valid:
        admin_throttle.record_failure(user_key, ip_key)
        raise HTTPException(401, "Credenciais inválidas")

    admin_throttle.reset(user_key)
    if needs_rehash:
        conn.execute("UPDATE admin_accounts SET password_hash = ? WHERE id = ?",
                     (security.hash_password(req.password), row["id"]))
        conn.commit()
    token = security.generate_token()
    hashed = security.hash_token(token)
    conn.execute(
        "INSERT INTO admin_sessions (admin_id, token, token_hash, expires_at) "
        "VALUES (?, ?, ?, datetime('now', ?))",
        (row["id"], hashed, hashed, f"+{ADMIN_SESSION_DAYS} days"),
    )
    conn.commit()
    return {
        "access_token": token,
        "admin": {"id": row["id"], "username": row["username"], "display_name": row["display_name"]},
    }


@app.post("/admin/logout")
def admin_logout(
    admin: dict = Depends(get_current_admin),
    credentials: HTTPAuthorizationCredentials = Depends(bearer),
    conn: sqlite3.Connection = Depends(get_db),
):
    conn.execute("DELETE FROM admin_sessions WHERE token_hash = ?", (security.hash_token(credentials.credentials),))
    conn.commit()
    return {"success": True}


def _robot_admin_status(robot, session) -> str:
    if robot is None:
        return "não configurado"
    if session is None:
        return "conectado (parado)"
    if session.state == "error":
        return "erro"
    if session.state in ("starting", "waiting_for_live"):
        return "aguardando"
    if session.state == "running":
        return "ativo"
    return "conectado (parado)"


@app.get("/admin/users")
def admin_list_users(admin: dict = Depends(get_current_admin), conn: sqlite3.Connection = Depends(get_db)):
    """One row per portal user: account info + robot/session/rule counts.
    Never includes password_hash, robot token or device_id - same "secrets
    never leave the server" rule as every other endpoint, just also enforced
    here for an admin looking at OTHER people's accounts.

    A handful of bulk queries instead of four per user: with hundreds of
    creators the old per-user loop meant thousands of queries per refresh."""
    users = conn.execute(
        "SELECT u.*, a.name AS agency_name FROM users u "
        "LEFT JOIN agencies a ON a.id = u.agency_id ORDER BY u.id ASC").fetchall()
    robots = {r["user_id"]: r for r in conn.execute(
        "SELECT user_id, nickname, auth_mode FROM robot_accounts")}
    watches = {r["user_id"]: r for r in conn.execute(
        "SELECT user_id, active, nickname FROM streamer_watch")}
    rule_counts = {r["user_id"]: r["n"] for r in conn.execute(
        "SELECT user_id, COUNT(*) AS n FROM moderation_rules GROUP BY user_id")}
    message_counts = {r["user_id"]: r["n"] for r in conn.execute(
        "SELECT user_id, COUNT(*) AS n FROM auto_messages GROUP BY user_id")}
    result = []
    for row in users:
        u = row_to_dict(row)
        uid = u["id"]
        robot = robots.get(uid)
        session = sessions.get(uid)
        watch = watches.get(uid)
        result.append({
            "id": uid,
            "username": u["username"],
            "email": u["email"],
            "display_name": u["display_name"],
            "is_admin": bool(u["is_admin"]),
            "created_at": u["created_at"],
            "agency_id": u["agency_id"],
            "agency_name": u["agency_name"],
            "egress_slot": u["egress_slot"],
            "robot": None if robot is None else {
                "nickname": robot["nickname"],
                "auth_mode": robot["auth_mode"],
            },
            "robot_status": _robot_admin_status(robot, session),
            "session_state": session.state if session else None,
            "session_livestream_id": session.livestream_id if session else None,
            "watch_active": bool(watch and watch["active"]),
            "watch_nickname": watch["nickname"] if watch else None,
            "rules_count": rule_counts.get(uid, 0),
            "messages_count": message_counts.get(uid, 0),
        })
    return result


class AdminAgencyCreate(BaseModel):
    name: str = Field(min_length=2, max_length=80)

    @field_validator("name")
    @classmethod
    def _name(cls, v: str) -> str:
        v = " ".join(v.split())
        if len(v) < 2:
            raise ValueError("nome muito curto")
        return v


class AdminAgencyActive(BaseModel):
    active: bool


@app.post("/admin/agencies")
def admin_create_agency(req: AdminAgencyCreate, admin: dict = Depends(get_current_admin),
                        conn: sqlite3.Connection = Depends(get_db)):
    """Creates an agency and returns its signup code. The code is generated
    here (random, unguessable), never chosen by the admin."""
    agency = db.create_agency(conn, req.name)
    logging.getLogger("super_moderator.main").info(
        "admin %s created agency %s", admin.get("username"), agency["id"])
    return agency


@app.get("/admin/agencies")
def admin_list_agencies(admin: dict = Depends(get_current_admin),
                        conn: sqlite3.Connection = Depends(get_db)):
    """Per agency: creators registered, with a robot connected, with the live
    watch on, and with a moderation session running right now. Creators who
    signed up before agencies existed are counted under ``no_agency``."""
    running_by_user = {uid for uid, s in sessions.all_sessions().items() if s.state == "running"}
    agency_of = {r["id"]: r["agency_id"] for r in conn.execute("SELECT id, agency_id FROM users")}
    running = {}
    for uid in running_by_user:
        key = agency_of.get(uid)
        running[key] = running.get(key, 0) + 1

    agencies = db.list_agencies_with_counts(conn)
    for a in agencies:
        a["running_now"] = running.get(a["id"], 0)
    legacy = conn.execute("""
        SELECT COUNT(u.id) AS users_total,
               COALESCE(SUM(CASE WHEN r.user_id IS NOT NULL THEN 1 ELSE 0 END), 0) AS with_robot,
               COALESCE(SUM(CASE WHEN w.active = 1 THEN 1 ELSE 0 END), 0) AS watching
        FROM users u
        LEFT JOIN robot_accounts r ON r.user_id = u.id
        LEFT JOIN streamer_watch w ON w.user_id = u.id
        WHERE u.agency_id IS NULL
    """).fetchone()
    no_agency = dict(legacy)
    no_agency["running_now"] = running.get(None, 0)
    return {"agencies": agencies, "no_agency": no_agency}


@app.post("/admin/agencies/{agency_id}/active")
def admin_set_agency_active(agency_id: int, req: AdminAgencyActive,
                            admin: dict = Depends(get_current_admin),
                            conn: sqlite3.Connection = Depends(get_db)):
    """Switch an agency's code on/off for NEW signups. Creators already
    registered under it are untouched."""
    if db.get_agency(conn, agency_id) is None:
        raise HTTPException(404, "Agência não encontrada")
    conn.execute("UPDATE agencies SET active = ? WHERE id = ?", (1 if req.active else 0, agency_id))
    conn.commit()
    return {"success": True}


@app.post("/admin/agencies/{agency_id}/rotate_code")
def admin_rotate_agency_code(agency_id: int, admin: dict = Depends(get_current_admin),
                             conn: sqlite3.Connection = Depends(get_db)):
    """New code for an agency whose code leaked. The old one stops working for
    signups at once; creators already registered are untouched."""
    agency = db.get_agency(conn, agency_id)
    if agency is None:
        raise HTTPException(404, "Agência não encontrada")
    for _ in range(10):
        code = "".join(secrets.choice(db.CODE_ALPHABET) for _ in range(db.CODE_LENGTH))
        try:
            conn.execute("UPDATE agencies SET code = ? WHERE id = ?", (code, agency_id))
            conn.commit()
            break
        except sqlite3.IntegrityError:
            conn.rollback()
    else:
        raise HTTPException(500, "Não foi possível gerar um novo código")
    return {"code": db.format_agency_code(code)}


@app.get("/admin/capacity")
def admin_capacity(admin: dict = Depends(get_current_admin), conn: sqlite3.Connection = Depends(get_db)):
    """Is the SuperLive egress keeping up? Per egress slot: creators pinned to
    it, watches on, requests waiting in its queue, and the poll interval the
    watcher is currently using. A queue that stays long means that egress needs
    more IPs (SUPERLIVE_PROXY_URLS) or fewer creators."""
    pool = get_proxy_pool()
    depths = queue_depths()
    per_slot = []
    for slot, proxy in enumerate(pool):
        users_n = conn.execute(
            "SELECT COUNT(*) AS n FROM users WHERE egress_slot = ?", (slot,)).fetchone()["n"]
        watch_n = conn.execute(
            "SELECT COUNT(*) AS n FROM streamer_watch w JOIN users u ON u.id = w.user_id "
            "WHERE w.active = 1 AND u.egress_slot = ?", (slot,)).fetchone()["n"]
        per_slot.append({
            "slot": slot,
            "users": users_n,
            "watches": watch_n,
            "queue_depth": depths.get(proxy, 0),
            "poll_interval_seconds": round(watch_poll_interval(watch_n)),
        })
    active = sum(1 for s in sessions.all_sessions().values() if s.is_active)
    return {
        "egress_count": len(pool),
        "slots": per_slot,
        "unassigned_users": conn.execute(
            "SELECT COUNT(*) AS n FROM users WHERE egress_slot IS NULL").fetchone()["n"],
        "active_sessions": active,
        "max_sessions": int(os.getenv("SM_MAX_SESSIONS", "0") or 0),
        # about 25 live sessions per egress IP is what its request budget sustains
        "suggested_max_sessions": 25 * len(pool),
    }


@app.get("/admin/sessions")
def admin_list_sessions(admin: dict = Depends(get_current_admin), conn: sqlite3.Connection = Depends(get_db)):
    """Every bot session currently held in memory, across every user, for
    monitoring - which lives are being moderated right now and the state of
    each connection. Read-only: no chat content, just state/counters."""
    all_sess = sessions.all_sessions()
    usernames: dict[int, str] = {}
    if all_sess:
        placeholders = ",".join("?" * len(all_sess))
        rows = conn.execute(
            f"SELECT id, username FROM users WHERE id IN ({placeholders})",
            tuple(all_sess.keys()),
        ).fetchall()
        usernames = {r["id"]: r["username"] for r in rows}

    order = {"running": 0, "starting": 1, "waiting_for_live": 2, "stopping": 3, "stopped": 4, "error": 5}
    result = []
    for uid, session in all_sess.items():
        snap = session.snapshot()
        result.append({
            "user_id": uid,
            "username": usernames.get(uid, f"usuário #{uid}"),
            "state": snap["state"],
            "ws_state": snap["ws_state"],
            "livestream_id": snap["livestream_id"],
            "started_at": snap["started_at"],
            "stop_reason": snap["stop_reason"],
            "watch_waiting_seconds": snap["watch_waiting_seconds"],
            "last_error": snap["last_error"],
            "counters": snap["counters"],
        })
    result.sort(key=lambda s: order.get(s["state"], 9))
    return result


# ─── Health check ────────────────────────────────────────────────────────────
@app.get("/health")
def health():
    return {"status": "ok", "service": "Atila's Client API", "version": app.version}


if __name__ == "__main__":
    import uvicorn

    host = os.getenv("SM_HOST", "127.0.0.1")  # localhost only; this API controls a bot
    port = int(os.getenv("SM_PORT", "8000"))
    # Real client IP behind the nginx chain: uvicorn only honours X-Forwarded-For
    # from these peers and takes the right-most address that is NOT one of them.
    # Default is loopback only (= ignore the header). In Docker set it to the
    # web container's pinned IP plus the shared reverse proxy's, never "*" or a
    # whole subnet: any listed peer can vouch for an address.
    trusted = os.getenv("FORWARDED_ALLOW_IPS", "127.0.0.1")
    if os.getenv("SM_RELOAD") == "1":
        # auto-reload restarts the process (and any running live session) on every file save
        uvicorn.run("main:app", host=host, port=port, reload=True,
                    proxy_headers=True, forwarded_allow_ips=trusted)
    else:
        uvicorn.run(app, host=host, port=port, proxy_headers=True, forwarded_allow_ips=trusted)
