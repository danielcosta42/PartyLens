# PartyLens no WoW: Forever — plano

Base: spec.md. Auditoria do código atual (TBC) em 2026-11-08: Core + 30 módulos, ~14.7k linhas, UIMain 3152 linhas.

## 1. Destino de cada módulo

| Módulo | Destino |
|---|---|
| Core.lua | Fica. Eventos com guarda de segredo; slash enxuto (`/pl`, `/partylens`: abrir, anunciar, camada, ajuda); sem comandos de dev; sem combat log; sem talentos. |
| Utils | Fica. `PlayerFullName(unit|sender)`, `MyName()`, `IsSecret(...)`, `SendChat` via `C_ChatInfo.SendChatMessage` (só chamado de clique), `ClassColoredName` por `RAID_CLASS_COLORS`. |
| Localization, LocalizedKeywords | Ficam (limpar chaves de módulos removidos). |
| Activity | Reescrita: masmorras e raides do Forever (vanilla + City of Dalaran, Ruins of Lordaeron, Excavation Site: Wetlands, The Hall of Thanes; raides que abrirem), aliases por idioma. Fonte de nomes: GuildOS `Data/ForeverDungeons.lua`, Lodestar `Guides/Dungeons`. |
| Needs, Spam, Entry, Search | Ficam; chaves por nome completo. |
| Database | Esquema novo (`schemaVersion = 100`, Forever): começa limpo; sem `rep`, sem buffs, sem chaves de Group Finder. |
| Chat | Fica: guarda de segredo, nome completo, detecção do canal de LFG. |
| Messaging | `SendWhisper` (clique) via `C_ChatInfo.SendChatMessage(msg, "WHISPER", nil, fullName)`; `OpenWhisper` via `ChatFrameUtil.SendTell`/`ChatFrame_SendTell(fullName)` (o que existir), nunca `"/w " .. nome`. |
| Roster | Nome completo (`GetUnitName(unit, true)` + `UnitFullName`), guarda de segredo. |
| Who | Fica (clique). |
| Summon | Fica (anúncio por clique); nomes completos. |
| Net | Reescrita fina sobre a LibChehulMesh: GUILD, grupo, WHISPER, `Realm` (diretório). Sem SAY/YELL diretos, sem o flush de canal por teclado (`SetPropagateKeyboardInput`): post visível só de clique. |
| Comm | Listagens `PartyLens` (formato atual mantido, versão no campo 1), por GUILD + grupo + `Realm`; repasse uma vez (saltos ≤ 2, cache de vistos). |
| Layer | Fica: zoneUID do GUID de criatura com guarda de segredo; mapIDs do Forever (sem as tabelas do TBC). |
| LayerNet | Reescrita como ferramenta de clique: presença de camada pelo HELLO da ChehulNet (`CN.peers[...].mapID/zoneUID`) + `S` próprio por GUILD/Realm; pedido `R` por WHISPER a um nó escolhido; quem serve vê o pedido e convida por clique; desfazer por clique. Sem convite/whisper automático, sem mutar sons, sem esconder party frames, sem filtros que engolem erros, sem override do `UIErrorsFrame`. |
| Autopilot | Só modo sugestão: candidatos do radar que fecham os papéis; botões Convidar/Whisper; nenhum tick convida, sussurra ou busca. |
| API | Fica (`_G.PartyLens_API`: `StartQuestGroup` abre o Anunciar com o contexto; `RequestLayer` abre a camada). Tirar a duplicata do LFGTool. |
| ChehulNet, LibChehulMesh | Sincronizadas de `danielcosta42/chehulnet` (`tools/sync.sh … Libs/LibChehulMesh.lua Modules/ChehulNet.lua`), com `chehulnet.lock` e `tools/chehulnet-lock.sh` no CI. |
| ChehulNetWire | Fica: tag `pl`, alertas (prioridade 3), `layerProvider`, DIAG `pl.*` (versão, entradas no radar, listagem ativa). |
| UIElements, UIMain, Minimap | Reescritas (§5). Minimap + `AddonCompartment`. |
| LFGTool, WorldBoss, LayerBuffs, Reputation, NetDiag | **Removidos.** |

## 2. Nomes

Uma regra: chave = nome completo como o jogo entrega no evento ("Nome Sobrenome"), `Ambiguate(name, "none")`,
minúsculo para chave de tabela; para exibir e para whisper, a grafia original. O próprio cliente:
`UnitFullName("player")` (nome + sobrenome; no retail o segundo campo é o realm, então só usar quando
`C_PlayerInfo.ShouldDisplaySurname()`), igual a `MyShortName` da ChehulNet. Unidades do grupo: `GetUnitName(unit,
true)` com guarda de segredo.

## 3. Rede

- `PartyLens` (listagens): `2|lfg/lfm/off|roles|activityType|activity|minIlvl|classFile|level|zoneUID|mapID|filled|target|seq|hops|origin|comment`.
  Envio: ao criar/atualizar a listagem e a cada 60 s enquanto ativa; GUILD + grupo + `Mesh:Realm(prefix, payload,
  "PartyLens:" .. eu)`. `seq` = `GetServerTime()` da mudança (renovado a cada 5 min sem mudança). Quem recebe uma
  listagem nova (versão maior) repassa uma vez por `Realm` com saltos+1, até 2, em 4 chaves de coalescência
  compartilhadas. Descartado: `seq` não inteiro, mais de 120 s no futuro ou mais velho que 15 min; `hops` fora de
  0..2. `off` só vale vindo direto da própria pessoa e nunca é repassado (cópias repassadas expiram em 3 min).
- `PLLnet` (camada): `S|map|zone|beacon|hops` presença (GUILD + grupo + Realm, 60 s e na troca de camada ou de
  plantão; `beacon` = 1 quando de plantão, `hops` = hops servidos); `R|reqMap|myZone|targetZone` pedido (WHISPER ao
  beacon escolhido); `A|map|zone` convite a caminho; `N|map|zone` "não posso agora" (o pedinte passa ao próximo
  beacon). Sem `SD` gossip, sem bridge por YELL. Novidades por camada (`Modules/LayerWatch.lua`) saem só do que já
  chega: presença, HELLO e listagens com mapID/zoneUID, comparados a cada 30 s.
- Nada sai de dentro de instância ou em lockdown (a lib já segura o diretório; os envios diretos também checam).

## 4. Testes

`tools/*.lua` rodando o código real sob um cliente simulado (estilo GuildOS/CehulNet):
- `chat.lua`: parsing de posts (LFG/LFM, papéis, atividades do Forever), nome completo, linha secreta ignorada, post
  assinado de outro usuário.
- `names.lua`: `MyName`, chaves, whisper target.
- `net.lua`: listagem enviada pelos barramentos certos, repasse com limite, nada em instância.
- `autopilot.lua`: sugestões sem nenhum convite/whisper de timer.
- `layer.lua`: pedido → aceite por clique → servido.
- `ui.lua`: monta a janela inteira sob um stub genérico de frames e desenha todas as páginas sem erro.
CI: luacheck bloqueante (globais 12.x declarados), harnesses, `tools/chehulnet-lock.sh`.

## 5. Interface nova

### Identidade
O assunto é um **radar**: o PartyLens escuta a facção e mostra o que acende. Uma escolha ousada, o resto calmo.

- **Cor**: fundo `#0F1626` (ardósia profunda), painel `#172036`, linha `#26324D`, **âmbar de radar `#FFB547`**
  (a varredura, a ação principal, o "novo"), papéis como cor de dado: tanque `#5AA9FF`, cura `#5BE39A`,
  dano `#FF6B6B`; texto `#E8EEF8`, secundário `#8A96B0`. LFM = âmbar, LFG = azul.
- **Tipo**: Friz Quadrata (`Fonts\FRIZQT__.TTF`) em títulos e números; Arial Narrow (`Fonts\ARIALN.TTF`) nos dados.
- **O elemento ousado**: o **radar** no topo da página Grupos: anéis concêntricos, uma varredura âmbar girando
  (animação de rotação, 4 s por volta) e um **blip** para cada grupo recente (posição por tipo/atividade, raio por
  frescor). Um grupo novo acende um blip com um "pop" (escala 0→1 + brilho que apaga).
- Sem caixa alta em rótulos, sem separadores "·" em todo lugar, sem cartões idênticos com sombra.

### Layout
```
+------------------------------------------------------------------------------------+
| (radar mini) PartyLens   ouvindo LookingForGroup, 34 grupos           ● rede 41  X |
+-----------+------------------------------------------------------------------------+
| Grupos    | [   RADAR   ]  34 grupos agora    12 precisam de você    rede: 41 nós  |
| Anunciar  | [T][H][D]  LFM|LFG  [atividade v]  [buscar ......]  só abertos        |
| Camada    | ┃ Ruins of Lordaeron   LFM   ● 2 min   [T][H][D] 3/5      [Whisper] [•] |
| Invocação | ┃ Kowa Druid: LF healer for RoL, need 1 heal                             |
| Rede      | ┃ ...                                                                    |
| Ajustes   |                                                                        |
+-----------+------------------------------------------------------------------------+
```
Barra lateral com ícone + rótulo; cabeçalho com o estado ("ouvindo LookingForGroup"); conteúdo com cabeçalho de
página, filtros e a lista. Cartão: faixa de cor à esquerda (LFM âmbar / LFG azul), atividade (Friz 14), tipo, frescor
(anel que esvazia com a idade), papéis que faltam como pips coloridos, preenchimento, líder na cor da classe, uma
linha de mensagem, ações à direita (Whisper principal; Convidar para LFG; Who; Bloquear num menu).

### Movimento (com propósito; `db.animations` desliga tudo)
- **Grupo novo** entra deslizando 12 px da direita com fade (0,25 s) e uma faixa âmbar que apaga em 2 s.
- **Precisa do seu papel**: o pip do seu papel pulsa uma vez ao chegar.
- **Troca de página**: o conteúdo faz fade cruzado (0,15 s).
- **Botões**: escala 0,96 ao apertar (0,08 s); Whisper vira "enviado" com um flash verde.
- **Alerta de grupo que serve**: um aviso desce do topo da janela e some sozinho.
- **Vazio**: o radar girando com "Ouvindo o canal…".
- **Camada**: anel de progresso enquanto espera o convite; o blip de camada pisca quando servido.
Implementação: `AnimationGroup` (`Alpha`, `Translation`, `Scale`, `Rotation`) criados uma vez por widget e
reaproveitados; texturas próprias geradas em `Media/` (`radar-sweep.tga` cônico com alfa, `ring.tga`, `blip.tga`,
`dot.tga`) — TGA 32 bits sem compressão.
