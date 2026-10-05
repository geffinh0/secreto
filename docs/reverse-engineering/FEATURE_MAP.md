# FEATURE MAP — SUPER CLIENT (SuperLive v2.31.0 Re-Engineering)

Este documento contém o mapeamento de **100% dos fluxos e módulos funcionais identificados** na análise estática e reversa do aplicativo SuperLive (`com.superlive.liveapp` v2.31.0).

---

## 1. Mapeamento Estrutural de Alto Nível

```text
SUPER CLIENT
├── 1. AUTENTICAÇÃO E SESSÃO
│   ├── Login com Email / Senha (POST user/signup/email_signin)
│   ├── Registro com Email (POST user/signup/email)
│   ├── Login/Registro via Google OAuth (POST user/signup/google)
│   ├── Login/Registro via SMS / Telefone (POST user/signup/send_phone_verification_code & auth_phone)
│   ├── Login/Registro via Twitter OAuth (POST user/signup/twitter)
│   ├── Recuperação de Senha por Email/OTP (POST user/signup/send_password_renewal_code & verify_password_renewal)
│   ├── Conexão de Contas Sociais (Google, Email, Phone, Twitter em UserConnectApiService)
│   ├── Gestão de Tokens de Sessão (Header: Authorization: Token <token>, Device-ID)
│   └── Logout Seguro (POST user/logout)
│
├── 2. SUPER BILLING (MÓDULO FINANCEIRO COMPLETO)
│   ├── Estatísticas de Ganhos Detalhadas (POST user_statistic/get_earning_statistic)
│   │   ├── Ganhos por Transmissão Pública (public_stream_earning + public_stream_percentage)
│   │   ├── Ganhos por Transmissão Privada (private_stream_earning + private_stream_percentage)
│   │   ├── Ganhos por Chamada de Vídeo Privada (private_call_earning + private_call_percentage)
│   │   ├── Ganhos por Conversa no Chat (conversation_earning + conversation_percentage)
│   │   ├── Salário Base de Streamer (salary)
│   │   ├── Comissões de Agência (agency_earning)
│   │   ├── Ganhos Período Anterior vs Atual (previous_earning, total_earning, decreased_earning)
│   │   └── Média de Ganhos (average_earning)
│   ├── Tabela de Resgate / Payout Chart (POST user_statistic/get_payout_chart)
│   │   ├── Taxa de Conversão Diamantes → Dólares (exchange_rate)
│   │   └── Faixas de Resgate Disponíveis (diamonds list)
│   ├── Histórico de Compras de Moedas (POST user/purchase_history)
│   │   ├── Compras da Última Semana (last_week_purchases com timestamp e coins)
│   │   ├── Compras Anteriores (before_last_week_purchases)
│   │   └── Total de Moedas Compradas na Semana (last_week_coins)
│   ├── Fluxo de Saque / Cash Out
│   │   ├── URL de Saque Dinâmica via Configuração (APISettings.urls.cash_out)
│   │   └── Integração com Provedor de Pagamento Externo (Hybrid WebView Bridge)
│   ├── Recarga de Moedas (BillingApiService)
│   │   ├── In-App Billing Google Play (POST inapp_purchase/android/consume)
│   │   ├── Recarga One-Tap (POST inapp_purchase/one_tap/payment)
│   │   ├── Descontos Multi-Payment Provider (POST inapp_purchase/get_multi_payment_provider_discount_url)
│   │   └── Auto-Refill Toggle (POST user/set_refill_balance_settings)
│   └── Configuração de Preço de Conteúdo Próprio
│       ├── Definir Custo de Chamada Privada Paga (POST user/paid_private_call_gift_update)
│       └── Definir Presente Mínimo para Live Privada (POST user/private_livestream_gift_update)
│
├── 3. SUPER RANKING & TABELAS DE LIDERANÇA
│   ├── Ranking de Streamers (POST /leaderboard)
│   │   ├── Timeframes: Todos os Tempos (0), Diário (1), Semanal (2)
│   │   ├── Filtro de Localização por ISO Codes de Países (iso_codes)
│   │   └── Posição Pessoal do Usuário (own_user: rank, points, diamonds)
│   ├── Ranking de Gifters / Apoiadores (POST /gifters_leaderboard)
│   │   ├── Timeframes: Diário, Semanal, Geral
│   │   ├── Modo Anônimo no Ranking de Gifters (POST user/set_gifters_leaderboard_anonymous)
│   │   └── Visibilidade de Gifter (POST user/toggle_gifter_visibility)
│   └── Ranking de Famílias (POST /family/get_family_leaderboard)
│       └── Desempenho e Pontuação Semanal/Mensal de Famílias
│
├── 4. SUPER ANALYTICS & DESEMPENHO DO STREAMER
│   ├── Estatísticas de Duração de Stream (POST user_statistic/get_stream_duration_statistic)
│   ├── Estatísticas de Espectadores (POST user_statistic/get_viewer_statistic)
│   ├── Estatísticas de Seguidores Conquistados (POST user_statistic/get_follower_statistic)
│   ├── Estatísticas Gerais de Performance (POST user_statistic/get_performance_statistic)
│   └── Filtro Temporal Unificado (0: DAY, 1: WEEK, 2: MONTH)
│
├── 5. PERFIL E CONFIGURAÇÕES DA CONTA
│   ├── Perfil Próprio Completo (POST users/own_profile)
│   │   ├── Saldo de Moedas (coins)
│   │   ├── Saldo de Diamantes (diamonds)
│   │   ├── Nível de Streamer / Usuário (level, xp)
│   │   ├── Status VIP e Distintivos (vip_badge, badges)
│   │   └── Status de Revendedor / Reseller
│   ├── Edição de Perfil (POST users/update)
│   │   ├── Nome de Exibição, Bio, Data de Nascimento, Gênero
│   │   └── Upload de Foto de Perfil (POST users/image/upload)
│   ├── Username Especial Único (Unique Username)
│   │   ├── Verificação de Disponibilidade (POST user/check_special_username_availability)
│   │   ├── Definição de Nome Único (POST user/set_special_username)
│   │   └── Alternância de Visibilidade (POST user/toggle_special_username_visibility)
│   ├── Visualizadores do Perfil (POST user/profile_viewers)
│   ├── Top Doadores do Usuário (POST user/top_gifters)
│   ├── Configurações de Privacidade e VIP
│   │   ├── Ocultar Moedas Enviadas (POST user/set_coins_sent_hidden)
│   │   ├── Ocultar Diamantes Recebidos (POST user/set_vip_diamonds_received_hidden)
│   │   ├── Ocultar Seguidores e Seguindo (POST user/set_follower_and_following_hidden)
│   │   ├── Ocultar Localização (POST user/set_location_hidden)
│   │   ├── Ocultar Status Online (POST user/set_online_status_hidden)
│   │   ├── Entrar em Lives em Modo Incógnito (POST user/set_public_stream_incognito)
│   │   ├── Ocultar Visualização de Perfis (POST user/set_hidden_profile_viewer)
│   │   ├── Ocultar Status VIP (POST user/set_vip_status_hidden)
│   │   └── Ativar Anúncio de Super Gift no Chat (POST user/set_super_gift_announcement_option)
│   └── Exclusão Definitiva de Conta (POST users/profile/delete)
│
├── 6. TRANSMISSÕES AO VIVO (LIVESTREAMS)
│   ├── Iniciar / Finalizar Transmissão (POST livestream/start & livestream/finish)
│   ├── Transmissão Privada por Convite / Ingresso de Presente (POST livestream/make_private & accept_private)
│   ├── Batalhas PK (1v1 e Team 4-Person PK)
│   │   ├── Convite de PK (livestream/pk/invitation/send, accept, reject, cancel)
│   │   ├── Início e Término de Guerra PK (livestream/pk/war/start & pk/end)
│   │   └── Top Doadores da Batalha PK (livestream/pk/team/top_gifters)
│   ├── Moderação de Transmissão
│   │   ├── Adicionar / Remover Moderadores (livestream/mod & unmod)
│   │   ├── Mutar / Desmutar Usuário no Chat (livestream/chat/mute & unmute)
│   │   └── Expulsar Usuário da Live (livestream/kick & unkick)
│   ├── Chat da Live e Tradução em Tempo Real (livestream/chat/send_text_message & translate_message)
│   ├── Lista de Espectadores Ativos (livestream/active_viewers_and_top_gifters)
│   └── Configuração de Mídia (Câmera On/Off, Microfone Mute, Background Mode)
│
├── 7. CHAMADAS PRIVADAS 1-ON-1
│   ├── Iniciar Chamada Privada (POST private_call/start)
│   ├── Aceitar / Rejeitar / Cancelar / Finalizar Chamada
│   ├── Bloquear Notificações Indesejadas de Chamada (private_call/prevent_notification)
│   └── Envio de Presentes Durante a Chamada (private_call/send_gift)
│
├── 8. MENSAGENS E INBOX
│   ├── Conversas 1-on-1 (POST conversation/messages & send_text_message)
│   ├── Envio de Mensagens de Áudio (POST conversation/send_audio_message)
│   ├── Mídia Premium / Álbum Pago com Bloqueio de Presente (POST conversation/premium_media_album/unlock)
│   ├── Fixar / Desafixar Conversa (POST conversation/pin & unpin)
│   ├── Status Online em Tempo Real dos Contatos (conversation/inbox_user_online_statuses)
│   └── Suporte ao Cliente / Abertura de Tickets (conversation/create_ticket & get_support_tickets)
│
├── 9. FAMÍLIAS & COMUNIDADE
│   ├── Criação e Perfil de Família (POST family/create & family/profile)
│   ├── Lista de Membros e Gestão de Moderadores (family/managers, add, remove)
│   ├── Convidar Membros / Solicitações de Ingresso (family/send_invitation & send_join_invitation)
│   ├── Chat Exclusivo da Família e Mensagens Fixadas (conversation/family_conversation_message_pin)
│   └── Transferência de Titularidade ou Dissolução (family/transfer_family & disband)
│
└── 10. VIP STORE & INVENTÁRIO
    ├── Catálogo de Itens da Loja VIP (POST user/vip_store/items)
    ├── Compra de Itens e Efeitos de Entrada (POST user/vip_store/purchase)
    ├── Descongelamento / Remoção de Ban via Moedas VIP (POST user/vip_store/spend_remove_freeze_ban)
    └── Inventário de Itens (ItemBagApiService: get_user_item_bag & use_item)
```

---

## 2. Matriz de Dependência e Fontes de Dados

| Módulo | Base URL Primária | Mecanismo de Dados | Requer Auth |
| :--- | :--- | :--- | :---: |
| **Auth** | `api.sprlv-api.com` | REST JSON (POST) | Opcional |
| **Super Billing** | `api.sprlv-api.com` | REST JSON (POST) + Secure Webview | Sim (Token) |
| **Super Ranking** | `api.sprlv-api.com` | REST JSON (POST) | Sim (Token) |
| **Super Analytics**| `api.sprlv-api.com` | REST JSON (POST) | Sim (Token) |
| **Live & WebRTC** | Agora RTC SDK / WebRTC | REST + WebRTC Media Stream | Sim (Token) |
| **Chat & Sockets** | Centrifugo WebSocket | WSS Protocol | Sim (Centrifugo Token) |
