"""Password hashing and login throttling."""
import hashlib
import hmac
import logging
import os
import secrets
import time
from collections import defaultdict

PBKDF2_ITERATIONS = 200_000
_SCHEME = "pbkdf2_sha256"


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, PBKDF2_ITERATIONS)
    return f"{_SCHEME}${PBKDF2_ITERATIONS}${salt.hex()}${digest.hex()}"


def verify_password(password: str, stored: str):
    """Return (is_valid, needs_rehash).

    Accepts the salted PBKDF2 format and the legacy unsalted SHA-256 hex digest
    used by the first version of the portal (those get upgraded on next login).
    """
    if stored.startswith(_SCHEME + "$"):
        try:
            _, iterations, salt_hex, digest_hex = stored.split("$")
            candidate = hashlib.pbkdf2_hmac(
                "sha256", password.encode(), bytes.fromhex(salt_hex), int(iterations)
            )
        except (ValueError, TypeError):
            return False, False
        ok = hmac.compare_digest(candidate.hex(), digest_hex)
        return ok, ok and int(iterations) < PBKDF2_ITERATIONS

    legacy = hashlib.sha256(password.encode()).hexdigest()
    ok = hmac.compare_digest(legacy, stored)
    return ok, ok


def burn_password_check(password: str) -> None:
    """Spend roughly the same time as a real check (avoids user-enumeration by timing)."""
    hashlib.pbkdf2_hmac("sha256", password.encode(), b"\x00" * 16, PBKDF2_ITERATIONS)


def generate_token() -> str:
    return secrets.token_hex(32)


def hash_token(token: str) -> str:
    """SHA-256 of a session token, as stored in the DB instead of the token itself.

    Session tokens are 256 random bits (``generate_token``), so a fast unsalted
    hash is enough here - there is nothing to brute-force, unlike a password.
    A leaked DB or backup no longer contains anything that can be replayed as
    a login.
    """
    return hashlib.sha256(token.encode()).hexdigest()


# ---- reversible encryption for the SuperLive robot token ---------------------
# The robot's session token has to be sent to SuperLive as-is, so it cannot be
# hashed - only encrypted at rest. The key lives in a file (a Docker secret),
# never in an environment variable (``docker inspect`` shows those) and never
# inside the SQLite volume it protects. Without a key nothing is ever written
# in clear: the callers get RobotKeyUnavailable and answer 503.
_ENC_PREFIX = "enc:v1:"
log = logging.getLogger("super_moderator.security")


class RobotKeyUnavailable(Exception):
    """No usable SM_TOKEN_KEY_FILE: refuse to store a robot token in clear."""


def _load_fernet():
    path = os.getenv("SM_TOKEN_KEY_FILE", "").strip()
    if not path:
        raise RobotKeyUnavailable("SM_TOKEN_KEY_FILE não configurado")
    try:
        from cryptography.fernet import Fernet
        with open(path, "rb") as fh:
            return Fernet(fh.read().strip())
    except Exception as exc:  # noqa: BLE001 - unreadable file, malformed key, missing lib
        raise RobotKeyUnavailable(f"chave de cifra inválida ou ilegível: {exc.__class__.__name__}") from None


def is_encrypted_token(value: str) -> bool:
    return isinstance(value, str) and value.startswith(_ENC_PREFIX)


def encrypt_robot_token(token: str) -> str:
    return _ENC_PREFIX + _load_fernet().encrypt(token.encode()).decode()


def decrypt_robot_token(stored: str) -> str:
    """Return the usable token. Rows written before encryption existed (no
    prefix) are still accepted so a deploy never strands a working robot; they
    get re-encrypted by ``db.encrypt_legacy_robot_tokens`` once a key exists."""
    if not is_encrypted_token(stored):
        return stored
    try:
        return _load_fernet().decrypt(stored[len(_ENC_PREFIX):].encode()).decode()
    except RobotKeyUnavailable:
        raise
    except Exception:  # noqa: BLE001 - wrong key / corrupted ciphertext
        raise RobotKeyUnavailable("não foi possível decifrar o token do robô (chave errada?)") from None


class LoginThrottle:
    """Blocks a key (username / IP) after too many failed logins in a time window."""

    def __init__(self, max_failures: int = 8, window_seconds: int = 300,
                 ip_max_failures: int = None):
        self.max_failures = max_failures
        # Keys starting with "ip:" get their own, higher budget. Until the real
        # client IP reaches the backend (see FORWARDED_ALLOW_IPS) that key can
        # be a single bucket shared by every visitor, so it must not trip at
        # the same threshold as one person's username.
        self.ip_max_failures = ip_max_failures if ip_max_failures is not None else max_failures
        self.window = window_seconds
        self._failures = defaultdict(list)

    def _prune(self, key):
        cutoff = time.monotonic() - self.window
        self._failures[key] = [t for t in self._failures[key] if t > cutoff]
        if not self._failures[key]:
            del self._failures[key]

    def is_blocked(self, *keys) -> bool:
        for key in keys:
            self._prune(key)
            limit = self.ip_max_failures if key.startswith("ip:") else self.max_failures
            if len(self._failures.get(key, ())) >= limit:
                return True
        return False

    def record_failure(self, *keys) -> None:
        now = time.monotonic()
        for key in keys:
            self._failures[key].append(now)

    def reset(self, *keys) -> None:
        for key in keys:
            self._failures.pop(key, None)

    def clear(self) -> None:
        """Forget every recorded failure (used by tests)."""
        self._failures.clear()
