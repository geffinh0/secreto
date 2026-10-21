# Operação do dia a dia

## O painel administrativo (`/admin`)
| Aba | O que faz |
|---|---|
| **Agências** | Cria agências, mostra o **código de cadastro**, liga/desliga novos cadastros, gera código novo. No topo, o bloco **Capacidade** (abaixo). |
| **Usuários** | Lista as criadoras, o robô de cada uma, a agência e o estado (moderando, esperando live, parado). **Liberar troca de senha** gera uma senha provisória de uso único. |
| **Sessões** | Quais lives estão sendo moderadas agora e o estado de cada conexão. |

## Capacidade (aba Agências)
- Selo no topo: **Tudo normal**, **Sem vagas: adicione um IP**, **Capacidade no limite** ou **Um IP não está respondendo**.
- **Vagas livres**: criadoras que ainda cabem (7 por IP). Com 0, o cadastro novo mostra "estamos sem vagas".
- Uma linha por IP: quantas criadoras (de 7), robôs ligados e **Rede ok / Sem resposta**.

### Adicionar um IP (liberar mais 7 vagas)
1. Contrate um IP fixo brasileiro no fornecedor e copie o endereço no formato
   `socks5h://usuario:senha@host:porta`. Se a senha tiver `@ : / # %`, troque por `%40 %3A %2F %23 %25`.
2. No painel: **Agências → Capacidade → Adicionar IP**, cole o endereço, **Testar e adicionar**.
3. O sistema testa a conexão com o SuperLive. Se não conectar, ele explica e **não** adiciona. Se o IP não
   for do Brasil, adiciona mas avisa.
4. As vagas aparecem na hora. Nada é reiniciado.

Regras: o IP vai sempre para o **fim** da lista e **não se remove nem se reordena**, porque cada criadora
fica presa ao IP onde conectou o robô (o SuperLive amarra o token ao IP).

### Quando "Um IP não está respondendo"
Quase sempre é o proxy: plano vencido, senha trocada ou fornecedor fora do ar. Veja o painel do
fornecedor. As criadoras daquele IP ficam sem moderação até ele voltar; o sistema retoma sozinho.

## Cadastro de uma criadora
1. Você cria a agência e passa o **código** a ela.
2. A criadora abre o portal, **cria a conta** com o código e conecta o robô (uma conta de SuperLive que
   será o moderador) informando o perfil da streamer a acompanhar.
3. O sistema atribui o IP com mais folga. Ela configura palavras proibidas e mensagens automáticas.

Para esquecimento de senha, use **Usuários → Liberar troca de senha**.

## Ranking de diamantes por live
Cada criadora pode ligar, na tela **Estatísticas**, "Guardar o ranking quando a live acabar". Ao fim de cada
live com presentes, o sistema guarda quem enviou quantos diamantes **só naquela live** (as 30 últimas lives),
com botão de copiar no formato `nome: enviou N diamantes`. Não posta no chat da live. Com a segunda opção
("Enviar o ranking por mensagem privada"), cerca de 1 minuto após o fim o robô manda o ranking nas mensagens
privadas do SuperLive para a streamer; nunca gasta moedas (se a primeira mensagem custar moedas, nada é enviado
e o app mostra o motivo).
Os valores contam os presentes que o robô viu enquanto estava na live (se ele entrou no meio, o começo não entra).

## Backup, restauração e atualização
```bash
./backup.sh                                  # copia o banco para backups/ (mantém os 30 últimos)
./restore.sh backups/atila-AAAAMMDD-HHMMSS.db   # volta um backup (faz outro backup antes)
./update.sh                                  # nova versão: backup + build + troca; recusa se houver live em moderação
FORCE=1 ./update.sh                          # mesmo assim (derruba sessões; as criadoras religam o robô)
```
Para atualizar: substitua os arquivos do projeto pela versão nova **mantendo `.env`, `secrets/` e `backups/`**
e rode `./update.sh`. Quem está com o app aberto vê um aviso de nova versão.

## Ajustes (no `.env`, depois `docker compose up -d`)
| Variável | Padrão | Para quê |
|---|---|---|
| `SM_SESSIONS_PER_EGRESS` | 7 | Criadoras por IP. Medido: 7 mantém mensagens em ~5 s; 14 já fica no limite. |
| `SM_ALLOW_REGISTRATION` | 1 | 0 fecha todo cadastro novo. |
| `SM_MAX_SESSIONS` | 0 | Teto global de robôs (0 = sem teto). |
| `SUPERLIVE_SESSION_POLL_S` | 20 | Intervalo do "já entrou ao vivo?" por criadora. |

## Logs
`docker compose logs -f backend` (ou `--since 1h`). Procure por "falhas de rede" (IP com problema) e "429" (limite do SuperLive).
