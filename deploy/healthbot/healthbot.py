"""Telegram bot: watches the Atila's Client stack + the notebook proxy chain
and reports in. Two jobs in one loop:

  1. Every CHECK_INTERVAL_SECONDS, runs every check below; if the result
     differs from the last known state, sends a message. Nothing to say =
     nothing sent, so a healthy stack stays quiet.
  2. Long-polls Telegram for messages; replies to /status on demand with a
     fresh check, right away, regardless of the timer above.

Only talks to TELEGRAM_CHAT_ID - a /status from anyone else is ignored.
Config comes from environment variables (see healthbot.env.example), never
hardcoded, so the token/chat id never need to live in the repo or in chat.
"""
import json
import os
import subprocess
import time

import requests

BOT_TOKEN = os.environ["TELEGRAM_BOT_TOKEN"]
CHAT_ID = os.environ["TELEGRAM_CHAT_ID"]
API = f"https://api.telegram.org/bot{BOT_TOKEN}"
STATE_FILE = os.environ.get("HEALTHBOT_STATE_FILE", "/home/deploy/.healthbot_state.json")
CHECK_INTERVAL_SECONDS = int(os.environ.get("HEALTHBOT_CHECK_INTERVAL", "300"))

OK_VALUES = {"up", "active", "ouvindo", 200}


def _run(cmd: str) -> str:
    try:
        out = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
        return out.stdout.strip()
    except Exception as exc:  # noqa: BLE001
        return f"erro: {exc}"


def _container_status(name: str) -> str:
    out = _run(f"docker ps --filter name=^{name}$ --format '{{{{.Status}}}}'")
    return "up" if out.startswith("Up") else (out or "parado")


def _port_listening(port: str) -> str:
    return "ouvindo" if port in _run("ss -tln") else "fechada"


def _http_status(url: str) -> int | str:
    try:
        return requests.get(url, timeout=10).status_code
    except Exception as exc:  # noqa: BLE001
        return f"erro: {exc}"


def check_all() -> dict:
    return {
        "atilas_client_backend": _container_status("atilas_client_backend"),
        "atilas_client_web": _container_status("atilas_client_web"),
        "cata_pobre_app": _container_status("cata_pobre_app"),
        "cata_pobre_ia": _container_status("cata_pobre_ia"),
        "cata_pobre_nginx": _container_status("cata_pobre_nginx"),
        "tunel_notebook (systemd)": _run("systemctl is-active atila-notebook-proxy"),
        "tunel_notebook (porta 2222)": _port_listening("2222"),
        "proxy_socks5 (porta 1080)": _port_listening("1080"),
        "atilaclient.tech": _http_status("https://atilaclient.tech"),
        "atilaclient.tech/api/health": _http_status("https://atilaclient.tech/api/health"),
        "catapobre.com.br": _http_status("https://catapobre.com.br"),
    }


def format_status(checks: dict) -> str:
    lines = ["📊 Status do Atila's Client\n"]
    for name, value in checks.items():
        ok = value in OK_VALUES
        lines.append(f"{'✅' if ok else '❌'} {name}: {value}")
    return "\n".join(lines)


def send_message(text: str, chat_id: str = CHAT_ID) -> None:
    try:
        requests.post(f"{API}/sendMessage", json={"chat_id": chat_id, "text": text}, timeout=10)
    except Exception:  # noqa: BLE001 - a failed alert must never crash the loop
        pass


def load_state() -> dict:
    try:
        with open(STATE_FILE, encoding="utf-8") as f:
            return json.load(f)
    except Exception:  # noqa: BLE001
        return {}


def save_state(state: dict) -> None:
    try:
        with open(STATE_FILE, "w", encoding="utf-8") as f:
            json.dump(state, f)
    except Exception:  # noqa: BLE001
        pass


def get_updates(offset):
    try:
        r = requests.get(f"{API}/getUpdates", params={"timeout": 25, "offset": offset}, timeout=30)
        return r.json().get("result", [])
    except Exception:  # noqa: BLE001
        return []


def main() -> None:
    print("healthbot: iniciado")
    last_state = load_state()
    last_check = 0.0
    offset = None

    while True:
        now = time.time()
        if now - last_check >= CHECK_INTERVAL_SECONDS:
            checks = check_all()
            if checks != last_state:
                send_message(format_status(checks))
                save_state(checks)
                last_state = checks
            last_check = now

        for update in get_updates(offset):
            offset = update["update_id"] + 1
            msg = update.get("message") or {}
            text = (msg.get("text") or "").strip().lower()
            chat_id = str(msg.get("chat", {}).get("id") or "")
            if chat_id != CHAT_ID:
                continue
            if text in ("/status", "/start"):
                send_message(format_status(check_all()), chat_id=chat_id)


if __name__ == "__main__":
    main()
