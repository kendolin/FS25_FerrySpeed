--
-- FerrySpeed
--
-- Speeds up (or slows down) the map ferries by scaling the frame time the
-- game's Ferry class receives. The ferry then believes more time has passed
-- per frame, so the whole crossing (travel, ramps, waiting) runs faster.
--
-- In game:   pause menu > Settings > Game Settings > "Ferry Speed" (at the bottom)
--
-- Console:   ferrySpeed            show the current multiplier
--            ferrySpeed 5          set it to 5x (0.1 - 10), saved for next time
--            ferrySpeedInfo        show what the mod has hooked / seen
--
-- Settings:  <FS25 user folder>/modSettings/FS25_FerrySpeed.xml
--

FerrySpeed = {}

FerrySpeed.DEFAULT_MULTIPLIER = 3
FerrySpeed.MIN_MULTIPLIER = 0.1
FerrySpeed.MAX_MULTIPLIER = 10

-- values offered in the in-game settings menu
FerrySpeed.MENU_VALUES = { 0.5, 1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10 }

FerrySpeed.multiplier = FerrySpeed.DEFAULT_MULTIPLIER
FerrySpeed.menu = { built = false, failed = false, option = nil }
FerrySpeed.hookedFunctions = {}
FerrySpeed.seenFerries = setmetatable({}, { __mode = "k" })

local SETTINGS_DIR = getUserProfileAppPath() .. "modSettings/"
local SETTINGS_FILE = SETTINGS_DIR .. "FS25_FerrySpeed.xml"
local LOG_PREFIX = "FerrySpeed: "


local function clampMultiplier(value)
    return math.max(FerrySpeed.MIN_MULTIPLIER, math.min(FerrySpeed.MAX_MULTIPLIER, value))
end


---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

function FerrySpeed.saveSettings()
    createFolder(SETTINGS_DIR)

    local xmlFile = createXMLFile("ferrySpeedSettings", SETTINGS_FILE, "ferrySpeed")
    if xmlFile ~= nil and xmlFile ~= 0 then
        setXMLFloat(xmlFile, "ferrySpeed#multiplier", FerrySpeed.multiplier)
        saveXMLFile(xmlFile)
        delete(xmlFile)
    end
end


function FerrySpeed.loadSettings()
    if not fileExists(SETTINGS_FILE) then
        -- write the default so there is a file to edit by hand
        FerrySpeed.saveSettings()
        return
    end

    local xmlFile = loadXMLFile("ferrySpeedSettings", SETTINGS_FILE)
    if xmlFile ~= nil and xmlFile ~= 0 then
        local value = getXMLFloat(xmlFile, "ferrySpeed#multiplier")
        if value ~= nil then
            FerrySpeed.multiplier = clampMultiplier(value)
        end
        delete(xmlFile)
    end
end


---------------------------------------------------------------------------
-- Ferry hook
---------------------------------------------------------------------------

local function scaledUpdate(self, superFunc, dt, ...)
    FerrySpeed.seenFerries[self] = true

    if type(dt) == "number" then
        dt = dt * FerrySpeed.multiplier
    end

    return superFunc(self, dt, ...)
end


function FerrySpeed.installHooks()
FerrySpeed.installMenuHook()
    if Ferry == nil then
        print(LOG_PREFIX .. "Warning: game class 'Ferry' not found, nothing to speed up")
        return
    end

    for _, name in ipairs({ "update", "updateTick" }) do
        if type(Ferry[name]) == "function" and not FerrySpeed.hookedFunctions[name] then
            Ferry[name] = Utils.overwrittenFunction(Ferry[name], scaledUpdate)
            FerrySpeed.hookedFunctions[name] = true
        end
    end

    if next(FerrySpeed.hookedFunctions) == nil then
        print(LOG_PREFIX .. "Warning: Ferry has no update functions to hook, the mod will have no effect")
    end
end


---------------------------------------------------------------------------
-- In-game settings menu
---------------------------------------------------------------------------

local function isMultiOption(element)
    if element == nil or element.setTexts == nil or element.setState == nil then
        return false
    end
    -- on/off toggles are the same element family but only have two states
    if element.typeName == "BinaryOption" then
        return false
    end
    if BinaryOptionElement ~= nil and element.isa ~= nil and element:isa(BinaryOptionElement) then
        return false
    end
    return true
end


local function findMultiOption(row)
    if row.elements ~= nil then
        for _, child in ipairs(row.elements) do
            if isMultiOption(child) then
                return child
            end
        end
    end
    return nil
end


local function renewFocusIds(element)
    if FocusManager == nil or FocusManager.serveAutoFocusId == nil then
        return
    end
    element.focusId = FocusManager:serveAutoFocusId()
    if element.elements ~= nil then
        for _, child in pairs(element.elements) do
            renewFocusIds(child)
        end
    end
end


local function formatMultiplier(value)
    return string.format("%gx", value)
end


-- index of the menu value closest to the current multiplier
function FerrySpeed.getMenuState()
    local bestState, bestDiff = 1, math.huge
    for state, value in ipairs(FerrySpeed.MENU_VALUES) do
        local diff = math.abs(value - FerrySpeed.multiplier)
        if diff < bestDiff then
            bestState, bestDiff = state, diff
        end
    end
    return bestState
end


function FerrySpeed.onMenuOptionChanged()
    local option = FerrySpeed.menu.option
    if option == nil or option.getState == nil then
        return
    end

    local value = FerrySpeed.MENU_VALUES[option:getState()]
    if value ~= nil then
        FerrySpeed.multiplier = clampMultiplier(value)
        FerrySpeed.saveSettings()
    end
end


function FerrySpeed.buildMenuOption()
    local layout = g_inGameMenu ~= nil and g_inGameMenu.pageSettings ~= nil and g_inGameMenu.pageSettings.gameSettingsLayout or nil
    if layout == nil or layout.elements == nil then
        error("game settings layout not found")
    end

    -- already added earlier (e.g. the menu survived a savegame change): just reuse it
    for _, element in pairs(layout.elements) do
        if element.name == "ferrySpeedRow" then
            local existing = findMultiOption(element)
            if existing ~= nil then
                existing.onClickCallback = FerrySpeed.onMenuOptionChanged
                FerrySpeed.menu.option = existing
                FerrySpeed.menu.built = true
                return
            end
        end
    end

    -- use existing rows of the page as templates so the new row matches the game's look
    local headerTemplate, rowTemplate
    for _, element in pairs(layout.elements) do
        if headerTemplate == nil and element.name == "sectionHeader" then
            headerTemplate = element
        end
        if rowTemplate == nil and element.typeName == "Bitmap" and findMultiOption(element) ~= nil then
            rowTemplate = element
        end
    end

    if rowTemplate == nil then
        error("no option row found to use as template")
    end

    local header
    if headerTemplate ~= nil then
        header = headerTemplate:clone(layout)
        header.id = nil
        header:setText("Ferry Speed")
    end

    local row = rowTemplate:clone(layout)
    row.id = nil
    row.name = "ferrySpeedRow"

    local option = findMultiOption(row)
    if option == nil then
        row:delete()
        if header ~= nil then
            header:delete()
        end
        error("cloned row has no option element")
    end

    for _, child in pairs(row.elements) do
        child.id = nil
        if child ~= option and child.typeName == "Text" and child.setText ~= nil then
            child:setText("Ferry speed")
        end
    end

    -- the first child of an option is its tooltip text
    local toolTip = option.elements ~= nil and option.elements[1] or nil
    if toolTip ~= nil and toolTip.setText ~= nil then
        toolTip:setText("How fast the ferries run compared to the standard game speed (1x).")
    end

    local texts = {}
    for _, value in ipairs(FerrySpeed.MENU_VALUES) do
        table.insert(texts, formatMultiplier(value))
    end
    option:setTexts(texts)

    option.target = nil
    option.onClickCallback = FerrySpeed.onMenuOptionChanged
    option.isAlwaysFocusedOnOpen = false
    option.focused = false
    if option.setDisabled ~= nil then
        option:setDisabled(false)
    end
    if row.setVisible ~= nil then
        row:setVisible(true)
    end

    if header ~= nil then
        renewFocusIds(header)
    end
    renewFocusIds(row)

    if layout.invalidateLayout ~= nil then
        layout:invalidateLayout()
    end

    FerrySpeed.menu.option = option
    FerrySpeed.menu.built = true
end


function FerrySpeed.onSettingsFrameOpen()
    local menu = FerrySpeed.menu

    if not menu.built and not menu.failed then
        local ok, err = pcall(FerrySpeed.buildMenuOption)
        if not ok then
            -- never break the game's settings page; console and settings file still work
            menu.failed = true
            print(LOG_PREFIX .. "Warning: could not add the in-game setting (" .. tostring(err) .. ")")
        end
    end

    if menu.built and menu.option ~= nil then
        pcall(function()
            menu.option:setState(FerrySpeed.getMenuState())
        end)
    end
end


function FerrySpeed.installMenuHook()
    if InGameMenuSettingsFrame == nil or InGameMenuSettingsFrame.onFrameOpen == nil then
        print(LOG_PREFIX .. "Warning: settings page not found, in-game setting unavailable")
        return
    end

    InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuSettingsFrame.onFrameOpen, FerrySpeed.onSettingsFrameOpen)
end


---------------------------------------------------------------------------
-- Console commands
---------------------------------------------------------------------------

function FerrySpeed:consoleCommandFerrySpeed(value)
    if value == nil then
        return string.format("Ferry speed multiplier is %.2fx. Usage: ferrySpeed <%.1f-%d>",
            FerrySpeed.multiplier, FerrySpeed.MIN_MULTIPLIER, FerrySpeed.MAX_MULTIPLIER)
    end

    local number = tonumber(value)
    if number == nil then
        return "Not a number: " .. tostring(value)
    end

    FerrySpeed.multiplier = clampMultiplier(number)
    FerrySpeed.saveSettings()

    return string.format("Ferry speed multiplier set to %.2fx", FerrySpeed.multiplier)
end


function FerrySpeed:consoleCommandFerrySpeedInfo()
    local hooked = {}
    for name in pairs(FerrySpeed.hookedFunctions) do
        table.insert(hooked, name)
    end
    print(LOG_PREFIX .. "multiplier = " .. tostring(FerrySpeed.multiplier))
    print(LOG_PREFIX .. "hooked Ferry functions: " .. (#hooked > 0 and table.concat(hooked, ", ") or "none"))

    local numFerries = 0
    for ferry in pairs(FerrySpeed.seenFerries) do
        numFerries = numFerries + 1
        print(LOG_PREFIX .. "ferry #" .. numFerries .. " number fields:")
        for key, fieldValue in pairs(ferry) do
            if type(fieldValue) == "number" then
                print(string.format("    %s = %s", tostring(key), tostring(fieldValue)))
            end
        end
    end

    return string.format("%d ferry object(s) seen so far (details in log)", numFerries)
end


---------------------------------------------------------------------------
-- Mod events
---------------------------------------------------------------------------

function FerrySpeed:loadMap()
    FerrySpeed.loadSettings()

    addConsoleCommand("ferrySpeed", "Sets the ferry speed multiplier (0.1 - 10)", "consoleCommandFerrySpeed", FerrySpeed)
    addConsoleCommand("ferrySpeedInfo", "Shows what the Ferry Speed mod has hooked", "consoleCommandFerrySpeedInfo", FerrySpeed)

    print(string.format("%sferries running at %.2fx", LOG_PREFIX, FerrySpeed.multiplier))
end


function FerrySpeed:deleteMap()
    removeConsoleCommand("ferrySpeed")
    removeConsoleCommand("ferrySpeedInfo")
end


FerrySpeed.installHooks()
FerrySpeed.installMenuHook()
addModEventListener(FerrySpeed)
