-- ReadyQuests: lists quests in your log that are ready to turn in,
-- grouped by turn-in location ("On this map" first), with distance and
-- optional Shortest Path Forever / TomTom integration.

local ADDON, ns = ...
local L = ns.L
local PREFIX = "|cff33ff99[ReadyQuests]|r "
local ROW_H, HEADER_H, WIDTH = 18, 18, 300
local OWNER = "ReadyQuests"

local db
local defaults = { shown = true, locked = false, autoHide = true, point = nil, locale = nil,
    width = WIDTH, maxHeight = 400, showRewards = true, showPlace = true, showChain = true }
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

-- questID -> { map, x, y } of the turn-in POI. Scans the player's own map
-- first (also when inside a dungeon), then every zone, then dungeon/cave maps,
-- and stops as soon as every ready quest has a location.
local function RebuildPOIs()
    wipe(poiCache)
    local wanted, missing = {}, 0
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID and info.questID > 0 and IsReady(info.questID) then
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
                    poiCache[id] = { map = m, x = poi.x, y = poi.y }
                    missing = missing - 1
                end
            end
        end
    end
    poiDirty = false
end

local function TurnInLocation(id)
    local p = poiCache[id]
    if p then return p.map, p.x, p.y end
    if C_QuestLog.GetNextWaypoint then
        local ok, map, x, y = pcall(C_QuestLog.GetNextWaypoint, id)
        if ok and map and x and y then return map, x, y end
    end
end

local function GetReadyQuests()
    if poiDirty then RebuildPOIs() end

    local pmap, px, py = PlayerPos()
    local pzone = ZoneOf(pmap)
    local pc, pwx, pwy = WorldPos(pmap, px, py)

    local list, header = {}, nil
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info then
            if info.isHeader then
                header = info.title
            elseif not info.isHidden and info.questID and info.questID > 0 then
                local id = info.questID
                if IsReady(id) then
                    local q = { id = id, title = info.title, level = info.level, header = header }
                    q.map, q.x, q.y = TurnInLocation(id)
                    q.zone = ZoneOf(q.map)

                    -- Distance: world coordinates to the turn-in, else the client's own estimate.
                    local qc, qwx, qwy = WorldPos(q.map, q.x, q.y)
                    if pc and qc and pc == qc then
                        q.dist = math.sqrt((qwx - pwx) ^ 2 + (qwy - pwy) ^ 2)
                    elseif C_QuestLog.GetDistanceSqToQuest then
                        local d = C_QuestLog.GetDistanceSqToQuest(id)
                        if d and d > 0 then q.dist = math.sqrt(d) end
                    end
                    q.wc, q.wx, q.wy = qc, qwx, qwy

                    q.here = (pzone and q.zone == pzone) or false
                    q.group = q.here and "\0here" or (MapName(q.zone) or header or L.UNKNOWN_ZONE)
                    q.eta = TravelSeconds(q, pmap, px, py)
                    q.rewards = ns:GetRewards(id)
                    q.place, q.placeName = ns:GetPlace(q.map, q.x, q.y)
                    q.chain = ns:GetChain(id)
                    q.qtype, q.qtypeName = ns:GetQuestType(id)
                    list[#list + 1] = q
                end
            end
        end
    end

    -- Group, ordering groups: current map first, then by closest quest, then by name.
    local groups, byName = {}, {}
    for _, q in ipairs(list) do
        local g = byName[q.group]
        if not g then
            g = { key = q.group, here = q.here, quests = {} }
            g.title = q.here and L.ON_THIS_MAP:format(MapName(pzone) or "?") or q.group
            byName[q.group] = g
            groups[#groups + 1] = g
        end
        g.quests[#g.quests + 1] = q
        if q.eta and (not g.bestEta or q.eta < g.bestEta) then g.bestEta = q.eta end
        if q.dist and (not g.bestDist or q.dist < g.bestDist) then g.bestDist = q.dist end
    end

    local function byDist(a, b)
        if a.eta and b.eta and a.eta ~= b.eta then return a.eta < b.eta end
        if a.dist and b.dist and a.dist ~= b.dist then return a.dist < b.dist end
        local ra, rb = a.eta or a.dist, b.eta or b.dist
        if (ra ~= nil) ~= (rb ~= nil) then return ra ~= nil end
        return a.title < b.title
    end
    for _, g in ipairs(groups) do table.sort(g.quests, byDist) end
    -- Easiest turn-in first: travel time (Shortest Path) when both groups have it,
    -- else straight-line distance; the current map only wins ties/unknowns.
    table.sort(groups, function(a, b)
        if a.bestEta and b.bestEta and a.bestEta ~= b.bestEta then return a.bestEta < b.bestEta end
        if a.bestDist and b.bestDist and a.bestDist ~= b.bestDist then return a.bestDist < b.bestDist end
        if a.here ~= b.here then return a.here end
        local ra, rb = a.bestEta or a.bestDist, b.bestEta or b.bestDist
        if (ra ~= nil) ~= (rb ~= nil) then return ra ~= nil end
        return a.title < b.title
    end)

    return groups, #list, pmap, px, py
end

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
        print(PREFIX .. L.NO_COORDS)
        OpenOnMap(q)
        return
    end
    local api = SPF()
    if api and api.NavigateRoute then
        local ok, started = pcall(api.NavigateRoute, OWNER, { {
            map = q.map, x = q.x, y = q.y,
            title = L.STOP_ONE:format(q.title),
            kind = "turnin", handins = { q.id },
        } })
        if ok and started then return end
        print(PREFIX .. L.ROUTE_FAILED)
    elseif TomTom and TomTom.AddWaypoint then
        TomTom:AddWaypoint(q.map, q.x, q.y, { title = q.title, questID = q.id, from = OWNER, crazy = true })
        return
    end
    -- Blizzard fallback: super-track the quest (arrow points to its turn-in).
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
        C_SuperTrack.SetSuperTrackedQuestID(q.id)
    end
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
    if not db.locked then self:StartMoving() end
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    db.point = { p, rp, x, y }
end)

local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
header:SetPoint("TOPLEFT", 8, -7)

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

local empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
empty:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)

-- Scrollable list area (mouse wheel) -------------------------------------
local scroll = CreateFrame("ScrollFrame", nil, frame)
scroll:SetPoint("TOPLEFT", 6, -26)
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
    self:SetVerticalScroll(self:GetVerticalScroll() - delta * ROW_H * 2)
    ClampScroll()
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

local function Icon(tex) return tex and ("|T%s:13:13|t"):format(tex) or "" end

local function LevelsUp(xpState, xp)
    if not xpState or xpState.atMax or not xp or xp <= 0 then return 0 end
    return math.floor((xpState.cur + xp) / xpState.max)
end

local function RewardTags(q, xpState)
    local t = {}
    if db.showPlace and q.place == "dungeon" then t[#t + 1] = "|cffff8040" .. L.TAG_DUNGEON .. "|r" end
    if db.showPlace and q.place == "cave" then t[#t + 1] = "|cffc8a060" .. L.TAG_CAVE .. "|r" end
    if db.showPlace and q.qtype then
        local name = q.qtypeName or (q.qtype == "raid" and L.QTYPE_RAID) or (q.qtype == "dungeon" and L.QTYPE_DUNGEON) or q.qtype
        t[#t + 1] = "|cffa335ee[" .. name .. "]|r"
    end
    if db.showChain and q.chain then
        t[#t + 1] = "|cffffcc00" .. L.TAG_CHAIN:format(q.chain.pos, q.chain.total) .. "|r"
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
    GameTooltip:AddLine(L.TURNIN_AT:format(MapName(q.zone) or q.header or L.UNKNOWN_ZONE), 1, 1, 1)
    if q.map and q.x then
        GameTooltip:AddLine(("%.1f, %.1f"):format(q.x * 100, q.y * 100), 0.7, 0.7, 0.7)
    end
    local wp = C_QuestLog.GetNextWaypointText and C_QuestLog.GetNextWaypointText(q.id)
    if wp and wp ~= "" then GameTooltip:AddLine(wp, 1, 0.82, 0, true) end
    if q.dist then GameTooltip:AddLine(L.DISTANCE:format(math.floor(q.dist + 0.5)), 0.8, 0.8, 0.8) end
    if q.eta then GameTooltip:AddLine(L.TRAVEL:format(FormatTime(q.eta)), 0.8, 0.8, 0.8) end
    if q.place then
        local txt = q.place == "dungeon" and L.PLACE_DUNGEON or L.PLACE_CAVE
        GameTooltip:AddLine(txt:format(q.placeName or "?"), 1, 0.55, 0.25)
    end
    if q.qtype then
        GameTooltip:AddLine(L.QTYPE_LINE:format(q.qtypeName or q.qtype), 0.75, 0.45, 1)
    end
    if q.chain then
        GameTooltip:AddLine(L.CHAIN_POS:format(q.chain.pos, q.chain.total) .. (q.chain.name and (" - " .. q.chain.name) or ""), 1, 0.8, 0)
        if q.chain.nextID then
            GameTooltip:AddLine(L.CHAIN_NEXT:format(q.chain.nextName or ("#" .. q.chain.nextID)), 1, 1, 1, true)
        else
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
    local q = self.quest
    if not q then return end
    if IsShiftKeyDown() then
        local link = GetQuestLink(q.id)
        local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
        if link and insert then insert(link) end
    elseif button == "RightButton" then
        OpenOnMap(q)
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

local function SetupHeaderRow(row, g, y)
    row.quest = nil
    row:EnableMouse(false)
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
    if g.here then
        row.text:SetText("|cff66ff66" .. g.title .. "|r")
    else
        row.text:SetText("|cffffd100" .. g.title .. "|r")
    end
    row.dist:SetText(("(%d)"):format(#g.quests))
    row:Show()
end

local function SetupQuestRow(row, q, y)
    row.quest = q
    row:EnableMouse(true)
    row:SetHeight(ROW_H)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
    row.icon:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", 10, 0)
    row.icon:Show()
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.text:SetPoint("RIGHT", row.tags, "LEFT", -4, 0) -- re-anchored below once icons are placed
    row.text:SetFontObject(GameFontHighlightSmall)
    local lvl = q.level and q.level > 0 and ("[%d] "):format(q.level) or ""
    row.text:SetText(lvl .. q.title)
    local right = FormatDist(q.dist)
    if q.eta then
        right = (right ~= "" and (right .. " · ") or "") .. FormatTime(q.eta)
    end
    row.dist:SetText(right)
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
local function Refresh()
    if not db then return end
    local groups, total = GetReadyQuests()

    local totalXP = 0
    for _, g in ipairs(groups) do
        for _, q in ipairs(g.quests) do totalXP = totalXP + (q.rewards and q.rewards.xp or 0) end
    end
    local lv = LevelsUp(ns:XPState(), totalXP)
    header:SetText(L.HEADER:format(total) .. (lv > 0 and ("  |cff00ff00" .. L.HEADER_LEVELS:format(lv) .. "|r") or ""))
    empty:SetText(L.EMPTY)
    empty:SetShown(total == 0)
    routeBtn:SetText(L.ROUTE_BTN)
    routeBtn:SetShown(total > 0 and SPF() ~= nil)

    local i, y = 0, 0
    for _, g in ipairs(groups) do
        i = i + 1
        SetupHeaderRow(GetRow(i), g, y)
        y = y - HEADER_H
        for _, q in ipairs(g.quests) do
            i = i + 1
            SetupQuestRow(GetRow(i), q, y)
            y = y - ROW_H
        end
    end
    for j = i + 1, #rows do
        rows[j]:Hide()
        rows[j].quest = nil
    end

    content:SetHeight(math.max(-y, 1))
    grip:SetShown(not db.locked)
    if not sizing then
        frame:SetWidth(db.width)
        local wanted = total == 0 and (26 + ROW_H + 8) or (26 - y + 8)
        frame:SetHeight(math.max(MIN_H, math.min(wanted, db.maxHeight)))
    end
    ClampScroll()

    local visible = db.shown and not (db.autoHide and total == 0)
    frame:SetShown(visible)
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
    "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP",
}) do
    events:RegisterEvent(e)
end

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        ReadyQuestsDB = ReadyQuestsDB or {}
        db = ReadyQuestsDB
        for k, v in pairs(defaults) do
            if db[k] == nil then db[k] = v end
        end
        ns:ApplyLocale(db.locale)
        if ns.BuildOptions and not ns.optionsCategory then ns:BuildOptions(db) end
        if db.point then
            frame:ClearAllPoints()
            frame:SetPoint(db.point[1], UIParent, db.point[2], db.point[3], db.point[4])
        end
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
        local _, total = GetReadyQuests()
        if total == 0 then print(PREFIX .. L.NONE_NOW) end
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
    elseif msg == "auto" then
        db.autoHide = not db.autoHide
        print(PREFIX .. L.AUTOHIDE:format(db.autoHide and L.ON or L.OFF))
        Refresh()
    elseif msg == "reset" then
        db.point = nil
        db.width, db.maxHeight = WIDTH, 400
        frame:ClearAllPoints()
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -260, 120)
        print(PREFIX .. L.RESET)
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
        local groups = GetReadyQuests()
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
        print(PREFIX .. L.HELP_CONFIG)
        print(PREFIX .. L.HELP3:format(table.concat(ns:AvailableLocales(), ", ")))
    else
        Toggle()
    end
end

function ReadyQuests_OnAddonCompartmentClick(_, button)
    if button == "RightButton" then ns:OpenOptions() else Toggle() end
end
