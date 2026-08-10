local addonName, CDMKeybinds = ...

local FONT_PATH = "Fonts\\FRIZQT__.TTF"
local FONT_SIZE = 12
local BUTTONS_PER_BAR = 12

local VIEWER_NAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
}

local ACTION_BAR_BINDINGS = {
    { prefix = "ACTIONBUTTON",          offset = 0 },
    { prefix = "MULTIACTIONBAR1BUTTON", offset = 60 },
    { prefix = "MULTIACTIONBAR2BUTTON", offset = 48 },
    { prefix = "MULTIACTIONBAR3BUTTON", offset = 24 },
    { prefix = "MULTIACTIONBAR4BUTTON", offset = 36 },
    { prefix = "MULTIACTIONBAR5BUTTON", offset = 72 },
    { prefix = "MULTIACTIONBAR6BUTTON", offset = 84 },
    { prefix = "MULTIACTIONBAR7BUTTON", offset = 96 },
    { prefix = "MULTIACTIONBAR8BUTTON", offset = 108 },
}

local KEY_SHORTENINGS = {
    { pattern = "SHIFT%-", replacement = "s-" },
    { pattern = "CTRL%-", replacement = "c-" },
    { pattern = "ALT%-", replacement = "a-" },
    { pattern = "META%-", replacement = "m-" },
    { pattern = "NUMPAD", replacement = "n" },
    { pattern = "BUTTON", replacement = "m" },
}

local MACRO_MODIFIERS = {
    shift = "SHIFT-",
    ctrl = "CTRL-",
    alt = "ALT-",
}

local keybindsBySpellID = {}
local keybindsBySpellName = {}
local keybindTextByItem = setmetatable({}, { __mode = "k" })
local hookedViewers = setmetatable({}, { __mode = "k" })
local cacheIsDirty = true
local updatePending = false

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function ShortenKey(key)
    for _, shortening in ipairs(KEY_SHORTENINGS) do
        key = key:gsub(shortening.pattern, shortening.replacement)
    end
    return key
end

local function StoreShortest(cache, id, key)
    local current = cache[id]
    if not current or #key < #current then
        cache[id] = key
    end
end

local function CacheSpellKey(spellID, key)
    if not spellID or IsSecret(spellID) then return end

    local shortenedKey = ShortenKey(key)
    StoreShortest(keybindsBySpellID, spellID, shortenedKey)

    local spellInfo = C_Spell.GetSpellInfo(spellID)
    if spellInfo and spellInfo.name then
        StoreShortest(keybindsBySpellName, spellInfo.name, shortenedKey)
    end
end

local function GetMacroModifierPrefix(segment)
    local prefixes = {}
    for conditions in segment:gmatch("%b[]") do
        for condition in conditions:sub(2, -2):gmatch("[^,]+") do
            local normalised = condition:match("^%s*(.-)%s*$"):lower()
            if not normalised:match("^no") then
                local modifier = normalised:match("^mod%a*:(%a+)")
                local prefix = modifier and MACRO_MODIFIERS[modifier]
                if prefix then prefixes[#prefixes + 1] = prefix end
            end
        end
    end
    return table.concat(prefixes)
end

local function CleanMacroSpellName(segment)
    local name = segment:gsub("%b[]", "")
        :gsub("^%s+", "")
        :gsub("%s+$", "")
        :gsub("^!", "")
        :gsub("^reset=%S+%s*", "")
    return name
end

local function CacheMacroSegment(segment, key, modifierPrefix)
    local spellName = CleanMacroSpellName(segment)
    if spellName == "" then return end

    modifierPrefix = modifierPrefix or GetMacroModifierPrefix(segment)
    local shortenedKey = ShortenKey(modifierPrefix .. key)
    StoreShortest(keybindsBySpellName, spellName, shortenedKey)

    local spellInfo = C_Spell.GetSpellInfo(spellName)
    if spellInfo and spellInfo.spellID then
        CacheSpellKey(spellInfo.spellID, modifierPrefix .. key)
    end
end

local function CacheCastSequence(arguments, key)
    for conditionGroup in arguments:gmatch("[^;]+") do
        local modifierPrefix = GetMacroModifierPrefix(conditionGroup)
        for segment in conditionGroup:gmatch("[^,]+") do
            CacheMacroSegment(segment, key, modifierPrefix)
        end
    end
end

local function CacheMacroLine(line, key)
    local command, arguments = line:match("^%s*/(%a+)%s+(.+)")
    if not command then return end

    command = command:lower()
    if command == "castsequence" then
        CacheCastSequence(arguments, key)
    elseif command == "cast" or command == "use" then
        for segment in arguments:gmatch("[^;]+") do
            CacheMacroSegment(segment, key)
        end
    end
end

local function CacheMacroSpells(macroID, key)
    local body = GetMacroBody(macroID)
    if not body then return end

    for line in body:gmatch("[^\n\r]+") do
        CacheMacroLine(line, key)
    end
end

local function GetActionSlot(bar, buttonIndex)
    if bar.prefix == "ACTIONBUTTON" then
        local button = _G["ActionButton" .. buttonIndex]
        if button and button.action then return button.action end
    end
    return bar.offset + buttonIndex
end

local function CacheAction(actionSlot, key)
    local actionType, id = GetActionInfo(actionSlot)
    if actionType == "spell" then
        CacheSpellKey(id, key)
    elseif actionType == "macro" then
        CacheMacroSpells(id, key)
        local macroSpellID = GetMacroSpell(id)
        if macroSpellID then CacheSpellKey(macroSpellID, key) end
    end
end

local function CacheButton(bar, buttonIndex)
    local bindingName = bar.prefix .. buttonIndex
    local keys = { GetBindingKey(bindingName) }
    for _, key in ipairs(keys) do
        CacheAction(GetActionSlot(bar, buttonIndex), key)
    end
end

local function RebuildCache()
    wipe(keybindsBySpellID)
    wipe(keybindsBySpellName)

    for _, bar in ipairs(ACTION_BAR_BINDINGS) do
        for buttonIndex = 1, BUTTONS_PER_BAR do
            CacheButton(bar, buttonIndex)
        end
    end
    cacheIsDirty = false
end

local function GetKeybindForSpell(spellID)
    if not spellID or IsSecret(spellID) then return nil end
    if cacheIsDirty then RebuildCache() end

    local keybind = keybindsBySpellID[spellID]
    if keybind then return keybind end

    local spellInfo = C_Spell.GetSpellInfo(spellID)
    return spellInfo and keybindsBySpellName[spellInfo.name] or nil
end

local function GetKeybindText(itemFrame)
    local text = keybindTextByItem[itemFrame]
    if text then return text end

    text = itemFrame:CreateFontString(nil, "OVERLAY")
    text:SetFont(FONT_PATH, FONT_SIZE, "OUTLINE")
    text:SetPoint("TOPLEFT", itemFrame, "TOPLEFT", 4, -3)
    text:SetTextColor(1, 1, 1)
    keybindTextByItem[itemFrame] = text
    return text
end

local function UpdateItem(itemFrame)
    local spellID = itemFrame.GetSpellID and itemFrame:GetSpellID()
    GetKeybindText(itemFrame):SetText(GetKeybindForSpell(spellID) or "")
end

local function UpdateViewer(viewer)
    if not viewer.GetItemFrames then return end
    for _, itemFrame in ipairs(viewer:GetItemFrames()) do
        UpdateItem(itemFrame)
    end
end

local function UpdateAllViewers()
    for _, viewerName in ipairs(VIEWER_NAMES) do
        local viewer = _G[viewerName]
        if viewer then UpdateViewer(viewer) end
    end
end

local function HookViewer(viewer)
    if hookedViewers[viewer] then return end
    hooksecurefunc(viewer, "RefreshLayout", UpdateViewer)
    hookedViewers[viewer] = true
end

local function InitialiseViewers()
    for _, viewerName in ipairs(VIEWER_NAMES) do
        local viewer = _G[viewerName]
        if viewer then HookViewer(viewer) end
    end
    UpdateAllViewers()
end

local function InvalidateAndUpdate()
    if InCombatLockdown() then
        updatePending = true
        return
    end

    cacheIsDirty = true
    UpdateAllViewers()
end

local function HandleCombatEnded()
    if not updatePending then return end
    updatePending = false
    InvalidateAndUpdate()
end

local function SlashCommandExists(command)
    for globalName, value in pairs(_G) do
        if type(globalName) == "string"
            and globalName:match("^SLASH_.+%d+$")
            and type(value) == "string"
            and value:lower() == command then
            return true
        end
    end
    return false
end

local function OpenQuickKeybindMode()
    if InCombatLockdown() then
        print("CDMKeybinds: Quick Keybind Mode is unavailable in combat.")
        return
    end

    if QuickKeybindFrame then
        QuickKeybindFrame:Show()
    else
        print("CDMKeybinds: Blizzard's Quick Keybind Mode is unavailable.")
    end
end

local function RegisterSlashCommand()
    if SlashCommandExists("/kb") then return end
    SLASH_CDMKEYBINDS1 = "/kb"
    SlashCmdList.CDMKEYBINDS = OpenQuickKeybindMode
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UPDATE_BINDINGS")
eventFrame:RegisterEvent("UPDATE_MACROS")
eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
eventFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        InitialiseViewers()
    elseif event == "PLAYER_REGEN_ENABLED" then
        HandleCombatEnded()
    else
        InvalidateAndUpdate()
    end
end)

CDMKeybinds.GetKeybindForSpell = GetKeybindForSpell
CDMKeybinds.name = addonName

RegisterSlashCommand()
InitialiseViewers()
