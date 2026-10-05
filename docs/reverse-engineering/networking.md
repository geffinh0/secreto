# ENGENHARIA REVERSA: REDE, PROTOCOLOS E INFRAESTRUTURA

Este documento descreve os nós de rede, domínios, protocolos de streaming e comunicação em tempo real utilizados pelo ecossistema SuperLive.

---

## 1. Topologia de Domínios e Resolução Dinâmica

### 1.1. Base URLs Identificadas
- **Produção Principal:** `https://api.sprlv-api.com/api/v1/` (base do Retrofit no app; **o prefixo `/api/v1/` é obrigatório**, sem ele o servidor responde `unknown urd`)
- **Staging / Testes:** `https://api.api-spl.com/`
- **Upload de Mídia / AWS:** Buckets S3 gerenciados via chamadas em `MediaUploadAWSService.java`

### 1.2. Provedor de Base URL Dinâmico (`BaseUrlProvider.java`)
O aplicativo implementa resiliência de conexão através de 3 camadas:
1. **Fallback Local:** `https://api.sprlv-api.com/api/v1/`
2. **Firebase Remote Config:** Chave `api_domain`. Se o domínio principal sofrer bloqueio ou rota congestionada, o Firebase fornece um domínio secundário.
3. **Firestore Listener em Tempo Real:** Escuta mudanças na coleção de configuração remota para atualização sem necessidade de reiniciar o app.

---

## 2. Tecnologias de Streaming e Mídia em Tempo Real

1. **WebRTC / Agora RTC SDK:**
   - Para chamadas privadas 1-on-1 e transmissões ao vivo com latência ultrabaixa (sub-segundo).
   - O endpoint `POST livestream/start` retorna o token RTC de sessão, canal do canal e UID.
2. **WebSocket próprio (não é Centrifugo):**
   - URL vem de `POST user/settings` → `websocket.url` (+ `heartbeat`), acrescida de `?device=<Device-ID>&auth=<token>`.
   - O servidor envia `{"id","type","data"}` (ex.: `livestream_message_sent`, `livestream_ended`); o cliente envia
     `{"id","action","data"}` (`enter_livestream`, `heartbeat`, `leave_livestream`).
