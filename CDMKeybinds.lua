local addonName, CDMKeybinds = ...

local FONT_PATH = "Fonts\\FRIZQT__.TTF"
local FONT_SIZE = 12
local BUTTONS_PER_BAR = 12
local FIRST_BINDING_KEY_INDEX = 3
local INVALID_MACRO_ID = 0
local KEYBINDING_ID_SEPARATOR = "\31"

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
local keybindingProviders = {}
local keybindTextByItem = setmetatable({}, { __mode = "k" })
local hookedViewers = setmetatable({}, { __mode = "k" })
local cacheIsDirty = true
local updatePending = false
local cliqueIsHooked = false
local bindPadIsHooked = false

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
    if type(spellID) == "string" then
        StoreShortest(keybindsBySpellName, spellID, shortenedKey)
    end

    local spellInfo = C_Spell.GetSpellInfo(spellID)
    local resolvedSpellID = type(spellID) == "number" and spellID
        or spellInfo and spellInfo.spellID
    if resolvedSpellID then
        StoreShortest(keybindsBySpellID, resolvedSpellID, shortenedKey)
    end
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

local function CacheMacroBody(body, key)
    if not body then return end

    for line in body:gmatch("[^\n\r]+") do
        CacheMacroLine(line, key)
    end
end

local function CacheMacroSpells(macroID, key)
    CacheMacroBody(GetMacroBody(macroID), key)
end

local function GetActionSlot(bar, buttonIndex)
    if bar.prefix == "ACTIONBUTTON" then
        local button = _G["ActionButton" .. buttonIndex]
        if button and button.action then return button.action end
    end
    return bar.offset + buttonIndex
end

local function CacheKeybinding(keybinding)
    local actionType = keybinding.actionType
    local id = keybinding.id
    local key = keybinding.key
    if actionType == "spell" then
        CacheSpellKey(id, key)
    elseif actionType == "macro" then
        CacheMacroSpells(id, key)
        local macroSpellID = GetMacroSpell(id)
        if macroSpellID then CacheSpellKey(macroSpellID, key) end
    elseif actionType == "macrotext" then
        CacheMacroBody(id, key)
    end
end

local function GetButtonKeybindings(bar, buttonIndex)
    local keybindings = {}
    local bindingName = bar.prefix .. buttonIndex
    local keys = { GetBindingKey(bindingName) }
    local actionType, id = GetActionInfo(GetActionSlot(bar, buttonIndex))
    for _, key in ipairs(keys) do
        keybindings[#keybindings + 1] = {
            actionType = actionType,
            id = id,
            key = key,
        }
    end
    return keybindings
end

local function GetActionBarKeybindings()
    local keybindings = {}
    for _, bar in ipairs(ACTION_BAR_BINDINGS) do
        for buttonIndex = 1, BUTTONS_PER_BAR do
            for _, keybinding in ipairs(GetButtonKeybindings(bar, buttonIndex)) do
                keybindings[#keybindings + 1] = keybinding
            end
        end
    end
    return keybindings
end

local function GetMacroID(name)
    if not GetMacroIndexByName then return nil end
    local macroID = GetMacroIndexByName(name)
    return macroID and macroID > INVALID_MACRO_ID and macroID or nil
end

local function NewKeybinding(actionType, id, key)
    if not id then return nil end
    return { actionType = actionType, id = id, key = key }
end

local function ParseBindingCommand(command, key)
    local bindPadType, value = command:match("^CLICK BindPadKey:(%u+) (.+)$")
    if bindPadType == "SPELL" then return NewKeybinding("spell", value, key) end
    if bindPadType == "MACRO" then
        return NewKeybinding("macro", GetMacroID(value), key)
    end

    local bindPadMacro = command:match("^CLICK BindPadMacro:(.+)$")
    if bindPadMacro and BindPadMacro then
        local body = BindPadMacro:GetAttribute("*macrotext-" .. bindPadMacro)
        return NewKeybinding("macrotext", body, key)
    end

    local actionType, action = command:match("^(%u+) (.+)$")
    if actionType == "SPELL" then return NewKeybinding("spell", action, key) end
    if actionType == "MACRO" then
        return NewKeybinding("macro", GetMacroID(action), key)
    end
end

local function GetStandardKeybindings()
    local keybindings = {}
    for bindingIndex = 1, GetNumBindings() do
        local bindingInfo = { GetBinding(bindingIndex) }
        for valueIndex = FIRST_BINDING_KEY_INDEX, #bindingInfo do
            local keybinding = ParseBindingCommand(bindingInfo[1], bindingInfo[valueIndex])
            if keybinding then keybindings[#keybindings + 1] = keybinding end
        end
    end
    return keybindings
end

local function GetBindPadKeybinding(slot, key)
    if slot.type == "SPELL" then
        return NewKeybinding("spell", slot.spellid or slot.name, key)
    elseif slot.type == "MACRO" then
        return NewKeybinding("macro", GetMacroID(slot.name), key)
    elseif slot.type == "CLICK" then
        return NewKeybinding("macrotext", slot.macrotext, key)
    end
end

local function GetBindPadKeybindings()
    local keybindings = {}
    if not BindPadCore or not BindPadCore.AllSlotInfoIter then return keybindings end

    for slot in BindPadCore.AllSlotInfoIter() do
        local keys = { GetBindingKey(slot.action) }
        for _, key in ipairs(keys) do
            local keybinding = GetBindPadKeybinding(slot, key)
            if keybinding then keybindings[#keybindings + 1] = keybinding end
        end
    end
    return keybindings
end

local function GetCliqueKeybinding(entry)
    if entry.type == "spell" then
        return NewKeybinding("spell", entry.spell, entry.key)
    elseif entry.type == "macro" and entry.macrotext then
        return NewKeybinding("macrotext", entry.macrotext, entry.key)
    elseif entry.type == "macro" and entry.macro then
        return NewKeybinding("macro", GetMacroID(entry.macro), entry.key)
    end
end

local function GetCliqueKeybindings()
    local keybindings = {}
    if not Clique or not Clique.bindings then return keybindings end

    for _, entry in ipairs(Clique.bindings) do
        local correctSpec = not Clique.IsBindingCorrectSpec
            or Clique:IsBindingCorrectSpec(entry)
        local keybinding = correctSpec and GetCliqueKeybinding(entry)
        if keybinding then keybindings[#keybindings + 1] = keybinding end
    end
    return keybindings
end

local function GetKeybindingIdentity(keybinding)
    if not keybinding.actionType or not keybinding.id or not keybinding.key then
        return nil
    end
    if IsSecret(keybinding.id) or IsSecret(keybinding.key) then return nil end
    return table.concat({
        keybinding.actionType,
        keybinding.id,
        keybinding.key,
    }, KEYBINDING_ID_SEPARATOR)
end

local function GetKeybindings()
    local keybindings = {}
    local seen = {}
    for _, provider in ipairs(keybindingProviders) do
        for _, keybinding in ipairs(provider()) do
            local identity = GetKeybindingIdentity(keybinding)
            if identity and not seen[identity] then
                seen[identity] = true
                keybindings[#keybindings + 1] = keybinding
            end
        end
    end
    return keybindings
end

local function RegisterKeybindingProvider(provider)
    keybindingProviders[#keybindingProviders + 1] = provider
    cacheIsDirty = true
end

RegisterKeybindingProvider(GetActionBarKeybindings)
RegisterKeybindingProvider(GetStandardKeybindings)
RegisterKeybindingProvider(GetBindPadKeybindings)
RegisterKeybindingProvider(GetCliqueKeybindings)

local function RebuildCache()
    wipe(keybindsBySpellID)
    wipe(keybindsBySpellName)

    for _, keybinding in ipairs(GetKeybindings()) do
        CacheKeybinding(keybinding)
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

local function HookClique()
    if cliqueIsHooked or not Clique or not Clique.RegisterMessage then return end
    Clique:RegisterMessage("BINDINGS_CHANGED", InvalidateAndUpdate)
    cliqueIsHooked = true
    InvalidateAndUpdate()
end

local function HookBindPad()
    if bindPadIsHooked or not BindPadCore or not BindPadCore.UpdateMacroText then
        return
    end
    hooksecurefunc(BindPadCore, "UpdateMacroText", InvalidateAndUpdate)
    bindPadIsHooked = true
    InvalidateAndUpdate()
end

local function HookBindingAddons()
    HookClique()
    HookBindPad()
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
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("UPDATE_BINDINGS")
eventFrame:RegisterEvent("UPDATE_MACROS")
eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
eventFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        InitialiseViewers()
    elseif event == "ADDON_LOADED" then
        HookBindingAddons()
    elseif event == "PLAYER_REGEN_ENABLED" then
        HandleCombatEnded()
    else
        InvalidateAndUpdate()
    end
end)

CDMKeybinds.GetKeybindForSpell = GetKeybindForSpell
CDMKeybinds.GetKeybindings = GetKeybindings
CDMKeybinds.RegisterKeybindingProvider = RegisterKeybindingProvider
CDMKeybinds.name = addonName

RegisterSlashCommand()
HookBindingAddons()
InitialiseViewers()
