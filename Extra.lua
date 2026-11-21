-- Extra quest info: where the turn-in is (dungeon / cave / indoor) and quest chains.
local _, ns = ...

local DUNGEON = Enum and Enum.UIMapType and Enum.UIMapType.Dungeon or 4
local MICRO = Enum and Enum.UIMapType and Enum.UIMapType.Micro or 5

---------------------------------------------------------------------------
-- Turn-in place
---------------------------------------------------------------------------
local instanceCache = {}
local function IsInstance(mapID)
    if instanceCache[mapID] ~= nil then return instanceCache[mapID] end
    local yes = false
    if EJ_GetInstanceForMap then
        local ok, id = pcall(EJ_GetInstanceForMap, mapID)
        yes = ok and type(id) == "number" and id > 0 or false
    end
    -- Fallback: you are inside an instance and this is (part of) its map.
    if not yes and IsInInstance then
        local inInstance, kind = IsInInstance()
        if inInstance and (kind == "party" or kind == "raid") then
            local pmap = C_Map.GetBestMapForUnit("player")
            local cur = pmap
            for _ = 1, 4 do
                if not cur then break end
                if cur == mapID then yes = true break end
                local info = C_Map.GetMapInfo(cur)
                cur = info and info.parentMapID
            end
            if yes then instanceCache[mapID] = true end
            return yes -- not cached when false: depends on where you are
        end
    end
    instanceCache[mapID] = yes
    return yes
end

-- Returns kind ("dungeon" | "cave" | nil), placeName
function ns:GetPlace(map, x, y)
    if not map then return nil end
    local info = C_Map.GetMapInfo(map)
    if info and info.mapType == DUNGEON then
        return IsInstance(map) and "dungeon" or "cave", info.name
    end
    if x and y and C_Map.GetMapInfoAtPosition then
        local ok, child = pcall(C_Map.GetMapInfoAtPosition, map, x, y)
        if ok and child and child.mapID and child.mapID ~= map then
            if child.mapType == DUNGEON then
                return IsInstance(child.mapID) and "dungeon" or "cave", child.name
            elseif child.mapType == MICRO then
                return "cave", child.name
            end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Quest chains: one quest leads to another. Game API only:
--  1. the game's quest lines (C_QuestLine), when it has one for the quest;
--  2. links learned while playing: you turn a quest in and the same NPC
--     offers / gives you the next one. Kept in ReadyQuestsDB.chainLinks
--     (account-wide), so every character benefits.
---------------------------------------------------------------------------
local chainCache = {}

local function FromQuestLine(questID, mapID)
    if not (C_QuestLine and C_QuestLine.GetQuestLineInfo and C_QuestLine.GetQuestLineQuests) then return nil end
    local ok, info = pcall(C_QuestLine.GetQuestLineInfo, questID, mapID)
    if not (ok and type(info) == "table" and info.questLineID) then return nil end
    local ok2, quests = pcall(C_QuestLine.GetQuestLineQuests, info.questLineID)
    if not (ok2 and type(quests) == "table" and #quests > 1) then return nil end
    for i, id in ipairs(quests) do
        if id == questID then
            return { name = info.questLineName, pos = i, total = #quests, nextID = quests[i + 1], source = "questline" }
        end
    end
end

-- Learned links: chainLinks[prev] = { [next] = true, ... }
local prevOf -- next -> prev, rebuilt from chainLinks
local function Links()
    local db = _G.ReadyQuestsDB
    if not db then return nil end
    db.chainLinks = db.chainLinks or {}
    if not prevOf then
        prevOf = {}
        for prev, nexts in pairs(db.chainLinks) do
            for nxt in pairs(nexts) do prevOf[nxt] = prevOf[nxt] or prev end
        end
    end
    return db.chainLinks
end

local function Learn(prev, nxt)
    local links = Links()
    if not (links and prev and nxt and prev ~= nxt) then return end
    if links[prev] and links[prev][nxt] then return end
    links[prev] = links[prev] or {}
    links[prev][nxt] = true
    prevOf[nxt] = prevOf[nxt] or prev
    wipe(chainCache)
    if ns.Refresh then ns.Refresh() end
end

local function OnlyNext(links, id)
    local t = links[id]
    if not t then return nil, false end
    local only, n = nil, 0
    for nxt in pairs(t) do only, n = nxt, n + 1 end
    return n == 1 and only or nil, true
end

local function FromLearned(questID)
    local links = Links()
    if not links then return nil end
    local before, cur, seen = 0, questID, { [questID] = true }
    while before < 40 do
        local p = prevOf[cur]
        if not p or seen[p] then break end
        seen[p] = true
        before = before + 1
        cur = p
    end
    local nextID, hasNext = OnlyNext(links, questID)
    if before == 0 and not hasNext then return nil end
    local after, id = hasNext and 1 or 0, nextID
    while id and after < 40 and not seen[id] do
        seen[id] = true
        local n, more = OnlyNext(links, id)
        if not more then break end
        after = after + 1
        id = n
    end
    return {
        pos = before + 1, total = before + 1 + after, nextID = nextID,
        nextName = nextID and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(nextID) or nil,
        prevID = prevOf[questID], source = "learned",
    }
end

-- Returns { pos, total, nextID, nextName, name, source } or false
function ns:GetChain(questID, mapID)
    local c = chainCache[questID]
    if c ~= nil then return c end
    c = FromQuestLine(questID, mapID) or FromLearned(questID) or false
    if c and c.nextID and not c.nextName and C_QuestLog.GetTitleForQuestID then
        c.nextName = C_QuestLog.GetTitleForQuestID(c.nextID)
    end
    chainCache[questID] = c
    return c
end

-- Learning: remember the last turn-in and who took it; a quest offered or
-- accepted from that same NPC right after is the next step.
local LINK_WINDOW = 30
local lastTurnIn -- { id, npc, t }
local dialogNpc

local function NpcGUID()
    return UnitGUID and UnitGUID("npc") or nil
end

local function FromSameGiver(npc)
    if not lastTurnIn or GetTime() - lastTurnIn.t > LINK_WINDOW then return false end
    if lastTurnIn.npc and npc then return lastTurnIn.npc == npc end
    -- no NPC on either side (auto-accepted follow-up): only right after
    return GetTime() - lastTurnIn.t < 3
end

local learner = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_COMPLETE", "QUEST_TURNED_IN", "QUEST_DETAIL", "QUEST_ACCEPTED" }) do
    pcall(learner.RegisterEvent, learner, e)
end
learner:SetScript("OnEvent", function(_, event, a, b)
    if event == "QUEST_COMPLETE" then
        dialogNpc = NpcGUID()
    elseif event == "QUEST_TURNED_IN" then
        lastTurnIn = { id = a, npc = NpcGUID() or dialogNpc, t = GetTime() }
    elseif event == "QUEST_DETAIL" then
        local id = GetQuestID and GetQuestID()
        if id and id > 0 and lastTurnIn and FromSameGiver(NpcGUID()) then Learn(lastTurnIn.id, id) end
    elseif event == "QUEST_ACCEPTED" then
        local id = b or a -- classic: (logIndex, questID); modern: (questID)
        if type(id) == "number" and lastTurnIn and FromSameGiver(NpcGUID()) then Learn(lastTurnIn.id, id) end
    end
end)

---------------------------------------------------------------------------
-- Quest type (dungeon / raid / group ...), from the game's quest tags
---------------------------------------------------------------------------
local QT = Enum and Enum.QuestTag or {}
local KIND = {
    [QT.Dungeon or 81] = "dungeon", [QT.Heroic or 85] = "dungeon",
    [QT.Raid or 62] = "raid", [QT.Raid10 or 88] = "raid", [QT.Raid25 or 89] = "raid",
    [QT.Group or 1] = "group", [QT.PvP or 41] = "pvp",
}
local typeCache = {}

-- Returns kind ("dungeon" | "raid" | "group" | "pvp" | nil), tagName
function ns:GetQuestType(questID)
    local c = typeCache[questID]
    if c then return c[1], c[2] end
    local tagID, tagName
    if C_QuestLog.GetQuestTagInfo then
        local ok, info = pcall(C_QuestLog.GetQuestTagInfo, questID)
        if ok and type(info) == "table" then tagID, tagName = info.tagID, info.tagName end
    elseif GetQuestTagInfo then
        local ok, id, name = pcall(GetQuestTagInfo, questID)
        if ok then tagID, tagName = id, name end
    end
    local kind = tagID and KIND[tagID] or nil
    typeCache[questID] = { kind, tagName }
    return kind, tagName
end

function ns:ResetPlaceCache()
    wipe(instanceCache)
end

---------------------------------------------------------------------------
-- Dungeon quests: is the turn-in inside or outside the dungeon?
-- Forever Dungeon Journal knows the turn-in NPC of dungeon quests (the game's
-- map often points at the entrance even when the NPC is inside). Without it,
-- the map at the turn-in spot decides.
---------------------------------------------------------------------------
local fdjIndex
local function FDJIndex()
    if fdjIndex ~= nil then return fdjIndex or nil end
    local FDJ = _G.ForeverDungeonJournal_NS
    if not (type(FDJ) == "table" and type(FDJ.DB) == "table") then
        fdjIndex = false
        return nil
    end
    fdjIndex = {}
    for name, dungeon in pairs(FDJ.DB) do
        if type(dungeon) == "table" and type(dungeon.quests) == "table" then
            for _, q in ipairs(dungeon.quests) do
                if type(q) == "table" and q.id and type(q.turnin) == "string" then
                    fdjIndex[q.id] = { turnin = q.turnin, dungeon = name }
                end
            end
        end
    end
    if type(FDJ.QUEST_PREREQ_DETAILS) == "table" then
        for id, d in pairs(FDJ.QUEST_PREREQ_DETAILS) do
            if type(d) == "table" and type(d.turnin) == "string" and not fdjIndex[id] then
                fdjIndex[id] = { turnin = d.turnin }
            end
        end
    end
    return fdjIndex
end

local function TextInside(turnin, dungeon)
    local FDJ = _G.ForeverDungeonJournal_NS
    if FDJ and FDJ.TurnInInsideDungeon then
        local ok, inside = pcall(FDJ.TurnInInsideDungeon, turnin, dungeon)
        if ok then return inside and true or false end
    end
    local t = turnin:lower()
    if t:find("outside", 1, true) then return false end
    return t:find("inside", 1, true) ~= nil
end

-- Returns "inside" | "outside" | nil, turn-in text (from Forever Dungeon Journal) or nil.
function ns:GetTurnInSide(q)
    local isDungeonQuest = q.qtype == "dungeon" or q.qtype == "raid"
    local idx = FDJIndex()
    local e = idx and idx[q.id]
    if e and (e.dungeon or isDungeonQuest) then
        return TextInside(e.turnin, e.dungeon) and "inside" or "outside", e.turnin
    end
    if isDungeonQuest and q.ready and q.map then
        return q.place == "dungeon" and "inside" or "outside", nil
    end
    return nil
end
