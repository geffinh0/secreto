# Super Moderator

Moderação automática de lives do SuperLive: um robô entra na live, silencia/bane quem usar
palavras proibidas e envia mensagens recorrentes. Portal em Flutter Web + backend
FastAPI/SQLite.

- **Rodar:** `start_server.bat` (ou veja os passos manuais).
- **Documentação completa:** [SUPER_MODERATOR.md](SUPER_MODERATOR.md) — arquitetura, API,
  como as regras funcionam, limitações e testes.
- **Engenharia reversa do app:** pasta `docs/`.

```bash
cd backend && pip install -r requirements.txt && python main.py     # API em :8000
flutter run -d web-server --web-port 3000 --web-hostname localhost   # portal em :3000
```

Testes: `cd backend && python -m unittest discover -s tests -t .` e `flutter test`.
