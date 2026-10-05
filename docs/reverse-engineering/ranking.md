# ENGENHARIA REVERSA DO SISTEMA DE RANKING: SUPER RANKING

Este documento detalha o funcionamento técnico e arquitetura dos rankings identificados no aplicativo SuperLive.

---

## 1. Classificação dos Rankings

O aplicativo opera 3 pilares de ranqueamento:

1. **Ranking de Streamers (`POST /leaderboard`):**
   - Ordena criadores de conteúdo pelo volume de diamantes recebidos.
   - Fornece o objeto `own_user` com a posição exata da conta do usuário logado, pontos acumulados e distância.
2. **Ranking de Gifters (`POST /gifters_leaderboard`):**
   - Ordena os usuários e apoiadores pelo volume de moedas presenteadas.
   - Possui controle de privacidade (modo anônimo).
3. **Ranking de Famílias (`POST /family/get_family_leaderboard`):**
   - Ordena clãs/famílias pelo somatório de atividade e presentes trocados pelos seus membros.

---

## 2. Parâmetros de Filtro do Ranking

A chamada `APIUserLeaderBoardRequest` aceita:

### 2.1. Tipos Temporais (`leaderboard_type`)
- `0`: **ALL_TIME** (Geral histórico)
- `1`: **DAILY** (Diário — reiniciado à 00:00 UTC)
- `2`: **WEEKLY** (Semanal — reiniciado toda segunda-feira)

### 2.2. Filtro Geográfico (`iso_codes`)
- Lista de códigos de país ISO-3166-1 alpha-2 (e.g. `["BR"]`, `["US"]`, `["TR"]`).
- Quando enviada lista vazia `[]`, o backend retorna a tabela global (Global Leaderboard).

---

## 3. Estrutura do Usuário Ranqueado (`APILeaderboardUser`)

Cada entrada na lista de ranking contém:
- `rank`: Posição ordinal (1º, 2º, 3º, ...)
- `points`: Pontuação acumulada
- `user_id`: Identificador único
- `nickname`: Nome de exibição
- `avatar`: URL da foto de perfil
- `level`: Nível de conta
- `vip_level` / `vip_badge`: Distintivo VIP se ativo
- `is_live`: Booleano informando se o criador está transmitindo no momento
- `stream_id`: Identificador da transmissão caso esteja ao vivo

---

## 4. Recursos de Privacidade Integrados

- **Modo Anônimo de Doador:** O usuário pode chamar `POST user/set_gifters_leaderboard_anonymous` com `is_anonymous = true` para ocultar sua identidade no ranking de gifters.
- **Alternar Visibilidade:** `POST user/toggle_gifter_visibility` permite alternar se seus presentes aparecem nos rankings de top doadores de salas de transmissão específicas.
