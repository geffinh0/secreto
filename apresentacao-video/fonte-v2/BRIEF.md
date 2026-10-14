# Brief compartilhado — vídeo de apresentação do app "Atila's Client"

## Produto (fatos confirmados no código-fonte; NÃO invente nada além disto)
- Nome: Atila's Client (cabeçalho do app mostra "Super Moderator"). Acesso do cliente: atilaclient.tech (web app / PWA, usado no celular).
- O que faz: moderação automática de lives do SuperLive. Uma conta "robô" entra na live, lê o chat em tempo real e aplica as regras da criadora.
- Funções reais: (1) Moderação: lista de palavras para SILENCIAR (mute) e para BANIR (kick), palavra inteira sem diferenciar maiúsculas, "Adicionar várias", "Testar regras", ativar/desativar. (2) Mensagens automáticas: fila de mensagens enviadas em ordem e em repetição durante a live, intervalo mínimo 10 s, arrastar para reordenar. (3) Robô: conectar conta do robô (e-mail/senha, celular por SMS ou código por e-mail), informar ID da live ou buscar pelo ID público da streamer; "Streamer favorita": o robô entra e modera sozinho quando ela abrir live. A streamer precisa adicionar o robô como moderador. (4) Painel com status (Ao vivo / Conectado / Desconectado), resumo das regras e da fila; (5) Estatísticas; (6) Configurações; (7) Login/cadastro.
- Moderação roda no servidor: fechar a aba não interrompe o robô.
- NÃO afirmar: métricas, números de usuários, depoimentos, IA, integrações extras, preços.
## Identidade visual real do app ("Herbário da raposa", Art Nouveau, tema claro)
- Papel #F4ECDC, papel claro #FBF6EA, sálvia #E3E8D6, tinta verde-floresta #1F3A2E, terracota (ação) #A8461F, ouro #9A7B2F / #D2B568 sobre floresta, sálvia #6F8A6A, linhas #CFC3A8.
- Tipografia: Fraunces (títulos serifados suaves, Bold/SemiBold) + Source Sans 3 (corpo).
- Mascote: uma raposa ilustrada (assets/fox/*.webp: fox_back, fox_garden_sitting, fox_head_calm, fox_head_laugh, fox_lookback, fox_medallion_calm, fox_medallion_smile, fox_sleeping).
- Navegação mobile: barra inferior Painel / Moderação / Robô / Mais (Mensagens automáticas, Estatísticas, Configurações).
## Formato e restrições
- Vídeo VERTICAL 9:16, 1080x1920, 30 fps, para celular (Reels/Stories/WhatsApp).
- Narração em português do Brasil (TTS Gemini). Duração livre, enxuta (estimativa 40–60 s).
- Ferramenta de produção: HyperFrames (composições HTML + GSAP renderizadas em MP4 com ffmpeg). Telas reais do app capturadas via Flutter Web em viewport de celular; elementos de apresentação animados em HTML/CSS/SVG/Canvas.
- Nunca mencionar no vídeo nem na documentação ao cliente: arquivos .bat, scripts, servidores locais, Docker, deploy, backend, comandos. Só o endereço atilaclient.tech como destino.
- Áudio: apenas material próprio/sintetizado (trilha e SFX sintetizados por código) — sem material com direitos autorais.
