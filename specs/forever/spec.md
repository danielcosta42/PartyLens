# PartyLens no WoW: Forever — especificação

Issue: danielcosta42/PartyLens#1. Decisões do dono em 2026-11-08.

## Contexto

O PartyLens nasceu no TBC Anniversary (interface 20506): radar de grupos que junta o canal LookingForGroup e o
Group Finder num painel, com uma malha própria entre usuários (troca de camada, world bosses, reputação). No
**WoW: Forever** (progressão da Blizzard, motor retail, interface **16001**, cliente 1.60.1.x) quase toda a rede dele
morre e várias APIs mudam. Fatos medidos no jogo (backoffice CehulNet, build 70862) e no próprio cliente:

- Mensagem de addon: GUILD, PARTY/RAID e WHISPER funcionam de timer. **SAY e YELL são recusados**
  (`InvalidChatType`), e **canal criado não entrega**. A lista de membros de um canal ainda se lê: é o diretório da
  LibChehulMesh v5+ (ver `danielcosta42/chehulnet` AGENTS.md).
- **Convite, chat visível, /who e busca no LFG exigem evento de hardware** (clique). Mensagem de addon, não.
- Nomes são **"Nome Sobrenome"**: `UnitName("player")` dá só o primeiro nome; o remetente de todo evento chega com
  o sobrenome. Whisper vai para "Nome Sobrenome".
- **Valores secretos**: payload de chat e identidade de unidade podem chegar secretos (lockdown/restrições);
  comparar, concatenar ou indexar um segredo dá erro. `issecretvalue(v)` diz.
- **O Group Finder da Blizzard não carrega no Forever** (`Blizzard_GroupFinder.toc`: `## ExcludeLoadGameType:
  camelot`). Funções clássicas do `C_LFGList` também faltam.
- APIs que sumiram/mudaram: abas de talento (`GetNumTalentTabs`), `GetMouseFocus` (→ `GetMouseFoci`), combat log
  para addons. `SendChatMessage` → `C_ChatInfo.SendChatMessage` (com clique).

## Decisões

1. **Só Forever.** TOC só com `16001`. A versão atual (0.33.x) continua no CurseForge para quem joga Anniversary.
2. **Núcleo (sempre):** radar de grupos (canal LookingForGroup + listagens da rede ChehulNet), whisper e convite em
   um clique, anunciar grupo (post visível no LFG por clique + listagem na rede), /who por clique.
3. **Extras:** troca de camada (pedido pela rede a um beacon de plantão, convite por clique do beacon),
   Autopilot em **modo sugestão** (ele monta, você confirma cada convite e whisper), invocação (bruxo).
4. **Saem:** reputação, world bosses, world buffs + NovaWorldBuffs, a ferramenta de Group Finder, NetDiag (o
   backoffice CehulNet cobre), o convite automático do beacon antigo (mutar sons, esconder party frames, engolir erros), comandos de dev.
5. **Visual novo**, mais impactante: identidade própria, transições, ações animadas (ver plan.md §5).
6. **Entrega única**: um PR, testado no jogo no fim. Publicação só com o ok do dono.

## Requisitos

### Funcionais
- R1 O addon carrega no Forever sem erro de Lua; todos os módulos removidos saem do TOC.
- R2 Radar: lê `CHAT_MSG_CHANNEL` do canal de LFG (detecção por nome, tolerante a idioma), reconhece LFG/LFM,
  papéis, atividade (masmorras/raides do Forever, incluindo as novas) e o post assinado de outro usuário.
  Só é grupo o que tem sinal forte (LFM/LFxM, "LF" + papel, forming, vagas, "N more") ou um "need/precisa" junto
  de papel, atividade ou quest; "more"/"mais" sozinhos e anúncio de guilda (tag `<Guilda>`, "guild", "recruiting")
  sem atividade nomeada não entram (visto no teste do dono, 2026-11-08).
- R3 Radar: recebe e mostra listagens de outros usuários pela rede (prefixo `PartyLens`), que chegam por GUILD,
  grupo e o diretório da ChehulNet (`Mesh:Realm`), com repasse limitado para alcançar a facção.
- R4 Cada grupo mostra papéis que faltam, preenchimento, frescor, atividade, líder (cor da classe) e mensagem;
  ações: Whisper (mensagem montada a partir dos seus papéis), Convidar (para quem procura grupo), Who, Bloquear.
- R5 Filtros: papel que eu faço, tipo (LFG/LFM), atividade, busca por texto, só abertos, esconder spam.
- R6 Anunciar: monta o post a partir de atividade, papéis que faltam e comentário; manda no canal de LFG por
  clique e publica a listagem na rede.
- R7 Autopilot (sugestão): com uma listagem ativa, sugere jogadores do radar que fecham os papéis que faltam, com
  botões Convidar/Whisper; nada sai sozinho.
- R8 Camadas (revisto no teste do dono, 2026-11-08): a página mostra **camadas, não pessoas**, e só as da zona em
  que o jogador está, como uma pilha de placas isométricas. Cada camada leva o número que o próprio jogo dá àquela
  cópia da zona (o zoneUID do GUID das criaturas), igual para todos, visitada ou não. Cada camada traz a população (nós ChehulNet ouvidos nela), quantos beacons estão de plantão, grupos se formando e as
  **novidades** dela (camada nova, beacon entrou/saiu, beacon trouxe alguém, população subiu/caiu, grupo começou a se
  formar). "Ir para esta camada" pede a um beacon dela, escolhido pelo addon (mais hops servidos primeiro); se ele
  recusa ou não responde em 40 s, o próximo é pedido sozinho. Nomes só aparecem para o beacon (quem ele convida).
  **Camadas são por zona no Forever** (medido em 2026-11-08 pelo log de HELLOs do backoffice: no mesmo intervalo,
  dez jogadores aleatórios em Thunder Bluff estavam todos na mesma cópia e oito membros da guilda em The Barrens em
  oito cópias diferentes; com camadas por continente as duas zonas teriam o mesmo número). No grupo do beacon, o
  jogo troca a camada quando o jogador clica no aviso de troca, ou sozinho em uns 5 minutos (confirmado pelo dono).
- R12 Beacon gamificado, **ligado por padrão** (opt-out em Ajustes e na página): quem está no mundo aberto, fora de
  combate, não ausente e sozinho (ou só com quem ele trouxe) fica de plantão e anuncia isso na presença. O pedido
  chega como um aviso fora da janela com Convidar/Recusar (e uma tecla de atalho "convidar o próximo"); o convite é
  sempre um clique (o jogo exige). Cada pessoa que **chega** na camada (o cliente dela avisa; uma vez por pessoa
  por dia) conta um hop servido; os hops
  dão patentes (Faísca, Lanterna, Farol, Luz-guia, Estrela do norte, Lenda), com barra de progresso, "+1" animado e
  aviso de patente nova. A contagem vai na presença e pesa na escolha do beacon.
- R9 Invocação: lista quem do grupo precisa de summon e anuncia por clique.
- R10 /who por clique completa nível/classe de quem não usa o addon.
- R11 Integração ChehulNet: tag `pl` no HELLO, alertas do operador com a identidade do PartyLens, DIAG `pl.*`,
  `layerProvider` com a camada detectada.

### Não funcionais
- N1 Nenhum handler de evento quebra com valor secreto (guarda na entrada).
- N2 "Nome Sobrenome" em toda chave, comparação, whisper e convite; o próprio cliente se reconhece.
- N3 Nenhum convite, whisper, chat visível, /who, busca ou uninvite sai de timer ou de evento: só de clique.
- N4 Nenhum taint: nada substitui método de frame da Blizzard.
- N5 Tráfego de rede limitado (coalesce, repasse com limite de saltos, nada em instância/lockdown).
- N6 Animações com propósito e um ajuste para desligá-las.
- N7 Harnesses em `tools/*.lua` (luajit) e luacheck bloqueantes no CI; lock da lib ChehulNet no CI.

## Fora de escopo
- Suporte ao Anniversary nesta linha.
- Ponte entre facções (Battle.net).
- Reputação, world bosses, world buffs.
