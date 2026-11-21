-- Zone progress: how many of a zone's quests you have done ("12/100"),
-- using Questie's own Journey "Quests by Zone" lists, so the numbers match it.
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

-- Returns progress for a zone-level uiMapID:
-- { zoneName, done, total, available = {...}, completed = {...}, missing = {...} }
-- or nil, reason ("noquestie" | "loading" | "nozone").
function ns:GetZoneProgress(uiMapID, zoneName)
    local journey, zoneDB, questDB = Questie_()
    if not journey then return nil, "noquestie" end
    if not (journey.zoneMap and journey.private and journey.private.questsByZone) then return nil, "loading" end
    if not (uiMapID and zoneDB and zoneDB.GetAreaIdByUiMapId) then return nil, "nozone" end

    local now = GetTime()
    if cache.key == uiMapID and cache.data and now - cache.t < 30 then return cache.data end

    local okA, areaId = pcall(zoneDB.GetAreaIdByUiMapId, zoneDB, uiMapID)
    if not (okA and areaId) then return nil, "nozone" end
    local okT, tree = pcall(journey.private.questsByZone.CollectZoneQuests, journey.private.questsByZone, areaId)
    if not (okT and type(tree) == "table") then return nil, "nozone" end

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
