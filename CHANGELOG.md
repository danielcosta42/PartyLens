# Changelog

Todas as mudanças relevantes do PartyLens. Formato baseado em
[Keep a Changelog](https://keepachangelog.com/), versionamento [SemVer](https://semver.org/).

## [Unreleased]

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
