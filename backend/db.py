"""SQLite access + schema/migrations for the Atila's Client backend."""
import logging
import os
import secrets
import sqlite3

import security

log = logging.getLogger("super_moderator.db")

DB_PATH = os.getenv("SM_DB_PATH") or os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "super_moderator.db"
)

SESSION_DAYS = 30
MAX_LOG_ROWS = 2000  # per portal user

DEFAULT_SETTINGS = {
    "auto_messages_enabled": False,
    "message_interval_seconds": 120,
    "moderation_enabled": True,
    "kick_permanent": False,
    "diamond_immunity_enabled": False,
    "diamond_immunity_threshold": 50,
}

MIN_DIAMOND_IMMUNITY_THRESHOLD = 50

_BOOL_KEYS = (
    "is_active", "is_admin", "auto_messages_enabled",
    "moderation_enabled", "kick_permanent", "diamond_immunity_enabled", "ok", "active",
)

# bot_settings columns exposed via the API. end_message_enabled/end_message_template
# still exist in older databases (discontinued; see init_db) but are never read back -
# same deal with ai_name_filter_mode now (discontinued AI name filter feature).
_SETTINGS_COLUMNS = (
    "id, user_id, auto_messages_enabled, message_interval_seconds, "
    "moderation_enabled, kick_permanent, diamond_immunity_enabled, diamond_immunity_threshold"
)


def shared_robot_allowed() -> bool:
    """SM_ALLOW_SHARED_ROBOT=1 lets several portal users connect the SAME
    SuperLive account (off by default: they would fight over one token)."""
    return os.getenv("SM_ALLOW_SHARED_ROBOT", "0") == "1"


def connect() -> sqlite3.Connection:
    # FastAPI resolves the `get_db` dependency in a worker thread but runs `async def`
    # routes on the event-loop thread. Each connection is used by one request at a
    # time (never shared), so lifting the same-thread check is safe.
    conn = sqlite3.connect(DB_PATH, timeout=10, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def row_to_dict(row):
    """sqlite3.Row -> dict, with 0/1 integer flags turned into real booleans."""
    if row is None:
        return None
    d = dict(row)
    for key in _BOOL_KEYS:
        if key in d and d[key] is not None:
            d[key] = bool(d[key])
    return d


def _columns(conn, table):
    return {r["name"] for r in conn.execute(f"PRAGMA table_info({table})")}


def init_db():
    """Create tables and apply additive migrations (safe to run on an existing DB)."""
    conn = connect()
    try:
        conn.execute("PRAGMA journal_mode = WAL")
        c = conn.cursor()

        c.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT UNIQUE NOT NULL,
                email TEXT UNIQUE NOT NULL,
                display_name TEXT,
                password_hash TEXT NOT NULL,
                is_admin INTEGER DEFAULT 0,
                created_at TEXT DEFAULT (datetime('now'))
            )
        """)
        c.execute("""
            CREATE TABLE IF NOT EXISTS sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                token TEXT UNIQUE NOT NULL,
                created_at TEXT DEFAULT (datetime('now')),
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )
        """)
        c.execute("""
            CREATE TABLE IF NOT EXISTS moderation_rules (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                keyword TEXT NOT NULL,
                action TEXT NOT NULL CHECK(action IN ('mute', 'kick')),
                is_active INTEGER DEFAULT 1,
                created_at TEXT DEFAULT (datetime('now')),
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )
        """)
        c.execute("""
            CREATE TABLE IF NOT EXISTS auto_messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                content TEXT NOT NULL,
                sort_order INTEGER DEFAULT 0,
                is_active INTEGER DEFAULT 1,
                created_at TEXT DEFAULT (datetime('now')),
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )
        """)
        # end_message_enabled/end_message_template used to exist here (the "end of
        # live" message, discontinued). New databases no longer get those columns;
        # older ones keep them on disk, unused - see _SETTINGS_COLUMNS below.
        c.execute("""
            CREATE TABLE IF NOT EXISTS bot_settings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER UNIQUE NOT NULL,
                auto_messages_enabled INTEGER DEFAULT 0,
                message_interval_seconds INTEGER DEFAULT 120,
                moderation_enabled INTEGER DEFAULT 1,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )
        """)
        # SuperLive robot account (one per portal user). Only the session token is
        # stored - never the robot's password.
        c.execute("""
            CREATE TABLE IF NOT EXISTS robot_accounts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER UNIQUE NOT NULL,
                sl_user_id TEXT,
                nickname TEXT,
                avatar TEXT,
                token TEXT NOT NULL,
                device_id TEXT NOT NULL,
                auth_mode TEXT NOT NULL DEFAULT 'password',
                created_at TEXT DEFAULT (datetime('now')),
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )
        """)
        # The streamer the user wants the robot to auto-join: remembered across
        # restarts, so when `active` is on the backend watches her profile and
        # starts moderating the moment she goes live, with no manual step.
        c.execute("""
            CREATE TABLE IF NOT EXISTS streamer_watch (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER UNIQUE NOT NULL,
                shared_id TEXT NOT NULL,
                nickname TEXT,
                avatar TEXT,
                active INTEGER NOT NULL DEFAULT 0,
                updated_at TEXT DEFAULT (datetime('now')),
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )
        """)
        # Audit trail of every automatic moderation action.
        c.execute("""
            CREATE TABLE IF NOT EXISTS moderation_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                livestream_id TEXT,
                target_user_id TEXT,
                target_name TEXT,
                action TEXT NOT NULL,
                keyword TEXT,
                message_text TEXT,
                ok INTEGER NOT NULL DEFAULT 1,
                detail TEXT,
                created_at TEXT DEFAULT (datetime('now')),
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )
        """)
        c.execute(
            "CREATE INDEX IF NOT EXISTS idx_modlog_user ON moderation_log(user_id, id DESC)"
        )
        # Account-level activity trail (login, rule/message/settings changes, robot
        # connect/disconnect, session start/stop) - separate from moderation_log,
        # which only covers automatic mute/kick actions against chat users.
        c.execute("""
            CREATE TABLE IF NOT EXISTS user_activity_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                action TEXT NOT NULL,
                detail TEXT,
                created_at TEXT DEFAULT (datetime('now')),
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )
        """)
        c.execute(
            "CREATE INDEX IF NOT EXISTS idx_activity_user ON user_activity_log(user_id, id DESC)"
        )

        # Admin panel login: its own accounts/sessions tables, deliberately separate
        # from users/sessions. The admin panel must work from its own
        # username+password, never from a portal user's is_admin flag - so there
        # is no foreign key to users here on purpose, and no public way to create
        # a row here (see main.py's startup bootstrap, env-var gated like
        # HEALTHBOT_API_KEY already is).
        c.execute("""
            CREATE TABLE IF NOT EXISTS admin_accounts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                display_name TEXT,
                created_at TEXT DEFAULT (datetime('now'))
            )
        """)
        c.execute("""
            CREATE TABLE IF NOT EXISTS admin_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                admin_id INTEGER NOT NULL,
                token TEXT UNIQUE NOT NULL,
                expires_at TEXT NOT NULL,
                created_at TEXT DEFAULT (datetime('now')),
                FOREIGN KEY (admin_id) REFERENCES admin_accounts(id) ON DELETE CASCADE
            )
        """)

        # Agencies: each new portal user signs up with one agency's code, so the
        # admin can see how many creators every agency has (and how many are
        # actually running a robot). `code` is the only secret: random, 8 chars.
        # egress IPs added from the admin panel; the URL (it carries the proxy password) is
        # stored encrypted with the same key as the robot tokens. Never deleted: a user's slot
        # number is her position in the pool.
        c.execute("""
            CREATE TABLE IF NOT EXISTS egress_proxies (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                url_enc TEXT NOT NULL,
                created_at TEXT DEFAULT (datetime('now'))
            )
        """)
        c.execute("""
            CREATE TABLE IF NOT EXISTS agencies (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                code TEXT UNIQUE NOT NULL,
                active INTEGER NOT NULL DEFAULT 1,
                created_at TEXT DEFAULT (datetime('now'))
            )
        """)

        # ---- additive migrations for databases created by older versions ----
        if "agency_id" not in _columns(conn, "users"):
            c.execute("ALTER TABLE users ADD COLUMN agency_id INTEGER REFERENCES agencies(id)")
        c.execute("CREATE INDEX IF NOT EXISTS idx_users_agency ON users(agency_id)")
        # Admin-released password reset: the admin hands the user a one-time temporary
        # password; she must replace it before using anything else (see main.py).
        if "must_change_password" not in _columns(conn, "users"):
            c.execute("ALTER TABLE users ADD COLUMN must_change_password INTEGER NOT NULL DEFAULT 0")
        if "temp_password_expires_at" not in _columns(conn, "users"):
            c.execute("ALTER TABLE users ADD COLUMN temp_password_expires_at TEXT")
        if "temp_password_used" not in _columns(conn, "users"):
            c.execute("ALTER TABLE users ADD COLUMN temp_password_used INTEGER NOT NULL DEFAULT 0")
        # usernames are unique regardless of case ('Nyx' == 'nyx'). The old UNIQUE
        # constraint is case-sensitive and the app-level check races, so enforce it here.
        # If rows already collide the index is NOT created (nothing is deleted or renamed)
        # and the log says which names to fix.
        try:
            c.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username_nocase "
                      "ON users(lower(username))")
        except sqlite3.IntegrityError:
            dupes = [r[0] for r in c.execute(
                "SELECT lower(username) FROM users GROUP BY lower(username) HAVING COUNT(*) > 1")]
            log.error("users has usernames that differ only by case (%s); case-insensitive "
                      "unique index NOT created - rename them and restart", ", ".join(dupes))
        if "egress_slot" not in _columns(conn, "users"):
            c.execute("ALTER TABLE users ADD COLUMN egress_slot INTEGER")
            # Everyone who already has a robot connected got their token through the
            # one egress that existed then (slot 0): keep them on that IP.
        # every startup (idempotent): a crash between the ALTER and this UPDATE must
        # not leave a robot owner unassigned, or she'd be moved to another IP later
        c.execute("UPDATE users SET egress_slot = 0 WHERE egress_slot IS NULL "
                  "AND id IN (SELECT user_id FROM robot_accounts)")
        if shared_robot_allowed():
            c.execute("DROP INDEX IF EXISTS idx_robot_sl_user")
        else:
            try:
                # one SuperLive account = one portal user (two users driving the same
                # account would fight over its token and double-moderate)
                c.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_robot_sl_user "
                          "ON robot_accounts(sl_user_id) WHERE sl_user_id IS NOT NULL")
            except sqlite3.IntegrityError:
                log.warning("robot_accounts already has duplicate sl_user_id rows; "
                            "unique index NOT created - resolve the duplicates and restart")
        if "expires_at" not in _columns(conn, "sessions"):
            c.execute("ALTER TABLE sessions ADD COLUMN expires_at TEXT")
        c.execute(
            "UPDATE sessions SET expires_at = datetime(created_at, ?) WHERE expires_at IS NULL",
            (f"+{SESSION_DAYS} days",),
        )
        if "kick_permanent" not in _columns(conn, "bot_settings"):
            c.execute("ALTER TABLE bot_settings ADD COLUMN kick_permanent INTEGER DEFAULT 0")
        if "diamond_immunity_enabled" not in _columns(conn, "bot_settings"):
            c.execute(
                "ALTER TABLE bot_settings ADD COLUMN diamond_immunity_enabled INTEGER DEFAULT 0"
            )
        if "diamond_immunity_threshold" not in _columns(conn, "bot_settings"):
            c.execute(
                "ALTER TABLE bot_settings ADD COLUMN diamond_immunity_threshold "
                f"INTEGER DEFAULT {MIN_DIAMOND_IMMUNITY_THRESHOLD}"
            )
        if "last_livestream_id" not in _columns(conn, "robot_accounts"):
            c.execute("ALTER TABLE robot_accounts ADD COLUMN last_livestream_id TEXT")

        # Session tokens are stored hashed (security.hash_token) so a leaked DB or
        # backup holds nothing replayable. token_hash is the lookup column; the
        # legacy plaintext `token` column (UNIQUE NOT NULL) is overwritten with the
        # same hash so no clear token survives. Idempotent: only rows still lacking
        # a token_hash are touched, so existing sessions simply keep working.
        # (Rolling back to an older image therefore logs everyone out once.)
        # secure_delete: the clear tokens being replaced must not linger in freed
        # pages / the WAL (old backups taken before this upgrade still hold them).
        c.execute("PRAGMA secure_delete = ON")
        for table in ("sessions", "admin_sessions"):
            if "token_hash" not in _columns(conn, table):
                c.execute(f"ALTER TABLE {table} ADD COLUMN token_hash TEXT")  # table is a literal
            c.execute(f"CREATE UNIQUE INDEX IF NOT EXISTS idx_{table}_token_hash ON {table}(token_hash)")
            for row_id, plain in c.execute(
                f"SELECT id, token FROM {table} WHERE token_hash IS NULL"
            ).fetchall():
                hashed = security.hash_token(plain)
                c.execute(f"UPDATE {table} SET token_hash = ?, token = ? WHERE id = ?",
                          (hashed, hashed, row_id))

        c.execute("DELETE FROM sessions WHERE expires_at < datetime('now')")
        c.execute("DELETE FROM admin_sessions WHERE expires_at < datetime('now')")
        conn.commit()
        encrypt_legacy_robot_tokens(conn)
        conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    finally:
        conn.close()


# ─── Agencies / egress slots ─────────────────────────────────────────────────
# No 0/O/1/I: codes get read out loud and typed from chat messages.
CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
CODE_LENGTH = 8


def normalize_agency_code(raw) -> str:
    """Upper-case, without spaces or dashes ('ab12-cd34' == 'AB12CD34')."""
    return "".join(ch for ch in str(raw or "").upper() if ch.isalnum())


def format_agency_code(code: str) -> str:
    return f"{code[:4]}-{code[4:]}" if len(code) == CODE_LENGTH else code


def create_agency(conn, name: str) -> dict:
    for _ in range(10):
        code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))
        try:
            cur = conn.execute("INSERT INTO agencies (name, code) VALUES (?, ?)", (name, code))
            conn.commit()
            agency = get_agency(conn, cur.lastrowid)
            agency["code"] = format_agency_code(agency["code"])
            return agency
        except sqlite3.IntegrityError:
            conn.rollback()  # code collision (astronomically unlikely): draw another
    raise RuntimeError("não foi possível gerar um código de agência único")


def get_agency(conn, agency_id: int):
    return row_to_dict(conn.execute("SELECT * FROM agencies WHERE id = ?", (agency_id,)).fetchone())


def get_agency_by_code(conn, raw_code):
    code = normalize_agency_code(raw_code)
    if len(code) != CODE_LENGTH:
        return None
    return row_to_dict(conn.execute("SELECT * FROM agencies WHERE code = ?", (code,)).fetchone())


def list_agencies_with_counts(conn) -> list:
    """One row per agency with its creators: registered, with a robot connected,
    and with the live watch switched on (the in-memory 'running now' count is
    added by the caller - it lives in the session manager, not here)."""
    rows = conn.execute("""
        SELECT a.id, a.name, a.code, a.active, a.created_at,
               COUNT(u.id) AS users_total,
               COALESCE(SUM(CASE WHEN r.user_id IS NOT NULL THEN 1 ELSE 0 END), 0) AS with_robot,
               COALESCE(SUM(CASE WHEN w.active = 1 THEN 1 ELSE 0 END), 0) AS watching
        FROM agencies a
        LEFT JOIN users u ON u.agency_id = a.id
        LEFT JOIN robot_accounts r ON r.user_id = u.id
        LEFT JOIN streamer_watch w ON w.user_id = u.id
        GROUP BY a.id
        ORDER BY a.id
    """).fetchall()
    result = []
    for row in rows:
        d = row_to_dict(row)
        d["code"] = format_agency_code(d["code"])
        result.append(d)
    return result


def get_live_pattern(conn, user_id: int):
    """What the activity log says about when this creator goes live: the start
    times of her lives over the last 21 days, when the last one ended, and when
    her account was created. All naive UTC datetimes (SQLite's datetime('now'))."""
    from datetime import datetime

    def parse(value):
        try:
            return datetime.strptime(value, "%Y-%m-%d %H:%M:%S")
        except (TypeError, ValueError):
            return None

    starts, last_end = [], None
    for row in conn.execute(
        "SELECT action, created_at FROM user_activity_log WHERE user_id = ? "
        "AND action IN ('session_auto_started', 'session_started', 'favorite_live_connected', 'live_ended') "
        "AND created_at >= datetime('now', '-21 days') ORDER BY id", (user_id,)
    ):
        when = parse(row["created_at"])
        if when is None:
            continue
        if row["action"] == "live_ended":
            last_end = when
        else:
            starts.append(when)
    created = conn.execute("SELECT created_at FROM users WHERE id = ?", (user_id,)).fetchone()
    return starts, last_end, parse(created["created_at"]) if created else None


def load_extra_proxies(conn) -> list:
    """The panel-added egress URLs, decrypted, oldest first. One that cannot be decrypted
    (wrong key) becomes an unreachable placeholder so every later slot keeps its number."""
    urls = []
    for row in conn.execute("SELECT url_enc FROM egress_proxies ORDER BY id"):
        try:
            urls.append(security.decrypt_robot_token(row["url_enc"]))
        except Exception:  # noqa: BLE001
            log.error("egress_proxies: nao consegui decifrar um proxy (chave errada?)")
            urls.append("socks5h://chave-errada.invalid:1")
    return urls


def add_extra_proxy(conn, url: str) -> None:
    conn.execute("INSERT INTO egress_proxies (url_enc) VALUES (?)", (security.encrypt_robot_token(url),))
    conn.commit()


def egress_seats(conn, pool_size: int, per_egress: int) -> dict:
    """Sign-up room: ``per_egress`` creators per IP. Everyone with an account takes a seat
    (a user who never connected a robot yet still gets a slot on her first connection)."""
    pool_size = max(1, pool_size)
    total = pool_size * per_egress if per_egress else 0
    used = conn.execute("SELECT COUNT(*) AS n FROM users").fetchone()["n"]
    return {"per_egress": per_egress, "total": total, "used": used,
            "free": max(0, total - used) if per_egress else None}


def signup_has_room(conn, pool_size: int, per_egress: int) -> bool:
    """False when every IP already has ``per_egress`` creators (0 = no cap)."""
    if not per_egress:
        return True
    pool_size = max(1, pool_size)
    seats = egress_seats(conn, pool_size, per_egress)
    if seats["free"] <= 0:
        return False
    load = {i: 0 for i in range(pool_size)}
    for r in conn.execute("SELECT egress_slot, COUNT(*) AS n FROM users "
                          "WHERE egress_slot IS NOT NULL GROUP BY egress_slot"):
        if (r["egress_slot"] % pool_size) in load:
            load[r["egress_slot"] % pool_size] += r["n"]
    return min(load.values()) < per_egress


def get_or_assign_egress_slot(conn, user_id: int, pool_size: int) -> int:
    """The user's fixed egress (proxy) slot. Assigned once, to the least loaded
    slot, then never changed: SuperLive ties a token to the IP it was issued
    from, so moving an account between IPs would invite a re-login/ban."""
    pool_size = max(1, pool_size)
    row = conn.execute("SELECT egress_slot FROM users WHERE id = ?", (user_id,)).fetchone()
    if row is None:
        return 0
    if row["egress_slot"] is not None:
        return row["egress_slot"] % pool_size
    load = {i: 0 for i in range(pool_size)}
    for r in conn.execute("SELECT egress_slot, COUNT(*) AS n FROM users "
                          "WHERE egress_slot IS NOT NULL GROUP BY egress_slot"):
        if r["egress_slot"] in load:
            load[r["egress_slot"]] = r["n"]
    chosen = min(load, key=lambda i: (load[i], i))
    conn.execute("UPDATE users SET egress_slot = ? WHERE id = ? AND egress_slot IS NULL",
                 (chosen, user_id))
    conn.commit()
    row = conn.execute("SELECT egress_slot FROM users WHERE id = ?", (user_id,)).fetchone()
    return (row["egress_slot"] if row["egress_slot"] is not None else chosen) % pool_size


# ─── Settings / rules / messages helpers (also used by the moderation engine) ───
def get_settings(conn, user_id: int) -> dict:
    query = f"SELECT {_SETTINGS_COLUMNS} FROM bot_settings WHERE user_id = ?"
    row = conn.execute(query, (user_id,)).fetchone()
    if row is None:
        conn.execute("INSERT OR IGNORE INTO bot_settings (user_id) VALUES (?)", (user_id,))
        conn.commit()
        row = conn.execute(query, (user_id,)).fetchone()
    return row_to_dict(row)


def load_engine_config(user_id: int) -> dict:
    """Snapshot of everything the engine needs, read fresh from the DB."""
    conn = connect()
    try:
        settings = get_settings(conn, user_id)
        rules = [
            row_to_dict(r) for r in conn.execute(
                "SELECT id, keyword, action FROM moderation_rules "
                "WHERE user_id = ? AND is_active = 1 ORDER BY id",
                (user_id,),
            )
        ]
        messages = [
            r["content"] for r in conn.execute(
                "SELECT content FROM auto_messages WHERE user_id = ? AND is_active = 1 "
                "ORDER BY sort_order ASC, id ASC",
                (user_id,),
            )
        ]
        return {"settings": settings, "rules": rules, "messages": messages}
    finally:
        conn.close()


def get_robot(conn, user_id: int, with_token: bool = True):
    """The user's robot account. ``token`` is decrypted for callers that talk to
    SuperLive; pass ``with_token=False`` where it is not needed (status payloads,
    the admin overview) so a missing key can never break those and the secret is
    never even decrypted. Raises security.RobotKeyUnavailable if it cannot be."""
    robot = row_to_dict(
        conn.execute("SELECT * FROM robot_accounts WHERE user_id = ?", (user_id,)).fetchone()
    )
    if robot is not None:
        robot["token"] = security.decrypt_robot_token(robot["token"]) if with_token else None
    return robot


def store_robot_token(token: str) -> str:
    """What goes in robot_accounts.token. Encrypts; never writes a clear token
    unless SM_ALLOW_PLAINTEXT_ROBOT_TOKEN=1 (local development only)."""
    try:
        return security.encrypt_robot_token(token)
    except security.RobotKeyUnavailable:
        if os.getenv("SM_ALLOW_PLAINTEXT_ROBOT_TOKEN") == "1":
            log.warning("SM_ALLOW_PLAINTEXT_ROBOT_TOKEN=1: storing the robot token UNENCRYPTED (dev only)")
            return token
        raise


def encrypt_legacy_robot_tokens(conn) -> None:
    """One-time upgrade of robot tokens saved before encryption existed. Skipped
    (with a warning) while no key is configured: those rows stay readable."""
    rows = conn.execute("SELECT id, token FROM robot_accounts").fetchall()
    legacy = [(r[0], r[1]) for r in rows if not security.is_encrypted_token(r[1])]
    if not legacy:
        return
    try:
        converted = [(security.encrypt_robot_token(tok), rid) for rid, tok in legacy]
    except security.RobotKeyUnavailable as exc:
        log.warning("%d robot token(s) still stored in clear: %s", len(legacy), exc)
        return
    conn.executemany("UPDATE robot_accounts SET token = ? WHERE id = ?", converted)
    conn.commit()
    log.info("encrypted %d legacy robot token(s)", len(converted))


def get_watch(conn, user_id: int):
    return row_to_dict(
        conn.execute("SELECT * FROM streamer_watch WHERE user_id = ?", (user_id,)).fetchone()
    )


def set_watch(conn, user_id: int, shared_id: str, nickname, avatar, active: bool):
    conn.execute(
        "INSERT INTO streamer_watch (user_id, shared_id, nickname, avatar, active, updated_at) "
        "VALUES (?, ?, ?, ?, ?, datetime('now')) "
        "ON CONFLICT(user_id) DO UPDATE SET shared_id = excluded.shared_id, "
        "nickname = excluded.nickname, avatar = excluded.avatar, active = excluded.active, "
        "updated_at = excluded.updated_at",
        (user_id, shared_id, nickname, avatar, int(active)),
    )
    conn.commit()


def all_active_watches(conn):
    return [row_to_dict(r) for r in conn.execute(
        "SELECT * FROM streamer_watch WHERE active = 1"
    )]


def log_action(user_id, livestream_id, target_user_id, target_name, action,
               keyword, message_text, ok, detail=None):
    conn = connect()
    try:
        cur = conn.execute(
            "INSERT INTO moderation_log (user_id, livestream_id, target_user_id, target_name, "
            "action, keyword, message_text, ok, detail) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (user_id, livestream_id, target_user_id, target_name, action, keyword,
             (message_text or "")[:300], int(bool(ok)), detail),
        )
        # keep the audit log bounded (it contains chat text of third parties)
        conn.execute(
            "DELETE FROM moderation_log WHERE user_id = ? AND id <= "
            "(SELECT id FROM moderation_log WHERE user_id = ? ORDER BY id DESC LIMIT 1 OFFSET ?)",
            (user_id, user_id, MAX_LOG_ROWS),
        )
        conn.commit()
        return cur.lastrowid
    finally:
        conn.close()


MAX_ACTIVITY_ROWS = 500  # per portal user


def log_activity(user_id: int, action: str, detail: str = None) -> None:
    """Record an account-level action (login, rule/message/settings change, robot
    connect/disconnect, session start/stop) for the user's own activity history."""
    conn = connect()
    try:
        conn.execute(
            "INSERT INTO user_activity_log (user_id, action, detail) VALUES (?, ?, ?)",
            (user_id, action, detail),
        )
        conn.execute(
            "DELETE FROM user_activity_log WHERE user_id = ? AND id <= "
            "(SELECT id FROM user_activity_log WHERE user_id = ? ORDER BY id DESC LIMIT 1 OFFSET ?)",
            (user_id, user_id, MAX_ACTIVITY_ROWS),
        )
        conn.commit()
    finally:
        conn.close()


def list_activity(conn, user_id: int, limit: int = 100) -> list:
    rows = conn.execute(
        "SELECT id, action, detail, created_at FROM user_activity_log "
        "WHERE user_id = ? ORDER BY id DESC LIMIT ?",
        (user_id, limit),
    ).fetchall()
    return [row_to_dict(r) for r in rows]


def action_totals(conn, user_id: int) -> dict:
    row = conn.execute(
        "SELECT COALESCE(SUM(ok = 1), 0) AS ok_count, COALESCE(SUM(ok = 0), 0) AS failed_count "
        "FROM moderation_log WHERE user_id = ?",
        (user_id,),
    ).fetchone()
    return {"actions_ok": row["ok_count"], "actions_failed": row["failed_count"]}


def get_stats(conn, user_id: int, days: int) -> dict:
    """Moderation history for the stats screen: everything comes from
    moderation_log, which already has one row per mute/kick with the live,
    keyword and outcome - nothing new to track, just aggregate what's there.
    """
    since = f"-{max(1, days)} days"

    totals = conn.execute(
        "SELECT COUNT(*) AS total, "
        "COALESCE(SUM(action = 'mute'), 0) AS mutes, "
        "COALESCE(SUM(action = 'kick'), 0) AS kicks, "
        "COALESCE(SUM(ok = 1), 0) AS ok_count "
        "FROM moderation_log WHERE user_id = ? AND created_at >= datetime('now', ?)",
        (user_id, since),
    ).fetchone()

    top_keywords = conn.execute(
        "SELECT keyword, COUNT(*) AS n FROM moderation_log "
        "WHERE user_id = ? AND created_at >= datetime('now', ?) AND keyword IS NOT NULL AND keyword != '' "
        "GROUP BY keyword ORDER BY n DESC LIMIT 8",
        (user_id, since),
    ).fetchall()

    by_day = conn.execute(
        "SELECT date(created_at) AS day, COUNT(*) AS n FROM moderation_log "
        "WHERE user_id = ? AND created_at >= datetime('now', ?) "
        "GROUP BY day ORDER BY day",
        (user_id, since),
    ).fetchall()

    recent_lives = conn.execute(
        "SELECT livestream_id, COUNT(*) AS n, MIN(created_at) AS first_at, MAX(created_at) AS last_at "
        "FROM moderation_log WHERE user_id = ? AND created_at >= datetime('now', ?) AND livestream_id IS NOT NULL "
        "GROUP BY livestream_id ORDER BY first_at DESC LIMIT 10",
        (user_id, since),
    ).fetchall()

    return {
        "days": days,
        "total_actions": totals["total"],
        "mutes": totals["mutes"],
        "kicks": totals["kicks"],
        "success_rate": round(totals["ok_count"] / totals["total"], 4) if totals["total"] else None,
        "top_keywords": [dict(r) for r in top_keywords],
        "by_day": [dict(r) for r in by_day],
        "recent_lives": [dict(r) for r in recent_lives],
    }
