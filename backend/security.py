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


PASSWORD_MIN_LENGTH = 8
PASSWORD_MAX_LENGTH = 128
# Passwords people actually pick; compared lowercase and with digits/symbols stripped,
# so "Senha@123" and "senha1234" are both caught. Kept short on purpose: the length +
# letter/digit rules do the heavy lifting, this only blocks the famous ones.
_COMMON_PASSWORDS = frozenset("""
password senha senhasenha senha123 senhaforte minhasenha qwerty qwertyuiop qwertyuiop asdfgh asdfghjkl
zxcvbnm abc abcd abcde abcdef abcdefgh abcdefghij iloveyou amorzinho eusouinteligente brasil brasil123
brasileiro flamengo corinthians palmeiras saopaulo santos gremio vasco cruzeiro atletico mudar123
mudar mudarsenha trocar trocarsenha bemvindo bemvinda admin administrador administrator
letmein welcome monkey dragon master superman batman princesa princess linda lindinha gatinha
superlive moderator moderador atilas atilasclient
""".split())


def password_problems(password: str, username: str = "", display_name: str = "") -> list:
    """Why ``password`` is too weak, in Portuguese (empty list = accepted).

    The required shape is: at least 8 characters, one uppercase letter and one special
    character (anything that is not a letter, digit or space). The rest blocks the cheap
    guesses an agency staff member could try (their own name, the username, the usual
    "Senha@123")."""
    problems = []
    if len(password) < PASSWORD_MIN_LENGTH:
        problems.append(f"use pelo menos {PASSWORD_MIN_LENGTH} caracteres")
    if len(password) > PASSWORD_MAX_LENGTH:
        problems.append(f"use no máximo {PASSWORD_MAX_LENGTH} caracteres")
    if not any(ch.isupper() for ch in password):
        problems.append("use pelo menos uma letra maiúscula")
    if not any(not ch.isalnum() and not ch.isspace() for ch in password):
        problems.append("use pelo menos um caractere especial (como ! @ # $ % & *)")
    lowered = password.lower()

    def squeeze(text: str) -> str:  # letters and digits only: "Fulana-de_Tal" == "fulana de tal"
        return "".join(ch for ch in text.lower() if ch.isalnum())

    squeezed = squeeze(password)
    if len(squeeze(username)) >= 3 and squeeze(username) in squeezed:
        problems.append("não use o seu nome de usuário na senha")
    if len(squeeze(display_name or "")) >= 4 and squeeze(display_name) in squeezed:
        problems.append("não use o seu nome de exibição na senha")
    letters_only = "".join(ch for ch in lowered if ch.isalpha())
    if lowered in _COMMON_PASSWORDS or letters_only in _COMMON_PASSWORDS:
        problems.append("essa senha é muito comum, escolha outra")
    if password and len(set(lowered)) <= 3:
        problems.append("a senha tem caracteres repetidos demais")
    if password and (lowered in "01234567890123456789" or lowered in "abcdefghijklmnopqrstuvwxyz"
                     or lowered in "9876543210" or lowered in "zyxwvutsrqponmlkjihgfedcba"):
        problems.append("não use sequências como 1234567890 ou abcdefghij")
    return problems


_TEMP_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789"  # no 0/O/1/l/I


def generate_temp_password() -> str:
    """12 random characters (~68 bits) in groups of four, e.g. ``Kp7x-Qm4e-Zb9w``,
    typed once by the user, so no look-alike characters."""
    raw = "".join(secrets.choice(_TEMP_ALPHABET) for _ in range(12))
    return "-".join(raw[i:i + 4] for i in range(0, 12, 4))


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
