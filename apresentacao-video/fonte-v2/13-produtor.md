# Plano de produção: vídeo "Atila's Client" (9:16, 40–60 s)

## Etapas e entregáveis
- **A. Análise:** validar cada fato do brief contra o app; fixar lista de afirmações permitidas. Entrega: matriz fato → fonte.
- **B. Exploração:** percorrer Painel, Moderação, Mensagens automáticas e Robô em viewport de celular. Entrega: roteiro de capturas por estado.
- **C. Direção de arte:** paleta Herbário, Fraunces + Source Sans 3, raposa como guia visual. Entrega: guia de estilo de uma página.
- **D. Roteiro:** 6–7 cenas, narração em pt-BR, tempo por cena. Entrega: roteiro e texto de narração.
- **E. Materiais:** capturas tratadas, assets da raposa, áudio sintetizado (narração, trilha, SFX). Entrega: pasta de materiais aprovada.
- **F. Produção:** uma composição HTML/GSAP por cena, pré-visualizada isoladamente. Entrega: cenas validadas.
- **G. Montagem:** sincronia cena/narração e transições. Entrega: timeline completa.
- **H. Finalização:** render final e áudio normalizado. Entrega: MP4.
- **I. QA:** checklist técnico e de conteúdo. Entrega: relatório de aprovação.

## Riscos e mitigação
- **Captura do app real** (login, dados de terceiros, instabilidade do Flutter Web): usar conta de demonstração, mascarar nomes e IDs, capturar em lote com estados reserva.
- **Render longo ou falha no encode:** renderizar por cena, testar trecho curto antes do render completo.
- **TTS Gemini** (pronúncia de "Atila's", ritmo, cortes): gerar por frase, revisar pronúncia, ajustar pontuação.
- **Legibilidade no celular:** testar textos em 390 px, definir tamanho mínimo.
- **Direitos autorais do áudio:** só material sintetizado por código, com origem registrada.
- **Promessas indevidas:** revisão de todo texto contra a matriz da etapa A.

## Estrutura de pastas
```
atila-video/
  01-briefing/
  02-capturas/        (brutas, tratadas)
  03-direcao-arte/
  04-roteiro/
  05-assets/          (raposa, fontes, paleta)
  06-audio/           (narracao, trilha, sfx)
  07-cenas/           (composicoes)
  08-render/          (previas, final)
  09-decisoes/
  10-qa/
```

## Checklist de entrega
- [ ] MP4 H.264, yuv420p, 1080x1920, 30 fps, áudio AAC
- [ ] Duração entre 40 e 60 s
- [ ] Narração em pt-BR, sem termos técnicos
- [ ] Único destino citado: atilaclient.tech
- [ ] Sem métricas, números, depoimentos, IA ou preços
- [ ] Capturas sem dados pessoais
- [ ] Áudio 100% sintetizado ou próprio
- [ ] Licença de fontes e da raposa confirmada
- [ ] Decisões registradas em 09-decisoes
