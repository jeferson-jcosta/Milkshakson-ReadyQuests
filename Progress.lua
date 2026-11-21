-- Zone progress: how many of a zone's quests you have done ("20/50").
-- Works on its own with the game's API: the quests of a zone are learned from
-- your quest log and from the quests the game shows as available on the map,
-- and the game says which of them you have completed. The game has no list of
-- every quest in a zone, so this total grows as you play. When Questie is
-- installed (optional), its quest database gives the full total instead.
local _, ns = ...

local function Questie_()
    local loader = _G.QuestieLoader
    if not (loader and loader.ImportModule) then return nil end
    local ok, journey = pcall(loader.ImportModule, loader, "QuestieJourney")
    if not (ok and journey) then return nil end
    local zoneDB = select(2, pcall(loader.ImportModule, loader, "ZoneDB"))
    local questDB = select(2, pcall(loader.ImportModule, loader, "QuestieDB"))
    return journey, zoneDB, questDB
end

local function Counts(text)
    local a, b = tostring(text or ""):match("%[%s*(%d+)%s*/%s*(%d+)%s*%]")
    return tonumber(a), tonumber(b)
end

local function QuestInfo(questDB, id, fallback)
    local name, level
    if questDB and questDB.QueryQuestSingle then
        local ok, n = pcall(questDB.QueryQuestSingle, id, "name")
        if ok then name = n end
        local ok2, l = pcall(questDB.QueryQuestSingle, id, "questLevel")
        if ok2 then level = l end
    end
    if not name and fallback then name = fallback:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
    return name or ("#" .. id), level
end

-- Where to pick the quest up: first NPC (or object) spawn of its quest giver.
local function StartLocation(questDB, zoneDB, id)
    if not (questDB and zoneDB and questDB.QueryQuestSingle) then return nil end
    local ok, startedBy = pcall(questDB.QueryQuestSingle, id, "startedBy")
    if not (ok and type(startedBy) == "table") then return nil end
    local sources = {
        { list = startedBy[1], query = questDB.QueryNPCSingle },
        { list = startedBy[2], query = questDB.QueryObjectSingle },
    }
    for _, src in ipairs(sources) do
        if type(src.list) == "table" and src.query then
            for _, sid in ipairs(src.list) do
                local ok2, name = pcall(src.query, sid, "name")
                local ok3, spawns = pcall(src.query, sid, "spawns")
                if ok3 and type(spawns) == "table" then
                    for areaId, points in pairs(spawns) do
                        local p = type(points) == "table" and points[1]
                        if p and p[1] and p[2] then
                            local okm, uiMap = pcall(zoneDB.GetUiMapIdByAreaId, zoneDB, areaId)
                            if okm and uiMap then
                                return { map = uiMap, x = p[1] / 100, y = p[2] / 100, giver = ok2 and name or nil }
                            end
                        end
                    end
                end
            end
        end
    end
end

local cache = { key = nil, t = 0, data = nil }

function ns:InvalidateZoneProgress() cache.key = nil end

---------------------------------------------------------------------------
-- Learned from the game (no other addon needed)
---------------------------------------------------------------------------
-- ReadyQuestsDB.zoneQuests[zoneMapID][questID] = { t = title, l = level }
local function ZoneStore(zone)
    local db = ns.db
    if not (db and zone) then return nil end
    db.zoneQuests = db.zoneQuests or {}
    db.zoneQuests[zone] = db.zoneQuests[zone] or {}
    return db.zoneQuests[zone]
end

-- Quests in your log: called by the list builder with each quest's zone.
function ns:LearnQuest(zone, id, title, level)
    local store = ZoneStore(zone)
    if not (store and id and id > 0) then return end
    local e = store[id]
    if not e then
        store[id] = { t = title, l = level }
        if cache.key == zone then cache.key = nil end
    elseif title and e.t ~= title then
        e.t, e.l = title, level or e.l
    end
end

-- Quests the game offers on this zone's map right now (not accepted yet).
local available = { zone = nil, t = 0, list = {} }
local function AvailableNow(zone)
    if not (C_QuestLine and C_QuestLine.GetAvailableQuestLines) then return {} end
    local now = GetTime()
    if available.zone == zone and now - available.t < 15 then return available.list end
    if C_QuestLine.RequestQuestLinesForMap then pcall(C_QuestLine.RequestQuestLinesForMap, zone) end
    local ok, lines = pcall(C_QuestLine.GetAvailableQuestLines, zone)
    local list = {}
    if ok and type(lines) == "table" then
        for _, info in ipairs(lines) do
            local id = type(info) == "table" and tonumber(info.questID)
            if id and id > 0 then
                list[id] = { title = info.questName, x = info.x, y = info.y }
            end
        end
    end
    available.zone, available.t, available.list = zone, now, list
    return list
end

local function IsDone(id)
    if C_QuestLog.IsQuestFlaggedCompleted then
        local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, id)
        if ok then return done and true or false end
    end
    return false
end

local function LearnedProgress(zone, zoneName)
    local store = ZoneStore(zone)
    if not store then return nil, "nozone" end
    local avail = AvailableNow(zone)
    for id, a in pairs(avail) do
        if not store[id] then store[id] = { t = a.title } end
    end
    local data = { zoneName = zoneName, available = {}, completed = {}, missing = {}, learned = true }
    local done, total = 0, 0
    for id, e in pairs(store) do
        total = total + 1
        local q = { id = id, title = e.t or (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)) or ("#" .. id),
            level = e.l, progressOnly = true }
        q.inLog = C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id) or false
        if IsDone(id) then
            done = done + 1
            data.completed[#data.completed + 1] = q
        else
            local a = avail[id]
            if a and a.x and a.y then q.map, q.x, q.y = zone, a.x, a.y end
            -- in your log, or offered on the map right now
            if q.inLog or a then
                data.available[#data.available + 1] = q
            else
                data.missing[#data.missing + 1] = q -- seen before, not offered now
            end
        end
    end
    local function byTitle(a, b) return (a.title or "") < (b.title or "") end
    table.sort(data.available, byTitle)
    table.sort(data.completed, byTitle)
    table.sort(data.missing, byTitle)
    data.done, data.total = done, total
    return data
end

-- Returns progress for a zone-level uiMapID:
-- { zoneName, done, total, available = {...}, completed = {...}, missing = {...} }
-- or nil, reason ("noquestie" | "loading" | "nozone").
local function QuestieInstalled()
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Questie") or (IsAddOnLoaded and IsAddOnLoaded("Questie")) or false
end

-- Questie's lists for a zone, or nil + the step that failed (for /rq debug).
local function QuestieTree(uiMapID)
    if not QuestieInstalled() then return nil, "not installed" end
    local journey, zoneDB, questDB = Questie_()
    if not journey then return nil, "no QuestieJourney module" end
    if not (journey.private and journey.private.questsByZone) then return nil, "no questsByZone" end
    if not journey.zoneMap then return nil, "loading (Journey zoneMap not built yet)" end
    if not (zoneDB and zoneDB.GetAreaIdByUiMapId) then return nil, "no ZoneDB" end
    local okA, areaId = pcall(zoneDB.GetAreaIdByUiMapId, zoneDB, uiMapID)
    if not (okA and areaId) then return nil, "no areaId for uiMap " .. tostring(uiMapID) .. (okA and "" or (": " .. tostring(areaId))) end
    local okT, tree = pcall(journey.private.questsByZone.CollectZoneQuests, journey.private.questsByZone, areaId)
    if not okT then return nil, "CollectZoneQuests error: " .. tostring(tree) end
    if type(tree) ~= "table" then return nil, "no quests for area " .. tostring(areaId) end
    return tree, zoneDB, questDB, areaId
end
ns.ZoneProgressDiag = function(uiMapID)
    local tree, a, _, areaId = QuestieTree(uiMapID)
    if not tree then return "Questie: " .. tostring(a) end
    return ("Questie: ok, area %s | %s | %s | %s"):format(tostring(areaId), tostring(tree[2] and tree[2].text),
        tostring(tree[4] and tree[4].text), tostring(tree[5] and tree[5].text))
end

function ns:GetZoneProgress(uiMapID, zoneName)
    if not uiMapID then return nil, "nozone" end
    local now = GetTime()
    if cache.key == uiMapID and cache.data and now - cache.t < 30 then return cache.data end

    local tree, zoneDB, questDB = QuestieTree(uiMapID)
    if not tree then
        local data, reason = LearnedProgress(uiMapID, zoneName)
        -- While Questie is still loading, ask again on the next refresh.
        if data and not QuestieInstalled() then cache.key, cache.t, cache.data = uiMapID, now, data end
        return data, reason
    end

    local data = { zoneName = zoneName, available = {}, completed = {}, missing = {} }
    local done, total = Counts(tree[4] and tree[4].text)
    local avail = Counts(tree[2] and tree[2].text)
    local miss = Counts(tree[5] and tree[5].text)
    data.done, data.total = done or 0, total or 0
    data.availableCount, data.missingCount = avail or 0, miss or 0

    local function Fill(node, out, withStart)
        if not (node and type(node.children) == "table") then return end
        for _, child in ipairs(node.children) do
            local id = tonumber(child.value)
            if id then
                local name, level = QuestInfo(questDB, id, child.text)
                local q = { id = id, title = name, level = level, progressOnly = true }
                q.inLog = C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id) or false
                if withStart and not q.inLog then
                    local s = StartLocation(questDB, zoneDB, id)
                    if s then q.map, q.x, q.y, q.giver = s.map, s.x, s.y, s.giver end
                end
                out[#out + 1] = q
            end
        end
    end
    Fill(tree[2], data.available, true)
    Fill(tree[4], data.completed, false)
    Fill(tree[5], data.missing, true)

    cache.key, cache.t, cache.data = uiMapID, now, data
    return data
end
