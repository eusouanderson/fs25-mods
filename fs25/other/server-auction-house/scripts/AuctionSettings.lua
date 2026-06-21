AuctionSettings = {}

AuctionSettings.SETTINGS = {}
AuctionSettings.CONTROLS = {}
AuctionSettings._menuInjected = false

AuctionSettings.menuItems = {
    'auctionHouseBotsEnabled'
}

AuctionSettings.SETTINGS.auctionHouseBotsEnabled = {
    ['default'] = 2,
    ['serverOnly'] = true,
    ['values'] = { false, true },
    ['strings'] = { "ui_off", "ui_on" }
}

function AuctionSettings.getStateIndex(id, value)
    local current = value
    if current == nil and g_currentMission ~= nil and g_currentMission.auctionSettings ~= nil then
        current = g_currentMission.auctionSettings[id]
    end

    local values = AuctionSettings.SETTINGS[id].values

    for i, v in ipairs(values) do
        if current == v then
            return i
        end
    end

    return AuctionSettings.SETTINGS[id].default
end

AuctionSettingsControls = {}

function AuctionSettingsControls.onMenuOptionChanged(self, state, menuOption)
    local id = menuOption.id
    local value = AuctionSettings.SETTINGS[id].values[state]

    if value ~= nil and g_currentMission ~= nil and g_currentMission.auctionSettings ~= nil then
        g_currentMission.auctionSettings[id] = value
    end

    if g_client ~= nil and g_client.getServerConnection ~= nil then
        if AuctionSettingsEvent ~= nil then
            g_client:getServerConnection():sendEvent(AuctionSettingsEvent.new(g_currentMission.auctionSettings))
        end
    end
end

function AuctionSettings:applySettings(newSettings, isAuthoritative)
    if g_currentMission == nil then return end

    g_currentMission.auctionSettings = g_currentMission.auctionSettings or {}
    local s = g_currentMission.auctionSettings

    for _, id in ipairs(self.menuItems) do
        local def = self.SETTINGS[id]
        local candidate = nil
        if newSettings ~= nil then
            candidate = newSettings[id]
        end

        local ok = false
        for _, v in ipairs(def.values) do
            if candidate == v then
                ok = true
                break
            end
        end

        if ok then
            s[id] = candidate
        elseif s[id] == nil then
            s[id] = def.values[def.default]
        end
    end

    for _, id in ipairs(self.menuItems) do
        local ctrl = self.CONTROLS[id]
        if ctrl ~= nil then
            ctrl:setState(self.getStateIndex(id, s[id]))
        end
    end

    if isAuthoritative and g_currentMission:getIsServer() then
        self:saveToXMLFile()
        if g_server ~= nil and AuctionSettingsEvent ~= nil then
            g_server:broadcastEvent(AuctionSettingsEvent.new(s), false)
        end
    end
end

function AuctionSettings:loadDefaultsIfMissing()
    if g_currentMission == nil then return end

    g_currentMission.auctionSettings = g_currentMission.auctionSettings or {}
    for _, id in ipairs(self.menuItems) do
        if g_currentMission.auctionSettings[id] == nil then
            local def = self.SETTINGS[id]
            g_currentMission.auctionSettings[id] = def.values[def.default]
        end
    end
end

function AuctionSettings:saveToXMLFile()
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end
    if g_currentMission.missionInfo == nil then return end

    local savegameDirectory = g_currentMission.missionInfo.savegameDirectory
    if savegameDirectory == nil then
        savegameDirectory = ('%ssavegame%d'):format(getUserProfileAppPath(), g_currentMission.missionInfo.savegameIndex)
    end
    
    local path = savegameDirectory .. "/server_auctionhouse_settings.xml"
    local xmlFile = createXMLFile("auctionSettings", path, "auctionSettings")
    if xmlFile ~= 0 then
        for _, id in ipairs(self.menuItems) do
            local val = g_currentMission.auctionSettings[id]
            if type(val) == "boolean" then
                setXMLBool(xmlFile, "auctionSettings." .. id, val)
            end
        end
        saveXMLFile(xmlFile, path)
        delete(xmlFile)
    end
end

function AuctionSettings:loadFromXMLFile()
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end
    if g_currentMission.missionInfo == nil then return end

    local savegameDirectory = g_currentMission.missionInfo.savegameDirectory
    if savegameDirectory == nil then
        savegameDirectory = ('%ssavegame%d'):format(getUserProfileAppPath(), g_currentMission.missionInfo.savegameIndex)
    end

    local path = savegameDirectory .. "/server_auctionhouse_settings.xml"
    local xmlFile = loadXMLFile("auctionSettings", path)
    if xmlFile ~= 0 then
        local loaded = {}
        for _, id in ipairs(self.menuItems) do
            if hasXMLProperty(xmlFile, "auctionSettings." .. id) then
                loaded[id] = getXMLBool(xmlFile, "auctionSettings." .. id)
            end
        end
        delete(xmlFile)
        self:applySettings(loaded, false)
    end
end

function AuctionSettings:injectMenu()
    local inGameMenu = g_gui.screenControllers[InGameMenu]
    if inGameMenu == nil then return end

    local settingsPage = inGameMenu.pageSettings
    if settingsPage == nil then return end

    AuctionSettingsControls.name = settingsPage.name

    local function addBinaryMenuOption(id)
        local i18n_title = "auction_setting_" .. id
        local i18n_tooltip = "auction_toolTip_" .. id

        local menuOptionBox = BitmapElement.new()
        menuOptionBox:loadProfile(g_gui:getProfile("fs25_multiTextOptionContainer"), true)

        local menuBinaryOption = BinaryOptionElement.new()
        menuBinaryOption.useYesNoTexts = true
        menuBinaryOption:loadProfile(g_gui:getProfile("fs25_settingsBinaryOption"), true)
        menuBinaryOption.id = id
        menuBinaryOption.target = AuctionSettingsControls
        menuBinaryOption:setCallback("onClickCallback", "onMenuOptionChanged")

        local setting = TextElement.new()
        setting:loadProfile(g_gui:getProfile("fs25_settingsMultiTextOptionTitle"), true)
        setting:setText(g_i18n:getText(i18n_title))

        local toolTip = TextElement.new()
        toolTip.name = "ignore"
        toolTip:loadProfile(g_gui:getProfile("fs25_multiTextOptionTooltip"), true)
        toolTip:setText(g_i18n:getText(i18n_tooltip))

        menuBinaryOption:addElement(toolTip)
        menuOptionBox:addElement(menuBinaryOption)
        menuOptionBox:addElement(setting)

        menuBinaryOption:onGuiSetupFinished()
        setting:onGuiSetupFinished()
        toolTip:onGuiSetupFinished()

        settingsPage.gameSettingsLayout:addElement(menuOptionBox)
        menuOptionBox:onGuiSetupFinished()

        menuBinaryOption:setState(self.getStateIndex(id))

        self.CONTROLS[id] = menuBinaryOption
    end

    local sectionTitle = TextElement.new()
    sectionTitle.name = "sectionHeader"
    sectionTitle:loadProfile(g_gui:getProfile("fs25_settingsSectionHeader"), true)
    sectionTitle:setText(g_i18n:getText("auction_settings_section_title"))
    settingsPage.gameSettingsLayout:addElement(sectionTitle)
    sectionTitle:onGuiSetupFinished()

    for _, id in ipairs(self.menuItems) do
        addBinaryMenuOption(id)
    end

    settingsPage.gameSettingsLayout:invalidateLayout()
    settingsPage:updateAlternatingElements(settingsPage.gameSettingsLayout)
    settingsPage:updateGeneralSettings(settingsPage.gameSettingsLayout)

    if not AuctionSettings._menuInjected then
        InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuSettingsFrame.onFrameOpen, function()
            local isAdmin = g_currentMission:getIsServer() or g_currentMission.isMasterUser
            for _, id in ipairs(AuctionSettings.menuItems) do
                local menuOption = AuctionSettings.CONTROLS[id]
                if menuOption ~= nil then
                    menuOption:setState(AuctionSettings.getStateIndex(id))
                    if AuctionSettings.SETTINGS[id].serverOnly and g_server == nil then
                        menuOption:setDisabled(not isAdmin)
                    else
                        menuOption:setDisabled(false)
                    end
                end
            end
        end)
        AuctionSettings._menuInjected = true
    end
end
