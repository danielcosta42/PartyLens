# Avistamentos de rare por camada (issue #9)

## Por quê

No Forever cada zona roda várias camadas e um rare existe numa só. Quem não estava lá nunca fica sabendo. Pela
rede ChehulNet, quem vê um rare avisa a zona, e a troca de camada por beacons (`LayerNet`) leva quem quiser até lá.

## Requisitos

- **R1 Detecção.** Alvo, mouseover ou placa de nome de uma criatura `rare`, `rareelite` ou `worldboss`, fora de
  instância: mapa, camada (zoneUID do GUID), npcID, nome, vivo ou morto e a minha posição (milésimos). Jogador, pet,
  valor secreto: nada.
- **R2 Envio.** `PLR1|S|mapID|zoneUID|npcID|x|y|vivo|tipo|visto|nome` por guilda, grupo e reino (repasse da
  ChehulNet v8+), uma vez por `SEND_GAP` por rare, camada e estado; a morte sai na hora. Nada de instância, lockdown
  ou com `rares.share` desligado.
- **R3 Recepção.** Campos validados; `visto` (hora do servidor) dentro de `FRESH` e não adiantado; `SENDER_BUDGET`
  por remetente por minuto; uma palavra mais velha sobre um rare conhecido não muda nada; o meu eco é ignorado.
  Relayed (`dist "RELAY"`): a origem é só alegada, nada depende dela além do orçamento.
- **R4 Aviso.** Um rare vivo no meu mapa ouvido da rede: `RARE_SPOTTED` uma vez por rare e camada por
  `NOTIFY_GAP`, com `rares.notify`. Toast fora da janela com **Ir para a camada** (há beacon lá) e **Marcar no mapa**
  (há posição).
- **R5 Página de camadas.** Raros vivos de cada camada abrem as novidades; uma camada do meu mapa conhecida só por
  um rare vivo aparece também.
- **R6 Ajustes.** `rares.notify` e `rares.share`, ligados por padrão.

## Fora de escopo

Raros em instâncias; contagem de quem viu; nomes de jogadores na interface.
