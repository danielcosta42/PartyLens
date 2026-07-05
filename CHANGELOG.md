# Changelog

Todas as mudanças relevantes do PartyLens. Formato baseado em
[Keep a Changelog](https://keepachangelog.com/), versionamento [SemVer](https://semver.org/).

## [Unreleased]

## [0.18.3]

- **Contador "PartyLens na rede" do Autopilot deixa de ficar travado em zero**: ele
  contava só usuários que estavam **anunciando um LFG naquele instante** (autopilot
  armado do outro lado gera uma msg Comm) — quem só estava com o addon aberto não
  contava, apesar do mesh já conhecer a pessoa (ela aparecia como "nó" na rede de
  layer). Agora o contador reflete a **presença viva do mesh**: conta os peers
  ChehulNet que rodam PartyLens (tag `pl`, anunciada automática e realm-wide por todo
  usuário) unidos aos que estão anunciando, sem duplicar por nome — a mesma sensação
  de rede viva do stat "Nodes online".
- **Toda a comunicação do Autopilot passa pelo mesh (verificado)**: o broadcast de
  intenção (`Comm.Broadcast`) já sai por Guild + Proximity + Realm; o recebimento de
  candidatos chega por `Mesh:Register("PartyLens")` + varredura de chat; o ranqueamento
  lê `partyLens.entries` (alimentado pelo mesh). Convites e sussurros de recrutamento
  seguem sendo ação direta do jogador, como devem ser.
- Rótulo do contador ajustado de "PartyLens por perto" para "PartyLens na rede" (agora
  reflete guild + proximidade + realm, não só quem está por perto).

## [0.18.2]

- **Ponto de beacon nos chips certo**: a marca de "beacon no ar" nos chips agora usa
  o MESMO número (ordinal NWB-aware) do stat "Layers covered" — antes casava pelo
  zoneUID cru + filtro de mapa, então um beacon de outro nó (com zoneUID diferente pra
  a mesma layer do servidor, ou em outra zona) era contado no stat mas não pintava o
  ponto no chip. Agora bate.

## [0.18.1]

- **Seletor de layer alinhado ao display**: os chips agora usam a MESMA numeração do
  "Sua layer" (o NWB quando instalado), então o chip dourado bate com a sua layer de
  verdade — corrige o caso de estar na **Layer 6** e o seletor marcar a **L5** (o
  conjunto visto pelo PL e o do NWB diferiam, e os chips usavam o índice do PL).

## [0.18.0]

- **Comunicações realm-wide de verdade**: toda a malha estruturada — sincronização de
  layer, pedido de layer, radar de world boss, digest de reputação e as listagens do
  Browse — agora também sai pelo bus **realm-wide** da LibChehulMesh (canal dedicado
  só-addon, **coalescido por tipo** pra não entupir), além do envio local instantâneo
  (guild/grupo/proximidade). O recebimento foi unificado pelo `Mesh:Register`, então
  posts do canal e mensagens ocultas caem no mesmo handler. *Limite do cliente: no
  reino o alcance é **eventual** (dispara no clique, throttle 1.5s) — beacons da
  guild/perto respondem na hora, o resto do reino converge aos poucos.*
- **Canal realm-wide mais robusto** (LibChehulMesh v2): **retry do join** do canal
  (não morre mais calado se o cap de 10 canais estava cheio no login) + flush no
  mouse-up. ⚠️ lib compartilhada — espelhar no GuildOS/ProfessionHelper.
- **"Hops served" conta na ENTRADA, não no convite**: o contador (e um log novo
  "Fulano entrou - hop feito!") só sobe quando a pessoa **realmente entra na party**,
  então convites recusados não inflam mais o número.

## [0.17.1]

- **Toda a malha do PartyLens agora fala pela LibChehulMesh**: o Browse, a rede de
  Layer, o radar de World Boss e os vouches passaram a enviar pelos buses da lib
  compartilhada (guild/grupo/proximidade), unificando o transporte com o
  ProfessionHelper e o GuildOS e centralizando a instrumentação (`/partylens
  netstat`). O post visível de LFG (o "LFM" do autopilot) segue no seu caminho
  próprio, por ser human-readable.

## [0.17.0]

- **Malha compartilhada entre addons (LibChehulMesh) + presença realm-wide**: o
  transporte de rede virou uma **lib única** (`_G.ChehulMesh`) usada por toda a
  família Chehul (PartyLens, ProfessionHelper, GuildOS). Além dos buses ocultos
  (guild/grupo/proximidade), ela adiciona um **bus realm-wide** por um canal
  dedicado "ChehulMesh" — só usuários dos addons entram (sem spam a terceiros),
  filtrado do chat, disparado no clique (post em canal é hardware-gated). O
  handshake de presença **ChehulNet** agora alcança o **reino inteiro**, não só a
  guild/proximidade.

## [0.16.4]

- **Beacon 100% silencioso — agora inclui os SONS**: além do texto e da voz de erro
  (0.16.1), o beacon agora **muta os efeitos sonoros** de convite/entrada na party
  (o "boop" de convite aceito, o som de alguém entrando, os sons de voz de erro) via
  `MuteSoundFile` enquanto está ligado, restaurando ao desligar. Também some com as
  linhas de **método de loot** ("Loot method set to...") que aparecem ao formar party.

## [0.16.3]

- **Numeração alinhada ao NWB (quando instalado)**: se você roda o NovaWorldBuffs,
  o PartyLens agora usa **o número de layer do NWB** (o padrão que a comunidade usa
  no chat) em vez do próprio ordinal — resolvendo o caso em que o PL mostrava "Layer
  3" e o NWB "Layer 5" pra mesma layer física. O NWB deriva o zoneID do mesmo campo
  do GUID que a gente usa, mas numera sobre um conjunto mais completo (compartilhado
  no reino), então o número dele é o "certo". Sem NWB, o PL segue 100% standalone com
  a própria numeração. O match entre usuários PL continua por **zoneUID exato**, então
  quem tem e quem não tem NWB ainda casam certo — só o número exibido/pedido alinha.

## [0.16.2]

- **Reconhecimento entre addons (família Chehul)**: novo módulo compartilhado
  **ChehulNet** — um handshake de presença por **guild + grupo + proximidade** que faz
  os addons do Chehul (PartyLens, GuildOS, ProfessionHelper) se reconhecerem no reino.
  O PartyLens continua 100% standalone; ele anuncia sua presença (e "LFG" quando o
  Autopilot está armado) pra rede da família, servindo de base para recursos
  cross-addon (ex.: saber que um jogador também roda outro addon da família).

## [0.16.1]

- **Beacon silencioso de verdade**: enquanto o beacon está ligado, o vai-e-vem de
  party (convida → não entra → party desfaz) não polui mais a tela. Filtra o **chat**
  ("You aren't in a party.", reset de dificuldade, "já está em grupo", convite
  recusado, etc.), some com o **texto de erro vermelho** no centro da tela (hook no
  `UIErrorsFrame`) e **muta a voz de erro** ("they can't join our group") via a CVar
  `Sound_EnableErrorSpeech` — restaurando exatamente a sua config quando o beacon
  desliga (sobrevive a /reload).

## [0.16.0]

- **Correção crítica — a malha voltou a entregar de verdade.** As mensagens de rede
  (radar de world boss, vouches, sincronização de layer, broker de grupo) eram
  enviadas pelo tipo **CHANNEL**, que está **bloqueado** neste cliente — o envio
  retornava erro em silêncio e **nada chegava a ninguém**. Agora todo o tráfego da
  malha vai por **guild + grupo + proximidade** (buses que entregam de fato), com
  instrumentação que nunca mais falha calada (`Net`).
- **Reconhecimento realm-wide:** usuários PartyLens agora se reconhecem pela
  **assinatura** nos posts do canal — badge **PL** em todo o reino, sem transporte
  extra. O "me leva pra layer N" e o **Gritar** de boss seguem realm-wide pelo post
  visível (disparado por clique).
- **Correção — re-anúncio de LFM (autopilot / build mode).** O re-spam a cada 60s
  estava sendo **bloqueado em silêncio** (só anunciava uma vez, ao armar). Agora
  re-posta de novo, disparado nos seus cliques naturais.
- **Diagnóstico:** `/partylens netdiag` mede o que cada transporte realmente entrega
  neste cliente; `/partylens netstat` mostra a saúde da malha (envios/ok por bus).

## [0.15.1]

- **Convite otimista (ganhar a corrida)**: o beacon agora dispara o convite como a
  **primeira ação** ao bater um pedido compatível — antes de qualquer gravação, log
  ou repaint da UI (o repaint era o que atrasava e deixava outros addons convidarem
  primeiro). A rede também é processada **antes** do Browse nos eventos de chat, e o
  teto de convites subiu de 4 para 10/min pra não segurar rajadas até o próximo tick.

## [0.15.0]

- **Radar de World Boss (aba nova)**: o addon reconhece world bosses / rares pelo
  npcID do GUID (Kazzak, Doomwalker, Fel Reaver — catálogo expansível), avisa no
  chat + som, e **espalha pela malha** ("boss X na layer N") pra todo usuário
  PartyLens do reino. A aba lista os avistamentos com **Ir** (pede a layer exata do
  boss, mesmo em outro mapa) e **Gritar** (rally assinado no chat público). Um
  banner de alerta também aparece no topo da aba Layer.
- **Reputação / Vouch (só positivo)**: dê **vouch** em quem jogou junto; cada vouch
  corre pela malha e todos somam "N pessoas endossaram" (sem downvote, resistente a
  auto-vouch). Companheiros de grupo viram sugestões automáticas; um digest
  periódico sincroniza a rede; a contagem tem TTL/cap pra não crescer sem limite.
- **Broker de grupo (aba Network)**: lista os usuários PartyLens **procurando grupo
  agora** (pela malha), com **Convidar** e **/w** — o LFG da rede, cross-layer.
- **Aba "Network" (dashboard)**: contadores ao vivo — **Nós · Layers · Bosses ·
  Hops · Pedidos · Sua rep** — mais o broker e a lista de vouch.
- Comandos: `/partylens radar`, `/partylens network`, `/partylens vouch Nome`,
  `/partylens boss`, `/partylens bosstest`.

## [0.14.0]

- **Rede de Layer (nova aba)**: detecção de layer **standalone** (sem integrar com
  NWB/AutoLayer — via zoneUID do GUID de NPC) e uma malha invisível entre usuários
  PartyLens sobre o canal LookingForGroup. Toggle de **beacon** (botão direito no
  minimapa ou no botão Beacon): como beacon você **convida em silêncio** quem pede a
  sua layer no chat — sem spam de party, sem popup de /w, com o frame da party
  escondido — e manda um /w assinado (marketing).
- **Seletor de layer visual**: em vez de digitar número, chips das layers que a rede
  **conhece de verdade** — ponto teal = beacon no ar ali, dourado = a sua layer,
  destaque = o que você pediu. Botões **Qualquer** / **Parar**. `/partylens reqlayer`
  segue como atalho.
- **Numeração que converge de verdade**: a malha compartilha o conjunto **completo**
  de layers, então "minha Layer 5 = a sua Layer 5" (e tende a bater com o NWB). O
  match de convite é por **identidade absoluta (zoneUID) + mesmo mapa** — nunca puxa
  ninguém pra layer errada; se não dá pra confirmar, **recusa** em vez de chutar.
- **Canal Layer dedicado**: o addon reconhece um canal chamado "Layer"/"Camada" (e
  qualquer canal customizado) e ali aceita pedidos curtos — `5`, `inv 4`, `hop me`,
  `any` — sem exigir a palavra "layer", filtrando spam de LFG cross-postado.
- **Corre pelo cliente**: pedidos de usuários de addons concorrentes (OpenLayer,
  AutoLayer) também são atendidos — quem convida primeiro leva o cliente.
- **Log de atividade** mostra o que o beacon detecta e faz ("Fulano quer L5",
  "convidou Fulano → L4"), com um status explicando por que está / não está
  convidando (beacon off, layer desconhecida, party cheia, no ar).
- **Créditos**: autoria de **Chehul (danielcosta42)** na TOC, no rodapé de
  Configurações e no tooltip do minimapa.

## [0.13.0]

- **Composição por classe/spec** (aba **Autopilot** → Construir): botão
  **Composição** abre um editor com uma linha por classe e os chips de spec
  (clique cicla 1→2→3→0). Ele **define quantos T/H/D** você quer (a conta sai das
  specs) e a **classe vira o filtro de quem o Autopilot convida**. A spec é sua
  "lista de desejos" (molda o plano e a conta de roles) — ela não é verificável
  em estranhos neste cliente, então não barra convite; a **classe** sim.
- **Filtro por classe e nível na Buscar**: fileira de toggles de classe (ícone) +
  campo de **nível mínimo** para filtrar a lista. A **classe** é filtro rígido
  (quase sempre conhecida); o **nível mínimo** só esconde quem está
  comprovadamente abaixo (e também vale nos convites do Autopilot).
- **Nível real via /who (sob clique)**: o `/who` é uma função restrita a evento
  de hardware neste cliente — só pode ser disparado por um clique real. Então o
  botão **Who** de cada card agora resolve nível + classe e mostra na linha; o
  addon **não** faz varredura automática (evita o erro de "função protegida" e
  spam). Nível de quem usa PartyLens vem de graça pela malha.
- **Malha PartyLens agora carrega classe + nível**: usuários do addon são
  reconhecidos na hora, sem gastar /who (retrocompatível com versões antigas).
- Nível do líder aparece no card do resultado quando conhecido.
- **Assinatura nas mensagens**: tudo que o addon envia por chat (whispers,
  anúncios no canal/grupo/raid) agora vai prefixado com `[PartyLens]: ` — num
  único ponto (`Utils.SendChat`). As mensagens ocultas da malha **não** são
  assinadas (protocolo próprio).
- **Seletores de atividade mais fáceis** (Criar e Autopilot): campo de **busca**
  no topo do dropdown (digite pra filtrar), **faixa de nível** de cada atividade
  à direita (ex.: `60-62`, `70`) e um **filtro de nível máximo** (`≤Nv`) pra
  esconder conteúdo acima do nível que você quer. Enter escolhe o primeiro
  resultado.
- **Spec define as roles (multi-spec)**: em Configurações → Perfil e no Autopilot
  → **Procurar**, o seletor de spec agora é **multi**. Em **Auto** ele detecta sua
  spec pela árvore de talentos com mais pontos (e atualiza no respec); ou marque
  manualmente **uma ou mais** specs da sua classe. As **roles saem das specs** (ex.:
  Restauração + Equilíbrio → *heal / dps*), então o "procurar grupo" casa com quem
  precisa de **qualquer** uma delas, e os whispers/malha anunciam todas. `{spec}` e
  `{role}` nos templates vêm daí.

## [0.12.0]

- **Autopilot "buscar grupo" mais inteligente**: agora lê o que o grupo realmente
  pede na descrição e só sussurra quem precisa da sua **role/classe**. Pula quem
  pede só outras roles (ex.: "need tank" e você é dps) ou outra classe específica
  (ex.: "need warlock" e você é mago). O **modo estrito** (padrão) ignora também
  anúncios vagos sem role; desligue no toggle "Só grupos que precisam de mim"
  para também responder grupos abertos ("LFM more").
- **Menos mensagens por período**: teto de whispers/convites por minuto reduzido
  de 8 para 4 — contato raro e certeiro em vez de varrer o canal.
- Casamento de classe por palavra inteira ("mage" não casa com "da**mage**",
  "lock" não casa com "b**lock**").

## [0.11.1]

- **Profundidade visual**: gradiente sutil nos painéis (janela, sidebar, host e
  cards), marca d'água do radar atrás do conteúdo, acento teal sob o cabeçalho e
  uma bolinha colorida por item da navegação — menos "genérico".
- **Correção**: o atualizador ao vivo da tela de Summon não era cancelado ao
  fechar a janela (ficava rodando em segundo plano).

## [0.11.0]

- **Coordenação de summon**: tela dedicada para a "pedra" — roster ao vivo (quem
  está fora de alcance precisa de summon), detecção de warlock (Ritual de
  Invocação), anúncios ordenados no /p e checklist clicável. Novo módulo `Summon`.
- **Filtro anti-spam + blacklist**: esconde WTS/boost/gold/links do canal LFG
  (toggle, GDKP não é marcado) e bloqueia líderes específicos com um clique.
  Novo módulo `Spam`.
- **Autopilot mais seguro**: teto de whispers/convites por minuto, blacklist por
  nome após N tentativas, auto-desarme de segurança após muito tempo armado.
- **Alerta** (opt-in) quando surge um grupo da categoria com a janela fechada, e
  **keybind** para abrir/fechar a janela.
- **Polimento visual**: bordas completas e simétricas (fim das "bordas de um lado
  só"), seleção teal uniforme, headers de seção em maiúsculas, logo próprio no
  minimapa, na janela e na lista de addons.
- **Engenharia**: lint com luacheck a cada push (informativo); `.gitattributes`
  normaliza as quebras de linha.

## [0.10.0]

- **Reformulação visual**: navegação por menu lateral (rótulos claros no lugar
  dos ícones), grade consistente com seções tituladas e divisórias, Browse com
  mais respiro e o Autopilot reorganizado em blocos legíveis (counts e toggles
  em linhas separadas).
- **Composição automática**: ao escolher a masmorra/raide, o Autopilot já
  preenche uma comp confortável pro tamanho do grupo (5→1/1/3, 10→2/3/5,
  25→2/6/17, 40→4/9/27) — totalmente editável depois.
- **PartyLens mesh**: usuários do addon se detectam e se priorizam via mensagens
  de addon ocultas no canal LookingForGroup — convite instantâneo, selo "PL" nos
  cards e contador de usuários por perto. Novo módulo `Comm`.
- Ícone próprio (radar teal sobre vidro escuro) e identidade visual.
- Pipeline de release automático para o CurseForge via GitHub Actions.

## [0.9.0]

- **Autopilot**: monta grupo (anuncia "LFM" no canal + auto-convida quem responde
  por whisper) ou busca grupo (auto-whisper nos líderes), com coordenação do
  summon na pedra. Novos módulos `Roster` e `Autopilot`. Respeita os limites do
  TBC — não cria listagem nativa (função protegida pelo cliente).

## [0.8.0]

- Badges de resultado redesenhadas (pill LFG/LFM + chip de conteúdo com status dot).
- Criar listagem escolhendo a masmorra/raide de uma lista ao vivo (sem IDs numéricos).

## [0.7.0]

- Filtragem simplificada: Create/Settings viraram ícones no header, Browse como padrão.
- Categoria única em dropdown; filtro de role por pips T/H/D.

## [0.6.0]

- Reestruturação da navegação: 3 modos (Browse · Create · Settings) e uma
  categoria de conteúdo unificada.

## [0.5.0]

- Redesign "dark glass": painéis translúcidos, cards ricos com pips de role.

## [0.4.0]

- Compatibilidade com o cliente TBC Anniversary (2.5.x) e correções de confiabilidade.

## [0.3.0]

- Suporte a 10 idiomas com detecção automática.
