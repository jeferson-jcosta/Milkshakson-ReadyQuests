-- Quest partners: other players with this addon in the same zone who have the
-- same kill or group/elite quest. The addon talks to the other copies with
-- addon messages on a hidden custom channel (no other addon needed); when one
-- matches, a small box offers Invite / Whisper, and one of the two players
-- (only one, so nobody gets two whispers) whispers the other automatically.
local _, ns = ...
local L = ns.L
local PREFIX_CHAT = "|cff33ff99[ReadyQuests]|r "

local MSG_PREFIX = "MilkRQ1"
local CHANNEL = "MilkshaksonRQ"
ns.PARTNER_CHANNEL = CHANNEL
local SEND_EVERY = 60        -- s between announces when nothing changed
local MIN_GAP = 10           -- s between two announces
local PEER_TTL = 300         -- s a peer's last announce is trusted
local NOTIFY_AGAIN = 900     -- s before the same player/quest is offered again
local WHISPER_GAP = 60       -- s between two automatic whispers (any player)
local MAX_IDS = 30

local db
local peers = {}             -- guid -> { name, map, ids = {id=flags}, at }
local notified = {}          -- guid..":"..questID -> time
local whispered = {}         -- guid -> time
local lastWhisper = -math.huge
local lastSent, lastPayload = -math.huge, nil
local joinTried = false
local dbg = { sent = 0, got = 0 }

local function Now() return GetTime() end

-- Never touch channels / addon messages inside instances or while the game
-- locks chat (encounters, Mythic+): blocked calls can make the game offer to
-- disable addons.
local function Restricted()
    if InCombatLockdown and InCombatLockdown() then return true end
    if IsInInstance and IsInInstance() then return true end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        if ok and locked then return true end
    end
    return false
end

-- ReadyQuestsDB is made by ReadyQuests.lua on ADDON_LOADED (order of the
-- two handlers is not guaranteed): read it when needed.
local function Enabled()
    db = ReadyQuestsDB or db
    return db and db.partners
end

---------------------------------------------------------------------------
-- What we announce: zone + quests that need other players
---------------------------------------------------------------------------
-- Zone the player is in (subzone maps climb to their zone; dungeons stay).
local function ZoneMap()
    local m = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local guard = 0
    while m and guard < 6 do
        local info = C_Map.GetMapInfo(m)
        if not info then break end
        local zone = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
        if (info.mapType or zone) <= zone or not info.parentMapID or info.parentMapID == 0 then break end
        if info.mapType and Enum.UIMapType.Dungeon and info.mapType == Enum.UIMapType.Dungeon then break end
        m = info.parentMapID
        guard = guard + 1
    end
    return m
end
ns.PartnerZone = ZoneMap

-- flags: "g" group/elite/dungeon, "k" kill objective still open
local function QuestFlags(info)
    local id = info.questID
    if C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(id) then return nil end
    local flags = ""
    local kind = ns.GetQuestType and ns:GetQuestType(id)
    if kind == "group" or kind == "dungeon" or kind == "raid" or (info.suggestedGroup or 0) > 1 then
        flags = flags .. "g"
    end
    local objs = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id) or {}
    for _, o in ipairs(objs) do
        if o.type == "monster" and not o.finished then flags = flags .. "k" break end
    end
    return flags ~= "" and flags or nil
end

local function MyQuests()
    local out, n = {}, 0
    local num = C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0
    for i = 1, num do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and not info.isHidden and info.questID and info.questID > 0 then
            local f = QuestFlags(info)
            if f and n < MAX_IDS then
                out[info.questID] = f
                n = n + 1
            end
        end
    end
    return out, n
end
ns.PartnerQuests = MyQuests

local function Payload()
    local map = ZoneMap()
    local guid = UnitGUID("player")
    if not (map and guid) then return nil end
    local q, n = MyQuests()
    if n == 0 then return nil end
    local ids = {}
    for id, f in pairs(q) do ids[#ids + 1] = id .. f end
    table.sort(ids)
    return ("Q|%s|%d|%s"):format(guid, map, table.concat(ids, ","))
end

---------------------------------------------------------------------------
-- Hidden channel
---------------------------------------------------------------------------
local function ChannelID()
    local id = GetChannelName and GetChannelName(CHANNEL)
    if type(id) == "number" and id > 0 then return id end
end

local function HideFromChat()
    if not ChatFrame_RemoveChannel then return end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local f = _G["ChatFrame" .. i]
        if f then pcall(ChatFrame_RemoveChannel, f, CHANNEL) end
    end
end

local function Join()
    if not Enabled() or ChannelID() then return end
    if Restricted() then return end
    joinTried = true
    local join = JoinTemporaryChannel or JoinChannelByName
    if join then pcall(join, CHANNEL) end
    HideFromChat()
end

local function Leave()
    if ChannelID() and LeaveChannelByName and not Restricted() then
        pcall(LeaveChannelByName, CHANNEL)
    end
end

local function Send(force)
    if not Enabled() then return end
    if Restricted() then return end
    local id = ChannelID()
    if not id then Join() return end
    local now = Now()
    if now - lastSent < MIN_GAP then return end
    local p = Payload()
    if not p then lastPayload = nil return end
    if not force and p == lastPayload and now - lastSent < SEND_EVERY then return end
    local send = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
    if not send then return end
    local ok = pcall(send, MSG_PREFIX, p, "CHANNEL", id)
    if ok then
        lastSent, lastPayload = now, p
        dbg.sent = dbg.sent + 1
        dbg.lastSent = p
    end
end
ns.PartnerSend = Send

---------------------------------------------------------------------------
-- Box: "<name> also has <quest> here"  [Invite] [Whisper] [x]
---------------------------------------------------------------------------
local box
local function CanInvite()
    if not (IsInGroup and IsInGroup()) then return true end
    if IsInRaid and IsInRaid() then return false end
    local leader = UnitIsGroupLeader and UnitIsGroupLeader("player")
    return leader and (GetNumGroupMembers() or 1) < 5
end

local function QuestLink(id)
    local link = GetQuestLink and GetQuestLink(id)
    if link then return link end
    local t = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
    return "[" .. (t or ("#" .. id)) .. "]"
end

local function Whisper(name, questID)
    local msg = L.PARTNER_WHISPER:format(QuestLink(questID))
    if #msg > 255 then msg = msg:sub(1, 252) .. "..." end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    pcall(send, msg, "WHISPER", nil, name)
end

local function Invite(name)
    local inv = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if inv then pcall(inv, name) end
end

local function ShortName(name) return (Ambiguate and Ambiguate(name, "short")) or name end

local function Box()
    if box then return box end
    box = CreateFrame("Frame", "ReadyQuestsPartnerBox", UIParent, "BackdropTemplate")
    box:SetSize(320, 74)
    box:SetPoint("TOP", UIParent, "TOP", 0, -140)
    box:SetFrameStrata("DIALOG")
    if box.SetBackdrop then
        box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        box:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
        box:SetBackdropBorderColor(0.2, 1, 0.6, 0.8)
    end
    box.text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    box.text:SetPoint("TOPLEFT", 10, -8)
    box.text:SetPoint("TOPRIGHT", -24, -8)
    box.text:SetJustifyH("LEFT")
    local function Btn(label, x)
        local b = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
        b:SetSize(96, 22)
        b:SetPoint("BOTTOMLEFT", x, 8)
        b:SetText(label)
        return b
    end
    box.invite = Btn(L.PARTNER_INVITE, 10)
    box.whisper = Btn(L.PARTNER_WHISPER_BTN, 112)
    box.close = CreateFrame("Button", nil, box, "UIPanelCloseButton")
    box.close:SetPoint("TOPRIGHT", 2, 2)
    box.close:SetScript("OnClick", function() box:Hide() end)
    box.invite:SetScript("OnClick", function() if box.name then Invite(box.name) end box:Hide() end)
    box.whisper:SetScript("OnClick", function() if box.name then Whisper(box.name, box.quest) end box:Hide() end)
    box:Hide()
    return box
end

local function Offer(peer, questID, flags)
    local b = Box()
    b.name, b.quest = peer.name, questID
    local tag = flags:find("g") and L.PARTNER_GROUP or L.PARTNER_KILL
    b.text:SetText(L.PARTNER_TEXT:format(ShortName(peer.name), QuestLink(questID), tag))
    b.invite:SetShown(CanInvite())
    b:Show()
    if PlaySound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then pcall(PlaySound, SOUNDKIT.TELL_MESSAGE) end
    local line = L.PARTNER_TEXT:format(ShortName(peer.name), QuestLink(questID), tag)
    if ns.Say then ns.Say(line) else print(PREFIX_CHAT .. line) end
end
ns.PartnerBox = function() return box end

---------------------------------------------------------------------------
-- Matching
---------------------------------------------------------------------------
local function InMyGroup(guid)
    return IsGUIDInGroup and IsGUIDInGroup(guid) or false
end

local function Match(guid)
    local peer = peers[guid]
    if not (peer and Enabled()) then return end
    if peer.map ~= ZoneMap() or InMyGroup(guid) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local mine = MyQuests()
    local now = Now()
    for id, f in pairs(peer.ids) do
        local my = mine[id]
        local key = guid .. ":" .. id
        if my and (not notified[key] or now - notified[key] > NOTIFY_AGAIN) then
            notified[key] = now
            local flags = my .. f
            Offer(peer, id, flags)
            -- Only one of the two whispers: the one with the smaller GUID.
            if db.partnersWhisper and UnitGUID("player") < guid
                and (not whispered[guid] or now - whispered[guid] > NOTIFY_AGAIN)
                and now - lastWhisper > WHISPER_GAP then
                whispered[guid], lastWhisper = now, now
                Whisper(peer.name, id)
            end
            dbg.lastMatch = ("%s #%d %s"):format(peer.name, id, flags)
            return
        end
    end
end

local function OnAddonMessage(prefix, text, channel, sender)
    if prefix ~= MSG_PREFIX or type(text) ~= "string" then return end
    local kind, guid, map, list = text:match("^(%a)|([^|]+)|(%d+)|(.*)$")
    if kind ~= "Q" or not guid or guid == UnitGUID("player") then return end
    dbg.got = dbg.got + 1
    local ids = {}
    for id, f in list:gmatch("(%d+)(%a+)") do ids[tonumber(id)] = f end
    peers[guid] = { name = sender, map = tonumber(map), ids = ids, at = Now() }
    Match(guid)
end

local function CheckAll()
    local now = Now()
    for guid, p in pairs(peers) do
        if now - p.at > PEER_TTL then peers[guid] = nil else Match(guid) end
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local pending = false
local function Soon(delay)
    if pending then return end
    pending = true
    C_Timer.After(delay or 5, function()
        pending = false
        Send()
        CheckAll()
    end)
end

ev:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= "Milkshakson-ReadyQuests" then return end
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            pcall(C_ChatInfo.RegisterAddonMessagePrefix, MSG_PREFIX)
        end
        return
    end
    if not Enabled() then return end
    if event == "CHAT_MSG_ADDON" then
        OnAddonMessage(...)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- the game sets up its own channels first
        C_Timer.After(10, function() Join() Soon(3) end)
    elseif event == "CHANNEL_UI_UPDATE" or event == "CHAT_MSG_CHANNEL_NOTICE" then
        if ChannelID() then HideFromChat() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if not ChannelID() and joinTried then Join() end
        Soon(2)
    else -- quest log / zone changes
        Soon(5)
    end
end)
for _, e in ipairs({ "ADDON_LOADED", "CHAT_MSG_ADDON", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
    "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE",
    "CHAT_MSG_CHANNEL_NOTICE" }) do
    pcall(ev.RegisterEvent, ev, e)
end
C_Timer.NewTicker(SEND_EVERY, function() if Enabled() then Send() CheckAll() end end)

function ns:PartnersToggled()
    if Enabled() then Join() Soon(1) else Leave() if box then box:Hide() end end
end

function ns:PartnersDebug()
    local n = 0
    for _ in pairs(peers) do n = n + 1 end
    local lines = {
        ("partners=%s whisper=%s channel=%s id=%s zone=%s"):format(tostring(db and db.partners),
            tostring(db and db.partnersWhisper), CHANNEL, tostring(ChannelID()), tostring(ZoneMap())),
        ("sent=%d got=%d peers=%d"):format(dbg.sent, dbg.got, n),
        "last sent: " .. tostring(dbg.lastSent),
        "last match: " .. tostring(dbg.lastMatch),
    }
    for guid, p in pairs(peers) do
        local ids = {}
        for id, f in pairs(p.ids) do ids[#ids + 1] = id .. f end
        lines[#lines + 1] = ("  %s map=%s %ds ago: %s"):format(p.name, tostring(p.map), Now() - p.at, table.concat(ids, ","))
    end
    return lines
end
