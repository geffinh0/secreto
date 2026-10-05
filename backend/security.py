"""Password hashing and login throttling."""
import hashlib
import hmac
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


class LoginThrottle:
    """Blocks a key (username / IP) after too many failed logins in a time window."""

    def __init__(self, max_failures: int = 8, window_seconds: int = 300):
        self.max_failures = max_failures
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
            if len(self._failures.get(key, ())) >= self.max_failures:
                return True
        return False

    def record_failure(self, *keys) -> None:
        now = time.monotonic()
        for key in keys:
            self._failures[key].append(now)

    def reset(self, *keys) -> None:
        for key in keys:
            self._failures.pop(key, None)
