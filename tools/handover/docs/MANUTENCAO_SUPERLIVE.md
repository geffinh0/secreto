# Manutenção: dependência do SuperLive

O sistema usa a **API do aplicativo do SuperLive, que não é oficial nem documentada para terceiros**.
Esse é o maior risco do negócio: o SuperLive pode mudar endpoints, exigir verificação ou limitar IPs a
qualquer momento, sem aviso. Nada neste pacote garante que isso continue funcionando.

## Como perceber
Muitas criadoras ao mesmo tempo sem moderação, erros 400/403/404 novos nos logs
(`docker compose logs backend`), robôs que não entram em lives que existem, ou chamadas que sempre
falham com o mesmo erro.

## Onde mexer
- Endereços e chamadas: `backend/superlive.py` (`DEFAULT_BASE_URL`, métodos do `SuperLiveClient`, cabeçalhos).
- WebSocket do chat (entrar, batimento, tipos de mensagem): `backend/engine.py` e `build_ws_url` em `superlive.py`.
- Referência dos endpoints conhecidos: `docs/api/API_CATALOG.md`.
- A base e o WebSocket podem ser trocados por variável (`SUPERLIVE_BASE_URL`, `SUPERLIVE_WS_URL`) sem mexer no código.

## Como investigar uma mudança
1. Reproduza o erro e anote a rota, o status e a resposta no log.
2. Compare com o aplicativo oficial atual (por exemplo, inspecionando o tráfego) e ajuste o cliente.
3. Rode os testes (`python -m unittest discover -s tests -t .`) e teste com uma conta de teste antes de liberar.
4. Atualize com `./update.sh` fora do horário de lives.

## Boas práticas
- Mantenha 7 criadoras por IP e IPs brasileiros fixos; não aumente a pressão sem medir.
- Evite mensagens automáticas mais frequentes que a cada 60 s por criadora.
- Tenha sempre um backup recente e a chave `secrets/sm_token_key` guardada fora do servidor.
