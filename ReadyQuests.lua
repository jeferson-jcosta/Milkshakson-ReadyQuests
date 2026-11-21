-- ReadyQuests: lists quests in your log that are ready to turn in,
-- grouped by turn-in location ("On this map" first), with distance and
-- optional Shortest Path Forever / TomTom integration.

local ADDON, ns = ...
local L = ns.L
local PREFIX = "|cff33ff99[ReadyQuests]|r "
local ROW_H, HEADER_H, OBJ_H, WIDTH = 18, 18, 14, 300
local TOP = 48 -- header + tab bar
local OWNER = "ReadyQuests"

local db
local defaults = { shown = true, locked = false, autoHide = true, point = nil, locale = nil,
    width = WIDTH, maxHeight = 400, showRewards = true, showPlace = true, showChain = true, showDistance = false,
    tab = "ready", collapsed = {}, showObjectives = true, autoSwitch = true,
    hideQuestie = false, hideBlizzard = false, collapsedWindow = false, avoidFDJ = true }
local MIN_W, MIN_H, MAX_W, MAX_H = 220, 70, 800, 1200

---------------------------------------------------------------------------
-- Map helpers
---------------------------------------------------------------------------
local ZONE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
local CONTINENT = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2

-- Normalize a uiMapID to its zone-level map (micro/dungeon maps -> parent zone).
local zoneCache = {}
local function ZoneOf(mapID)
    if not mapID then return nil end
    if zoneCache[mapID] ~= nil then return zoneCache[mapID] or nil end
    local id, info = mapID, C_Map.GetMapInfo(mapID)
    while info and info.mapType and info.mapType > ZONE and info.parentMapID and info.parentMapID > 0 do
        id = info.parentMapID
        info = C_Map.GetMapInfo(id)
    end
    zoneCache[mapID] = id or false
    return id
end

local function MapName(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    return info and info.name
end

local function WorldPos(mapID, x, y)
    if not (mapID and x and y) then return nil end
    local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if ok and continent and pos then return continent, pos.x, pos.y end
end

-- The zone a POI really sits in. A zone map can also list a neighbouring
-- zone's POI (The Barrens lists Theramore's turn-ins, in Dustwallow Marsh), so
-- ask the continent map which zone is at that spot and move the POI there.
local function OwnerZone(mapID, x, y)
    local info = C_Map.GetMapInfo(mapID)
    if not (info and info.mapType == ZONE and C_Map.GetMapInfoAtPosition and C_Map.GetMapPosFromWorldPos) then
        return mapID, x, y
    end
    local cont = info.parentMapID
    local cinfo = cont and C_Map.GetMapInfo(cont)
    while cinfo and cinfo.mapType and cinfo.mapType > CONTINENT and cinfo.parentMapID and cinfo.parentMapID > 0 do
        cont = cinfo.parentMapID
        cinfo = C_Map.GetMapInfo(cont)
    end
    if not (cinfo and cinfo.mapType == CONTINENT) then return mapID, x, y end
    local ok, instance, world = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if not (ok and instance and world) then return mapID, x, y end
    local ok2, _, cpos = pcall(C_Map.GetMapPosFromWorldPos, instance, world, cont)
    if not (ok2 and cpos) then return mapID, x, y end
    local ok3, at = pcall(C_Map.GetMapInfoAtPosition, cont, cpos.x, cpos.y)
    if not (ok3 and at and at.mapID) then return mapID, x, y end
    local owner = ZoneOf(at.mapID)
    local oinfo = owner and C_Map.GetMapInfo(owner)
    if not owner or owner == mapID or not (oinfo and oinfo.mapType == ZONE) then return mapID, x, y end
    local ok4, _, opos = pcall(C_Map.GetMapPosFromWorldPos, instance, world, owner)
    if not (ok4 and opos) then return mapID, x, y end
    local ox, oy = opos.x, opos.y
    if not (ox and oy and ox >= 0 and ox <= 1 and oy >= 0 and oy <= 1) then return mapID, x, y end
    return owner, ox, oy
end

local function PlayerPos()
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not (ok and pos) then return map end
    local x, y = pos:GetXY()
    return map, x, y
end

-- All zone and dungeon/cave maps of the world, collected once per loading screen.
local DUNGEON_T = Enum and Enum.UIMapType and Enum.UIMapType.Dungeon or 4
local allMaps
local function AllMaps()
    if allMaps then return allMaps end
    local map = C_Map.GetBestMapForUnit("player")
    local root, info = map, map and C_Map.GetMapInfo(map)
    while info and info.parentMapID and info.parentMapID > 0 do
        root = info.parentMapID
        info = C_Map.GetMapInfo(root)
    end
    -- Inside some instances the parent chain stops at the instance itself.
    if (not info or (info.mapType or 0) > CONTINENT) and C_Map.GetFallbackWorldMapID then
        root = C_Map.GetFallbackWorldMapID()
    end
    local list, seen = {}, {}
    local ok, children = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
    if ok and children then
        -- zones first, then dungeons / caves
        for pass = 1, 2 do
            for _, child in ipairs(children) do
                local want = (pass == 1 and child.mapType == ZONE) or (pass == 2 and child.mapType == DUNGEON_T)
                if want and not seen[child.mapID] then
                    seen[child.mapID] = true
                    list[#list + 1] = child.mapID
                end
            end
        end
    end
    if #list > 0 then allMaps = list end
    return list
end

---------------------------------------------------------------------------
-- Optional integrations
---------------------------------------------------------------------------
local function SPF()
    local api = ShortestPathForever and ShortestPathForever.API
    if type(api) == "table" and (api.version == 1 or api.version == 2) then return api end
end

local etaCache = {}
local function TravelSeconds(q, pmap, px, py)
    local api = SPF()
    if not (api and api.Estimate and q.map and pmap and px) then return nil end
    local key = q.id
    local c = etaCache[key]
    local now = GetTime()
    if c and now - c.t < 5 then return c.s end
    local ok, s = pcall(api.Estimate, pmap, px, py, q.map, q.x, q.y)
    s = ok and type(s) == "number" and s or nil
    etaCache[key] = { t = now, s = s }
    return s
end

local function FormatTime(s)
    if not s then return nil end
    s = math.floor(s + 0.5)
    if s >= 60 then return ("%dm%02ds"):format(math.floor(s / 60), s % 60) end
    return ("%ds"):format(s)
end

local function FormatDist(d)
    if not d then return "" end
    if d >= 1000 then return ("%.1fk yd"):format(d / 1000) end
    return ("%d yd"):format(math.floor(d + 0.5))
end

---------------------------------------------------------------------------
-- Collect ready quests + turn-in locations
---------------------------------------------------------------------------
local poiCache, poiDirty = {}, true

local function IsReady(id)
    local ready = C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(id)
    if ready == nil then ready = C_QuestLog.IsComplete(id) end
    return ready and not (C_QuestLog.IsFailed and C_QuestLog.IsFailed(id))
end

-- questID -> { map, x, y } of the quest's POI (turn-in for ready quests,
-- objective area otherwise). Scans the player's own map first (also inside a
-- dungeon), then every zone, then dungeon/cave maps, and stops as soon as
-- every quest in the log has a location.
local function RebuildPOIs()
    wipe(poiCache)
    local wanted, missing = {}, 0
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID and info.questID > 0 then
            wanted[info.questID] = true
            missing = missing + 1
        end
    end
    local pmap = C_Map.GetBestMapForUnit("player")
    local maps, seen = {}, {}
    local function add(m) if m and not seen[m] then seen[m] = true; maps[#maps + 1] = m end end
    add(pmap)
    add(ZoneOf(pmap))
    for _, m in ipairs(AllMaps()) do add(m) end

    for _, m in ipairs(maps) do
        if missing <= 0 then break end
        local ok, list = pcall(C_QuestLog.GetQuestsOnMap, m)
        if ok and list then
            for _, poi in ipairs(list) do
                local id = poi.questID
                if id and wanted[id] and not poiCache[id] and poi.x and poi.y then
                    local om, ox, oy = OwnerZone(m, poi.x, poi.y)
                    poiCache[id] = { map = om, x = ox, y = oy, listedOn = m }
                    missing = missing - 1
                end
            end
        end
    end
    poiDirty = false
end

local function QuestLocation(id)
    local p = poiCache[id]
    if p then return p.map, p.x, p.y end
    if C_QuestLog.GetNextWaypoint then
        local ok, map, x, y = pcall(C_QuestLog.GetNextWaypoint, id)
        if ok and map and x and y then return map, x, y end
    end
end

-- The quest's usable item (the one the game's tracker shows a button for).
local function QuestUseItem(id, ready)
    if not GetQuestLogSpecialItemInfo then return nil end
    local idx = (C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id))
        or (GetQuestLogIndexByID and GetQuestLogIndexByID(id))
    if not idx or idx <= 0 then return nil end
    local ok, link, icon, charges, showWhenComplete = pcall(GetQuestLogSpecialItemInfo, idx)
    if not (ok and link) then return nil end
    if ready and not showWhenComplete then return nil end
    local itemID = tonumber(tostring(link):match("item:(%d+)"))
    return { link = link, icon = icon, charges = charges, itemID = itemID, logIndex = idx }
end

local function Objectives(id)
    local ok, list = pcall(C_QuestLog.GetQuestObjectives, id)
    if not (ok and type(list) == "table") then return nil end
    local out = {}
    for _, o in ipairs(list) do
        local text = o.text
        if (not text or text == "") and o.type == "progressbar" and GetQuestProgressBarPercent then
            local pct = GetQuestProgressBarPercent(id)
            text = pct and ("%d%%"):format(pct) or nil
        end
        if text and text ~= "" then
            out[#out + 1] = { text = text, finished = o.finished and true or false }
        end
    end
    return out
end

ns.TABS = { "ready", "progress", "zone", "all" }

-- Inside a dungeon the game gives no player position, so distances are
-- unknown there. Quests that belong to the instance you are in count as
-- "here" (distance 0) instead of dropping to the end of the list.
local function EJInstance(mapID)
    if not (mapID and EJ_GetInstanceForMap) then return nil end
    local ok, id = pcall(EJ_GetInstanceForMap, mapID)
    return ok and type(id) == "number" and id > 0 and id or nil
end

local function CurrentInstance(pmap)
    if not IsInInstance then return nil end
    local inInstance, kind = IsInInstance()
    if not inInstance or kind == "pvp" or kind == "arena" then return nil end
    local name = GetInstanceInfo and GetInstanceInfo()
    return { name = name, ej = EJInstance(pmap), map = pmap }
end

local function InCurrentInstance(inst, q, zname)
    if not inst then return false end
    if q.map and q.map == inst.map then return true end
    if inst.ej and q.map and EJInstance(q.map) == inst.ej then return true end
    local n = inst.name
    return n ~= nil and (q.placeName == n or q.header == n or zname == n)
end

-- Every quest in the log, with location, distance and extras.
local lastOutside -- last known position outside an instance: { map, x, y }

local function CollectQuests()
    if poiDirty then RebuildPOIs() end

    local pmap, px, py = PlayerPos()
    local pzone = ZoneOf(pmap)
    local pzoneName = MapName(pzone)
    local inst = CurrentInstance(pmap)
    ns.currentInstanceName = inst and inst.name or nil
    -- Inside a dungeon there is no player position: measure from where you
    -- were before going in (the entrance), so the order does not change.
    if px and not inst then
        lastOutside = { pmap, px, py }
    elseif inst and not WorldPos(pmap, px, py) and lastOutside then
        pmap, px, py = lastOutside[1], lastOutside[2], lastOutside[3]
    end
    local pc, pwx, pwy = WorldPos(pmap, px, py)

    local list, header = {}, nil
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info then
            if info.isHeader then
                header = info.title
            elseif not info.isHidden and info.questID and info.questID > 0 then
                local id = info.questID
                local q = { id = id, title = info.title, level = info.level, header = header }
                q.ready = IsReady(id) and true or false
                q.failed = C_QuestLog.IsFailed and C_QuestLog.IsFailed(id) or false
                q.map, q.x, q.y = QuestLocation(id)
                q.zone = ZoneOf(q.map)

                -- Distance: world coordinates to the POI, else the client's own estimate.
                local qc, qwx, qwy = WorldPos(q.map, q.x, q.y)
                if pc and qc and pc == qc then
                    q.dist = math.sqrt((qwx - pwx) ^ 2 + (qwy - pwy) ^ 2)
                elseif C_QuestLog.GetDistanceSqToQuest then
                    local d = C_QuestLog.GetDistanceSqToQuest(id)
                    if d and d > 0 then q.dist = math.sqrt(d) end
                end
                q.wc, q.wx, q.wy = qc, qwx, qwy

                local zname = MapName(q.zone)
                q.here = (pzone and q.zone == pzone) or (not q.zone and pzoneName ~= nil and header == pzoneName) or false
                q.group = q.here and "\0here" or (zname or header or L.UNKNOWN_ZONE)
                q.eta = TravelSeconds(q, pmap, px, py)
                q.rewards = ns:GetRewards(id)
                q.place, q.placeName = ns:GetPlace(q.map, q.x, q.y)
                q.chain = ns:GetChain(id, q.map or pmap)
                q.qtype, q.qtypeName = ns:GetQuestType(id)
                q.side, q.sideText = ns:GetTurnInSide(q)
                if InCurrentInstance(inst, q, zname) then
                    q.dist, q.here, q.group, q.inInstance = 0, true, "\0here", true
                elseif inst and q.here then
                    -- inside a dungeon, only its own quests are "here"
                    q.here = false
                    q.group = zname or header or L.UNKNOWN_ZONE
                end
                if not q.ready then q.objectives = Objectives(id) end
                q.useItem = QuestUseItem(id, q.ready)
                list[#list + 1] = q
            end
        end
    end
    return list, pmap, px, py, pzone
end

local function byDist(a, b)
    if a.eta and b.eta and a.eta ~= b.eta then return a.eta < b.eta end
    if a.dist and b.dist and a.dist ~= b.dist then return a.dist < b.dist end
    local ra, rb = a.eta or a.dist, b.eta or b.dist
    if (ra ~= nil) ~= (rb ~= nil) then return ra ~= nil end
    return a.title < b.title
end

local function InTab(q, tab)
    if tab == "ready" then return q.ready end
    if tab == "progress" then return not q.ready end
    if tab == "zone" then return q.here end
    return true
end

-- Groups the quests of one tab. Returns groups, count, pmap, px, py, counts (per tab).
local function GetQuests(tab)
    local list, pmap, px, py, pzone = CollectQuests()
    local counts = { ready = 0, progress = 0, zone = 0, all = 0 }
    for _, q in ipairs(list) do
        for _, t in ipairs(ns.TABS) do
            if InTab(q, t) then counts[t] = counts[t] + 1 end
        end
    end

    local groups, byName, n = {}, {}, 0
    for _, q in ipairs(list) do
        if InTab(q, tab) then
            n = n + 1
            local key, title, here
            if tab == "zone" then
                key = q.ready and "\1ready" or "\2progress"
                title = q.ready and L.GROUP_READY or L.GROUP_PROGRESS
                here = q.ready
            else
                key, here = q.group, q.here
                title = q.here and L.ON_THIS_MAP:format(ns.currentInstanceName or MapName(pzone) or "?") or q.group
            end
            local g = byName[key]
            if not g then
                g = { key = key, here = here, title = title, quests = {} }
                byName[key] = g
                groups[#groups + 1] = g
            end
            g.quests[#g.quests + 1] = q
            if q.eta and (not g.bestEta or q.eta < g.bestEta) then g.bestEta = q.eta end
            if q.dist and (not g.bestDist or q.dist < g.bestDist) then g.bestDist = q.dist end
        end
    end

    for _, g in ipairs(groups) do table.sort(g.quests, byDist) end
    if tab == "zone" then
        table.sort(groups, function(a, b) return a.key < b.key end)
    else
        -- Nearest first: travel time (Shortest Path) when both groups have it,
        -- else straight-line distance; the current map only wins ties/unknowns.
        table.sort(groups, function(a, b)
            if a.bestEta and b.bestEta and a.bestEta ~= b.bestEta then return a.bestEta < b.bestEta end
            if a.bestDist and b.bestDist and a.bestDist ~= b.bestDist then return a.bestDist < b.bestDist end
            if a.here ~= b.here then return a.here end
            local ra, rb = a.bestEta or a.bestDist, b.bestEta or b.bestDist
            if (ra ~= nil) ~= (rb ~= nil) then return ra ~= nil end
            return a.title < b.title
        end)
    end
    return groups, n, pmap, px, py, counts, list
end

local function GetReadyQuests() return GetQuests("ready") end

---------------------------------------------------------------------------
-- Navigation
---------------------------------------------------------------------------
local function OpenOnMap(q)
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
        C_SuperTrack.SetSuperTrackedQuestID(q.id)
    end
    if QuestMapFrame_OpenToQuestDetails and not InCombatLockdown() then
        QuestMapFrame_OpenToQuestDetails(q.id)
    end
end

local function NavigateTo(q)
    if not q.map then
        print(PREFIX .. (q.ready and L.NO_COORDS or L.NO_COORDS_OBJ))
        OpenOnMap(q)
        return
    end
    local title = q.ready and L.STOP_ONE:format(q.title) or L.STOP_OBJ:format(q.title)
    local api = SPF()
    if api and api.NavigateRoute then
        local ok, started = pcall(api.NavigateRoute, OWNER, { {
            map = q.map, x = q.x, y = q.y, title = title,
            kind = q.ready and "turnin" or "objective",
            handins = q.ready and { q.id } or nil,
        } })
        if ok and started then return end
        print(PREFIX .. L.ROUTE_FAILED)
    elseif TomTom and TomTom.AddWaypoint then
        TomTom:AddWaypoint(q.map, q.x, q.y, { title = q.title, questID = q.id, from = OWNER, crazy = true })
        return
    end
    -- Blizzard fallback: super-track the quest (arrow points to its POI).
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
        C_SuperTrack.SetSuperTrackedQuestID(q.id)
    end
end

local function IsWatched(id)
    if C_QuestLog.GetQuestWatchType then return C_QuestLog.GetQuestWatchType(id) ~= nil end
    if IsQuestWatched and GetQuestLogIndexByID then
        local i = GetQuestLogIndexByID(id)
        return i and i > 0 and IsQuestWatched(i) or false
    end
    return false
end

local function SetWatched(id, on)
    if on then
        if C_QuestLog.AddQuestWatch then pcall(C_QuestLog.AddQuestWatch, id) end
    else
        if C_QuestLog.RemoveQuestWatch then pcall(C_QuestLog.RemoveQuestWatch, id) end
    end
end

local function ShareQuest(q)
    if C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(q.id) end
    if QuestLogPushQuest then pcall(QuestLogPushQuest) end
end

local function AbandonQuest(q)
    if not (C_QuestLog.SetSelectedQuest and C_QuestLog.SetAbandonQuest and StaticPopup_Show) then
        OpenOnMap(q)
        return
    end
    C_QuestLog.SetSelectedQuest(q.id)
    C_QuestLog.SetAbandonQuest()
    StaticPopup_Show("ABANDON_QUEST", q.title)
end

-- Ask for help: post the quest (link + what is still missing) in party/raid
-- or in a chat channel you have joined. Sent from the menu click, which is a
-- hardware event, as the game requires for public channels.
local HELP_COOLDOWN = 30
local lastHelp = {}

local function HelpMessage(q)
    local link = GetQuestLink and GetQuestLink(q.id) or ("[" .. (q.title or "?") .. "]")
    local missing = {}
    for _, o in ipairs(Objectives(q.id) or {}) do
        if not o.finished then missing[#missing + 1] = o.text end
    end
    local msg = L.HELP_MSG:format(link)
    if #missing > 0 then
        msg = msg .. " - " .. table.concat(missing, ", ")
    end
    if #msg > 255 then msg = msg:sub(1, 252) .. "..." end
    return msg
end

local function JoinedChannels()
    local out = {}
    if not GetChannelList then return out end
    local list = { GetChannelList() }
    -- id, name, disabled triples (older clients: id, name pairs)
    local stride = (type(list[3]) == "boolean") and 3 or 2
    for i = 1, #list, stride do
        local id, name, disabled = list[i], list[i + 1], stride == 3 and list[i + 2]
        if type(id) == "number" and type(name) == "string" and not disabled then
            out[#out + 1] = { id = id, name = name }
        end
    end
    return out
end

local function AskForHelp(q, chatType, channel)
    local key = chatType .. (channel or "")
    local now = GetTime()
    if lastHelp[key] and now - lastHelp[key] < HELP_COOLDOWN then
        print(PREFIX .. L.HELP_WAIT:format(math.ceil(HELP_COOLDOWN - (now - lastHelp[key]))))
        return
    end
    lastHelp[key] = now
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    send(HelpMessage(q), chatType, nil, channel)
end

local function HelpMenu(root, q)
    local sub = root:CreateButton(L.MENU_HELP)
    if IsInGroup and IsInGroup() then
        local kind = (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
        sub:CreateButton(kind == "RAID" and L.MENU_HELP_RAID or L.MENU_HELP_PARTY,
            function() AskForHelp(q, kind) end)
    end
    for _, c in ipairs(JoinedChannels()) do
        sub:CreateButton(("%d. %s"):format(c.id, c.name), function() AskForHelp(q, "CHANNEL", c.id) end)
    end
    sub:CreateButton(L.MENU_HELP_SAY, function() AskForHelp(q, "SAY") end)
end

local function QuestMenu(owner, q)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        OpenOnMap(q)
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(q.title)
        root:CreateButton(L.MENU_ROUTE, function() NavigateTo(q) end)
        root:CreateButton(L.MENU_MAP, function() OpenOnMap(q) end)
        if IsWatched(q.id) then
            root:CreateButton(L.MENU_UNTRACK, function() SetWatched(q.id, false) end)
        else
            root:CreateButton(L.MENU_TRACK, function() SetWatched(q.id, true) end)
        end
        local pushable = C_QuestLog.IsPushableQuest and C_QuestLog.IsPushableQuest(q.id)
        if pushable and IsInGroup and IsInGroup() then
            root:CreateButton(L.MENU_SHARE, function() ShareQuest(q) end)
        end
        if not q.ready then HelpMenu(root, q) end
        local canAbandon = not C_QuestLog.CanAbandonQuest or C_QuestLog.CanAbandonQuest(q.id)
        if canAbandon then
            root:CreateButton("|cffff4040" .. L.MENU_ABANDON .. "|r", function() AbandonQuest(q) end)
        end
    end)
end

-- One journey through every known turn-in, nearest-neighbour order,
-- quests turned in at the same spot merged into one stop.
local function RouteAll(onlyHere)
    local api = SPF()
    if not (api and api.NavigateRoute) then
        print(PREFIX .. L.NEED_SPF)
        return
    end
    local groups, _, pmap, px, py = GetReadyQuests()
    local pc, cx, cy = WorldPos(pmap, px, py)

    local stops = {}
    for _, g in ipairs(groups) do
        if not onlyHere or g.here then
            for _, q in ipairs(g.quests) do
                if q.map and q.wc then
                    local merged
                    for _, s in ipairs(stops) do
                        if s.wc == q.wc and (s.wx - q.wx) ^ 2 + (s.wy - q.wy) ^ 2 < 15 * 15 then
                            merged = s
                        end
                    end
                    if merged then
                        merged.handins[#merged.handins + 1] = q.id
                        merged.names[#merged.names + 1] = q.title
                    else
                        stops[#stops + 1] = { map = q.map, x = q.x, y = q.y, wc = q.wc, wx = q.wx, wy = q.wy,
                            handins = { q.id }, names = { q.title } }
                    end
                end
            end
        end
    end
    if #stops == 0 then
        print(PREFIX .. L.ROUTE_NONE)
        return
    end

    -- Nearest neighbour; stops on another continent go last, in group order.
    local ordered, left = {}, stops
    while #left > 0 and #ordered < 64 do
        local bi, bd
        for i, s in ipairs(left) do
            local d = (pc and s.wc == pc) and ((s.wx - cx) ^ 2 + (s.wy - cy) ^ 2) or math.huge
            if not bd or d < bd then bi, bd = i, d end
        end
        local s = table.remove(left, bi)
        ordered[#ordered + 1] = s
        if s.wc ~= pc then pc = s.wc end
        cx, cy = s.wx, s.wy
    end

    local route = {}
    for _, s in ipairs(ordered) do
        route[#route + 1] = {
            map = s.map, x = s.x, y = s.y, kind = "turnin", handins = s.handins,
            title = #s.names == 1 and L.STOP_ONE:format(s.names[1]) or L.STOP_MANY:format(#s.names),
            tooltip = table.concat(s.names, "\n"),
        }
    end
    local ok, started = pcall(api.NavigateRoute, OWNER, route)
    if ok and started then
        print(PREFIX .. L.ROUTE_STARTED:format(#route))
    else
        print(PREFIX .. L.ROUTE_FAILED)
    end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local frame = CreateFrame("Frame", "ReadyQuestsFrame", UIParent, "BackdropTemplate")
frame:SetSize(WIDTH, 40)
frame:SetPoint("RIGHT", UIParent, "RIGHT", -260, 120)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
frame:SetBackdropColor(0, 0, 0, 0.75)
frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
frame:Hide()

frame:SetScript("OnDragStart", function(self)
    if not db.locked and not (ns.UseButtonsLocked and ns.UseButtonsLocked()) then self:StartMoving() end
end)
local dock = { active = false, userMoved = false }

local function HomePoint()
    frame:ClearAllPoints()
    if db and db.point then
        frame:SetPoint(db.point[1], UIParent, db.point[2], db.point[3], db.point[4])
    else
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -260, 120)
    end
end

frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if ns.SyncUseButtons then ns.SyncUseButtons() end
    local p, _, rp, x, y = self:GetPoint()
    db.point = { p, rp, x, y }
    if dock.active then dock.active, dock.userMoved = false, true end
end)

-- ForeverDungeonJournal's run tracker (bosses, timer) opens in the same corner.
-- While it is shown and covers this window, sit right below it; go back home
-- when it closes. Dragging this window turns it off until the tracker closes.
local function Rect(f)
    local l, b, w, h = f:GetRect()
    if not l then return nil end
    local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return l * k, b * k, (l + w) * k, (b + h) * k
end

local function Overlaps(a, b)
    local al, ab, ar, at = Rect(a)
    local bl, bb, br, bt = Rect(b)
    if not (al and bl) then return false end
    return al < br and ar > bl and ab < bt and at > bb
end

local fdjHooked = false
local function UpdateDock()
    if not db then return end
    local fdj = _G.ForeverDungeonJournalRunTracker
    if fdj and not fdjHooked then
        fdjHooked = true
        fdj:HookScript("OnShow", function() C_Timer.After(0, UpdateDock) end)
        fdj:HookScript("OnHide", function() C_Timer.After(0, UpdateDock) end)
        fdj:HookScript("OnSizeChanged", function() C_Timer.After(0, UpdateDock) end)
    end
    local open = db.avoidFDJ and fdj and fdj:IsShown() and frame:IsShown()
    if not open then
        dock.userMoved = false
        if dock.active then
            dock.active = false
            HomePoint()
        end
        return
    end
    if dock.userMoved then return end
    if not dock.active then
        HomePoint()
        if not Overlaps(frame, fdj) then return end
        dock.active = true
    end
    local l, b, r = Rect(fdj)
    if not l then return end
    local myR = select(3, Rect(frame)) or r
    frame:ClearAllPoints()
    frame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", myR, b - 4)
end
ns.UpdateDock = function() UpdateDock() end

local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
header:SetPoint("TOPLEFT", 24, -7)

-- Collapse / expand button (like Questie's tracker): keeps only the title bar.
local Refresh
local collapseBtn = CreateFrame("Button", nil, frame)
collapseBtn:SetSize(14, 14)
collapseBtn:SetPoint("TOPLEFT", 7, -6)
local function UpdateCollapseButton()
    local tex = db and db.collapsedWindow and "Interface\\Buttons\\UI-PlusButton-" or "Interface\\Buttons\\UI-MinusButton-"
    collapseBtn:SetNormalTexture(tex .. "Up")
    collapseBtn:SetPushedTexture(tex .. "Down")
    collapseBtn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
end
local function ToggleCollapsed()
    db.collapsedWindow = not db.collapsedWindow
    Refresh()
end
ns.ToggleCollapsed = function() ToggleCollapsed() end
collapseBtn:SetScript("OnClick", ToggleCollapsed)
collapseBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(db.collapsedWindow and L.EXPAND or L.COLLAPSE)
    GameTooltip:Show()
end)
collapseBtn:SetScript("OnLeave", GameTooltip_Hide)

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
close:SetSize(20, 20)
close:SetPoint("TOPRIGHT", 0, 0)
close:SetScript("OnClick", function()
    db.shown = false
    frame:Hide()
    print(PREFIX .. L.HIDDEN)
end)

-- "Route" button (only with Shortest Path Forever)
local routeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
routeBtn:SetSize(56, 18)
routeBtn:SetPoint("RIGHT", close, "LEFT", -2, 0)
routeBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
routeBtn:SetScript("OnClick", function(_, button) RouteAll(button == "RightButton") end)
routeBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L.ROUTE_BTN)
    GameTooltip:AddLine(L.ROUTE_TIP, 1, 1, 1, true)
    GameTooltip:AddLine(L.ROUTE_TIP_RIGHT, 0.5, 0.8, 1, true)
    GameTooltip:Show()
end)
routeBtn:SetScript("OnLeave", GameTooltip_Hide)

-- Tab bar ------------------------------------------------------------------
local tabs = {}
local TAB_LABEL = { ready = "TAB_READY", progress = "TAB_PROGRESS", zone = "TAB_ZONE", all = "TAB_ALL" }
local TAB_TIP = { ready = "TAB_READY_TIP", progress = "TAB_PROGRESS_TIP", zone = "TAB_ZONE_TIP", all = "TAB_ALL_TIP" }
local tabBar = CreateFrame("Frame", nil, frame)
tabBar:SetPoint("TOPLEFT", 6, -25)
tabBar:SetPoint("TOPRIGHT", -6, -25)
tabBar:SetHeight(18)

local function SelectTab(key)
    db.tab = key
    Refresh()
end

for i, key in ipairs({ "ready", "progress", "zone", "all" }) do
    local b = CreateFrame("Button", nil, tabBar)
    b.key = key
    b:SetHeight(18)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetPoint("BOTTOMLEFT")
    b.line:SetPoint("BOTTOMRIGHT")
    b.line:SetHeight(2)
    b.line:SetColorTexture(1, 0.82, 0, 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("LEFT", 2, 0)
    b.text:SetPoint("RIGHT", -2, 0)
    b.text:SetWordWrap(false)
    b:SetScript("OnClick", function(self) SelectTab(self.key) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L[TAB_LABEL[self.key]])
        GameTooltip:AddLine(L[TAB_TIP[self.key]], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    tabs[i] = b
end
-- Tab widths follow their labels, so counts like "28/40" are never cut off.
local function LayoutTabs()
    local w = tabBar:GetWidth()
    if not w or w <= 0 then return end
    local need, sum = {}, 0
    for i, b in ipairs(tabs) do
        local tw = b.text.GetUnboundedStringWidth and b.text:GetUnboundedStringWidth() or b.text:GetStringWidth()
        need[i] = (tw or 40) + 10
        sum = sum + need[i]
    end
    local free = w - 3 * 2
    local extra = (free - sum) / #tabs
    local x = 0
    for i, b in ipairs(tabs) do
        local bw = math.max(20, need[i] + extra)
        if sum > free then bw = free * need[i] / sum end
        b:SetWidth(bw)
        b:ClearAllPoints()
        b:SetPoint("LEFT", x, 0)
        x = x + bw + 2
    end
end
tabBar:SetScript("OnSizeChanged", LayoutTabs)

local function MaxQuests()
    local max = C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept()
        or (C_QuestLog.GetMaxNumQuests and C_QuestLog.GetMaxNumQuests()) or _G.MAX_QUESTS
    if issecretvalue and issecretvalue(max) then return nil end
    max = tonumber(max)
    return max and max > 0 and max or nil
end

local function UpdateTabs(counts)
    for _, b in ipairs(tabs) do
        local n = counts[b.key] or 0
        local active = db.tab == b.key
        local count = n > 0 and (" |cffffffff%d|r"):format(n) or ""
        if b.key == "all" then
            local max = MaxQuests()
            if max then count = (" |cffffffff%d/%d|r"):format(n, max) end
        end
        b.text:SetText(L[TAB_LABEL[b.key]] .. count)
        b.text:SetFontObject(active and GameFontHighlightSmall or GameFontNormalSmall)
        b.bg:SetColorTexture(1, 1, 1, active and 0.12 or 0.04)
        b.line:SetShown(active)
        if not active then b.text:SetTextColor(0.75, 0.75, 0.75) end
    end
    LayoutTabs()
end

local empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
empty:SetPoint("TOPLEFT", 10, -(TOP + 4))

-- Scrollable list area (mouse wheel) -------------------------------------
local scroll = CreateFrame("ScrollFrame", nil, frame)
scroll:SetPoint("TOPLEFT", 6, -TOP)
scroll:SetPoint("BOTTOMRIGHT", -6, 8)
scroll:EnableMouseWheel(true)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(WIDTH - 12, 1)
scroll:SetScrollChild(content)
scroll:SetScript("OnSizeChanged", function(self, w) content:SetWidth(w) end)

local function ClampScroll()
    local maxScroll = math.max(0, content:GetHeight() - scroll:GetHeight())
    scroll:SetVerticalScroll(math.min(math.max(scroll:GetVerticalScroll(), 0), maxScroll))
end
scroll:SetScript("OnMouseWheel", function(self, delta)
    if ns.UseButtonsLocked and ns.UseButtonsLocked() then return end
    self:SetVerticalScroll(self:GetVerticalScroll() - delta * ROW_H * 2)
    ClampScroll()
    if ns.SyncUseButtons then ns.SyncUseButtons() end
end)

-- Resize grip (bottom-right) ----------------------------------------------
local sizing = false
frame:SetResizable(true)
if frame.SetResizeBounds then
    frame:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
elseif frame.SetMinResize then
    frame:SetMinResize(MIN_W, MIN_H)
    frame:SetMaxResize(MAX_W, MAX_H)
end
local grip = CreateFrame("Button", nil, frame)
grip:SetSize(14, 14)
grip:SetPoint("BOTTOMRIGHT", -3, 3)
grip:SetFrameLevel(frame:GetFrameLevel() + 10)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

---------------------------------------------------------------------------
-- Rows (pooled; used for group headers and quests)
---------------------------------------------------------------------------
local rows = {}

---------------------------------------------------------------------------
-- Reward indicators
---------------------------------------------------------------------------
local ICON_GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12|t"
local ICON_UP = "|TInterface\\Buttons\\UI-MicroStream-Green:12:12|t"
local ICON_CHAIN = "|TInterface\\AddOns\\Milkshakson-ReadyQuests\\Media\\Chain:13:13|t"

local function Icon(tex) return tex and ("|T%s:13:13|t"):format(tex) or "" end

local function LevelsUp(xpState, xp)
    if not xpState or xpState.atMax or not xp or xp <= 0 then return 0 end
    return math.floor((xpState.cur + xp) / xpState.max)
end

local function RewardTags(q, xpState)
    local t = {}
    if db.showPlace and q.side == "inside" then
        t[#t + 1] = "|cffff8040" .. L.TAG_INSIDE .. "|r"
    elseif db.showPlace and q.side == "outside" then
        t[#t + 1] = "|cff80c8ff" .. L.TAG_OUTSIDE .. "|r"
    elseif db.showPlace and q.place == "dungeon" then
        t[#t + 1] = "|cffff8040" .. L.TAG_DUNGEON .. "|r"
    end
    if db.showPlace and q.place == "cave" and not q.side then t[#t + 1] = "|cffc8a060" .. L.TAG_CAVE .. "|r" end
    if db.showPlace and q.qtype then
        local name = q.qtypeName or (q.qtype == "raid" and L.QTYPE_RAID) or (q.qtype == "dungeon" and L.QTYPE_DUNGEON) or q.qtype
        t[#t + 1] = "|cffa335ee[" .. name .. "]|r"
    end
    if db.showChain and q.chain then
        local c = q.chain
        local known = c.source ~= "learned"
        t[#t + 1] = ICON_CHAIN .. "|cffffcc00" .. (known and ("%d/%d"):format(c.pos, c.total) or tostring(c.pos)) .. "|r"
    end
    local r = q.rewards
    if not r or not db.showRewards then return table.concat(t, " ") end
    if LevelsUp(xpState, r.xp) > 0 then t[#t + 1] = "|cff00ff00" .. L.TAG_LEVEL .. "|r" end
    if r.xp > 0 and xpState and not xpState.atMax then t[#t + 1] = "|cff9999ff" .. L.TAG_XP .. "|r" end
    if r.money > 0 then t[#t + 1] = ICON_GOLD end
    return table.concat(t, " ")
end

local function AddItemLines(list, label)
    if #list == 0 then return end
    GameTooltip:AddLine(label, 1, 0.82, 0)
    for _, it in ipairs(list) do
        local text = Icon(it.texture) .. " " .. (it.link or it.name or "...")
        if it.count and it.count > 1 then text = text .. " x" .. it.count end
        if it.upgrade then
            text = text .. " " .. ICON_UP .. "|cff00ff00" .. L.REW_UPGRADE .. "|r"
            if it.upgradeDetail == "empty" then
                text = text .. " |cff999999(" .. L.REW_EMPTY_SLOT .. ")|r"
            elseif it.upgradeDetail then
                text = text .. " |cff999999(" .. it.upgradeDetail .. ")|r"
            end
        elseif it.usable == false then
            text = text .. " |cffff4040" .. L.REW_UNUSABLE .. "|r"
        end
        GameTooltip:AddLine(text, 1, 1, 1)
    end
end

local function AddRewardTooltip(q)
    local r = q.rewards
    if not r then return end
    local xpState = ns:XPState()
    local any = r.xp > 0 or r.money > 0 or #r.items > 0 or #r.choices > 0 or #r.currencies > 0
    if not any then return end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.REW_HEADER, 1, 0.82, 0)
    if r.xp > 0 and xpState and not xpState.atMax then
        local pct = math.floor(r.xp / xpState.max * 100 + 0.5)
        GameTooltip:AddLine(L.REW_XP:format(BreakUpLargeNumbers and BreakUpLargeNumbers(r.xp) or r.xp, pct), 0.6, 0.6, 1)
        if LevelsUp(xpState, r.xp) > 0 then
            GameTooltip:AddLine(L.REW_LEVELUP:format(xpState.level + 1), 0, 1, 0)
        end
    end
    if r.money > 0 then
        GameTooltip:AddLine(L.REW_MONEY:format(GetMoneyString and GetMoneyString(r.money) or (r.money .. "c")), 1, 1, 1)
    end
    AddItemLines(r.items, L.REW_ITEMS)
    AddItemLines(r.choices, L.REW_CHOICE)
    for _, c in ipairs(r.currencies) do
        GameTooltip:AddLine(Icon(c.texture) .. " " .. (c.name or "?") .. (c.count and (" x" .. c.count) or ""), 1, 1, 1)
    end
end

local MAX_ICONS, ICON_SIZE = 4, 15

local function ItemButton_OnEnter(self)
    local it = self.item
    if not it then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if it.link then
        GameTooltip:SetHyperlink(it.link) -- Pawn, GearQuest etc. add their lines here
    else
        GameTooltip:SetText(it.name or "...")
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(self.isChoice and L.ITEM_CHOICE or L.ITEM_REWARD, 1, 0.82, 0)
    if it.upgrade then
        local why = it.upgradeDetail == "empty" and L.REW_EMPTY_SLOT or it.upgradeDetail
        GameTooltip:AddLine(L.REW_UPGRADE .. (why and (" (" .. why .. ")") or ""), 0, 1, 0)
    elseif it.usable == false then
        GameTooltip:AddLine(L.REW_UNUSABLE, 1, 0.25, 0.25)
    end
    GameTooltip:AddLine(L.HINT_ITEM, 0.5, 0.8, 1)
    GameTooltip:Show()
    -- Side-by-side comparison with what you wear (Shift, or "always compare" setting).
    local compare = (IsModifiedClick and IsModifiedClick("COMPAREITEMS"))
        or (GetCVarBool and GetCVarBool("alwaysCompareItems"))
    if it.link and compare and GameTooltip_ShowCompareItem then
        pcall(GameTooltip_ShowCompareItem, GameTooltip)
    end
end

local function ItemButton_OnClick(self)
    local it = self.item
    if not (it and it.link) then return end
    if IsShiftKeyDown() then
        local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
        if insert then insert(it.link) end
    elseif IsControlKeyDown() and DressUpItemLink then
        DressUpItemLink(it.link)
    end
end

local function CreateItemButtons(row)
    row.items = {}
    for i = 1, MAX_ICONS do
        local b = CreateFrame("Button", nil, row)
        b:SetSize(ICON_SIZE, ICON_SIZE)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.up = b:CreateTexture(nil, "OVERLAY")
        b.up:SetSize(10, 10)
        b.up:SetPoint("BOTTOMRIGHT", 3, -2)
        b.up:SetTexture("Interface\\Buttons\\UI-MicroStream-Green")
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.25)
        b:SetScript("OnEnter", ItemButton_OnEnter)
        b:SetScript("OnLeave", function()
            GameTooltip:Hide()
            if ShoppingTooltip1 then ShoppingTooltip1:Hide() end
            if ShoppingTooltip2 then ShoppingTooltip2:Hide() end
        end)
        b:SetScript("OnClick", ItemButton_OnClick)
        b:Hide()
        row.items[i] = b
    end
end

-- Lays out reward icons right-to-left, left of the text tags. Returns the leftmost anchor.
local function SetItemButtons(row, q)
    local list = {}
    local r = q and db.showRewards and q.rewards
    if r then
        for _, it in ipairs(r.items) do list[#list + 1] = { it, false } end
        for _, it in ipairs(r.choices) do list[#list + 1] = { it, true } end
        -- Upgrades first so they are never cut off.
        table.sort(list, function(a, b)
            if (a[1].upgrade == true) ~= (b[1].upgrade == true) then return a[1].upgrade == true end
            return false
        end)
    end
    local anchor = row.tags
    for i, b in ipairs(row.items) do
        local entry = list[i]
        if entry then
            local it, isChoice = entry[1], entry[2]
            b.item, b.isChoice = it, isChoice
            b.icon:SetTexture(it.texture or 134400)
            b.icon:SetDesaturated(it.usable == false)
            if it.usable == false then b.icon:SetVertexColor(1, 0.3, 0.3) else b.icon:SetVertexColor(1, 1, 1) end
            b.up:SetShown(it.upgrade == true)
            b:ClearAllPoints()
            b:SetPoint("RIGHT", anchor, "LEFT", anchor == row.tags and -4 or -2, 0)
            b:Show()
            anchor = b
        else
            b.item = nil
            b:Hide()
        end
    end
    return anchor
end

local function Row_OnEnter(self)
    local q = self.quest
    if not q then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    local link = GetQuestLink(q.id)
    if not (link and pcall(GameTooltip.SetHyperlink, GameTooltip, link)) then
        GameTooltip:SetText(q.title)
    end
    GameTooltip:AddLine(" ")
    local where = MapName(q.zone) or q.header or L.UNKNOWN_ZONE
    if q.ready then
        GameTooltip:AddLine(L.TURNIN_AT:format(where), 1, 1, 1)
    else
        GameTooltip:AddLine(L.OBJECTIVE_AT:format(where), 1, 1, 1)
    end
    if q.map and q.x then
        GameTooltip:AddLine(("%.1f, %.1f"):format(q.x * 100, q.y * 100), 0.7, 0.7, 0.7)
    end
    local wp = C_QuestLog.GetNextWaypointText and C_QuestLog.GetNextWaypointText(q.id)
    if wp and wp ~= "" then GameTooltip:AddLine(wp, 1, 0.82, 0, true) end
    if q.dist then GameTooltip:AddLine(L.DISTANCE:format(math.floor(q.dist + 0.5)), 0.8, 0.8, 0.8) end
    if q.eta then GameTooltip:AddLine(L.TRAVEL:format(FormatTime(q.eta)), 0.8, 0.8, 0.8) end
    if q.side then
        local line = q.side == "inside" and L.SIDE_INSIDE or L.SIDE_OUTSIDE
        GameTooltip:AddLine(line, q.side == "inside" and 1 or 0.5, q.side == "inside" and 0.55 or 0.8, q.side == "inside" and 0.25 or 1)
        if q.sideText then GameTooltip:AddLine(q.sideText, 0.8, 0.8, 0.8, true) end
    elseif q.place and q.ready then
        local txt = q.place == "dungeon" and L.PLACE_DUNGEON or L.PLACE_CAVE
        GameTooltip:AddLine(txt:format(q.placeName or "?"), 1, 0.55, 0.25)
    end
    if q.qtype then
        GameTooltip:AddLine(L.QTYPE_LINE:format(q.qtypeName or q.qtype), 0.75, 0.45, 1)
    end
    if q.chain then
        local c = q.chain
        local pos = c.source ~= "learned" and L.CHAIN_POS:format(c.pos, c.total) or L.CHAIN_STEP:format(c.pos)
        GameTooltip:AddLine(pos .. (c.name and (" - " .. c.name) or ""), 1, 0.8, 0)
        if c.prevID and C_QuestLog.GetTitleForQuestID then
            local pt = C_QuestLog.GetTitleForQuestID(c.prevID)
            if pt then GameTooltip:AddLine(L.CHAIN_PREV:format(pt), 0.8, 0.8, 0.8, true) end
        end
        if q.chain.nextID then
            GameTooltip:AddLine(L.CHAIN_NEXT:format(q.chain.nextName or ("#" .. q.chain.nextID)), 1, 1, 1, true)
        elseif q.chain.source ~= "learned" then
            GameTooltip:AddLine(L.CHAIN_LAST, 0.7, 0.7, 0.7)
        end
    end
    if db.showRewards then AddRewardTooltip(q) end
    GameTooltip:AddLine(" ")
    if SPF() then
        GameTooltip:AddLine(L.HINT_CLICK_SPF, 0.5, 0.8, 1)
    elseif TomTom and TomTom.AddWaypoint then
        GameTooltip:AddLine(L.HINT_CLICK_TOMTOM, 0.5, 0.8, 1)
    else
        GameTooltip:AddLine(L.HINT_CLICK, 0.5, 0.8, 1)
    end
    GameTooltip:AddLine(L.HINT_RIGHT, 0.5, 0.8, 1)
    GameTooltip:AddLine(L.HINT_SHIFT, 0.5, 0.8, 1)
    GameTooltip:Show()
end

local function Row_OnClick(self, button)
    if self.groupKey then
        db.collapsed[self.groupKey] = not db.collapsed[self.groupKey] or nil
        Refresh()
        return
    end
    local q = self.quest
    if not q then return end
    if IsShiftKeyDown() then
        local link = GetQuestLink(q.id)
        local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
        if link and insert then insert(link) end
    elseif button == "RightButton" then
        QuestMenu(self, q)
    else
        NavigateTo(q)
    end
end

local function GetRow(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, content)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("LEFT", 2, 0)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)

    row.dist = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.dist:SetPoint("RIGHT", -2, 0)
    row.dist:SetJustifyH("RIGHT")

    row.tags = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.tags:SetPoint("RIGHT", row.dist, "LEFT", -4, 0)
    row.tags:SetJustifyH("RIGHT")
    CreateItemButtons(row)

    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0.08)

    row:SetScript("OnEnter", Row_OnEnter)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", Row_OnClick)
    rows[i] = row
    return row
end

local function SetupHeaderRow(row, g, y, collapsed)
    row.quest = nil
    row.groupKey = db.tab .. ":" .. g.key
    row:EnableMouse(true)
    row:SetHeight(HEADER_H)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
    row.icon:Hide()
    row.tags:SetText("")
    SetItemButtons(row, nil)
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", 2, -2)
    row.text:SetPoint("RIGHT", -60, -2)
    row.text:SetFontObject(GameFontNormalSmall)
    row.text:SetTextColor(1, 1, 1)
    local sign = collapsed and "|cff999999[+]|r " or "|cff999999[-]|r "
    if g.here then
        row.text:SetText(sign .. "|cff66ff66" .. g.title .. "|r")
    else
        row.text:SetText(sign .. "|cffffd100" .. g.title .. "|r")
    end
    row.dist:ClearAllPoints()
    row.dist:SetPoint("RIGHT", -2, 0)
    row.dist:SetText(("(%d)"):format(#g.quests))
    row.tags:ClearAllPoints()
    row.tags:SetPoint("RIGHT", row.dist, "LEFT", -4, 0)
    row:Show()
end

local function SetupObjectiveRow(row, o, y)
    row.quest, row.groupKey = nil, nil
    row:EnableMouse(false)
    row:SetHeight(OBJ_H)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
    row.icon:Hide()
    row.tags:SetText("")
    row.dist:SetText("")
    SetItemButtons(row, nil)
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", 30, 0)
    row.text:SetPoint("RIGHT", -4, 0)
    row.text:SetFontObject(GameFontHighlightSmall)
    if o.finished then
        row.text:SetText("|cff00c000- " .. o.text .. "|r")
    else
        row.text:SetText("|cffc8c8c8- " .. o.text .. "|r")
    end
    row:Show()
end

local function SetupQuestRow(row, q, y)
    row.quest, row.groupKey = q, nil
    row:EnableMouse(true)
    row:SetHeight(ROW_H)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
    if q.ready then
        row.icon:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
        row.icon:SetDesaturated(false)
    else
        row.icon:SetTexture("Interface\\GossipFrame\\IncompleteQuestIcon")
        row.icon:SetDesaturated(false)
    end
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", 10, 0)
    row.icon:Show()
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.text:SetPoint("RIGHT", row.tags, "LEFT", -4, 0) -- re-anchored below once icons are placed
    row.text:SetFontObject(GameFontHighlightSmall)
    local lvl = q.level and q.level > 0 and ("[%d] "):format(q.level) or ""
    local title = q.title
    if q.failed then title = "|cffff4040" .. title .. "|r" end
    row.text:SetText(lvl .. title)
    local right = ""
    if db.showDistance then
        right = q.inInstance and "" or FormatDist(q.dist)
        if q.eta then right = (right ~= "" and (right .. " · ") or "") .. FormatTime(q.eta) end
    end
    row.dist:ClearAllPoints()
    row.dist:SetPoint("RIGHT", row, "RIGHT", q.useItem and -(ROW_H + 4) or -2, 0)
    row.dist:SetText(right)
    row.tags:ClearAllPoints()
    row.tags:SetPoint("RIGHT", row.dist, "LEFT", right ~= "" and -4 or 0, 0)
    row.tags:SetText(RewardTags(q, ns:XPState()))
    local left = SetItemButtons(row, q)
    if left ~= row.tags then
        row.text:SetPoint("RIGHT", left, "LEFT", -4, 0)
    end
    row:Show()
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
-- Other quest trackers (Questie, Blizzard) hidden while this window is shown.
local hiddenByUs = {}
local function OtherTrackers()
    local list = {}
    if db.hideQuestie and _G.Questie_BaseFrame then list[#list + 1] = _G.Questie_BaseFrame end
    local blizz = _G.ObjectiveTrackerFrame or _G.QuestWatchFrame
    if db.hideBlizzard and blizz then list[#list + 1] = blizz end
    return list
end

local hooked = {}
local function ShouldHide(f)
    if not (db and frame:IsShown()) then return false end
    if f == _G.Questie_BaseFrame then return db.hideQuestie end
    return db.hideBlizzard
end

-- Forever's quest tracker can show itself during combat, when Hide() is not
-- allowed on it. Alpha is never restricted, so it is made invisible right
-- away and really hidden as soon as combat ends (same approach as Questie).
local function CanToggle(f)
    return not InCombatLockdown() or not (f.IsProtected and f:IsProtected())
end

local function Suppress(f)
    hiddenByUs[f] = true
    f:SetAlpha(0)
    if CanToggle(f) and f:IsShown() then f:Hide() end
end

local function Release(f)
    if not hiddenByUs[f] then return end
    if not CanToggle(f) then return end -- retried on PLAYER_REGEN_ENABLED
    hiddenByUs[f] = nil
    f:SetAlpha(1)
    -- Questie keeps the game's tracker hidden itself when its own tracker is on.
    local questieOwns = f ~= _G.Questie_BaseFrame and Questie and Questie.db and Questie.db.profile
        and Questie.db.profile.trackerEnabled
    if not questieOwns then f:Show() end
end

local function ApplyTrackerHiding()
    if not db then return end
    for _, name in ipairs({ "Questie_BaseFrame", "ObjectiveTrackerFrame", "QuestWatchFrame" }) do
        local f = _G[name]
        if f then
            if not hooked[f] then
                hooked[f] = true
                f:HookScript("OnShow", function(self)
                    if ShouldHide(self) then Suppress(self) end
                end)
            end
            if ShouldHide(f) then Suppress(f) else Release(f) end
        end
    end
end
ns.ApplyTrackerHiding = function() ApplyTrackerHiding() end

local prevReady -- questID -> ready, from the previous refresh

local function QuestsForTab()
    local groups, total, _, _, _, counts, list = GetQuests(db.tab)
    -- A quest that was already in the log just became ready: jump to the Ready tab.
    local now, newlyReady = {}, false
    for _, q in ipairs(list) do
        now[q.id] = q.ready
        if q.ready and prevReady and prevReady[q.id] == false then newlyReady = true end
    end
    prevReady = now
    if newlyReady and db.autoSwitch and db.tab ~= "ready" then
        db.tab = "ready"
        groups, total, _, _, _, counts = GetQuests("ready")
    end
    return groups, total, counts
end

---------------------------------------------------------------------------
-- "Use item" buttons. They must be secure buttons, which cannot be created,
-- moved, shown or hidden in combat. So they are parented to UIParent and
-- placed over their rows (never anchored to them, which would lock the whole
-- window in combat). In combat the list keeps its layout while buttons are
-- shown (a change is applied when combat ends), scrolling and dragging wait,
-- and a button whose row is not where it was only goes transparent.
---------------------------------------------------------------------------
local useButtons, usedButtons = {}, 0
local layoutSig, pendingRefresh

local function UseButton_OnEnter(self)
    if not self.link then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
    GameTooltip:Show()
end

local function GetUseButton(i)
    local b = useButtons[i]
    if b then return b end
    b = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    b:SetSize(ROW_H - 2, ROW_H - 2)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "item")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", 1, -1)
    if CreateFrame and pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate") then
        b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
        b.cd:SetAllPoints()
    end
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.25)
    b:SetScript("OnEnter", UseButton_OnEnter)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:Hide()
    useButtons[i] = b
    return b
end

local function RowInView(row)
    if not (row:IsVisible() and scroll:IsVisible()) then return false end
    local top, bottom = row:GetTop(), row:GetBottom()
    local stop, sbottom = scroll:GetTop(), scroll:GetBottom()
    return top and bottom and stop and sbottom and bottom >= sbottom - 1 and top <= stop + 1
end

local function PlaceUseButton(b, row)
    local s = row:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local right, mid = row:GetRight(), select(2, row:GetCenter())
    if not (right and mid) then return false end
    b:ClearAllPoints()
    b:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", (right - 3) * s, mid * s)
    b:SetFrameStrata(frame:GetFrameStrata())
    b:SetFrameLevel(frame:GetFrameLevel() + 20)
    b.x, b.y = right, mid
    return true
end

-- Cooldown, charges, and visibility. Safe in combat (alpha only).
local function UpdateUseButtons()
    local combat = InCombatLockdown()
    for i = 1, usedButtons do
        local b = useButtons[i]
        local row = b.row
        local ok = row and type(row.quest) == "table" and row.quest.id == b.questID and RowInView(row)
        if ok and combat then
            local right, mid = row:GetRight(), select(2, row:GetCenter())
            ok = right == b.x and mid == b.y
        end
        if combat then
            b:SetAlpha(ok and 1 or 0)
        else
            b:SetShown(ok and true or false)
            b:SetAlpha(1)
        end
        if ok and b.logIndex then
            if b.cd and GetQuestLogSpecialItemCooldown then
                local start, dur, enable = GetQuestLogSpecialItemCooldown(b.logIndex)
                if start and dur and dur > 0 and enable ~= 0 then b.cd:SetCooldown(start, dur) else b.cd:Clear() end
            end
        end
    end
end

local function SyncUseButtons()
    if InCombatLockdown() then UpdateUseButtons(); return end
    local n = 0
    for _, row in ipairs(rows) do
        local q = row:IsShown() and row.quest
        if type(q) == "table" and q.useItem and RowInView(row) then
            n = n + 1
            local b = GetUseButton(n)
            local it = q.useItem
            b:SetAttribute("item", it.itemID and ("item:" .. it.itemID) or it.link)
            b.icon:SetTexture(it.icon)
            b.count:SetText(it.charges and it.charges > 1 and it.charges or "")
            b.link, b.logIndex, b.questID, b.row = it.link, it.logIndex, q.id, row
            if PlaceUseButton(b, row) then b:Show() else b:Hide() end
        end
    end
    for i = n + 1, #useButtons do
        local b = useButtons[i]
        b:Hide()
        b.row, b.questID = nil, nil
    end
    usedButtons = n
    UpdateUseButtons()
end
ns.SyncUseButtons = SyncUseButtons

local function UseButtonsLocked()
    return usedButtons > 0 and InCombatLockdown()
end
ns.UseButtonsLocked = UseButtonsLocked
for _, ev in ipairs({ "OnShow", "OnHide", "OnSizeChanged" }) do
    frame:HookScript(ev, function() SyncUseButtons() end)
end
scroll:HookScript("OnVerticalScroll", function() SyncUseButtons() end)

local function LayoutSignature(groups)
    local t = { db.tab, tostring(db.collapsedWindow) }
    for _, g in ipairs(groups) do
        t[#t + 1] = g.key .. (db.collapsed[db.tab .. ":" .. g.key] and "-" or "+")
        for _, q in ipairs(g.quests) do
            t[#t + 1] = q.id .. ":" .. (q.objectives and #q.objectives or 0)
        end
    end
    return table.concat(t, ",")
end

function Refresh()
    if not db then return end
    if not tContains(ns.TABS, db.tab) then db.tab = "ready" end
    local groups, total, counts = QuestsForTab()
    local sig = LayoutSignature(groups)
    if UseButtonsLocked() and sig ~= layoutSig then
        pendingRefresh = true -- the buttons cannot follow now; redo after combat
        UpdateUseButtons()
        return
    end
    layoutSig = sig

    local text
    if db.tab == "ready" then
        local totalXP = 0
        for _, g in ipairs(groups) do
            for _, q in ipairs(g.quests) do totalXP = totalXP + (q.rewards and q.rewards.xp or 0) end
        end
        local lv = LevelsUp(ns:XPState(), totalXP)
        text = L.HEADER:format(total) .. (lv > 0 and ("  |cff00ff00" .. L.HEADER_LEVELS:format(lv) .. "|r") or "")
    elseif db.tab == "progress" then
        text = L.HEADER_PROGRESS:format(total)
    elseif db.tab == "zone" then
        text = L.HEADER_ZONE:format(MapName(ZoneOf(C_Map.GetBestMapForUnit("player"))) or "?", total)
    else
        local max = MaxQuests()
        text = max and L.HEADER_ALL_MAX:format(total, max) or L.HEADER_ALL:format(total)
    end
    header:SetText(text)
    UpdateTabs(counts)
    empty:SetText(L["EMPTY_" .. db.tab:upper()])
    empty:SetShown(total == 0)
    routeBtn:SetText(L.ROUTE_BTN)
    routeBtn:SetShown(db.tab == "ready" and total > 0 and SPF() ~= nil)

    local i, y = 0, 0
    for _, g in ipairs(groups) do
        local key = db.tab .. ":" .. g.key
        local collapsed = db.collapsed[key] and true or false
        i = i + 1
        SetupHeaderRow(GetRow(i), g, y, collapsed)
        y = y - HEADER_H
        if not collapsed then
            for _, q in ipairs(g.quests) do
                i = i + 1
                SetupQuestRow(GetRow(i), q, y)
                y = y - ROW_H
                if db.showObjectives and q.objectives then
                    for _, o in ipairs(q.objectives) do
                        i = i + 1
                        SetupObjectiveRow(GetRow(i), o, y)
                        y = y - OBJ_H
                    end
                end
            end
        end
    end
    for j = i + 1, #rows do
        rows[j]:Hide()
        rows[j].quest, rows[j].groupKey = nil, nil
    end

    content:SetHeight(math.max(-y, 1))
    local collapsed = db.collapsedWindow
    UpdateCollapseButton()
    tabBar:SetShown(not collapsed)
    scroll:SetShown(not collapsed)
    if collapsed then empty:Hide() end
    grip:SetShown(not db.locked and not collapsed)
    if not sizing then
        frame:SetWidth(db.width)
        if collapsed then
            frame:SetHeight(26)
        else
            local wanted = total == 0 and (TOP + ROW_H + 8) or (TOP - y + 8)
            frame:SetHeight(math.max(MIN_H, math.min(wanted, db.maxHeight)))
        end
    end
    ClampScroll()

    local visible = db.shown and not (db.autoHide and counts.all == 0)
    frame:SetShown(visible)
    ApplyTrackerHiding()
    UpdateDock()
    SyncUseButtons()
end

ns.Refresh = function() Refresh() end

grip:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" or db.locked then return end
    sizing = true
    frame:StartSizing("BOTTOMRIGHT")
end)
grip:SetScript("OnMouseUp", function()
    if not sizing then return end
    frame:StopMovingOrSizing()
    sizing = false
    db.width = math.floor(frame:GetWidth() + 0.5)
    db.maxHeight = math.floor(frame:GetHeight() + 0.5)
    Refresh()
end)

local pending = false
local RequestRefresh
ns.OnRewardsChanged = function() if RequestRefresh then RequestRefresh() end end
function RequestRefresh(rescan)
    if rescan then poiDirty = true end
    if pending then return end
    pending = true
    C_Timer.After(0.25, function()
        pending = false
        Refresh()
    end)
end

-- Distances change as you move: refresh every 2s while visible.
C_Timer.NewTicker(2, function()
    if frame:IsShown() then Refresh() end
end)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
for _, e in ipairs({
    "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE",
    "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_POI_UPDATE",
    "QUEST_WATCH_UPDATE", "UNIT_QUEST_LOG_CHANGED", "ZONE_CHANGED_NEW_AREA",
    "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED",
}) do
    events:RegisterEvent(e)
end

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_REGEN_ENABLED" then
        ApplyTrackerHiding()
        if pendingRefresh then pendingRefresh = false; Refresh() else SyncUseButtons() end
        return
    end
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then
            if db and (arg1 == "Questie" or arg1 == "Blizzard_ObjectiveTracker") then
                C_Timer.After(1, ApplyTrackerHiding)
            end
            return
        end
        ReadyQuestsDB = ReadyQuestsDB or {}
        db = ReadyQuestsDB
        db.zoneQuests = nil -- data from a removed zone-progress experiment
        for k, v in pairs(defaults) do
            if db[k] == nil then db[k] = type(v) == "table" and {} or v end
        end
        ns:ApplyLocale(db.locale)
        if ns.BuildOptions and not ns.optionsCategory then ns:BuildOptions(db) end
        HomePoint()
        return
    end
    if event == "UNIT_QUEST_LOG_CHANGED" and arg1 ~= "player" then return end
    if event == "PLAYER_ENTERING_WORLD" then allMaps = nil; ns:ResetPlaceCache() end
    if event == "PLAYER_LEVEL_UP" then ns:InvalidateRewards() end
    RequestRefresh(true)
end)

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
local function Toggle()
    db.shown = not db.shown
    if db.shown and db.autoHide then
        local counts = select(6, GetQuests("all"))
        if counts.all == 0 then print(PREFIX .. L.NONE_NOW) end
    end
    Refresh()
end

SLASH_READYQUESTS1 = "/rq"
SLASH_READYQUESTS2 = "/readyquests"
SLASH_READYQUESTS3 = "/entregar"
SLASH_READYQUESTS4 = "/mrq"
SlashCmdList.READYQUESTS = function(msg)
    msg = strtrim((msg or ""):lower())
    if msg == "lock" then
        db.locked = not db.locked
        print(PREFIX .. (db.locked and L.LOCKED or L.UNLOCKED))
        Refresh()
    elseif msg == "min" or msg == "collapse" or msg == "recolher" then
        ToggleCollapsed()
    elseif msg == "auto" then
        db.autoHide = not db.autoHide
        print(PREFIX .. L.AUTOHIDE:format(db.autoHide and L.ON or L.OFF))
        Refresh()
    elseif msg == "reset" then
        db.point = nil
        db.width, db.maxHeight = WIDTH, 400
        dock.active, dock.userMoved = false, false
        HomePoint()
        UpdateDock()
        print(PREFIX .. L.RESET)
    elseif msg:match("^tab") then
        local arg = strtrim(msg:sub(4))
        local alias = { ready = "ready", prontas = "ready", progress = "progress", active = "progress",
            andamento = "progress", zone = "zone", zona = "zone", all = "all", todas = "all" }
        local key = alias[arg]
        if key then
            db.tab = key
            db.shown = true
            Refresh()
        else
            print(PREFIX .. L.HELP_TAB)
        end
    elseif msg == "route" then
        RouteAll(false)
    elseif msg == "route here" then
        RouteAll(true)
    elseif msg == "list" then
        local groups, total = GetReadyQuests()
        print(PREFIX .. L.LIST_HEADER:format(total))
        for _, g in ipairs(groups) do
            print("|cffffd100" .. g.title .. "|r")
            for _, q in ipairs(g.quests) do
                local extra = FormatDist(q.dist)
                print("  - " .. q.title .. (extra ~= "" and (" |cff999999(" .. extra .. ")|r") or ""))
            end
        end
    elseif msg:match("^lang") then
        local arg = strtrim(msg:sub(5))
        local available = table.concat(ns:AvailableLocales(), ", ")
        local function Name(c) return ns.Locales[c]._name end
        if arg == "" then
            print(PREFIX .. L.HELP3:format(available))
        elseif arg == "auto" then
            db.locale = nil
            local c = ns:ApplyLocale(nil)
            print(PREFIX .. L.LANG_AUTO:format(Name(c), c))
        else
            local code
            for c in pairs(ns.Locales) do
                if c:lower() == arg then code = c end
            end
            if code then
                db.locale = code
                ns:ApplyLocale(code)
                print(PREFIX .. L.LANG_SET:format(Name(code), code))
            else
                print(PREFIX .. L.LANG_UNKNOWN:format(arg, available))
            end
        end
        Refresh()
    elseif msg == "debug" then
        local pmap = C_Map.GetBestMapForUnit("player")
        local pinfo = pmap and C_Map.GetMapInfo(pmap)
        local inInst, instType = IsInInstance()
        print(PREFIX .. ("player map %s (%s, type %s), instance: %s %s, EJ: %s"):format(
            tostring(pmap), pinfo and pinfo.name or "?", pinfo and tostring(pinfo.mapType) or "?",
            tostring(inInst), tostring(instType), tostring(EJ_GetInstanceForMap ~= nil)))
        print(PREFIX .. ("options: shown=%s autoHide=%s locked=%s rewards=%s place=%s chain=%s locale=%s"):format(
            tostring(db.shown), tostring(db.autoHide), tostring(db.locked), tostring(db.showRewards),
            tostring(db.showPlace), tostring(db.showChain), tostring(db.locale)))
        for _, name in ipairs({ "Questie_BaseFrame", "ObjectiveTrackerFrame", "QuestWatchFrame" }) do
            local f = _G[name]
            if f then
                print(PREFIX .. ("%s: shown=%s alpha=%.1f protected=%s hiddenByUs=%s"):format(name,
                    tostring(f:IsShown()), f:GetAlpha() or -1, tostring(f.IsProtected and f:IsProtected()),
                    tostring(hiddenByUs[f] or false)))
            end
        end
        print(PREFIX .. ("hideQuestie=%s hideBlizzard=%s maxQuests=%s"):format(tostring(db.hideQuestie),
            tostring(db.hideBlizzard), tostring(MaxQuests())))
        local pm = C_Map.GetBestMapForUnit("player")
        local iname, itype, _, _, _, _, _, iid = GetInstanceInfo()
        print(PREFIX .. ("instance: name=%s type=%s id=%s | EJ(playerMap)=%s | zoneOf=%s %s"):format(
            tostring(iname), tostring(itype), tostring(iid), tostring(EJInstance(pm)),
            tostring(ZoneOf(pm)), tostring(MapName(ZoneOf(pm)))))
        local groups = GetQuests("all")
        for _, g in ipairs(groups) do
            for _, q in ipairs(g.quests) do
                print(("  [%s] #%d %s | header=%s | map=%s %s (listed on %s) EJ=%s | place=%s | here=%s inst=%s | dist=%s | chain=%s"):format(
                    g.title, q.id, q.title, tostring(q.header), tostring(q.map), tostring(MapName(q.map)), tostring(poiCache[q.id] and poiCache[q.id].listedOn),
                    tostring(EJInstance(q.map)), tostring(q.placeName), tostring(q.here), tostring(q.inInstance),
                    q.dist and ("%.0f"):format(q.dist) or "nil",
                    q.chain and (q.chain.pos .. "/" .. q.chain.total .. " " .. tostring(q.chain.source)) or "-"))
            end
        end
        groups = GetReadyQuests()
        for _, g in ipairs(groups) do
            for _, q in ipairs(g.quests) do
                local mi = q.map and C_Map.GetMapInfo(q.map)
                local child
                if q.map and q.x and C_Map.GetMapInfoAtPosition then
                    local ok, c = pcall(C_Map.GetMapInfoAtPosition, q.map, q.x, q.y)
                    child = ok and c or nil
                end
                print(("  #%d %s | map %s %s (type %s) @ %s,%s | at-pos: %s (type %s) | place=%s | qtype=%s/%s | chain=%s"):format(
                    q.id, q.title, tostring(q.map), mi and mi.name or "-", mi and tostring(mi.mapType) or "-",
                    q.x and ("%.2f"):format(q.x) or "-", q.y and ("%.2f"):format(q.y) or "-",
                    child and child.name or "-", child and tostring(child.mapType) or "-",
                    tostring(q.place), tostring(q.qtype), tostring(q.qtypeName),
                    q.chain and (q.chain.pos .. "/" .. q.chain.total) or "-"))
            end
        end
    elseif msg == "config" or msg == "options" or msg == "opcoes" then
        ns:OpenOptions()
    elseif msg == "help" then
        print(PREFIX .. L.HELP1)
        print(PREFIX .. L.HELP2)
        print(PREFIX .. L.HELP4)
        print(PREFIX .. L.HELP_TAB)
        print(PREFIX .. L.HELP_MIN)
        print(PREFIX .. L.HELP_CONFIG)
        print(PREFIX .. L.HELP3:format(table.concat(ns:AvailableLocales(), ", ")))
    else
        Toggle()
    end
end

function ReadyQuests_OnAddonCompartmentClick(_, button)
    if button == "RightButton" then ns:OpenOptions() else Toggle() end
end
