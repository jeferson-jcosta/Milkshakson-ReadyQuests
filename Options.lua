-- Options panel: Options > AddOns > Milkshakson > Ready Quests
local _, ns = ...
local L = ns.L

function ns:BuildOptions(db)
    local UI = MilkshaksonUI
    if not UI then return end
    local function R() if ns.Refresh then ns.Refresh() end end

    local p = UI:NewPanel("Ready Quests", L.CFG_DESC)

    UI:Section(p, L.CFG_WINDOW)
    UI:Check(p, L.CFG_SHOWN, nil, function() return db.shown end, function(v) db.shown = v; R() end)
    UI:Check(p, L.CFG_AUTOHIDE, L.CFG_AUTOHIDE_TIP, function() return db.autoHide end, function(v) db.autoHide = v; R() end)
    UI:Check(p, L.CFG_LOCKED, L.CFG_LOCKED_TIP, function() return db.locked end, function(v) db.locked = v; R() end)
    UI:Slider(p, L.CFG_WIDTH, 220, 800, 10, "%d", function() return db.width end, function(v) db.width = v; R() end)
    UI:Slider(p, L.CFG_MAXH, 70, 1200, 10, "%d", function() return db.maxHeight end, function(v) db.maxHeight = v; R() end)
    UI:Buttons(p, {
        { L.CFG_RESET, function() SlashCmdList.READYQUESTS("reset") end },
    })

    UI:Section(p, L.CFG_LIST)
    UI:Check(p, L.CFG_SHOW_REWARDS, nil, function() return db.showRewards end, function(v) db.showRewards = v; R() end)
    UI:Check(p, L.CFG_SHOW_PLACE, L.CFG_SHOW_PLACE_TIP, function() return db.showPlace end, function(v) db.showPlace = v; R() end)
    UI:Check(p, L.CFG_SHOW_CHAIN, L.CFG_SHOW_CHAIN_TIP, function() return db.showChain end, function(v) db.showChain = v; R() end)

    UI:Section(p, L.CFG_TRACKER)
    UI:Check(p, L.CFG_SHOW_OBJ, nil, function() return db.showObjectives end, function(v) db.showObjectives = v; R() end)
    UI:Check(p, L.CFG_AUTOSWITCH, nil, function() return db.autoSwitch end, function(v) db.autoSwitch = v; R() end)
    UI:Check(p, L.CFG_HIDE_QUESTIE, L.CFG_HIDE_TIP, function() return db.hideQuestie end, function(v) db.hideQuestie = v; R() end)
    UI:Check(p, L.CFG_HIDE_BLIZZ, L.CFG_HIDE_TIP, function() return db.hideBlizzard end, function(v) db.hideBlizzard = v; R() end)

    UI:Section(p, L.CFG_ROUTE)
    UI:Buttons(p, {
        { L.ROUTE_BTN, function() SlashCmdList.READYQUESTS("route") end, L.ROUTE_TIP },
        { L.CFG_ROUTE_HERE, function() SlashCmdList.READYQUESTS("route here") end, L.ROUTE_TIP_RIGHT },
    })

    UI:Section(p, L.CFG_LANGUAGE)
    UI:Language(p, ns, db, R, L.CFG_LANG_NOTE)

    UI:Support(p)

    ns.optionsCategory = UI:Register(p, "Ready Quests")
end

function ns:OpenOptions()
    if MilkshaksonUI then MilkshaksonUI:Open(ns.optionsCategory) end
end
