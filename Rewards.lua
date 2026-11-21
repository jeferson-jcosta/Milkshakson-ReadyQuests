-- Rewards: reads a quest's rewards from the quest log and checks item upgrades.
-- Results are cached per quest; the cache is cleared when equipment changes,
-- and entries whose item data was not loaded yet are retried.

local _, ns = ...

local cache = {}
local pendingItems = {}

---------------------------------------------------------------------------
-- Equipment slots per inventory type
---------------------------------------------------------------------------
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_SHIELD = { 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18, 16 },
    INVTYPE_RANGEDRIGHT = { 18, 16 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
local ARMOR_CLASS = Enum and Enum.ItemClass and Enum.ItemClass.Armor or 4

local function ItemInfo(link)
    if not link then return nil end
    local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name, _, quality, ilvl, _, _, _, _, equipLoc, texture, _, classID, subclassID = GetInfo(link)
    if not name then return nil end
    local detailed = C_Item and C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
    return { ilvl = detailed or ilvl or 0, equipLoc = equipLoc, quality = quality,
             classID = classID, subclassID = subclassID, texture = texture }
end

-- Returns isUpgrade, detail ("ilvl 24 > 18", "empty slot", "Pawn").
local function CheckUpgrade(link, usable)
    if not link or usable == false then return false end

    -- Pawn knows your stat weights: trust it when installed.
    if PawnShouldItemLinkHaveUpgradeArrow then
        local ok, up = pcall(PawnShouldItemLinkHaveUpgradeArrow, link, true)
        if ok and up ~= nil then return up and true or false, "Pawn" end
    end

    local cand = ItemInfo(link)
    if not cand then return nil end -- not loaded yet
    local slots = cand.equipLoc and SLOTS[cand.equipLoc]
    if not slots then return false end

    -- Compare with the weakest item in the possible slots.
    local worst, worstInfo, empty
    for _, slot in ipairs(slots) do
        local eq = GetInventoryItemLink("player", slot)
        if not eq then
            empty = true
        else
            local info = ItemInfo(eq)
            if info and (not worst or info.ilvl < worst) then worst, worstInfo = info.ilvl, info end
        end
    end
    if empty then return true, "empty" end
    if not worst then return nil end

    -- Do not suggest a lighter armor type than what you already wear there.
    if cand.classID == ARMOR_CLASS and worstInfo.classID == ARMOR_CLASS
        and cand.subclassID and worstInfo.subclassID
        and cand.subclassID >= 1 and cand.subclassID <= 4
        and cand.subclassID < worstInfo.subclassID then
        return false
    end
    if cand.ilvl > worst then return true, ("ilvl %d > %d"):format(cand.ilvl, worst) end
    return false
end

---------------------------------------------------------------------------
-- Reading rewards
---------------------------------------------------------------------------
local function WithSelected(questID, fn)
    local prev = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
    if C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(questID) end
    local ok, err = pcall(fn)
    if C_QuestLog.SetSelectedQuest and prev and prev ~= questID then C_QuestLog.SetSelectedQuest(prev) end
    if not ok then geterrorhandler()(err) end
end

local function ReadItem(kind, index, questID, name, texture, count, quality, usable, itemID)
    local link = GetQuestLogItemLink and GetQuestLogItemLink(kind, index, questID)
    local item = { name = name, texture = texture, count = count or 1, quality = quality,
                   usable = usable, itemID = itemID, link = link }
    if not name or not link then
        item.loading = true
        if itemID and C_Item and C_Item.RequestLoadItemDataByID then
            pendingItems[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
        end
        return item
    end
    local up, detail = CheckUpgrade(link, usable)
    if up == nil then item.loading = true end
    item.upgrade, item.upgradeDetail = up or false, detail
    return item
end

local function Load(questID)
    local r = { xp = 0, money = 0, items = {}, choices = {}, currencies = {} }

    r.xp = (GetQuestLogRewardXP and GetQuestLogRewardXP(questID)) or 0
    r.money = (GetQuestLogRewardMoney and GetQuestLogRewardMoney(questID)) or 0

    WithSelected(questID, function()
        for i = 1, (GetNumQuestLogRewards and GetNumQuestLogRewards(questID)) or 0 do
            local name, texture, count, quality, usable, itemID = GetQuestLogRewardInfo(i, questID)
            r.items[#r.items + 1] = ReadItem("reward", i, questID, name, texture, count, quality, usable, itemID)
        end
        for i = 1, (GetNumQuestLogChoices and GetNumQuestLogChoices(questID, false)) or 0 do
            local name, texture, count, quality, usable, itemID = GetQuestLogChoiceInfo(i, questID)
            r.choices[#r.choices + 1] = ReadItem("choice", i, questID, name, texture, count, quality, usable, itemID)
        end
    end)

    if C_QuestLog.GetQuestRewardCurrencies then
        local ok, list = pcall(C_QuestLog.GetQuestRewardCurrencies, questID)
        if ok and list then
            for _, c in ipairs(list) do
                r.currencies[#r.currencies + 1] = { name = c.name, texture = c.texture, count = c.totalRewardAmount or c.baseRewardAmount or c.quantity }
            end
        end
    end

    r.loading = false
    for _, it in ipairs(r.items) do if it.loading then r.loading = true end end
    for _, it in ipairs(r.choices) do if it.loading then r.loading = true end end
    for _, it in ipairs(r.items) do if it.upgrade then r.upgrade = true end end
    for _, it in ipairs(r.choices) do if it.upgrade then r.upgrade = true end end
    return r
end

function ns:GetRewards(questID)
    local r = cache[questID]
    if not r or r.loading then
        r = Load(questID)
        cache[questID] = r
    end
    return r
end

function ns:InvalidateRewards()
    wipe(cache)
end

-- Player XP helpers --------------------------------------------------------
function ns:XPState()
    local level = UnitLevel("player")
    local maxLevel = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion())
        or (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
    local cur, max = UnitXP("player"), UnitXPMax("player")
    if issecretvalue and (issecretvalue(cur) or issecretvalue(max)) then return nil end
    return { level = level, atMax = level >= maxLevel, cur = cur or 0, max = (max and max > 0) and max or 1 }
end

-- Item data arrived: retry quests that were waiting for it.
local ev = CreateFrame("Frame")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
ev:SetScript("OnEvent", function(_, event, itemID)
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        wipe(cache)
        if ns.OnRewardsChanged then ns.OnRewardsChanged() end
    elseif itemID and pendingItems[itemID] then
        pendingItems[itemID] = nil
        if ns.OnRewardsChanged then ns.OnRewardsChanged() end
    end
end)
