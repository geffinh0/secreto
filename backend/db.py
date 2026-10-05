"""SQLite access + schema/migrations for the Super Moderator backend."""
import os
import sqlite3

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
}

_BOOL_KEYS = (
    "is_active", "is_admin", "auto_messages_enabled",
    "moderation_enabled", "kick_permanent", "ok",
)

# bot_settings columns exposed via the API. end_message_enabled/end_message_template
# still exist in older databases (discontinued; see init_db) but are never read back.
_SETTINGS_COLUMNS = (
    "id, user_id, auto_messages_enabled, message_interval_seconds, "
    "moderation_enabled, kick_permanent"
)


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

        # ---- additive migrations for databases created by older versions ----
        if "expires_at" not in _columns(conn, "sessions"):
            c.execute("ALTER TABLE sessions ADD COLUMN expires_at TEXT")
        c.execute(
            "UPDATE sessions SET expires_at = datetime(created_at, ?) WHERE expires_at IS NULL",
            (f"+{SESSION_DAYS} days",),
        )
        if "kick_permanent" not in _columns(conn, "bot_settings"):
            c.execute("ALTER TABLE bot_settings ADD COLUMN kick_permanent INTEGER DEFAULT 0")

        c.execute("DELETE FROM sessions WHERE expires_at < datetime('now')")
        conn.commit()
    finally:
        conn.close()


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


def get_robot(conn, user_id: int):
    return row_to_dict(
        conn.execute("SELECT * FROM robot_accounts WHERE user_id = ?", (user_id,)).fetchone()
    )


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


def action_totals(conn, user_id: int) -> dict:
    row = conn.execute(
        "SELECT COALESCE(SUM(ok = 1), 0) AS ok_count, COALESCE(SUM(ok = 0), 0) AS failed_count "
        "FROM moderation_log WHERE user_id = ?",
        (user_id,),
    ).fetchone()
    return {"actions_ok": row["ok_count"], "actions_failed": row["failed_count"]}
