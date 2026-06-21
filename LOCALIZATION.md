# PartyLens - Localization System

PartyLens possui um sistema robusto de localização multi-idiomas que detecta automaticamente o idioma do cliente WoW.

## 🌍 Idiomas Suportados

- ✅ **enUS** - English (US)
- ✅ **ptBR** - Português (Brasil)
- ✅ **deDE** - Deutsch (Deutschland)
- ✅ **frFR** - Français (France)
- ✅ **esES** - Español (España)
- ✅ **itIT** - Italiano (Italia)
- ✅ **ruRU** - Русский (Россия)
- ✅ **zhCN** - 简体中文 (China)
- ✅ **zhTW** - 繁體中文 (Taiwan)
- ✅ **koKR** - 한국어 (Korea)

## 📦 Módulos de Localização

### Localization.lua
Gerencia strings de UI e mensagens.

**Uso:**
```lua
local Localization = require(ADDON_NAME .. "-Localization")

-- Obter string
local title = Localization.L("TITLE")  -- "PartyLens"
local loaded = Localization.L("LOADED")  -- "loaded. Use /partylens."

-- Com formatação
local msg = Localization.L("RESULT_COUNT", 42)  -- "42 results"
```

**Strings Disponíveis:**

| Chave | Descrição |
|-------|-----------|
| `TITLE` | Título do addon |
| `SUBTITLE` | Subtítulo |
| `SEARCH_PLACEHOLDER` | Placeholder busca |
| `CHAT_TOGGLE` | Label toggleChat |
| `LFG_TOOL_TOGGLE` | Label toggle LFG |
| `OPEN_ONLY_TOGGLE` | Label toggle grupos abertos |
| `SPEC_LABEL` | Label especialização |
| `ROLE_LABEL` | Label role |
| `COMMENT_LABEL` | Label comentário |
| `TEMPLATE_LABEL` | Label template |
| `TEMPLATE_HINT` | Dica de template |
| `JOIN_LFG` | Botão entrar LFG |
| `SEARCH_DUNGEONS` | Botão masmorras |
| `SEARCH_RAIDS` | Botão raides |
| `SEND_WHISPER` | Botão enviar |
| `EDIT_WHISPER` | Botão editar |
| `WHO_CHECK` | Botão who |
| `CLOSE` | Botão fechar |
| `RESULT_COUNT` | Contador resultados (formatável) |
| `SOURCE_CHAT` | Origem chat |
| `SOURCE_LFG` | Origem LFG |
| `OPEN_STATUS` | Status aberto |
| `CLOSED_STATUS` | Status fechado |
| `LOADED` | Mensagem carregamento |
| `WHISPER_SENT` | Mensagem whisper enviado (formatável) |
| `NO_MESSAGE` | Erro sem mensagem |
| `LFG_NOT_AVAILABLE` | Erro LFG indisponível |
| `LFG_SEARCH_FAILED` | Erro busca falhou |
| `LFG_JOIN_ATTEMPT` | Mensagem tentativa entrar |

### LocalizedKeywords.lua
Gerencia palavras-chave para detecção de chat.

**Uso:**
```lua
local LocalizedKeywords = require(ADDON_NAME .. "-LocalizedKeywords")

-- Obter palavras-chave positivas (LFM)
local posKeywords = LocalizedKeywords.GetPositiveKeywords()
-- Resultado: { "lfm", "lf1m", "lf2m", ... }

-- Obter palavras-chave negativas (LFG)
local negKeywords = LocalizedKeywords.GetNegativeKeywords()
-- Resultado: { "lfg", "looking for group", ... }

-- Obter keywords de roles
local roleKeywords = LocalizedKeywords.GetRoleKeywords()
-- Resultado: { tank = {...}, heal = {...}, dps = {...} }
```

**Estrutura de Idiomas:**

```
LocalizedKeywords.Keywords = {
    enUS = {
        positive = { "lfm", "lf1m", "need", ... },
        negative = { "lfg", "looking for group", ... },
        tank = { "tank", "prot", ... },
        heal = { "heal", "healer", ... },
        dps = { "dps", "melee", ... },
    },
    ptBR = {
        positive = { "lfm", "precisa", "montando", ... },
        negative = { "lfg", "procuro grupo", ... },
        tank = { "tanque", "prot", ... },
        heal = { "curador", "cura", ... },
        dps = { "dano", "melee", ... },
    },
    -- ... mais idiomas
}
```

## 🔧 Como Adicionar Uma Nova Linguagem

### 1. Adicionar em Localization.lua

```lua
zhTW = {
    TITLE = "PartyLens",
    SUBTITLE = "智能隊伍雷達",
    -- ... adicionar todas as strings
}
```

### 2. Adicionar em LocalizedKeywords.lua

```lua
LocalizedKeywords.Keywords.zhTW = {
    positive = { "lfm", "找", "需要", ... },
    negative = { "lfg", "找團", ... },
    tank = { "坦克", ... },
    heal = { "治療", ... },
    dps = { "傷害", ... },
}
```

## 🎯 Detecção de Idioma

O addon detecta o idioma automaticamente:

```lua
local locale = GetLocale()  -- Retorna: "enUS", "ptBR", "deDE", etc.
Localization.CurrentLocale = locale
```

Se o idioma não é suportado, fallback para `enUS`.

## 📝 Usando Localization no Código

### Em Módulos
```lua
local Localization = require(ADDON_NAME .. "-Localization")

function MyModule.SomeFunction()
    Utils.Print(Localization.L("LOADED"))
end
```

### Em UI
```lua
local title = UIElements.CreateLabel(frame, Localization.L("TITLE"), 24)
local button = UIElements.CreateButton(frame, Localization.L("JOIN_LFG"), 90)
```

### Com Formatação
```lua
Localization.L("RESULT_COUNT", 42)     -- "42 results" ou "42 resultados"
Localization.L("WHISPER_SENT", name, msg)  -- "Message sent to X: Y"
```

## 🔄 Fluxo de Tradução

```
Chat/UI
  ↓
Localization.L(key)
  ↓
Verifica CurrentLocale
  ↓
Busca chave no idioma atual
  ↓
Se não encontrado → Fallback para enUS
  ↓
Retorna string traduzida
```

## 📊 Estatísticas

- **Total de Strings**: 25+ keys
- **Idiomas Suportados**: 10
- **Palavras-chave por Idioma**: 20+ palavras

## 💡 Boas Práticas

1. **Sempre use chaves maiúsculas** para strings
2. **Use Localization.L()** em vez de hardcoded strings
3. **Teste com múltiplos locales** para UI/Layout
4. **Mantenha consistência** entre idiomas
5. **Use formatação com %s** para valores dinâmicos

## 🚀 Exemplo Completo

```lua
local ADDON_NAME = ...
local Localization = require(ADDON_NAME .. "-Localization")
local Utils = require(ADDON_NAME .. "-Utils")

-- Imprimir mensagem de carregamento
Utils.Print(Localization.L("LOADED"))

-- Criar botão com string localizada
local btn = UIElements.CreateButton(frame, Localization.L("JOIN_LFG"), 90)

-- Usar em formatação
Utils.Print(Localization.L("WHISPER_SENT", playerName, message))
```

---

**PartyLens v0.3.0** - Multi-language Support ✅
