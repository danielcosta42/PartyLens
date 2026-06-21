# PartyLens - Modular Architecture

PartyLens é um addon World of Warcraft refatorado com arquitetura modular baseada em componentes reutilizáveis.

## 📁 Estrutura de Módulos

```
PartyLens/
├── Modules/
│   ├── Utils.lua          # Funções utilitárias comuns
│   ├── Activity.lua       # Reconhecimento de atividades (masmorras, raides)
│   ├── Needs.lua          # Detecção de roles (tank, heal, dps)
│   ├── Database.lua       # Gerenciamento de dados persistentes
│   ├── Entry.lua          # Gerenciamento de entradas de grupos
│   ├── Chat.lua           # Captura de mensagens do canal LFG
│   ├── LFGTool.lua        # Integração com LFG do jogo
│   ├── Messaging.lua      # Construção e envio de mensagens
│   ├── UIElements.lua     # Componentes UI reutilizáveis
│   ├── Search.lua         # Filtragem e scoring de resultados
│   └── UIMain.lua         # Interface principal
├── Core.lua               # Orquestrador principal
├── PartyLens.toc          # Manifesto do addon
└── README.md              # Este arquivo
```

## 🧩 Descrição dos Módulos

### Utils.lua
Funções utilitárias para trabalho com strings, nomes de jogadores e tempo:
- `Print()` - Mensagens para o chat
- `SafeLower()` - Normaliza strings para lowercase
- `Trim()` - Remove espaços em branco
- `PlayerShortName()` - Extrai nome curto do jogador
- `ContainsAny()` - Busca múltiplas palavras
- `SecondsAgo()` - Formata tempo decorrido
- `ClassColoredName()` - Retorna nome colorido por classe

### Activity.lua
Reconhecimento e categorização de atividades:
- `ACTIVITY_ALIASES` - Mapa de nomes de dungeon/raids
- `GuessActivity()` - Identifica atividade em uma mensagem

### Needs.lua
Detecção de roles e necessidades:
- `ROLE_KEYWORDS` - Palavras-chave para cada role
- `GuessNeeds()` - Extrai roles necessários de uma mensagem

### Database.lua
Gerenciamento de dados salvos e persistência:
- `EnsureDB()` - Inicializa base de dados com defaults
- `SaveField()` - Salva valor de campo e atualiza UI

### Entry.lua
Gerenciamento de entradas de grupos no painel:
- `AddOrUpdateEntry()` - Adiciona ou atualiza entrada
- `PruneOldChat()` - Remove entradas antigas de chat

### Chat.lua
Captura de mensagens do canal LookingForGroup:
- `NEGATIVE_GROUP_WORDS` - Palavras que indicam LFG (ignoradas)
- `POSITIVE_GROUP_WORDS` - Palavras que indicam LFM
- `HandleChatMessage()` - Processa mensagens de chat

### LFGTool.lua
Integração com o LFG Tool oficial do jogo:
- `CaptureToolResults()` - Captura resultados da busca
- `SearchTool()` - Realiza busca no LFG

### Messaging.lua
Construção e envio de mensagens de contato:
- `BuildMessageForLeader()` - Monta mensagem com templates
- `SendWhisper()` - Envia whisper
- `OpenWhisper()` - Abre chat de whisper
- `JoinLookingForGroup()` - Entra no canal LFG

### UIElements.lua
Componentes UI reutilizáveis e temas:
- `PALETTE` - Cores do addon
- `CreatePanel()` - Frame com bordas
- `CreateLabel()` - Texto colorido
- `CreateButton()` - Botão interativo
- `CreateEditBox()` - Caixa de entrada
- `CreateToggle()` - Switch on/off
- `CreateDivider()` - Linha separadora
- `SetButtonEnabled()` - Controla estado do botão

### Search.lua
Filtragem e scoring de resultados:
- `ScoreEntry()` - Calcula score para ranking
- `GetFilteredEntries()` - Filtra e ordena entradas

### UIMain.lua
Interface principal e layout:
- `CreateMainUI()` - Constrói janela principal
- `CreateResultRow()` - Cria linha de resultado
- Constantes de dimensões (UI_WIDTH, UI_HEIGHT, ROW_HEIGHT)

### Core.lua
Orquestrador e gateway para eventos:
- Carrega todos os módulos
- Registra eventos do jogo
- Implementa handlers de eventos
- Expõe API global do addon

## 🔄 Fluxo de Dados

```
Chat Message / LFG Search
    ↓
Chat.lua / LFGTool.lua
    ↓
Activity.lua + Needs.lua (Parsing)
    ↓
Entry.lua (Adiciona/Atualiza)
    ↓
Search.lua (Filtragem)
    ↓
UIMain.lua (Renderiza)
```

## 🎯 Benefícios da Arquitetura Modular

✅ **Reutilização** - Componentes podem ser usados em outros addons  
✅ **Manutenção** - Cada módulo tem responsabilidade única  
✅ **Testabilidade** - Fácil testar módulos isoladamente  
✅ **Escalabilidade** - Adicionar features sem quebrar código existente  
✅ **Readabilidade** - Código organizado e bem separado  

## 📝 Como Estender

### Adicionar novo componente UI
```lua
-- Modules/MyComponent.lua
local ADDON_NAME = ...
local UIElements = require(ADDON_NAME .. "-UIElements")

local MyComponent = {}

function MyComponent.Create(parent, name)
    return UIElements.CreatePanel(parent, name, UIElements.PALETTE.panel)
end

return MyComponent
```

### Adicionar novo tipo de busca
```lua
-- Editar Activity.lua para adicionar novo alias
local newActivity = {
    key = "myraid",
    name = "My Raid",
    aliases = { "myraid", "mr" },
    raid = true
}
table.insert(Activity.ACTIVITY_ALIASES, newActivity)
```

### Integrar novo módulo ao Core
```lua
-- Core.lua
local MyModule = require(ADDON_NAME .. "-MyModule")

-- Usar no event handler
PartyLens:SetScript("OnEvent", function(self, event, ...)
    if event == "MY_EVENT" then
        MyModule.HandleEvent(self, ...)
    end
end)
```

## 📌 Versão
- **Versão Atual**: 0.4.0 (Compatibilidade 2.5.x + correções)
- **Versão Anterior**: 0.3.0 (Multi-idioma)

> Nota: os exemplos de "Como Estender" abaixo usam `require(...)` apenas como
> ilustração. O cliente WoW não possui `require`; os módulos reais usam o padrão
> `local X = _G[ADDON_NAME .. "_X"]` (veja qualquer arquivo em `Modules/`).

---

**PartyLens** - Radar inteligente de grupos para TBC Anniversary
