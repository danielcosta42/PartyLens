# Pedido de summon para o reino (issue #10)

## Por quê

A página de Summon só ajuda dentro do grupo. Quem precisa chegar longe pede no chat e torce. Pela rede ChehulNet o
pedido chega aos bruxos com PartyLens do reino, e a oferta volta direto para quem pediu.

## Requisitos

- **R1 Pedir.** Um lugar (texto livre, 40 caracteres) e um clique: `PLS1|Q|id|nível|classe|visto|destino` por
  guilda, grupo e reino (repasse v8+), de novo a cada 2 min enquanto aberto, por até 10 min; um pedido por vez;
  cancelar avisa a rede (`PLS1|X|id|visto`).
- **R2 Bruxo.** Classe WARLOCK, nível 20+ e `summonNet.offer`: aviso com **Oferecer** e **Ignorar**; oferecer
  sussurra `PLS1|O|id|zona` a quem pediu (um clique, uma oferta por pedido).
- **R3 Quem pediu.** Cada oferta sussurrada para o meu pedido aberto vira um aviso com **Convidar** e um botão
  **Convidar** na página (o aviso pode sumir; o botão fica enquanto o pedido estiver aberto); fora isso não conta.
- **R4 Limites.** Campos validados; `visto` recente (adiantado conta como agora); só pedido novo gasta orçamento:
  `SENDER_BUDGET` por remetente por minuto (pelo par que sussurrou, quando repassado) e `GLOBAL_BUDGET` no total;
  avisos: `PROMPT_BUDGET` por minuto, um por pessoa por `ASK_TTL` e um pedido repassado por `RELAY_PROMPT_GAP`;
  jogador bloqueado é ignorado; um cancelamento só conta vindo direto de quem pediu, e um pedido mais novo reabre;
  nada de instância ou lockdown; tabelas com teto e validade.
- **R5 Avisos na tela.** Um lugar no topo da tela para todos os avisos: o do beacon vai primeiro; raros e summons
  esperam o lugar vagar.

## Fora de escopo

Detectar a chegada; coordenar os dois ajudantes do ritual.
