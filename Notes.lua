-- Release notes shown once after an update (MilkshaksonUI:WhatsNew) and by the
-- "What's new" button in Options. Newest first; en = English, pt = Portuguese.
-- At each release: add the new version on top (from CHANGELOG.md).
local ADDON, ns = ...

ns.NOTES = {
    { v = "2.14.0",
      en = {
        "**Alliance / Horde colors:** the window, its title and the partner box follow your faction (or the one you pick) — Options > Appearance. The window keeps its transparency.",
      },
      pt = {
        "**Cores da Aliança / Horda:** a janela, o título e a caixa de parceiros seguem a sua facção (ou a que você escolher) — Opções > Aparência. A janela mantém a transparência.",
      } },
    { v = "2.13.0",
      en = {
        "**Gold icon on rewards** that are not an upgrade but are worth good money (vendor price, or the Auction House price with Auctionator). Threshold in Options > List.",
        "Money shows with the coin icons, like the bags.",
        "**What's new** popup after an update (this window), also from Options.",
        "Options: changing the language changes the page right away.",
      },
      pt = {
        "**Ícone de ouro nas recompensas** que não são upgrade mas valem um bom dinheiro (preço no vendedor, ou na Casa de Leilões com o Auctionator). Valor mínimo em Opções > Lista.",
        "Dinheiro aparece com os ícones de moedas, como na bolsa.",
        "Janela de **novidades** depois de atualizar (esta), também pelas Opções.",
        "Opções: trocar o idioma muda a página na hora.",
      } },
    { v = "2.12.0",
      en = {
        "Title bar items centered on one line.",
        "Messages also go to **Milkshakson-Phone**'s Milkshakson-Addons chat when it is installed.",
        "Options > **Diagnostics** buttons.",
      },
      pt = {
        "Itens da barra de título centralizados numa linha.",
        "Mensagens também vão para o chat Milkshakson-Addons do **Milkshakson-Phone** quando instalado.",
        "Botões de **Diagnóstico** nas Opções.",
      } },
}

local function Version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return get and get(ADDON, "Version") or "?"
end

function ns:ShowWhatsNew(force)
    local UI = MilkshaksonUI
    if not (UI and UI.WhatsNew) then return end
    UI:WhatsNew({ title = "Ready Quests", version = Version(), notes = ns.NOTES,
        db = ReadyQuestsDB, lang = ns.localeCode, force = force })
end

-- Options > About: the addon's description (About.lua, same text as the README / CurseForge page)
function ns:ShowAbout()
    local UI = MilkshaksonUI
    if not (UI and UI.About and ns.ABOUT) then return end
    UI:About({ title = "Ready Quests", version = Version(), about = ns.ABOUT, lang = ns.localeCode })
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function()
    f:UnregisterAllEvents()
    ns:ShowWhatsNew(false)
end)
