# Problemas comuns

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Painel mostra "Um IP não está respondendo" | Proxy fora do ar, plano vencido ou senha trocada | Conferir no fornecedor; o sistema volta sozinho quando o IP voltar |
| Criadora diz "o robô não entra na live" | IP dela sem resposta, ou o robô está esperando a próxima live (normal) | Ver o estado em **Usuários**/**Sessões**; ela pode apertar **Entrei ao vivo** no app |
| "Estamos sem vagas" no cadastro | Todos os IPs têm 7 criadoras | **Adicionar IP** no painel |
| "Capacidade de robôs simultâneos atingida" ao ligar o robô | O IP dela já tem 7 robôs ligados | Adicionar IP ou esperar uma criadora desligar |
| Mensagens automáticas atrasam muito | IP sobrecarregado (mais de 7) ou o SuperLive limitando | Ver "Fila mais longa" na Capacidade; reduzir mensagens ou adicionar IP |
| Robôs param de repente depois de atualizar | Atualizar reinicia o servidor (derruba sessões) | Use `./update.sh` fora do horário de lives; as criadoras religam o robô |
| "O token do robô expirou" | O SuperLive invalidou a sessão do robô | A criadora reconecta o robô no app |
| Todos os robôs perderam a conexão ao mesmo tempo, sem mudança | `secrets/sm_token_key` foi perdida ou trocada | Restaurar a chave original; sem ela, cada robô precisa ser reconectado |
| O app não carrega / erro 502 | O servidor ou o Caddy não subiu | `docker compose ps` e `docker compose logs caddy web backend` |
| HTTPS não emite | DNS não aponta para o servidor ou portas 80/443 fechadas | Corrigir DNS/firewall; `docker compose logs caddy` |
| Conflito com a rede `172.28.0.0/24` | Outra rede do servidor usa a mesma faixa | Trocar a faixa e os IPs fixos no `docker-compose.yml` (172.28.0.10 e .11, `FORWARDED_ALLOW_IPS`) |
| Disco enchendo | Logs ou backups | Limpe `backups/` antigos e rode `docker system prune -f` (nunca remova os volumes) |
| Tudo falha ao mesmo tempo com erros novos do SuperLive | Mudança na API deles | Ver [MANUTENCAO_SUPERLIVE.md](MANUTENCAO_SUPERLIVE.md) |
