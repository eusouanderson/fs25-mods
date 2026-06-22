-- Server Auction House - Main bootstrap
-- Scripts are loaded by modDesc.xml extraSourceFiles in order; no source() needed here.

local modDirectory = g_currentModDirectory
local modName = g_currentModName

AuctionLogger.info("main", "=== Server Auction House bootstrap starting ===")

-- Global namespace
AuctionHouse = {}
AuctionHouse.modDirectory = modDirectory
AuctionHouse.modName = modName
AuctionHouse.manager = nil
AuctionHouse.screen = nil
AuctionHouse.createAuctionDialog = nil

-- I18N extension: resolve mod keys without modEnv
local AuctionHouseI18NTexts = {
    ["ah_title"] = true,
    ["ah_createAuction"] = true,
    ["ah_cancelAuction"] = true,
    ["ah_close"] = true,
    ["ah_filterAll"] = true,
    ["ah_filterMine"] = true,
    ["ah_colItem"] = true,
    ["ah_colCurrentBid"] = true,
    ["ah_colTimeLeft"] = true,
    ["ah_colSeller"] = true,
    ["ah_empty"] = true,
    ["ah_placeBid"] = true,
    ["ah_detailNoSelection"] = true,
    ["ah_seller"] = true,
    ["ah_startingBid"] = true,
    ["ah_currentBid"] = true,
    ["ah_highestBidder"] = true,
    ["ah_noBidsYet"] = true,
    ["ah_timeLeft"] = true,
    ["ah_statusActive"] = true,
    ["ah_statusEnded"] = true,
    ["ah_auctionRequested"] = true,
    ["ah_cancelRequested"] = true,
    ["ah_bidRequested"] = true,
    ["ah_error_invalidAmount"] = true,
    ["ah_error_noVehicle"] = true,
    ["ah_error_vehicleInAuction"] = true,
    ["ah_error_noAuction"] = true,
    ["ah_error_selfBid"] = true,
    ["ah_error_minBid"] = true,
    ["ah_error_noFunds"] = true,
    ["ah_error_notOwner"] = true,
    ["ah_error_hasBids"] = true,
    ["ah_bot_name_100"] = true,
    ["ah_bot_name_101"] = true,
    ["ah_bot_name_102"] = true,
    ["ah_bot_name_103"] = true,
    ["ah_bot_name_104"] = true,
    ["ah_bot_name_105"] = true,
    ["ah_bot_name_106"] = true,
    ["ah_bot_name_107"] = true,
    ["ah_global_auctionStarted"] = true,
    ["ah_global_newBid"] = true,
    ["ah_global_cancelled"] = true,
    ["ah_global_ended"] = true,
    ["ah_global_vehicleNotFound"] = true,
    ["ah_global_noBids"] = true,
    ["ah_dialogTitle"] = true,
    ["ah_dialogVehicleLabel"] = true,
    ["ah_dialogNoVehicles"] = true,
    ["ah_dialogSelectVehicle"] = true,
    ["ah_dialogStartingBidLabel"] = true,
    ["ah_dialogDurationLabel"] = true,
    ["ah_dialogCreateBtn"] = true,
    ["input_AUCTION_OPEN"] = true,
}

local function auctionHouseGetText(self, superFunc, text, modEnv)
    if modEnv == nil and AuctionHouseI18NTexts[text] then
        return superFunc(self, text, modName)
    end
    return superFunc(self, text, modEnv)
end

I18N.getText = Utils.overwrittenFunction(I18N.getText, auctionHouseGetText)
AuctionLogger.info("main", "I18N override installed")

local function initAuctionManager()
    AuctionLogger.info("main", "initAuctionManager")
    if AuctionHouse.manager == nil then
        AuctionHouse.manager = AuctionManager.new()
        AuctionHouse.manager:init()
        g_auctionManager = AuctionHouse.manager
        AuctionLogger.info("main", "AuctionManager created and initialized")
    end
end

local function loadSavegameData()
    AuctionLogger.info("main", "loadSavegameData")
    if g_server ~= nil and AuctionHouse.manager ~= nil then
        AuctionLogger.info("main", "Server mode: loading savegame")
        AuctionHouse.manager:loadFromSavegame()
        if AuctionSettings then AuctionSettings:loadFromXMLFile() end
        AuctionHouse.manager:syncToClients()
        AuctionLogger.info("main", "Savegame loaded and synced to clients")
    end
end

local function setupGUI()
    AuctionLogger.info("main", "setupGUI")

    -- Load custom GUI profiles BEFORE loading any GUI XML that references them
    local profilesOk = g_gui:loadProfiles(modDirectory .. "gui/guiProfiles.xml")
    AuctionLogger.info("main", "guiProfiles.xml loaded: " .. tostring(profilesOk))

    -- Create and load AuctionScreen (InGameMenu page)
    AuctionHouse.screen = AuctionScreen.new(g_i18n, g_messageCenter)
    AuctionLogger.info("main", "AuctionScreen instance created")

    local screenOk = g_gui:loadGui(modDirectory .. "gui/AuctionScreen.xml", "AuctionScreen", AuctionHouse.screen, true)
    AuctionLogger.info("main", "AuctionScreen GUI loaded: " .. tostring(screenOk))

    -- Register in InGameMenu
    AuctionHouse.registerInGameMenuPage(AuctionHouse.screen, "AuctionScreen", {0, 0, 1024, 1024}, function() return true end)

    AuctionHouse.screen:initialize()
    AuctionLogger.info("main", "AuctionScreen initialized and registered in InGameMenu")

    -- Create and load AuctionCreateDialog
    AuctionHouse.createAuctionDialog = AuctionCreateDialog.new(AuctionHouse.screen)
    AuctionLogger.info("main", "AuctionCreateDialog instance created")

    local dialogOk = g_gui:loadGui(modDirectory .. "gui/AuctionCreateDialog.xml", "AuctionCreateDialog", AuctionHouse.createAuctionDialog)
    AuctionLogger.info("main", "AuctionCreateDialog GUI loaded: " .. tostring(dialogOk))

    AuctionHouse.screen:setCreateAuctionDialog(AuctionHouse.createAuctionDialog)

    if AuctionSettings then
        AuctionSettings:loadDefaultsIfMissing()
        AuctionSettings:injectMenu()
    end
end

function AuctionHouse.registerInGameMenuPage(frame, pageName, uvs, predicateFunc)
    AuctionLogger.info("main", "registerInGameMenuPage: " .. pageName .. " frame=" .. tostring(frame))
    AuctionLogger.info("main", "  g_inGameMenu=" .. tostring(g_inGameMenu) .. " pagingElement=" .. tostring(g_inGameMenu and g_inGameMenu.pagingElement))
    AuctionLogger.info("main", "  g_inGameMenu.pages=" .. tostring(g_inGameMenu and g_inGameMenu.pages))
    AuctionLogger.info("main", "  g_inGameMenu.pageFrames=" .. tostring(g_inGameMenu and g_inGameMenu.pageFrames))

    local targetPosition = 1

    if g_inGameMenu.controlIDs then
        g_inGameMenu.controlIDs[pageName] = nil
    end

    g_inGameMenu[pageName] = frame

    if g_inGameMenu.pagingElement then
        g_inGameMenu.pagingElement:addElement(g_inGameMenu[pageName])
        AuctionLogger.info("main", "  added to pagingElement")
    end

    if g_inGameMenu.exposeControlsAsFields then
        g_inGameMenu:exposeControlsAsFields(pageName)
        AuctionLogger.info("main", "  exposeControlsAsFields done")
    end

    if g_inGameMenu.pagingElement and g_inGameMenu.pagingElement.elements then
        for i = 1, #g_inGameMenu.pagingElement.elements do
            local child = g_inGameMenu.pagingElement.elements[i]
            if child == g_inGameMenu[pageName] then
                table.remove(g_inGameMenu.pagingElement.elements, i)
                table.insert(g_inGameMenu.pagingElement.elements, targetPosition, child)
                AuctionLogger.info("main", "  moved element to position " .. targetPosition)
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
                AuctionLogger.info("main", "  moved page to position " .. targetPosition)
                break
            end
        end
    end

    if g_inGameMenu.pagingElement then
        g_inGameMenu.pagingElement:updateAbsolutePosition()
        g_inGameMenu.pagingElement:updatePageMapping()
        AuctionLogger.info("main", "  absolute position and page mapping updated")
    end

    if g_inGameMenu.registerPage then
        g_inGameMenu:registerPage(g_inGameMenu[pageName], nil, predicateFunc)
        AuctionLogger.info("main", "  page registered")
    end

    local iconFileName = Utils.getFilename('images/icon_AuctionHouse.dds', AuctionHouse.modDirectory)
    AuctionLogger.info("main", "  icon path: " .. tostring(iconFileName) .. " exists: " .. tostring(fileExists(iconFileName)))

    if g_inGameMenu.addPageTab then
        g_inGameMenu:addPageTab(g_inGameMenu[pageName], iconFileName, GuiUtils.getUVs(uvs))
        AuctionLogger.info("main", "  page tab added")
    end

    if g_inGameMenu.pageFrames then
        for i = 1, #g_inGameMenu.pageFrames do
            local child = g_inGameMenu.pageFrames[i]
            if child == g_inGameMenu[pageName] then
                table.remove(g_inGameMenu.pageFrames, i)
                table.insert(g_inGameMenu.pageFrames, targetPosition, child)
                AuctionLogger.info("main", "  moved pageFrame to position " .. targetPosition)
                break
            end
        end
    end

    if g_inGameMenu.rebuildTabList then
        g_inGameMenu:rebuildTabList()
        AuctionLogger.info("main", "  tab list rebuilt")
    end

    -- Replace custom DDS tab icon with standard game slice for correct selected-state rendering
    if g_inGameMenu.pageTabs and g_inGameMenu.pageTabs[g_inGameMenu[pageName]] then
        local tab = g_inGameMenu.pageTabs[g_inGameMenu[pageName]]
        tab.iconFilename = nil
        tab.iconUVs = nil
        tab.iconSliceId = "gui.icon_ingameMenu_finances"
        AuctionLogger.info("main", "  tab icon replaced with game slice")
        if g_inGameMenu.rebuildTabList then
            g_inGameMenu:rebuildTabList()
            AuctionLogger.info("main", "  tab list rebuilt after icon swap")
        end
    else
        AuctionLogger.warning("main", "  could not find pageTabs entry for icon swap")
    end

    AuctionLogger.info("main", "registerInGameMenuPage complete for " .. pageName)
end

-- Open auction house in InGameMenu
local function openAuctionHouse()
    AuctionLogger.info("main", "openAuctionHouse called - AuctionHouse.screen=" .. tostring(AuctionHouse.screen))
    if g_inGameMenu == nil then
        AuctionLogger.warning("main", "g_inGameMenu is nil - cannot open auction house")
        return
    end
    if AuctionHouse.screen == nil then
        AuctionLogger.warning("main", "AuctionHouse.screen is nil - cannot navigate")
        return
    end

    if g_inGameMenu:getIsOpen() then
        AuctionLogger.info("main", "InGameMenu already open, switching to AuctionScreen")
        g_inGameMenu:goToPage(AuctionHouse.screen)
    else
        AuctionLogger.info("main", "Opening InGameMenu with AuctionScreen frame")
        g_inGameMenu:openMenu(nil, AuctionHouse.screen)
    end
end

-- Hook into mission lifecycle
local function loadedMission()
    AuctionLogger.info("main", "loadedMission called")
    AuctionLogger.info("main", "modDirectory=" .. tostring(modDirectory) .. " modName=" .. tostring(modName))

    local ok

    ok = pcall(function() initAuctionManager() end)
    AuctionLogger.info("main", "initAuctionManager ok=" .. tostring(ok) .. " manager=" .. tostring(AuctionHouse.manager))

    ok = pcall(function() setupGUI() end)
    AuctionLogger.info("main", "setupGUI ok=" .. tostring(ok) .. " screen=" .. tostring(AuctionHouse.screen))

    ok = pcall(function() loadSavegameData() end)
    AuctionLogger.info("main", "loadSavegameData ok=" .. tostring(ok))

    -- Test translation override
    local testText = ""
    if g_i18n then
        testText = g_i18n:getText("ah_title")
        AuctionLogger.info("main", "i18n test: ah_title = '" .. tostring(testText) .. "'")
    end

    AuctionLogger.info("main", "=== Server Auction House initialization complete ===")
end

local function onSaveToXMLFile()
    if not g_currentMission:getIsServer() then return end
    if AuctionHouse.manager then
        AuctionLogger.info("main", "Saving to savegame on game save")
        AuctionHouse.manager:saveToSavegame()
    end
    if AuctionSettings then
        AuctionSettings:saveToXMLFile()
    end
end

local function sendInitialClientState(self, connection, user, farm)
    if g_server == nil then return end
    if connection == nil then
        AuctionLogger.warning("main", "sendInitialClientState: connection is nil")
        return
    end
    if AuctionHouse.manager == nil then
        AuctionLogger.warning("main", "sendInitialClientState: manager not initialized")
        return
    end
    AuctionLogger.info("main", "sendInitialClientState: syncing to new client")
    connection:sendEvent(AuctionEvent.new(AuctionEvent.TYPE_SYNC, AuctionHouse.manager:getAuctions()))
    
    if AuctionSettingsEvent ~= nil and g_currentMission and g_currentMission.auctionSettings then
        connection:sendEvent(AuctionSettingsEvent.new(g_currentMission.auctionSettings))
    end
end

local function onUpdate(_, dt)
    if AuctionHouse.manager then
        AuctionHouse.manager:update(dt)
    end
    if g_server ~= nil and AuctionBotManager ~= nil then
        AuctionBotManager.update(dt)
    end
end

local function initAuctionHouse()
    AuctionLogger.info("main", "initAuctionHouse - registering lifecycle hooks")

    pcall(function()
        if FSBaseMission.keyEvent == nil then
            FSBaseMission.keyEvent = function() end
        end
        FSBaseMission.keyEvent = Utils.appendedFunction(FSBaseMission.keyEvent, function(self, key, isDown, symbol, repeated)
            if isDown and not repeated and key == Input.KEY_k then
                openAuctionHouse()
            end
        end)
        AuctionLogger.info("main", "keyEvent handler installed at bootstrap")
    end)

    Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, loadedMission)

    Mission00.update = Utils.appendedFunction(Mission00.update, onUpdate)

    FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, onSaveToXMLFile)

    FSBaseMission.sendInitialClientState = Utils.appendedFunction(FSBaseMission.sendInitialClientState, sendInitialClientState)

    BaseMission.delete = Utils.appendedFunction(BaseMission.delete, function()
        AuctionLogger.info("main", "Mission cleanup")
        if AuctionHouse.manager then
            AuctionHouse.manager:cleanup()
            AuctionHouse.manager = nil
        end
        AuctionHouse.screen = nil
        AuctionHouse.createAuctionDialog = nil
    end)

    AuctionLogger.info("main", "Lifecycle hooks registered")
end

initAuctionHouse()

AuctionLogger.info("main", "=== Server Auction House bootstrap complete ===")
