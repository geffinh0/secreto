import logging
import os
import re
import sqlite3
import time
import uuid
from contextlib import asynccontextmanager
from dataclasses import dataclass
from typing import Literal, Optional

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field, field_validator

import db
import security
from db import row_to_dict
from engine import IDLE_SNAPSHOT, MIN_INTERVAL_SECONDS, SessionManager, WatchManager, normalize
from superlive import SuperLiveClient, SuperLiveError

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

sessions = SessionManager()
watchers = WatchManager(sessions)
throttle = security.LoginThrottle()

USERNAME_RE = re.compile(r"^[A-Za-z0-9_.-]{3,32}$")
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
LIVESTREAM_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
PHONE_RE = re.compile(r"^\+[1-9]\d{7,14}$")  # E.164: '+', country code, 8-15 digits total

# Phone login is two steps (send SMS code, then verify it) with a real SMS in between,
# so the pending attempt is held here between the two calls. In-memory only: a backend
# restart simply makes the user ask for a new code.
PHONE_CODE_TTL_SECONDS = 600


@dataclass
class _PendingPhoneLogin:
    device_id: str
    phone_number: str
    verification_id: str
    expires_at: float


_pending_phone_logins: dict[int, _PendingPhoneLogin] = {}


# ─── App setup ───────────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(_app: FastAPI):
    db.init_db()
    conn = db.connect()
    try:
        for watch in db.all_active_watches(conn):
            watchers.start(watch["user_id"])
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
        "WHERE s.token = ? AND s.expires_at > datetime('now')",
        (credentials.credentials,),
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
    conn.execute(
        "INSERT INTO sessions (user_id, token, expires_at) VALUES (?, ?, datetime('now', ?))",
        (user_id, token, f"+{db.SESSION_DAYS} days"),
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
def register(req: RegisterRequest, conn: sqlite3.Connection = Depends(get_db)):
    existing = conn.execute(
        "SELECT id FROM users WHERE lower(username) = lower(?) OR lower(email) = lower(?)",
        (req.username, req.email),
    ).fetchone()
    if existing:
        raise HTTPException(400, "Usuário ou e-mail já cadastrado")

    try:
        cursor = conn.execute(
            "INSERT INTO users (username, email, display_name, password_hash) VALUES (?, ?, ?, ?)",
            (req.username, req.email, req.display_name or req.username,
             security.hash_password(req.password)),
        )
        conn.commit()
    except sqlite3.IntegrityError:
        raise HTTPException(400, "Usuário ou e-mail já cadastrado") from None
    user_id = cursor.lastrowid
    db.get_settings(conn, user_id)  # creates the default settings row

    token = create_session(conn, user_id)
    user = public_user(conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone())
    db.log_activity(user_id, "account_created", f"usuário {req.username}")
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
        conn.execute("DELETE FROM sessions WHERE token = ?", (credentials.credentials,))
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
    robot = db.get_robot(conn, user_id)
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
    conn.execute(
        "INSERT INTO robot_accounts (user_id, sl_user_id, nickname, avatar, token, device_id, auth_mode) "
        "VALUES (?, ?, ?, ?, ?, ?, ?) "
        "ON CONFLICT(user_id) DO UPDATE SET sl_user_id = excluded.sl_user_id, "
        "nickname = excluded.nickname, avatar = excluded.avatar, token = excluded.token, "
        "device_id = excluded.device_id, auth_mode = excluded.auth_mode",
        (
            user_id,
            str(profile.get("id") or profile.get("user_id") or "") or None,
            profile.get("nickname") or profile.get("name") or profile.get("username")
            or "Atila's Client",
            profile.get("avatar") or profile.get("profile_picture") or profile.get("picture_url"),
            client.token, client.device_id, mode,
        ),
    )
    conn.commit()


def _require_no_active_session(user_id: int) -> None:
    session = sessions.get(user_id)
    if session is not None and session.is_active:
        raise HTTPException(409, "Pare a sessão do robô antes de trocar a conta.")


def _robot_device_client(conn, user_id: int) -> SuperLiveClient:
    """A client reusing the robot's already-registered device id, if any."""
    existing = db.get_robot(conn, user_id)
    return SuperLiveClient(device_id=existing["device_id"] if existing else None)


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

    client = _robot_device_client(conn, user_id)
    try:
        if not client.device_id:
            await client.register_device()
        result = await client.send_phone_code(req.phone_number, is_retry=req.resend)
    except SuperLiveError as exc:
        raise _superlive_http_error(exc, "o envio do código por SMS", login=True) from None

    _pending_phone_logins[user_id] = _PendingPhoneLogin(
        device_id=client.device_id,
        phone_number=req.phone_number,
        verification_id=result["verification_id"],
        expires_at=time.monotonic() + PHONE_CODE_TTL_SECONDS,
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

    client = SuperLiveClient(device_id=pending.device_id)
    try:
        await client.verify_phone_code(pending.verification_id, pending.phone_number, req.code)
        profile = await client.own_profile()
    except SuperLiveError as exc:
        raise _superlive_http_error(exc, "a confirmação do código", login=True) from None

    _pending_phone_logins.pop(user_id, None)
    _save_robot_account(conn, user_id, client, profile, "phone")
    db.log_activity(user_id, "robot_connected", "modo: phone")
    return _robot_payload(conn, user_id)


@app.post("/robot/disconnect")
async def robot_disconnect(current_user: dict = Depends(get_current_user),
                           conn: sqlite3.Connection = Depends(get_db)):
    user_id = current_user["id"]
    await sessions.stop(user_id)
    await watchers.stop(user_id)
    _pending_phone_logins.pop(user_id, None)
    robot = db.get_robot(conn, user_id)
    # Only end the SuperLive session if we created it (password/phone login). A pasted
    # token belongs to a session the user may still be using elsewhere.
    if robot is not None and robot["auth_mode"] in ("password", "phone"):
        try:
            await SuperLiveClient(robot["token"], robot["device_id"]).logout()
        except SuperLiveError:
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

    client = SuperLiveClient(robot["token"], robot["device_id"])
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
        if (session is None or not session.is_active) and found.get("live") and found.get("livestream_id"):
            try:
                await sessions.start(user_id, client, robot["sl_user_id"], str(found["livestream_id"]),
                                     ws_url_override=os.getenv("SUPERLIVE_WS_URL") or None)
            except (RuntimeError, SuperLiveError):
                pass  # the background watcher will retry
    else:
        await watchers.stop(user_id)

    return _watch_payload(conn, user_id)


@app.get("/robot/status")
def robot_status(current_user: dict = Depends(get_current_user),
                 conn: sqlite3.Connection = Depends(get_db)):
    return _robot_payload(conn, current_user["id"])


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
    client = SuperLiveClient(robot["token"], robot["device_id"])
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
    client = SuperLiveClient(robot["token"], robot["device_id"])
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


# ─── Health check ────────────────────────────────────────────────────────────
@app.get("/health")
def health():
    return {"status": "ok", "service": "Atila's Client API", "version": app.version}


if __name__ == "__main__":
    import uvicorn

    host = os.getenv("SM_HOST", "127.0.0.1")  # localhost only; this API controls a bot
    port = int(os.getenv("SM_PORT", "8000"))
    if os.getenv("SM_RELOAD") == "1":
        # auto-reload restarts the process (and any running live session) on every file save
        uvicorn.run("main:app", host=host, port=port, reload=True)
    else:
        uvicorn.run(app, host=host, port=port)
