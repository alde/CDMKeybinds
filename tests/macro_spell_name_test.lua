local macroBody = [[
#showtooltip Thunder Focus Tea
/use 14
/cast Thunder Focus Tea
]]

local function Noop() end
local eventHandler
local settingsByID = {}

_G = _G or _ENV
C_Spell = {
    GetSpellInfo = function(spell)
        local spells = {
            [100780] = { name = "Tiger Palm", spellID = 100780 },
            [101643] = { name = "Transcendence", spellID = 101643 },
            [115310] = { name = "Revival", spellID = 115310 },
            [116841] = { name = "Tiger's Lust", spellID = 116841 },
            [116680] = { name = "Thunder Focus Tea", spellID = 116680 },
            [119996] = { name = "Transcendence: Transfer", spellID = 119996 },
        }
        return spells[spell]
    end,
}
CreateFrame = function()
    return {
        RegisterEvent = Noop,
        SetScript = function(_, script, handler)
            if script == "OnEvent" then eventHandler = handler end
        end,
    }
end
GetActionInfo = function(actionSlot)
    if actionSlot == 1 then return "macro", 116680 end
end
GetActionText = function(actionSlot)
    if actionSlot == 1 then return "Tea Macro" end
end
GetBindingKey = function(bindingName)
    if bindingName == "ACTIONBUTTON1" then return "SHIFT-F" end
    if bindingName == "CLICK BindPadKey:SPELL Transcendence" then return "SHIFT-X" end
    if bindingName == "CLICK BindPadMacro:Transfer" then return "X" end
    if bindingName == "CLICK BindPadKey:MACRO Tea Macro" then return "ALT-Q" end
end
GetNumBindings = function() return 3 end
GetBinding = function(bindingIndex)
    if bindingIndex == 1 then
        return "CLICK BindPadKey:SPELL Transcendence", "BindPad", "SHIFT-X"
    end
    if bindingIndex == 2 then
        return "CLICK BindPadMacro:Transfer", "BindPad", "X"
    end
    return "CLICK BindPadKey:MACRO Tea Macro", "BindPad", "ALT-Q"
end
GetMacroBody = function(macroID)
    if macroID == 1 then return macroBody end
end
GetMacroSpell = function() return nil end
GetMacroIndexByName = function(name)
    return name == "Tea Macro" and 1 or 0
end
InCombatLockdown = function() return false end
SlashCmdList = {}
Settings = {
    VarType = { String = "string", Boolean = "boolean" },
    RegisterVerticalLayoutCategory = function(name) return { name = name } end,
    RegisterProxySetting = function(_, id, _, _, _, getter, setter)
        local setting = { getter = getter, setter = setter }
        settingsByID[id] = setting
        return setting
    end,
    CreateControlTextContainer = function()
        local container = { data = {} }
        function container:Add(value, label)
            self.data[#self.data + 1] = { value = value, label = label }
        end
        function container:GetData() return self.data end
        return container
    end,
    CreateDropdown = function(_, setting, getOptions)
        setting.getOptions = getOptions
    end,
    CreateCheckbox = Noop,
    RegisterAddOnCategory = Noop,
}
LibStub = function(libraryName)
    if libraryName ~= "LibSharedMedia-3.0" then return end
    return {
        Fetch = function(_, mediaType, fontName)
            if mediaType == "font" and fontName == "Test Font" then
                return "Fonts\\TEST.TTF"
            end
        end,
        List = function()
            return { "Friz Quadrata TT", "Test Font" }
        end,
    }
end
wipe = function(tableToWipe)
    for key in pairs(tableToWipe) do tableToWipe[key] = nil end
end

BindPadMacro = {
    GetAttribute = function(_, attribute)
        if attribute == "*macrotext-Transfer" then
            return "/cast Transcendence: Transfer"
        end
    end,
}

local cliqueHandler
local bindPadHandler
local bindPadInitialisedHandler
local bindPadIteratorCalls = 0
local bindPadSlots = {
    {
        type = "SPELL",
        spellid = 101643,
        action = "CLICK BindPadKey:SPELL Transcendence",
    },
    {
        type = "CLICK",
        macrotext = "/cast Transcendence: Transfer",
        action = "CLICK BindPadMacro:Transfer",
    },
    {
        type = "MACRO",
        name = "Tea Macro",
        action = "CLICK BindPadKey:MACRO Tea Macro",
    },
}
BindPadCore = {
    InitBindPadOnce = Noop,
    UpdateMacroText = Noop,
    AllSlotInfoIter = function()
        bindPadIteratorCalls = bindPadIteratorCalls + 1
        local index = 0
        return function()
            index = index + 1
            return bindPadSlots[index]
        end
    end,
}
hooksecurefunc = function(owner, method, handler)
    if owner == BindPadCore and method == "UpdateMacroText" then
        bindPadHandler = handler
    elseif owner == BindPadCore and method == "InitBindPadOnce" then
        bindPadInitialisedHandler = handler
    end
end
Clique = {
    bindings = {
        { type = "spell", spell = "Thunder Focus Tea", key = "Q" },
        { type = "macro", macrotext = "/cast Revival", key = "ALT-R" },
        { type = "spell", spell = "Ignored Spell", key = "I", inactive = true },
    },
    IsBindingCorrectSpec = function(_, entry) return not entry.inactive end,
    RegisterMessage = function(_, message, handler)
        assert(message == "BINDINGS_CHANGED")
        cliqueHandler = handler
    end,
}

local addon = {}
assert(loadfile("CDMKeybinds.lua"))("CDMKeybinds", addon)
assert(_G.CDMKeybinds == addon, "expected globally accessible add-on API")
eventHandler(nil, "ADDON_LOADED", "CDMKeybinds")

local fontSetting = settingsByID.CDMKEYBINDS_FONT
local unicodeSetting = settingsByID.CDMKEYBINDS_UNICODE_ARROWS
assert(fontSetting and unicodeSetting, "expected add-on settings to be registered")
assert(#fontSetting.getOptions() == 2, "expected SharedMedia font options")
fontSetting.setter("Test Font")
assert(CDMKeybindsDB.font == "Test Font", "expected selected font to be saved")

addon.GetKeybindings()
assert(bindPadIteratorCalls == 0, "expected uninitialised BindPad to be skipped")
BindPadCore.initialized = true
BindPadCore.character = "test-character"
bindPadInitialisedHandler()

addon.RegisterKeybindingProvider(function()
    return {
        { actionType = "macro", id = 1, key = "SHIFT-F" },
    }
end)

local keybindings = addon.GetKeybindings()
local duplicateCount = 0
for _, keybinding in ipairs(keybindings) do
    if keybinding.actionType == "macro"
        and keybinding.id == 1
        and keybinding.key == "SHIFT-F" then
        duplicateCount = duplicateCount + 1
    end
end
assert(duplicateCount == 1, "expected duplicate binding to be removed")

assert(addon.GetKeybindForSpell(101643) == "s-X", "expected BindPad spell binding")
assert(addon.GetKeybindForSpell(119996) == "X", "expected BindPad macro binding")
assert(addon.GetKeybindForSpell(116680) == "s-F", "expected action-bar macro binding")
assert(addon.GetKeybindForSpell(115310) == "a-R", "expected Clique macro binding")
assert(type(cliqueHandler) == "function", "expected Clique refresh hook")
assert(type(bindPadHandler) == "function", "expected BindPad refresh hook")

Clique.bindings = {
    { type = "spell", spell = "Tiger Palm", key = "MOUSEWHEELUP" },
    { type = "spell", spell = "Revival", key = "MOUSEWHEELDOWN" },
    { type = "spell", spell = "Tiger's Lust", key = "SHIFT-MOUSEWHEELUP" },
}
cliqueHandler()
assert(addon.GetKeybindForSpell(100780) == "mwu", "expected wheel-up shortening")
assert(addon.GetKeybindForSpell(115310) == "mwd", "expected wheel-down shortening")
assert(addon.GetKeybindForSpell(116841) == "s-mwu", "expected modified wheel shortening")

unicodeSetting.setter(true)
cliqueHandler()
assert(addon.GetKeybindForSpell(100780) == "m↑", "expected Unicode wheel-up shortening")
assert(addon.GetKeybindForSpell(115310) == "m↓", "expected Unicode wheel-down shortening")
assert(addon.GetKeybindForSpell(116841) == "s-m↑", "expected modified Unicode wheel shortening")

print("keybinding tests: pass")
