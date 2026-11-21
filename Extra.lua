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
-- Quest chains (Blizzard quest lines first, then Questie's database)
---------------------------------------------------------------------------
local chainCache = {}

local function QuestieDB()
    local QL = _G.QuestieLoader
    if not (QL and QL.ImportModule) then return nil end
    local ok, db = pcall(QL.ImportModule, QL, "QuestieDB")
    if ok and type(db) == "table" and db.QueryQuestSingle then return db end
end

local function Q(db, id, key)
    local ok, v = pcall(db.QueryQuestSingle, id, key)
    if ok then return v end
end

local function FromQuestLine(questID)
    if not (C_QuestLine and C_QuestLine.GetQuestLineInfo and C_QuestLine.GetQuestLineQuests) then return nil end
    local ok, info = pcall(C_QuestLine.GetQuestLineInfo, questID)
    if not (ok and type(info) == "table" and info.questLineID) then return nil end
    local ok2, quests = pcall(C_QuestLine.GetQuestLineQuests, info.questLineID)
    if not (ok2 and type(quests) == "table" and #quests > 1) then return nil end
    for i, id in ipairs(quests) do
        if id == questID then
            return { name = info.questLineName, pos = i, total = #quests, nextID = quests[i + 1] }
        end
    end
end

-- Questie marks many chains only backwards (the next step lists this one as
-- its prerequisite, nextQuestInChain stays empty). Reverse index
-- prerequisite -> follow-up quests, built once in small slices.
local followUps, followBuilding

local function PreOf(db, id)
    local pre = Q(db, id, "preQuestSingle")
    if type(pre) == "number" then return pre > 0 and pre or nil end
    if type(pre) == "table" and #pre == 1 then return pre[1] end
end

local function BuildFollowUps(db, onDone)
    if followUps or followBuilding then return end
    local ptrs = db.QuestPointers
    if type(ptrs) ~= "table" then return end
    followBuilding = true
    local ids = {}
    for k, v in pairs(ptrs) do ids[#ids + 1] = type(k) == "number" and k or v end
    local map, i = {}, 1
    local function slice()
        local stop = math.min(i + 499, #ids)
        for n = i, stop do
            local id = ids[n]
            local p = type(id) == "number" and PreOf(db, id)
            if p then
                local t = map[p]
                if not t then t = {}; map[p] = t end
                t[#t + 1] = id
            end
        end
        i = stop + 1
        if i <= #ids then
            C_Timer.After(0, slice)
        else
            followUps, followBuilding = map, false
            C_Timer.After(0, onDone)
        end
    end
    slice()
end

local function NextOf(db, id)
    local n = Q(db, id, "nextQuestInChain")
    if type(n) == "number" and n > 0 then return n end
    local f = followUps and followUps[id]
    if f and #f == 1 then return f[1] end
    -- branching follow-ups: still a chain, but no single next step
    if f and #f > 1 then return nil, true end
end

local function FromQuestie(questID)
    local db = QuestieDB()
    if not db then return nil end
    local nextID, branches = NextOf(db, questID)

    -- Steps after this one
    local after, id, seen = (branches and 1 or 0), nextID, { [questID] = true }
    while id and after < 40 and not seen[id] do
        seen[id] = true
        after = after + 1
        local n, more = NextOf(db, id)
        if more then after = after + 1 end
        id = n
    end
    -- Steps before this one (single prerequisite chains)
    local before, cur = 0, questID
    while before < 40 do
        local p = PreOf(db, cur)
        if not p or seen[p] then break end
        seen[p] = true
        before = before + 1
        cur = p
    end
    if after == 0 and before == 0 then return nil end
    local nextName = nextID and (Q(db, nextID, "name") or C_QuestLog.GetTitleForQuestID(nextID))
    return { pos = before + 1, total = before + 1 + after, nextID = nextID, nextName = nextName, source = "questie" }
end

local function FromQuestLineTagged(questID)
    local c = FromQuestLine(questID)
    if c then c.source = "questline" end
    return c
end

-- Returns { pos, total, nextID, nextName, name } or false
function ns:GetChain(questID)
    local c = chainCache[questID]
    if c ~= nil then return c end
    local qdb = QuestieDB()
    if qdb and not followUps then
        -- Questie still loading or index not built yet: answer without
        -- caching, and refresh once the follow-up index is ready.
        BuildFollowUps(qdb, function() wipe(chainCache); if ns.Refresh then ns.Refresh() end end)
        return FromQuestLineTagged(questID) or FromQuestie(questID) or false
    end
    c = FromQuestLineTagged(questID) or FromQuestie(questID) or false
    if c and c.nextID and not c.nextName then
        c.nextName = C_QuestLog.GetTitleForQuestID(c.nextID)
    end
    chainCache[questID] = c
    return c
end

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
