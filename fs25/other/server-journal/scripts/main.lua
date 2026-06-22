-- Server Journal - Main bootstrap
-- Scripts are loaded by modDesc.xml extraSourceFiles in order; no source() needed here.

local modDirectory = g_currentModDirectory
local modName = g_currentModName

JournalLogger.info("main", "=== Server Journal bootstrap starting ===")

-- Global namespace
Journal = {}
Journal.modDirectory = modDirectory
Journal.modName = modName
Journal.manager = nil
Journal.screen = nil
Journal.createPostDialog = nil

-- I18N extension: resolve mod keys without modEnv
local JournalI18NTexts = {
    ["journal_title"] = true,
    ["journal_createPost"] = true,
    ["journal_close"] = true,
    ["journal_filterAll"] = true,
    ["journal_filterJob"] = true,
    ["journal_filterSale"] = true,
    ["journal_filterFreight"] = true,
    ["journal_filterRP"] = true,
    ["journal_postCreated"] = true,
    ["journal_postRequested"] = true,
    ["journal_by"] = true,
    ["journal_category"] = true,
    ["journal_payment"] = true,
    ["journal_posted"] = true,
    ["journal_description"] = true,
    ["journal_author"] = true,
    ["journal_dialogTitle"] = true,
    ["journal_dialogTitleLabel"] = true,
    ["journal_dialogDescLabel"] = true,
    ["journal_dialogCatLabel"] = true,
    ["journal_dialogPayLabel"] = true,
    ["journal_dialogCreateBtn"] = true,
    ["journal_dialogRequired"] = true,
    ["journal_dialogNotLoaded"] = true,
    ["journal_detailNoSelection"] = true,
    ["journal_postDelete"] = true,
    ["journal_deleted"] = true,
    ["journal_colPost"] = true,
    ["input_JOURNAL_OPEN"] = true,
}

local function journalGetText(self, superFunc, text, modEnv)
    if modEnv == nil and JournalI18NTexts[text] then
        return superFunc(self, text, modName)
    end
    return superFunc(self, text, modEnv)
end

I18N.getText = Utils.overwrittenFunction(I18N.getText, journalGetText)
JournalLogger.info("main", "I18N override installed")

local function initJournalManager()
    JournalLogger.info("main", "initJournalManager")
    if Journal.manager == nil then
        Journal.manager = JournalManager:new()
        Journal.manager:init()
        g_journalManager = Journal.manager
        JournalLogger.info("main", "JournalManager created and initialized")
    end
end

local function loadSavegameData()
    JournalLogger.info("main", "loadSavegameData")
    if g_server ~= nil and Journal.manager ~= nil then
        JournalLogger.info("main", "Server mode: loading savegame")
        Journal.manager:loadFromSavegame()
        if JournalSettings ~= nil then JournalSettings.loadFromXMLFile() end
        Journal.manager:syncToClients()
        JournalLogger.info("main", "Savegame loaded and synced to clients")
    end
end

local function setupGUI()
    JournalLogger.info("main", "setupGUI")

    -- Load custom GUI profiles BEFORE loading any GUI XML that references them
    local profilesOk = g_gui:loadProfiles(modDirectory .. "gui/guiProfiles.xml")
    JournalLogger.info("main", "guiProfiles.xml loaded: " .. tostring(profilesOk))

    -- Create and load JournalScreen (InGameMenu page)
    Journal.screen = JournalScreen.new(g_i18n, g_messageCenter)
    JournalLogger.info("main", "JournalScreen instance created")

    local screenOk = g_gui:loadGui(modDirectory .. "gui/JournalScreen.xml", "JournalScreen", Journal.screen, true)
    JournalLogger.info("main", "JournalScreen GUI loaded: " .. tostring(screenOk))

    -- Register in InGameMenu
    Journal.registerInGameMenuPage(Journal.screen, "JournalScreen", {0, 0, 1024, 1024}, function() return true end)

    Journal.screen:initialize()
    JournalLogger.info("main", "JournalScreen initialized and registered in InGameMenu")

    -- Create and load CreatePostDialog
    Journal.createPostDialog = JournalCreatePostDialog.new(Journal.screen)
    JournalLogger.info("main", "JournalCreatePostDialog instance created")

    local dialogOk = g_gui:loadGui(modDirectory .. "gui/JournalCreatePostDialog.xml", "JournalCreatePostDialog", Journal.createPostDialog)
    JournalLogger.info("main", "JournalCreatePostDialog GUI loaded: " .. tostring(dialogOk))

    Journal.screen:setCreatePostDialog(Journal.createPostDialog)
end

function Journal.registerInGameMenuPage(frame, pageName, uvs, predicateFunc)
    JournalLogger.info("main", "registerInGameMenuPage: " .. pageName .. " frame=" .. tostring(frame))
    JournalLogger.info("main", "  g_inGameMenu=" .. tostring(g_inGameMenu) .. " pagingElement=" .. tostring(g_inGameMenu and g_inGameMenu.pagingElement))
    JournalLogger.info("main", "  g_inGameMenu.pages=" .. tostring(g_inGameMenu and g_inGameMenu.pages))
    JournalLogger.info("main", "  g_inGameMenu.pageFrames=" .. tostring(g_inGameMenu and g_inGameMenu.pageFrames))

    local targetPosition = 1

    if g_inGameMenu.controlIDs then
        g_inGameMenu.controlIDs[pageName] = nil
    end

    g_inGameMenu[pageName] = frame

    if g_inGameMenu.pagingElement then
        g_inGameMenu.pagingElement:addElement(g_inGameMenu[pageName])
        JournalLogger.info("main", "  added to pagingElement")
    end

    if g_inGameMenu.exposeControlsAsFields then
        g_inGameMenu:exposeControlsAsFields(pageName)
        JournalLogger.info("main", "  exposeControlsAsFields done")
    end

    if g_inGameMenu.pagingElement and g_inGameMenu.pagingElement.elements then
        for i = 1, #g_inGameMenu.pagingElement.elements do
            local child = g_inGameMenu.pagingElement.elements[i]
            if child == g_inGameMenu[pageName] then
                table.remove(g_inGameMenu.pagingElement.elements, i)
                table.insert(g_inGameMenu.pagingElement.elements, targetPosition, child)
                JournalLogger.info("main", "  moved element to position " .. targetPosition)
                break
            end
        end
    end

    if g_inGameMenu.pagingElement and g_inGameMenu.pagingElement.pages then
        for i = 1, #g_inGameMenu.pagingElement.pages do
            local child = g_inGameMenu.pagingElement.pages[i]
            if child and child.element == g_inGameMenu[pageName] then
                table.remove(g_inGameMenu.pagingElement.pages, i)
                table.insert(g_inGameMenu.pagingElement.pages, targetPosition, child)
                JournalLogger.info("main", "  moved page to position " .. targetPosition)
                break
            end
        end
    end

    if g_inGameMenu.pagingElement then
        g_inGameMenu.pagingElement:updateAbsolutePosition()
        g_inGameMenu.pagingElement:updatePageMapping()
        JournalLogger.info("main", "  absolute position and page mapping updated")
    end

    if g_inGameMenu.registerPage then
        g_inGameMenu:registerPage(g_inGameMenu[pageName], nil, predicateFunc)
        JournalLogger.info("main", "  page registered")
    end

    local iconFileName = Utils.getFilename('images/icon_Journal.dds', Journal.modDirectory)
    JournalLogger.info("main", "  icon path: " .. tostring(iconFileName) .. " exists: " .. tostring(fileExists(iconFileName)))

    if g_inGameMenu.addPageTab then
        g_inGameMenu:addPageTab(g_inGameMenu[pageName], iconFileName, GuiUtils.getUVs(uvs))
        JournalLogger.info("main", "  page tab added")
    end

    if g_inGameMenu.pageFrames then
        for i = 1, #g_inGameMenu.pageFrames do
            local child = g_inGameMenu.pageFrames[i]
            if child == g_inGameMenu[pageName] then
                table.remove(g_inGameMenu.pageFrames, i)
                table.insert(g_inGameMenu.pageFrames, targetPosition, child)
                JournalLogger.info("main", "  moved pageFrame to position " .. targetPosition)
                break
            end
        end
    end

    if g_inGameMenu.rebuildTabList then
        g_inGameMenu:rebuildTabList()
        JournalLogger.info("main", "  tab list rebuilt")
    end

    -- Replace custom DDS tab icon with standard game slice for correct selected-state rendering
    if g_inGameMenu.pageTabs and g_inGameMenu.pageTabs[g_inGameMenu[pageName]] then
        local tab = g_inGameMenu.pageTabs[g_inGameMenu[pageName]]
        tab.iconFilename = nil
        tab.iconUVs = nil
        tab.iconSliceId = "gui.icon_ingameMenu_contracts"
        JournalLogger.info("main", "  tab icon replaced with game slice")
        if g_inGameMenu.rebuildTabList then
            g_inGameMenu:rebuildTabList()
            JournalLogger.info("main", "  tab list rebuilt after icon swap")
        end
    else
        JournalLogger.warning("main", "  could not find pageTabs entry for icon swap")
    end

    JournalLogger.info("main", "registerInGameMenuPage complete for " .. pageName)
end

-- Open journal in InGameMenu
local function openJournal()
    JournalLogger.info("main", "openJournal called - Journal.screen=" .. tostring(Journal.screen))
    if g_inGameMenu == nil then
        JournalLogger.warning("main", "g_inGameMenu is nil - cannot open journal")
        return
    end
    if Journal.screen == nil then
        JournalLogger.warning("main", "Journal.screen is nil - cannot navigate")
        return
    end

    if g_inGameMenu:getIsOpen() then
        JournalLogger.info("main", "InGameMenu already open, switching to JournalScreen")
        g_inGameMenu:goToPage(Journal.screen)
    else
        JournalLogger.info("main", "Opening InGameMenu with JournalScreen frame")
        g_inGameMenu:openMenu(nil, Journal.screen)
    end
end

-- Hook into mission lifecycle
local function loadedMission()
    JournalLogger.info("main", "loadedMission called")
    JournalLogger.info("main", "modDirectory=" .. tostring(modDirectory) .. " modName=" .. tostring(modName))

    local ok

    ok = pcall(function() initJournalManager() end)
    JournalLogger.info("main", "initJournalManager ok=" .. tostring(ok) .. " manager=" .. tostring(Journal.manager))

    ok = pcall(function() setupGUI() end)
    JournalLogger.info("main", "setupGUI ok=" .. tostring(ok) .. " screen=" .. tostring(Journal.screen))

    ok = pcall(function() loadSavegameData() end)
    JournalLogger.info("main", "loadSavegameData ok=" .. tostring(ok))

    if JournalSettings ~= nil then
        JournalSettings.loadDefaultsIfMissing()
    end

    -- Test translation override
    local testText = ""
    if g_i18n then
        testText = g_i18n:getText("journal_filterAll")
        JournalLogger.info("main", "i18n test: journal_filterAll = '" .. tostring(testText) .. "'")
        testText = g_i18n:getText("journal_title")
        JournalLogger.info("main", "i18n test: journal_title = '" .. tostring(testText) .. "'")
    end

    JournalLogger.info("main", "=== Server Journal initialization complete ===")
end

local function onSaveToXMLFile()
    if not g_currentMission:getIsServer() then return end
    if Journal.manager then
        JournalLogger.info("main", "Saving to savegame on game save")
        Journal.manager:saveToSavegame()
    end
    if JournalSettings ~= nil then
        JournalSettings.saveToXMLFile()
    end
end

local function sendInitialClientState(self, connection, user, farm)
    if g_server == nil then return end
    if connection == nil then
        JournalLogger.warning("main", "sendInitialClientState: connection is nil")
        return
    end
    if Journal.manager == nil then
        JournalLogger.warning("main", "sendInitialClientState: manager not initialized")
        return
    end
    JournalLogger.info("main", "sendInitialClientState: syncing to new client")
    connection:sendEvent(JournalEvent.new(JournalEvent.TYPE_SYNC, Journal.manager:getPosts()))
    if JournalSettingsEvent ~= nil and g_currentMission and g_currentMission.journalSettings then
        connection:sendEvent(JournalSettingsEvent.new(g_currentMission.journalSettings))
    end
end

local function initJournal()
    JournalLogger.info("main", "initJournal - registering lifecycle hooks")

    -- Original keyEvent handler (was working before)
    pcall(function()
        if FSBaseMission.keyEvent == nil then
            FSBaseMission.keyEvent = function() end
        end
        FSBaseMission.keyEvent = Utils.appendedFunction(FSBaseMission.keyEvent, function(self, key, isDown, symbol, repeated)
            if isDown and not repeated and key == Input.KEY_j then
                openJournal()
            end
        end)
        JournalLogger.info("main", "keyEvent handler installed at bootstrap")
    end)

    Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, loadedMission)

    FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, onSaveToXMLFile)

    FSBaseMission.sendInitialClientState = Utils.appendedFunction(FSBaseMission.sendInitialClientState, sendInitialClientState)

    BaseMission.delete = Utils.appendedFunction(BaseMission.delete, function()
        JournalLogger.info("main", "Mission cleanup")
        if Journal.manager then
            Journal.manager:cleanup()
            Journal.manager = nil
        end
        Journal.screen = nil
        Journal.createPostDialog = nil
    end)

    JournalLogger.info("main", "Lifecycle hooks registered")
end

initJournal()

JournalLogger.info("main", "=== Server Journal bootstrap complete ===")
