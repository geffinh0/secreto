"""Telegram bot: watches the Atila's Client stack + the notebook proxy chain,
reports live stream events (favourited streamer went live, broadcast end summaries),
and answers interactive commands (/status, /live, /resumo, /ajuda).
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
LIVE_CHECK_INTERVAL_SECONDS = int(os.environ.get("HEALTHBOT_LIVE_CHECK_INTERVAL", "10"))
ATILA_API_URL = os.environ.get("ATILA_API_URL", "http://127.0.0.1:8088/api").rstrip("/")

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
    lines = ["📊 Status da Infraestrutura — Atila's Client\n"]
    for name, value in checks.items():
        ok = value in OK_VALUES
        lines.append(f"{'✅' if ok else '❌'} {name}: {value}")
    return "\n".join(lines)


def get_live_status() -> dict:
    for base in (ATILA_API_URL, "https://atilaclient.tech/api"):
        try:
            r = requests.get(f"{base}/robot/live_status", timeout=6)
            if r.status_code == 200:
                return r.json()
        except Exception:  # noqa: BLE001
            pass
    return {}


def format_live_command(status: dict) -> str:
    if not status:
        return "⚠️ Não foi possível obter o status da live no momento (API indisponível)."

    watch = status.get("watch") or {}
    streamer_name = watch.get("nickname") or watch.get("shared_id") or "Nenhuma"
    shared_id = watch.get("shared_id") or "-"
    watch_active = watch.get("active", False)

    session = status.get("session") or {}
    state = session.get("state", "idle")
    is_running = session.get("running", False) and state == "running"
    livestream_id = session.get("livestream_id")
    ws_state = session.get("ws_state", "disconnected")

    counters = session.get("counters") or {}
    chat_seen = counters.get("chat_seen", 0)
    actions_ok = counters.get("actions_ok", 0)
    actions_failed = counters.get("actions_failed", 0)
    messages_sent = counters.get("messages_sent", 0)

    started_at = session.get("started_at")
    last_error = session.get("last_error")

    lines = []
    if is_running and livestream_id:
        lines.append("🔴 STATUS DA LIVE — AO VIVO\n")
        lines.append(f"👤 Streamer: {streamer_name} (ID: {shared_id})")
        lines.append(f"🆔 Live ID: {livestream_id}")
        lines.append(f"📡 Conexão Robô: {'Conectado ✅' if ws_state == 'connected' else ws_state}")
        lines.append(f"💬 Mensagens lidas: {chat_seen}")
        mod_text = f"🛡️ Moderações: {actions_ok} aplicadas"
        if actions_failed:
            mod_text += f" ({actions_failed} falhas)"
        lines.append(mod_text)
        lines.append(f"🤖 Msgs automáticas: {messages_sent}")
        if started_at:
            lines.append(f"⏱️ Início: {started_at}")
    else:
        lines.append("⚪ STATUS DA LIVE — OFFLINE\n")
        lines.append(f"👤 Streamer favorita: {streamer_name} (ID: {shared_id})")
        lines.append(f"👁️ Modo Vigia: {'Ativo e monitorando 🟢' if watch_active else 'Inativo ⚪'}")
        lines.append(f"🤖 Status do Robô: {state}")

    if last_error:
        lines.append(f"\n⚠️ Aviso: {last_error}")

    return "\n".join(lines)


def format_summary_command(status: dict) -> str:
    if not status:
        return "⚠️ Não foi possível obter o resumo de live no momento."

    session = status.get("session") or {}
    last_summary = session.get("last_live_summary")

    if not last_summary:
        recent = status.get("recent_activities") or []
        for act in recent:
            if act.get("action") == "live_summary":
                return f"🏁 ÚLTIMO RESUMO DE TRANSMISSÃO\n\n{act.get('detail')}"
        return "ℹ️ Nenhum resumo de transmissão registrado recentemente."

    dur = last_summary.get("duration_formatted") or f"{last_summary.get('duration_seconds', 0)}s"
    lines = [
        "🏁 ÚLTIMO RESUMO DE TRANSMISSÃO\n",
        f"🆔 Live ID: {last_summary.get('livestream_id')}",
        f"⏱️ Duração: {dur}",
        f"💬 Chat monitorado: {last_summary.get('chat_seen', 0)} mensagens",
        f"🛡️ Moderações: {last_summary.get('actions_ok', 0)} ({last_summary.get('mutes', 0)} silenciamentos, {last_summary.get('kicks', 0)} expulsões)",
        f"🤖 Mensagens automáticas: {last_summary.get('messages_sent', 0)}",
        f"💎 Diamantes arrecadados: {last_summary.get('diamonds', 0)}",
    ]
    if last_summary.get("ts"):
        lines.append(f"📅 Registrado em: {last_summary.get('ts')}")
    return "\n".join(lines)


def format_help_command() -> str:
    return (
        "🤖 Comandos do Atila's Client no Telegram:\n\n"
        "📊 /status — Checagem de toda a infraestrutura (containers, proxies, portas e sites).\n"
        "🔴 /live — Status em tempo real da transmissão (streamer, chat, moderações).\n"
        "🏁 /resumo — Resumo completo da última transmissão encerrada.\n"
        "❓ /ajuda — Lista de comandos disponíveis."
    )


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
        r = requests.get(f"{API}/getUpdates", params={"timeout": 20, "offset": offset}, timeout=25)
        return r.json().get("result", [])
    except Exception:  # noqa: BLE001
        return []


def check_live_alerts(state: dict) -> None:
    """Checks for newly generated live events and sends instant Telegram alerts."""
    live_data = get_live_status()
    if not live_data:
        return

    recent_acts = live_data.get("recent_activities") or []
    last_id = int(state.get("last_activity_id") or 0)
    max_id = last_id

    # Process activities chronologically
    sorted_acts = sorted(recent_acts, key=lambda a: a.get("id") or 0)
    for act in sorted_acts:
        act_id = int(act.get("id") or 0)
        if act_id > last_id:
            action = act.get("action")
            detail = act.get("detail") or ""
            if action == "favorite_live_connected":
                send_message(f"🔴 STREAMER AO VIVO!\n\n{detail}")
            elif action == "live_summary":
                send_message(f"🏁 RESUMO DA TRANSMISSÃO\n\n{detail}")
            if act_id > max_id:
                max_id = act_id

    if max_id > last_id:
        state["last_activity_id"] = max_id
        save_state(state)


def main() -> None:
    print("healthbot: iniciado")
    state = load_state()
    last_infra_check = 0.0
    last_live_check = 0.0
    offset = None

    # Initial priming of activity id so we don't dump old historical logs on boot
    initial_live = get_live_status()
    if initial_live and "last_activity_id" not in state:
        acts = initial_live.get("recent_activities") or []
        if acts:
            state["last_activity_id"] = max(int(a.get("id") or 0) for a in acts)
            save_state(state)

    while True:
        now = time.time()

        # 1. Periodic live event alerts (every ~10 seconds)
        if now - last_live_check >= LIVE_CHECK_INTERVAL_SECONDS:
            check_live_alerts(state)
            last_live_check = now

        # 2. Infrastructure state monitoring (every ~300 seconds)
        if now - last_infra_check >= CHECK_INTERVAL_SECONDS:
            checks = check_all()
            if checks != state.get("infra_checks"):
                send_message(format_status(checks))
                state["infra_checks"] = checks
                save_state(state)
            last_infra_check = now

        # 3. Interactive Telegram commands
        for update in get_updates(offset):
            offset = update["update_id"] + 1
            msg = update.get("message") or {}
            text = (msg.get("text") or "").strip().lower()
            chat_id = str(msg.get("chat", {}).get("id") or "")
            if chat_id != CHAT_ID:
                continue

            # Command routing
            cmd = text.split()[0] if text else ""
            if cmd in ("/status",):
                send_message(format_status(check_all()), chat_id=chat_id)
            elif cmd in ("/live", "/stream"):
                send_message(format_live_command(get_live_status()), chat_id=chat_id)
            elif cmd in ("/resumo", "/summary"):
                send_message(format_summary_command(get_live_status()), chat_id=chat_id)
            elif cmd in ("/ajuda", "/help", "/start", "/comandos"):
                send_message(format_help_command(), chat_id=chat_id)


if __name__ == "__main__":
    main()
