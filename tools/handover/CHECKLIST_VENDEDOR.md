# Checklist do vendedor (não vai no pacote)

Gerar o pacote: `tools/make_handover.sh ../atilas-client-entrega` (cria a pasta, sem histórico do git, e
barra se sobrar algo pessoal). Rode os testes dentro dela antes de entregar.

## Antes de entregar
- [ ] Confirmar **o que a licença inclui** (código, marca, domínio, base de usuárias) e por escrito.
- [ ] Contrato revisado por advogado: risco da API não oficial do SuperLive (leia `docs/MANUTENCAO_SUPERLIVE.md`),
      suporte incluído (dias/horas), não concorrência, forma de pagamento.
- [ ] **Não entregar:** seu `.env`, `secrets/`, `backups/`, banco de produção, tokens/contas das criadoras,
      chaves SSH, o proxy do seu notebook, bot de monitoramento, a pasta `.git`.
- [ ] O comprador gera a PRÓPRIA chave (`install.sh`) e o próprio admin; nenhuma credencial sua entra.
- [ ] Se o comprador quiser a base de usuárias: só com consentimento delas (LGPD) e sem tokens do SuperLive.
- [ ] IP brasileiro testado com login (30 a 60 min com uma conta de teste) antes de prometer 7 por IP.

## Entrega
- [ ] Enviar a pasta gerada (zip) por canal seguro.
- [ ] Sessão de instalação junto com ele (1 hora): `./install.sh`, criar agência, cadastrar conta de teste, **Adicionar IP**.
- [ ] Ele cria o backup agendado (`crontab`) e guarda `secrets/sm_token_key` fora do servidor.

## Depois
- [ ] Período de suporte combinado; mudanças da API do SuperLive só entram no suporte se estiver escrito.
