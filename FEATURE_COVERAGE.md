# MATRIZ DE COBERTURA DE FUNCIONALIDADES — SUPER CLIENT

Esta matriz correlaciona cada funcionalidade identificada no aplicativo original (SuperLive v2.31.0) com sua respectiva API, estado de implementação e validação de testes no Super Client.

---

| Funcionalidade | Encontrada no APK | API Identificada | Implementada no Web | Implementada no Flutter | Testada |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Login por Email e Senha** | ✓ | `POST user/signup/email_signin` | ✓ | ✓ | ✓ |
| **Login por SMS / Telefone** | ✓ | `POST user/signup/auth_phone` | ✓ | ✓ | ✓ |
| **Login Social Google/OAuth** | ✓ | `POST user/signup/google` | ✓ | ✓ | ✓ |
| **Recuperação de Senha / OTP** | ✓ | `POST user/signup/otp` | ✓ | ✓ | ✓ |
| **Logout de Sessão** | ✓ | `POST user/logout` | ✓ | ✓ | ✓ |
| **Perfil Próprio (Moedas, Nível, VIP)**| ✓ | `POST users/own_profile` | ✓ | ✓ | ✓ |
| **Edição de Perfil e Avatar** | ✓ | `POST users/update` | ✓ | ✓ | ✓ |
| **Super Billing: Ganhos Detalhados** | ✓ | `POST user_statistic/get_earning_statistic` | ✓ | ✓ | ✓ |
| **Super Billing: Divisão por Canal** | ✓ | `APIStreamerEarningStatistic` | ✓ | ✓ | ✓ |
| **Super Billing: Tabela de Saque (Payout)**| ✓ | `POST user_statistic/get_payout_chart` | ✓ | ✓ | ✓ |
| **Super Billing: Histórico de Compras**| ✓ | `POST user/purchase_history` | ✓ | ✓ | ✓ |
| **Super Billing: Resgate / Cash-Out** | ✓ | `urls.cash_out` (Secure Webview) | ✓ | ✓ | ✓ |
| **Super Billing: Calculadora de Câmbio**| ✓ | `exchange_rate` formula | ✓ | ✓ | ✓ |
| **Super Ranking: Streamers** | ✓ | `POST leaderboard` | ✓ | ✓ | ✓ |
| **Super Ranking: Gifters (Apoiadores)**| ✓ | `POST gifters_leaderboard` | ✓ | ✓ | ✓ |
| **Super Ranking: Famílias** | ✓ | `POST family/get_family_leaderboard` | ✓ | ✓ | ✓ |
| **Super Ranking: Filtro por País (ISO)**| ✓ | `iso_codes` param | ✓ | ✓ | ✓ |
| **Super Ranking: Modo Anônimo** | ✓ | `POST user/set_gifters_leaderboard_anonymous` | ✓ | ✓ | ✓ |
| **Super Analytics: Horas de Stream** | ✓ | `POST user_statistic/get_stream_duration_statistic` | ✓ | ✓ | ✓ |
| **Super Analytics: Espectadores** | ✓ | `POST user_statistic/get_viewer_statistic` | ✓ | ✓ | ✓ |
| **Super Analytics: Seguidores** | ✓ | `POST user_statistic/get_follower_statistic` | ✓ | ✓ | ✓ |
| **Visualizadores do Perfil** | ✓ | `POST user/profile_viewers` | ✓ | ✓ | ✓ |
| **Top Doadores do Usuário** | ✓ | `POST user/top_gifters` | ✓ | ✓ | ✓ |
| **Controles de Privacidade VIP** | ✓ | `UserActionsApiService` (8 switches) | ✓ | ✓ | ✓ |
| **Transmissão ao Vivo (Start/Finish)** | ✓ | `LiveStreamApiService` | ✓ | ✓ | ✓ |
| **Batalhas PK (1v1 & 4-Person PK)** | ✓ | `livestream/pk/*` | ✓ | ✓ | ✓ |
| **Chamadas Privadas 1-on-1** | ✓ | `PrivateCallApiService` | ✓ | ✓ | ✓ |
| **Mensagens e Álbuns Pagos** | ✓ | `ConversationApiService` | ✓ | ✓ | ✓ |
| **Loja VIP e Efeitos** | ✓ | `VipStoreApiService` | ✓ | ✓ | ✓ |
| **Exportação de Dados (CSV / JSON)** | ✓ | Módulo Super Client | ✓ | ✓ | ✓ |
