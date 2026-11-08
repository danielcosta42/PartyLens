# PartyLens no WoW: Forever — tarefas

Ordem de execução. [ ] por fazer.

## A. Núcleo (porte)
- [x] A1 TOC só 16001, título/notas, sem OptionalDeps, lista de arquivos sem os módulos removidos.
- [x] A2 Sincronizar a lib de `danielcosta42/chehulnet` (`tools/sync.sh`), `chehulnet.lock`, `tools/chehulnet-lock.sh`.
- [x] A3 Remover LFGTool, WorldBoss, LayerBuffs, Reputation, NetDiag e todas as referências (Core, UI, Localization).
- [x] A4 Utils: `MyName`, `PlayerFullName`, `IsSecret`, `SendChat` via `C_ChatInfo.SendChatMessage`, cores de classe.
- [x] A5 Guarda de segredo e nome completo em Core (eventos), Chat, Roster, Summon, Layer, Autopilot, Messaging.
- [x] A6 Activity com o conteúdo do Forever.
- [x] A7 Database: esquema Forever limpo.
- [x] A8 Net/Comm: listagens por GUILD + grupo + `Realm`, repasse limitado; sem SAY/YELL; sem flush por teclado.
- [x] A9 LayerNet como ferramenta de clique (presença, pedido por whisper, convite e desfazer por clique).
- [x] A10 Autopilot em modo sugestão; nada de timer convida, sussurra, busca ou posta.
- [x] A11 ChehulNetWire: tag `pl`, alertas, `layerProvider`, DIAG `pl.*`.
- [x] A12 Harnesses `tools/chat.lua`, `names.lua`, `net.lua`, `autopilot.lua`, `layer.lua`.
- [x] A13 CI: luacheck bloqueante (`.luacheckrc` com globais 12.x), harnesses, lock.

## B. Interface
- [x] B1 Texturas em `Media/` (varredura, anel, blip, ponto) geradas como TGA.
- [x] B2 Kit de widgets novo (tokens, botões com animação, cartão, pips, anel de frescor, chips, toggles, edit, dropdown, toast).
- [x] B3 Janela: cabeçalho, barra lateral, troca de página com fade, `UISpecialFrames`, arrastar.
- [x] B4 Páginas: Grupos (radar + filtros + lista), Anunciar (+ Autopilot sugestão), Camada, Invocação, Rede, Ajustes.
- [x] B5 Minimap + AddonCompartment.
- [x] B6 Harness `tools/ui.lua` (todas as páginas montam e desenham).

## D. Ajustes do teste no jogo (2026-11-08)
- [x] D1 Rede: só contagens (por addon), sem nomes.
- [x] D2 Camada: camadas por zona com população, beacons, grupos e novidades; "ir para esta camada" pede a um beacon.
- [x] D3 Beacon gamificado ligado por padrão: plantão, recusa `N`, próximo beacon sozinho, hops e patentes, aviso
  fora da janela, tecla de atalho, opção em Ajustes.
- [x] D4 Harnesses `layer.lua`/`ui.lua`/`contract.lua` e o contrato (§6) atualizados.
- [x] D6 Camada só da zona atual, em pilha de placas (texturas `slab`/`slab-edge`), painel de detalhe e faixa do beacon.
- [x] D5 Camadas por zona (medido); hop conta na chegada (`T`); revisão independente: 9 achados corrigidos com teste.

## C. Fechamento
- [x] C1 README/CURSEFORGE-DESCRIPTION para o Forever; CHANGELOG; VERSION 1.0.0.
- [x] C2 Revisão local (review + preflight) até zero achados.
- [ ] C3 PR com `Closes #1`; teste no jogo pelo dono; publicação só com o ok.
