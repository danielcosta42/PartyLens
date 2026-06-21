local ADDON_NAME = ...
-- WoW has no global require(); Localization is guaranteed loaded first by the .toc.
local Localization = _G[ADDON_NAME .. "_Localization"]
assert(Localization, ADDON_NAME .. ": Localization must load before LocalizedKeywords")

local LocalizedKeywords = {}

-- Palavras-chave por idioma
LocalizedKeywords.Keywords = {
    enUS = {
        positive = { "lfm", "lf1m", "lf2m", "lf3m", "lf4m", "need", "needs", "need all", "forming", "more" },
        negative = { "lfg", "looking for group", "lf group" },
        tank = { "tank", "tanks", "prot", "bear" },
        heal = { "heal", "healer", "heals", "resto", "holy", "disc" },
        dps = { "dps", "pump", "caster", "melee", "ranged" },
    },
    ptBR = {
        positive = { "lfm", "lf1m", "lf2m", "lf3m", "lf4m", "need", "needs", "precisa", "precisamos", "need all", "forming", "montando", "recrutando", "vaga", "vagas", "mais" },
        negative = { "lfg", "looking for group", "procuro grupo", "busco grupo", "lf group" },
        tank = { "tank", "tanks", "prot", "bear", "tanque" },
        heal = { "heal", "healer", "heals", "resto", "holy", "disc", "curador", "cura" },
        dps = { "dps", "pump", "caster", "melee", "ranged", "dano" },
    },
    deDE = {
        positive = { "lfm", "lf1m", "lf2m", "lf3m", "lf4m", "need", "needs", "benötigt", "benötigen", "bildet", "suchen" },
        negative = { "lfg", "looking for group", "suche gruppe", "sucht gruppe" },
        tank = { "tank", "tanks", "prot" },
        heal = { "heal", "healer", "heals", "resto", "holy", "disc", "heiler" },
        dps = { "dps", "schaden", "caster", "melee" },
    },
    frFR = {
        positive = { "lfm", "lf1m", "lf2m", "lf3m", "lf4m", "cherche", "cherchent", "besoin", "besoins", "forme", "plus" },
        negative = { "lfg", "looking for group", "cherche groupe", "recherche groupe" },
        tank = { "tank", "tanks", "prot", "tanker" },
        heal = { "heal", "healer", "heals", "resto", "holy", "disc", "soigneur" },
        dps = { "dps", "dégat", "caster", "melee" },
    },
    esES = {
        positive = { "lfm", "lf1m", "lf2m", "lf3m", "lf4m", "busco", "buscamos", "necesita", "necesitamos", "armando", "más" },
        negative = { "lfg", "looking for group", "busco grupo", "buscamos grupo" },
        tank = { "tank", "tanks", "prot", "tanque" },
        heal = { "heal", "healer", "heals", "resto", "holy", "disc", "sanador" },
        dps = { "dps", "daño", "caster", "melee" },
    },
    itIT = {
        positive = { "lfm", "lf1m", "lf2m", "lf3m", "lf4m", "cerco", "cerchiamo", "serve", "servono", "formando", "più" },
        negative = { "lfg", "looking for group", "cerco gruppo", "cerchiamo gruppo" },
        tank = { "tank", "tanks", "prot" },
        heal = { "heal", "healer", "heals", "resto", "holy", "disc", "guaritore" },
        dps = { "dps", "danno", "caster", "melee" },
    },
    ruRU = {
        positive = { "lfm", "lf1m", "lf2m", "lf3m", "lf4m", "ищу", "ищем", "нужен", "нужны", "собираем", "еще" },
        negative = { "lfg", "looking for group", "ищу группу", "ищем группу" },
        tank = { "tank", "tanks", "prot", "танк" },
        heal = { "heal", "healer", "heals", "resto", "holy", "disc", "целитель" },
        dps = { "dps", "урон", "caster", "melee" },
    },
    zhCN = {
        -- 找 alone means "seek" for both LFG and LFM; keep it out of positive and
        -- list the solo-seeking compounds as negative so a lone player is detected.
        positive = { "lfm", "lf1m", "lf2m", "lf3m", "lf4m", "需要", "招募", "更多" },
        negative = { "lfg", "looking for group", "找团", "寻找团队", "找队伍", "找队", "找人" },
        tank = { "tank", "tanks", "prot", "坦克" },
        heal = { "heal", "healer", "heals", "resto", "holy", "disc", "治疗" },
        dps = { "dps", "伤害", "caster", "melee" },
    },
    zhTW = {
        positive = { "lfm", "lf1m", "lf2m", "lf3m", "lf4m", "需要", "招募", "更多" },
        negative = { "lfg", "looking for group", "找團", "尋找團隊", "找隊伍", "找隊", "找人" },
        tank = { "tank", "tanks", "prot", "坦克" },
        heal = { "heal", "healer", "heals", "resto", "holy", "disc", "治療" },
        dps = { "dps", "傷害", "caster", "melee" },
    },
    koKR = {
        positive = { "lfm", "lf1m", "lf2m", "lf3m", "lf4m", "찾기", "모집", "필요", "구성", "추가" },
        negative = { "lfg", "looking for group", "팀 찾기", "팀 구하기" },
        tank = { "tank", "tanks", "prot", "탱크" },
        heal = { "heal", "healer", "heals", "resto", "holy", "disc", "힐러" },
        dps = { "dps", "피해", "caster", "melee" },
    },
}

-- Obtém palavras-chave do idioma atual
function LocalizedKeywords.GetKeywords(locale)
    locale = locale or Localization.CurrentLocale
    return LocalizedKeywords.Keywords[locale] or LocalizedKeywords.Keywords.enUS
end

-- Obtém palavras-chave positivas
function LocalizedKeywords.GetPositiveKeywords()
    local keywords = LocalizedKeywords.GetKeywords()
    return keywords.positive
end

-- Obtém palavras-chave negativas
function LocalizedKeywords.GetNegativeKeywords()
    local keywords = LocalizedKeywords.GetKeywords()
    return keywords.negative
end

function LocalizedKeywords.GetLFMKeywords()
    return LocalizedKeywords.GetPositiveKeywords()
end

function LocalizedKeywords.GetLFGKeywords()
    return LocalizedKeywords.GetNegativeKeywords()
end

-- Obtém palavras-chave de roles
function LocalizedKeywords.GetRoleKeywords()
    local keywords = LocalizedKeywords.GetKeywords()
    return {
        tank = keywords.tank,
        heal = keywords.heal,
        dps = keywords.dps,
    }
end

_G[ADDON_NAME .. "_LocalizedKeywords"] = LocalizedKeywords
return LocalizedKeywords
