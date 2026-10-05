"""Reset a portal user's password.

    python reset_password.py <username>

The new password is typed at the prompt (not echoed, not stored anywhere else).
All of that user's existing login sessions are revoked.
"""
import getpass
import sys

import db
import security


def main() -> int:
    if len(sys.argv) != 2:
        print("uso: python reset_password.py <usuario>")
        return 2
    username = sys.argv[1]

    conn = db.connect()
    try:
        row = conn.execute(
            "SELECT id, username FROM users WHERE lower(username) = lower(?)", (username,)
        ).fetchone()
        if row is None:
            print(f"Usuario '{username}' nao encontrado.")
            return 1

        password = getpass.getpass(f"Nova senha para {row['username']} (minimo 8 caracteres): ")
        if len(password) < 8:
            print("A senha precisa ter pelo menos 8 caracteres.")
            return 1
        if getpass.getpass("Repita a senha: ") != password:
            print("As senhas nao conferem.")
            return 1

        conn.execute("UPDATE users SET password_hash = ? WHERE id = ?",
                     (security.hash_password(password), row["id"]))
        conn.execute("DELETE FROM sessions WHERE user_id = ?", (row["id"],))
        conn.commit()
        print(f"Senha de '{row['username']}' redefinida. Entre no portal com a nova senha.")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
