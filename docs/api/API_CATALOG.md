# CATÁLOGO DE TODAS AS APIs — SUPER CLIENT (SuperLive v2.31.0)

Este catálogo documenta rigorosamente todos os endpoints REST identificados nas 32 interfaces Retrofit localizadas em `module.network.services.*`.

---

## 1. Configurações Globais de Rede

- **Host de Produção Padrão:** `https://api.sprlv-api.com/` (Definido em `remote_config_defaults.xml`)
- **Host de Testes / Staging:** `https://api.api-spl.com/`
- **Host Dinâmico:** Atualizável via Firebase Remote Config chave `api_domain` ou Firebase Firestore Listener em `BaseUrlProvider.java`.
- **Headers Padrão Obrigatórios (`HeaderInterceptor.java`):**
  - `User-Agent: SuperLive/2.31.0 (<Manufacturer>; Android <OS_Version>; Scale/<Density>)`
  - `Device-ID: <UUID-v4>` (Persistido no SharedPreferences)
  - `Authorization: Token <userAccessToken>` (Quando o usuário está autenticado)
  - `Content-Type: application/json; charset=UTF-8`
  - `Accept: application/json`

---

## 2. Streamer Statistics & Super Billing (`StreamerStatisticsApiService`)

### 2.1. Obter Estatísticas Detalhadas de Ganhos
- **Nome:** Obter Estatísticas de Ganhos
- **Categoria:** FINANCIAL / READ
- **Método:** `POST`
- **Endpoint:** `user_statistic/get_earning_statistic`
- **Host:** `api.sprlv-api.com`
- **Autenticação:** Requer Token
- **Headers:** Padrão (`Authorization: Token <token>`, `Device-ID`)
- **Body (`APIGetStreamerStatisticGenericRequest`):**
  ```json
  {
    "statistic_type": 0, // 0: DAY, 1: WEEK, 2: MONTH
    "meta": { "page": 1, "per_page": 20 }
  }
  ```
- **Response (`APIStreamerEarningStatisticsResponse`):**
  ```json
  {
    "exchange_rate": 210,
    "average_earning": 450.50,
    "earning_statistics": [
      {
        "current_date": 1727280000000,
        "public_stream_earning": 12000.0,
        "private_stream_earning": 4500.0,
        "private_call_earning": 3200.0,
        "conversation_earning": 800.0,
        "total_earning": 20500.0,
        "previous_earning": 18000.0,
        "decreased_earning": 0.0,
        "agency_earning": 1500.0,
        "salary": 500.0,
        "percentages": {
          "public_stream_earning": 58.5,
          "private_stream_earning": 22.0,
          "private_call_earning": 15.6,
          "conversation_earning": 3.9
        }
      }
    ],
    "meta": { "page": 1, "has_more": false }
  }
  ```
- **Status:** CONFIRMADO
- **Uso:** Tela principal do Super Billing para exibir faturamento detalhado por canal.

### 2.2. Obter Tabela de Saque (Payout Chart)
- **Nome:** Tabela de Conversão e Resgate de Diamantes
- **Categoria:** FINANCIAL / READ
- **Método:** `POST`
- **Endpoint:** `user_statistic/get_payout_chart`
- **Host:** `api.sprlv-api.com`
- **Autenticação:** Requer Token
- **Body:** `{}` (Vazio)
- **Response (`APIPayoutChartResponse`):**
  ```json
  {
    "exchange_rate": 210,
    "diamonds": [2100, 4200, 10500, 21000, 52500, 105000, 210000]
  }
  ```
- **Regra de Conversão:** `Dólar = Diamantes / exchange_rate`. Exemplo: `21000 / 210 = $100.00 USD`.
- **Status:** CONFIRMADO

### 2.3. Estatísticas de Duração de Stream
- **Nome:** Duração de Transmissões
- **Categoria:** READ / ANALYTICS
- **Método:** `POST`
- **Endpoint:** `user_statistic/get_stream_duration_statistic`
- **Body:** `APIGetStreamerStatisticGenericRequest` (`statistic_type`: 0, 1, 2)
- **Response:** `APIStreamerDurationStatisticsResponse` (total de minutos transmitidos, média diária)
- **Status:** CONFIRMADO

### 2.4. Estatísticas de Espectadores
- **Nome:** Contagem de Visualizadores
- **Categoria:** READ / ANALYTICS
- **Método:** `POST`
- **Endpoint:** `user_statistic/get_viewer_statistic`
- **Body:** `APIGetStreamerStatisticGenericRequest`
- **Response:** `APIStreamerViewerStatisticsResponse` (pico de espectadores, média concorrente)
- **Status:** CONFIRMADO

### 2.5. Estatísticas de Seguidores
- **Nome:** Novos Seguidores Conquistados
- **Categoria:** READ / ANALYTICS
- **Método:** `POST`
- **Endpoint:** `user_statistic/get_follower_statistic`
- **Body:** `APIGetStreamerStatisticGenericRequest`
- **Response:** `APIStreamerFollowerStatisticsResponse` (taxa de conversão de novos seguidores)
- **Status:** CONFIRMADO

### 2.6. Estatísticas Gerais de Desempenho
- **Nome:** Métricas de Performance Consolidada
- **Categoria:** READ / ANALYTICS
- **Método:** `POST`
- **Endpoint:** `user_statistic/get_performance_statistic`
- **Body:** `APIGetStreamerStatisticGenericRequest`
- **Response:** `APIStreamerPerformanceStatisticsResponse`
- **Status:** CONFIRMADO

---

## 3. Histórico Financeiro & Compras (`UserListsApiService` & `BillingApiService`)

### 3.1. Histórico de Compras de Moedas
- **Nome:** Histórico de Compras do Usuário
- **Categoria:** FINANCIAL / READ
- **Método:** `POST`
- **Endpoint:** `user/purchase_history`
- **Autenticação:** Requer Token
- **Body:** `{}` (Vazio)
- **Response (`APIUserPurchaseHistoryResponse`):**
  ```json
  {
    "last_week_coins": 15000,
    "last_week_purchases": [
      {
        "purchase": {
          "coins": 5000,
          "timestamp": 1727193600000
        }
      }
    ],
    "before_last_week_purchases": [
      {
        "purchase": {
          "coins": 10000,
          "timestamp": 1726588800000
        }
      }
    ]
  }
  ```
- **Status:** CONFIRMADO

### 3.2. URL de Desconto para Provedores de Pagamento
- **Nome:** Obter URL de Desconto para Recarga Externa
- **Categoria:** FINANCIAL / READ
- **Método:** `POST`
- **Endpoint:** `inapp_purchase/get_multi_payment_provider_discount_url`
- **Response (`APIMultiPaymentProviderDiscountURLResponse`):** URL para checkout web com desconto de moedas.
- **Status:** CONFIRMADO

### 3.3. Confirmação de Compra In-App (Google Play)
- **Nome:** Consumir Compra In-App
- **Categoria:** FINANCIAL / WRITE
- **Método:** `POST`
- **Endpoint:** `inapp_purchase/android/consume`
- **Body (`APIBillingVerifyRequest`):** Token do Google Play, OrderId, ProductId.
- **Response:** `APIBillingInAppVerifyResponse`
- **Status:** CONFIRMADO

### 3.4. Pagamento One-Tap
- **Nome:** Recarga de Um Toque
- **Categoria:** FINANCIAL / WRITE
- **Método:** `POST`
- **Endpoint:** `inapp_purchase/one_tap/payment`
- **Body (`APIOneTapRequest`):** Identificador do pacote de moedas.
- **Response:** `APIOneTapResponse`
- **Status:** CONFIRMADO

---

## 4. Leaderboards & Rankings (`LeaderBoardApiService`)

### 4.1. Ranking de Streamers
- **Nome:** Tabela de Líderes de Streamers
- **Categoria:** READ / RANKING
- **Método:** `POST`
- **Endpoint:** `leaderboard`
- **Autenticação:** Requer Token
- **Body (`APIUserLeaderBoardRequest`):**
  ```json
  {
    "leaderboard_type": 1, // 0: ALL_TIME, 1: DAILY, 2: WEEKLY
    "iso_codes": ["US", "BR"] // [] para ranking mundial
  }
  ```
- **Response (`APIUserLeaderBoardResponse`):**
  - `own_user`: `APILeaderboardUser` (contém `rank`, `points`, `diamonds`, dados de perfil)
  - `users`: Lista de `APILeaderboardUser` ordenada por pontuação decrescente.
- **Status:** CONFIRMADO

### 4.2. Ranking de Gifters (Apoiadores)
- **Nome:** Tabela de Doadores
- **Categoria:** READ / RANKING
- **Método:** `POST`
- **Endpoint:** `gifters_leaderboard`
- **Autenticação:** Requer Token
- **Body (`APIUserLeaderBoardRequest`):**
  ```json
  {
    "leaderboard_type": 1, // 0: ALL_TIME, 1: DAILY, 2: WEEKLY
    "iso_codes": []
  }
  ```
- **Response (`APIGiftersLeaderBoardResponse`):** Lista de top usuários ordenados por volume de moedas presenteadas.
- **Status:** CONFIRMADO

---

## 5. Autenticação & Cadastro (`UserSignUpApiService` & `UserConnectApiService`)

### 5.1. Login por Email e Senha
- **Nome:** Login por Email
- **Categoria:** AUTH / WRITE
- **Método:** `POST`
- **Endpoint:** `user/signup/email_signin`
- **Body (`APIMailLoginRequest`):**
  ```json
  {
    "email": "user@example.com",
    "password": "hashed_or_plain_password"
  }
  ```
- **Response (`APISignUpResponse`):** `token`, `user_id`, `profile`
- **Status:** CONFIRMADO

### 5.2. Cadastro por Email
- **Nome:** Registro por Email
- **Categoria:** AUTH / WRITE
- **Método:** `POST`
- **Endpoint:** `user/signup/email`
- **Status:** CONFIRMADO

### 5.3. Login / Cadastro via Google
- **Nome:** Google OAuth Auth
- **Categoria:** AUTH / WRITE
- **Método:** `POST`
- **Endpoint:** `user/signup/google`
- **Body (`APIGoogleSignUpRequest`):** `id_token` do Google Play Services.
- **Status:** CONFIRMADO

### 5.4. Login / Cadastro via Telefone e SMS
- **Nome:** Enviar Código SMS
- **Método:** `POST`
- **Endpoint:** `user/signup/send_phone_verification_code`
- **Nome:** Validar Código SMS
- **Método:** `POST`
- **Endpoint:** `user/signup/auth_phone`
- **Status:** CONFIRMADO

### 5.5. Logout de Usuário
- **Nome:** Encerrar Sessão
- **Categoria:** AUTH / WRITE
- **Método:** `POST`
- **Endpoint:** `user/logout`
- **Body:** `{}`
- **Response:** `APIGenericBooleanResponse` (`success: true`)
- **Status:** CONFIRMADO

---

## 6. Perfil, Usuário e Configurações (`UserActionsApiService`)

### 6.1. Perfil Próprio do Usuário
- **Nome:** Carregar Perfil Autenticado
- **Categoria:** READ
- **Método:** `POST`
- **Endpoint:** `users/own_profile`
- **Body:** `{}`
- **Response (`APIOwnProfileResponse`):** Dados de saldo de moedas, saldo de diamantes, nível, avatar, bio, badges VIP, reseller flag.
- **Status:** CONFIRMADO

### 6.2. Configurações Globais do Usuário & URLs
- **Nome:** Carregar Configurações e URLs da Conta
- **Categoria:** READ
- **Método:** `POST`
- **Endpoint:** `user/settings`
- **Body:** `{}`
- **Response (`APISettings`):** Contém dicionário `urls` com a URL do portal de saque (`cash_out`), termos de uso, privacidade, suporte.
- **Status:** CONFIRMADO

### 6.3. Atualizar Dados do Perfil
- **Nome:** Atualizar Perfil
- **Categoria:** WRITE
- **Método:** `POST`
- **Endpoint:** `users/update`
- **Body (`APIUpdateOwnUserProfileRequest`):** `nickname`, `bio`, `birthday`, `gender`.
- **Status:** CONFIRMADO

### 6.4. Ajustar Preço de Chamada Privada Paga
- **Nome:** Atualizar Presente Exigido para Chamada Privada
- **Categoria:** FINANCIAL / WRITE
- **Método:** `POST`
- **Endpoint:** `user/paid_private_call_gift_update`
- **Body (`APIPaidPrivateCallGiftUpdateRequest`):** `gift_id`, `coins`.
- **Status:** CONFIRMADO

### 6.5. Ajustar Presente Exigido para Live Privada
- **Nome:** Atualizar Presente Exigido para Live Privada
- **Categoria:** FINANCIAL / WRITE
- **Método:** `POST`
- **Endpoint:** `user/private_livestream_gift_update`
- **Body (`APIPrivateLivestreamGiftUpdateRequest`):** `gift_id`.
- **Status:** CONFIRMADO

### 6.6. Alternar Modo Anônimo no Ranking de Gifters
- **Nome:** Ativar / Desativar Anonimato no Ranking
- **Categoria:** WRITE
- **Método:** `POST`
- **Endpoint:** `user/set_gifters_leaderboard_anonymous`
- **Body (`APIUserSetAnonymousRequest`):** `is_anonymous`: boolean.
- **Status:** CONFIRMADO

### 6.7. Alternância de Opções de Privacidade VIP
- `user/set_coins_sent_hidden` (Ocultar moedas enviadas)
- `user/set_vip_diamonds_received_hidden` (Ocultar diamantes recebidos)
- `user/set_follower_and_following_hidden` (Ocultar lista de seguidores)
- `user/set_location_hidden` (Ocultar país/cidade)
- `user/set_online_status_hidden` (Ocultar status online)
- `user/set_public_stream_incognito` (Modo fantasma em lives)
- `user/set_hidden_profile_viewer` (Ver perfis sem ser registrado na lista de visualizadores)
- `user/set_vip_status_hidden` (Ocultar ícone VIP)
- **Status:** CONFIRMADO

---

## 7. Módulo de Transmissões ao Vivo (`LiveStreamApiService`)

- `POST livestream/start`: Inicia stream pública. Retorna token RTC Agora, StreamID, canal WebRTC.
- `POST livestream/finish`: Encerra stream. Retorna resumo estatístico (diamantes ganhos, novos seguidores, tempo de live).
- `POST livestream/make_private`: Converte transmissão em modo restrito por presente.
- `POST livestream/accept_private`: Aceita solicitação de transmissão privada individual.
- `POST livestream/pk/invitation/send`: Convida outro streamer para batalha PK.
- `POST livestream/pk/war/start`: Inicia o cronômetro da guerra PK.
- `POST livestream/pk/end`: Finaliza guerra PK e calcula vencedor por pontos de presentes.
- `POST livestream/chat/send_text_message`: Envia mensagem no chat da live.
- `POST livestream/chat/mute`: Muta usuário no chat da live.
- `POST livestream/kick`: Expulsa usuário da live.
- **Status:** CONFIRMADO

---

## 8. Módulo de Chamadas Privadas 1-on-1 (`PrivateCallApiService`)

- `POST private_call/start`: Dispara chamada de vídeo privada tarifada por minuto ou presente inicial.
- `POST private_call/accept`: Atende chamada recebida.
- `POST private_call/end`: Finaliza chamada e deduz/credita diamantes e moedas.
- `POST private_call/send_gift`: Envia presente durante a chamada.
- **Status:** CONFIRMADO

---

## 9. Módulo de Mensagens & Inbox (`ConversationApiService`)

- `POST conversation/messages`: Lista histórico de mensagens de uma conversa.
- `POST conversation/send_text_message`: Envia mensagem de texto privada.
- `POST conversation/send_audio_message`: Envia áudio gravado (multipart).
- `POST conversation/premium_media_album/unlock`: Desbloqueia álbum pago mediante envio de presente.
- `POST conversation/pin`: Fixa conversa no topo da caixa de entrada.
- `POST conversation/create_ticket`: Abre chamado no SAC da plataforma.
- **Status:** CONFIRMADO
