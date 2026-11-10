# Avistamentos de rare por camada (issue #9)

## Por quê

No Forever cada zona roda várias camadas e um rare existe numa só. Quem não estava lá nunca fica sabendo. Pela
rede ChehulNet, quem vê um rare avisa a zona, e a troca de camada por beacons (`LayerNet`) leva quem quiser até lá.

## Requisitos

- **R1 Detecção.** Alvo, mouseover ou placa de nome de uma criatura `rare`, `rareelite` ou `worldboss`, fora de
  instância: mapa, camada (zoneUID do GUID), npcID, nome, vivo ou morto e a minha posição (milésimos). Jogador, pet,
  valor secreto: nada.
- **R2 Envio.** `PLR1|S|mapID|zoneUID|npcID|x|y|vivo|tipo|visto|nome` por guilda, grupo e reino (repasse da
  ChehulNet v8+), uma vez por `SEND_GAP` por rare, camada e estado, depois de esperar `SEND_DELAY` + até
  `SEND_JITTER` segundos: se a rede disse o mesmo rare e estado nesse tempo (ou dentro de `SEND_GAP`), fica quieto.
  A morte segue a mesma regra. Nada de instância, lockdown ou com `rares.share` desligado.
- **R3 Recepção.** Campos validados; `visto` (hora do servidor) dentro de `FRESH`, e uma hora adiantada conta como
  agora; só notícia (rare novo ou estado novo) gasta orçamento: `SENDER_BUDGET` por remetente (pelo par que
  sussurrou, quando repassado) e `GLOBAL_BUDGET` no total, por minuto; uma palavra mais velha sobre um rare conhecido
  não muda nada; o que eu mesmo vejo sempre substitui; o meu eco é ignorado.
- **R4 Aviso.** Um rare vivo no meu mapa ouvido da rede: `RARE_SPOTTED` uma vez por rare e camada por
  `NOTIFY_GAP` e um aviso no máximo por `PROMPT_GAP`, com `rares.notify`. Toast fora da janela com **Ir para a camada** (há beacon lá) e **Marcar no mapa**
  (há posição).
- **R5 Página de camadas.** Raros vivos de cada camada abrem as novidades; uma camada do meu mapa que eu já vi,
  conhecida agora só por um rare vivo, aparece também (um avistamento sozinho nunca cria camada).
- **R6 Ajustes.** `rares.notify` e `rares.share`, ligados por padrão.

## Fora de escopo

Raros em instâncias; contagem de quem viu; nomes de jogadores na interface.
