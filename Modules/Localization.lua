local ADDON_NAME = ...

local Localization = {}

Localization.CurrentLocale = GetLocale() or "enUS"

-- Every key has enUS and ptBR; the other locales translate what they can and fall back to enUS.
Localization.Strings = {
    enUS = {
        BINDING_TOGGLE = "Toggle PartyLens window",
        BINDING_SERVE = "Beacon: invite the next layer request",
        LOADED = "loaded. Use /partylens.",
        HELP = "/pl opens the window. /pl announce, /pl layer, /pl help.",

        ROLE_TANK = "Tank",
        ROLE_HEAL = "Healer",
        ROLE_DPS = "DPS",
        TYPE_LFG = "LFG",
        TYPE_LFM = "LFM",
        ACTIVITY_DUNGEON = "Dungeons",
        ACTIVITY_RAID = "Raids",
        ACTIVITY_QUEST = "Quests",
        ACTIVITY_GUILD = "Guild",
        ACTIVITY_OTHER = "Other",
        ACTIVITY_ANY = "any dungeon",
        LEVEL_SHORT = "Lv",

        WHISPER_TEMPLATE = "Hi {name}! {class} {role}, level {level}, for {activity}. {comment}",
        WHISPER_RECRUIT = "Hi {name}! Forming {activity}, we need {role}. Want an invite?",
        POST_LFM = "LFM %s, need %s",
        POST_LFG = "LFG %s, %s level %d",
        POST_ANY_ROLE = "all roles",

        WHISPER_SENT = "Message sent to %s: %s",
        NO_MESSAGE = "Set up a message before sending.",
        LFG_JOIN_ATTEMPT = "Attempting to join LookingForGroup channel.",
        NOTICE_POST_COOLDOWN = "Wait a few seconds before posting again.",
        NOTICE_CANNOT_INVITE = "Only the group leader can invite.",
        NOTICE_GROUP_FULL = "Your group is full.",
        NOTICE_INVITED = "Invited %s.",
        NOTICE_BLOCKED = "Blocked %s.",
        NOTICE_WHO_THROTTLED = "Wait a moment between /who lookups.",
        NOTICE_LAYER_REQUESTED = "Asking a beacon on that layer.",
        NOTICE_LAYER_NOBODY = "No beacon on that layer could take you now. Try again in a moment.",
        NOTICE_LAYER_ACCEPTED = "%s is inviting you to their layer: accept the invite.",
        NOTICE_LAYER_INCOMING = "%s asks to come to your layer.",
        NOTICE_LAYER_HOPPED = "You are on the new layer.",

        SUMMON_NEEDED_MSG = "summon needed — %s",
        SUMMON_NEXT_MSG = "summoning %s next — to the stone!",
        SUMMON_ALL_HERE = "everyone is here, no summons needed.",
    },
    ptBR = {
        BINDING_TOGGLE = "Abrir/fechar o PartyLens",
        BINDING_SERVE = "Beacon: convidar o próximo pedido de camada",
        LOADED = "carregado. Use /partylens.",
        HELP = "/pl abre a janela. /pl announce, /pl layer, /pl help.",

        ROLE_TANK = "Tank",
        ROLE_HEAL = "Healer",
        ROLE_DPS = "DPS",
        TYPE_LFG = "LFG",
        TYPE_LFM = "LFM",
        ACTIVITY_DUNGEON = "Masmorras",
        ACTIVITY_RAID = "Raides",
        ACTIVITY_QUEST = "Quests",
        ACTIVITY_GUILD = "Guilda",
        ACTIVITY_OTHER = "Outros",
        ACTIVITY_ANY = "qualquer masmorra",
        LEVEL_SHORT = "Nv",

        WHISPER_TEMPLATE = "Oi {name}! {class} {role}, nível {level}, para {activity}. {comment}",
        WHISPER_RECRUIT = "Oi {name}! Montando {activity}, falta {role}. Quer convite?",
        POST_LFM = "LFM %s, falta %s",
        POST_LFG = "LFG %s, %s nível %d",
        POST_ANY_ROLE = "todas as funções",

        WHISPER_SENT = "Mensagem enviada para %s: %s",
        NO_MESSAGE = "Configure uma mensagem antes de enviar.",
        LFG_JOIN_ATTEMPT = "Tentando entrar no canal LookingForGroup.",
        NOTICE_POST_COOLDOWN = "Espere alguns segundos antes de postar de novo.",
        NOTICE_CANNOT_INVITE = "Só o líder do grupo pode convidar.",
        NOTICE_GROUP_FULL = "Seu grupo está cheio.",
        NOTICE_INVITED = "Convidou %s.",
        NOTICE_BLOCKED = "Bloqueou %s.",
        NOTICE_WHO_THROTTLED = "Espere um pouco entre buscas de /who.",
        NOTICE_LAYER_REQUESTED = "Pedindo a um beacon daquela camada.",
        NOTICE_LAYER_NOBODY = "Nenhum beacon daquela camada pôde te levar agora. Tente de novo daqui a pouco.",
        NOTICE_LAYER_ACCEPTED = "%s está te convidando para a camada dele: aceite o convite.",
        NOTICE_LAYER_INCOMING = "%s pede para vir para a sua camada.",
        NOTICE_LAYER_HOPPED = "Você está na nova camada.",

        SUMMON_NEEDED_MSG = "precisa summon — %s",
        SUMMON_NEXT_MSG = "invocando %s agora — pra pedra!",
        SUMMON_ALL_HERE = "todos presentes, sem summons.",
    },
    deDE = {
        LOADED = "geladen. Verwenden Sie /partylens.",
        WHISPER_SENT = "Nachricht gesendet an %s: %s",
        NO_MESSAGE = "Legen Sie vor dem Senden eine Nachricht fest.",
        LFG_JOIN_ATTEMPT = "Versuch, dem LookingForGroup-Kanal beizutreten.",
        ACTIVITY_GUILD = "Gilde",
        ACTIVITY_QUEST = "Quests",
        ACTIVITY_OTHER = "Sonstiges",
        ACTIVITY_DUNGEON = "Dungeons",
        ACTIVITY_RAID = "Schlachtzüge",
    },
    frFR = {
        LOADED = "chargé. Utilisez /partylens.",
        WHISPER_SENT = "Message envoyé à %s: %s",
        NO_MESSAGE = "Configurez un message avant d'envoyer.",
        LFG_JOIN_ATTEMPT = "Tentative de rejoindre le canal LookingForGroup.",
        ACTIVITY_GUILD = "Guilde",
        ACTIVITY_QUEST = "Quêtes",
        ACTIVITY_OTHER = "Autre",
        ACTIVITY_DUNGEON = "Donjons",
        ACTIVITY_RAID = "Raids",
    },
    esES = {
        LOADED = "cargado. Use /partylens.",
        WHISPER_SENT = "Mensaje enviado a %s: %s",
        NO_MESSAGE = "Configure un mensaje antes de enviar.",
        LFG_JOIN_ATTEMPT = "Intentando unirse al canal LookingForGroup.",
        ACTIVITY_GUILD = "Hermandad",
        ACTIVITY_QUEST = "Misiones",
        ACTIVITY_OTHER = "Otro",
        ACTIVITY_DUNGEON = "Mazmorras",
        ACTIVITY_RAID = "Bandas",
    },
    itIT = {
        LOADED = "caricato. Usa /partylens.",
        WHISPER_SENT = "Messaggio inviato a %s: %s",
        NO_MESSAGE = "Configura un messaggio prima di inviare.",
        LFG_JOIN_ATTEMPT = "Tentativo di unirsi al canale LookingForGroup.",
        ACTIVITY_GUILD = "Gilda",
        ACTIVITY_QUEST = "Missioni",
        ACTIVITY_OTHER = "Altro",
        ACTIVITY_DUNGEON = "Spedizioni",
        ACTIVITY_RAID = "Incursioni",
    },
    ruRU = {
        LOADED = "загружен. Используйте /partylens.",
        WHISPER_SENT = "Сообщение отправлено %s: %s",
        NO_MESSAGE = "Установите сообщение перед отправкой.",
        LFG_JOIN_ATTEMPT = "Попытка присоединиться к каналу LookingForGroup.",
        ACTIVITY_GUILD = "Гильдия",
        ACTIVITY_QUEST = "Задания",
        ACTIVITY_OTHER = "Прочее",
        ACTIVITY_DUNGEON = "Подземелья",
        ACTIVITY_RAID = "Рейды",
    },
    zhCN = {
        LOADED = "已加载。使用 /partylens。",
        WHISPER_SENT = "消息已发送给 %s: %s",
        NO_MESSAGE = "发送前请设置消息。",
        LFG_JOIN_ATTEMPT = "尝试加入 LookingForGroup 频道。",
        ACTIVITY_GUILD = "公会",
        ACTIVITY_QUEST = "任务",
        ACTIVITY_OTHER = "其他",
        ACTIVITY_DUNGEON = "地下城",
        ACTIVITY_RAID = "团队副本",
    },
    zhTW = {
        LOADED = "已載入。使用 /partylens。",
        WHISPER_SENT = "訊息已傳送至 %s: %s",
        NO_MESSAGE = "傳送前請設定訊息。",
        LFG_JOIN_ATTEMPT = "嘗試加入 LookingForGroup 頻道。",
        ACTIVITY_GUILD = "公會",
        ACTIVITY_QUEST = "任務",
        ACTIVITY_OTHER = "其他",
        ACTIVITY_DUNGEON = "地城",
        ACTIVITY_RAID = "團隊副本",
    },
    koKR = {
        LOADED = "로드됨. /partylens를 사용하세요.",
        WHISPER_SENT = "%s에게 보낸 메시지: %s",
        NO_MESSAGE = "보내기 전에 메시지를 설정하세요.",
        LFG_JOIN_ATTEMPT = "LookingForGroup 채널에 참가하려고 시도했습니다.",
        ACTIVITY_GUILD = "길드",
        ACTIVITY_QUEST = "퀘스트",
        ACTIVITY_OTHER = "기타",
        ACTIVITY_DUNGEON = "던전",
        ACTIVITY_RAID = "공격대",
    },
}

function Localization.Get(key)
    local own = Localization.Strings[Localization.CurrentLocale]
    if own and own[key] then
        return own[key]
    end
    return Localization.Strings.enUS[key] or key
end

function Localization.L(key, ...)
    local str = Localization.Get(key)
    if select("#", ...) > 0 then
        return string.format(str, ...)
    end
    return str
end

-- Another file's strings (the UI's), merged in: theirs never replace a core key.
function Localization.Add(locale, strings)
    local into = Localization.Strings[locale]
    if not into then
        into = {}
        Localization.Strings[locale] = into
    end
    for key, text in pairs(strings or {}) do
        if into[key] == nil then
            into[key] = text
        end
    end
end

-- L["KEY"] reads, L("KEY", ...) formats.
Localization.T = setmetatable({}, {
    __index = function(_, key) return Localization.Get(key) end,
    __call = function(_, key, ...) return Localization.L(key, ...) end,
})

_G[ADDON_NAME .. "_Localization"] = Localization
return Localization
