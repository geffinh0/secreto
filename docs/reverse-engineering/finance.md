# ENGENHARIA REVERSA DO SISTEMA FINANCEIRO: SUPER BILLING

Este documento descreve toda a arquitetura da economia virtual, monetização e resgate de valores identificada no aplicativo SuperLive (`com.superlive.liveapp` v2.31.0).

---

## 1. O Modelo Econômico Dual: Moedas vs Diamantes

O ecossistema financeiro do SuperLive opera através de um modelo dual bem delineado:

```text
[ DINHEIRO FIAT ]
       │  (Compra via Google Play ou Stripe Multi-payment Gateway)
       ▼
 [ MOEDAS (Coins) ] ── (Consumidas pelo usuário comum)
       │
       ├─► Envio de Presentes em Lives Públicas
       ├─► Pagamento de Entrada em Lives Privadas
       ├─► Minutos e Presentes de Chamadas Privadas 1-on-1
       ├─► Desbloqueio de Álbuns de Mídia Premium no Chat
       └─► Compras na Loja VIP (Efeitos, Molduras)
       │
       ▼ (Convertido pela plataforma)
[ DIAMANTES (Diamonds) ] ── (Recebidos pelo Streamer / Criador)
       │
       ├─► public_stream_earning
       ├─► private_stream_earning
       ├─► private_call_earning
       └─► conversation_earning
       │
       ▼ (Resgate via Cash-Out com taxa de câmbio)
[ DINHEIRO FIAT / DÓLAR USD ]
```

---

## 2. Métricas de Ganhos (`APIStreamerEarningStatistic`)

A API `POST user_statistic/get_earning_statistic` expõe a partição de receitas do criador com exatidão:

1. **`public_stream_earning`**: Diamantes gerados por presentes enviados pelos espectadores durante lives abertas.
2. **`private_stream_earning`**: Diamantes gerados pelo custo de ingresso ou presentes em transmissões privadas.
3. **`private_call_earning`**: Diamantes provenientes de tarifação por tempo e presentes em chamadas de vídeo 1-on-1.
4. **`conversation_earning`**: Diamantes obtidos via desbloqueio de mídias pagas ou presentes enviados nas mensagens de chat.
5. **`total_earning`**: Soma total de diamantes brutos conquistados no período.
6. **`salary`**: Bônus monetário concedido diretamente pela plataforma para streamers contratados ou que cumpriram metas de horas.
7. **`agency_earning`**: Repasses recebidos ou descontados referentes à agência de streamers vinculada.
8. **`decreased_earning`**: Deduções financeiras (penalidades por infração de termos, estornos de cartão ou correções).
9. **`previous_earning`**: Total de diamantes do período anterior homólogo (usado para cálculo de crescimento ou queda).
10. **`percentages`**: Distribuição percentual de receita de cada canal:
    - `public_stream_earning`: % sobre o total
    - `private_stream_earning`: % sobre o total
    - `private_call_earning`: % sobre o total
    - `conversation_earning`: % sobre o total

---

## 3. Fórmula e Tabela de Saque (Payout Chart)

A rota `POST user_statistic/get_payout_chart` fornece a taxa de câmbio vigente e os limites de saque autorizados:

### Fórmula de Conversão
$$\text{Valor em Dólar (USD)} = \frac{\text{Diamantes}}{\text{exchange\_rate}}$$
$$\text{Diamantes Necessários} = \text{Dólar} \times \text{exchange\_rate}$$

### Exemplo Base Encontrado:
- Se `exchange_rate = 210`:
  - 2.100 Diamantes = **$10,00 USD**
  - 21.000 Diamantes = **$100,00 USD**
  - 105.000 Diamantes = **$500,00 USD**
  - 210.000 Diamantes = **$1.000,00 USD**

### Faixas de Resgate (`diamonds` array)
A API retorna os limites pré-fixados de resgate disponíveis para seleção do streamer.

---

## 4. Fluxo de Saque / Cash-Out

No aplicativo original, o resgate de saldo acumulado não é executado por um endpoint REST puro exposto diretamente no app nativo por razões de conformidade financeira e KYC (Know Your Customer).

Em vez disso:
1. O aplicativo consulta `POST user/settings`.
2. O campo `urls.cash_out` retorna uma URL segura com parâmetro de sessão.
3. O app abre um componente interno `HybridWebViewFragment` (utilizando interface JavaScript `APIJSI`).
4. Nessa interface web segura do provedor financeiro, o streamer seleciona a conta bancária/chave internacional (e.g. Payoneer, Transferência Internacional ou carteira local) e formaliza a solicitação.
5. O Super Client integra esse fluxo permitindo a abertura direta e autenticada da URL oficial de saque da conta do usuário.

---

## 5. Histórico de Compras de Moedas (`user/purchase_history`)

O usuário possui visibilidade de compras de moedas divididas em 2 períodos:
- `last_week_purchases`: Compras realizadas nos últimos 7 dias. Cada item contém `coins` e `timestamp`.
- `before_last_week_purchases`: Compras efetuadas em períodos anteriores.
- `last_week_coins`: Soma total de moedas adquiridas nos últimos 7 dias.

---

## 6. Diferenciais do Módulo SUPER BILLING

O **Super Billing** não se limita a replicar os números da API. Ele consolida:
1. **Saldo Disponível vs Estimado em Dólar:** Cálculo instantâneo do saldo em USD com base no `exchange_rate` atual da API.
2. **Gráfico de Evolução e Composição:** Visualização gráfica da distribuição de renda (Live Pública, Live Privada, Chamadas, Mensagens, Salário).
3. **Simulador de Resgate:** O streamer pode digitar qualquer valor de diamantes e simular o valor líquido em USD ou BRL.
4. **Comparativo de Crescimento:** Cálculo automático de variação percentual de ganhos em relação ao período anterior (`total_earning` vs `previous_earning`).
5. **Exportação de Dados:** Exportação de extrato financeiro em JSON e CSV para fins contábeis e declaração fiscal do streamer.
