-- Server Auction House - InGameMenu page
-- Follows FS25_ServerJournal's JournalScreen pattern

AuctionScreen = {}
local AuctionScreen_mt = Class(AuctionScreen, TabbedMenuFrameElement)

AuctionScreen.FILTER = {
    ALL  = 1,
    MINE = 2,
}

AuctionScreen.CONTROLS = {
    HEADER_ICON      = "headerIcon",
    HEADER_TITLE     = "headerTitleText",
    LIST_AUCTIONS    = "listAuctions",
    LIST_SLIDER_BOX  = "listSliderBox",
    EMPTY_LIST_TEXT  = "emptyListText",
    DETAIL_PANEL     = "detailPanel",
    DETAIL_VBOX      = "detailVBox",
    DETAIL_TITLE     = "detailTitle",
    DETAIL_SELLER    = "detailSeller",
    DETAIL_STARTING  = "detailStarting",
    DETAIL_CURRENT   = "detailCurrent",
    DETAIL_BIDDER    = "detailBidder",
    DETAIL_TIME      = "detailTime",
    BID_ROW          = "bidRow",
    BID_INPUT        = "bidInput",
    BID_BUTTON       = "bidButton",
    FILTER_BOX       = "filterBox",
    FILTER_PAGING    = "filterPaging",
    CONTENT_AREA     = "contentArea",
    LIST_PANEL       = "listPanel",
    FILTER_BTNS      = "filterBtns",
}

function AuctionScreen.new(i18n, messageCenter)
    AuctionLogger.info("AuctionScreen", "new")
    local self = AuctionScreen:superClass().new(nil, AuctionScreen_mt)

    self.name = "AuctionScreen"
    self.i18n = i18n or g_i18n
    self.messageCenter = messageCenter or g_messageCenter

    self.currentFilter = AuctionScreen.FILTER.ALL
    self.auctions = {}
    self.filteredAuctions = {}
    self.selectedAuctionIndex = nil
    self.createAuctionDialog = nil
    self.timeAccum = 0

    AuctionLogger.info("AuctionScreen", "instance created")
    return self
end

function AuctionScreen:setCreateAuctionDialog(dialog)
    self.createAuctionDialog = dialog
    AuctionLogger.info("AuctionScreen", "createAuctionDialog set")
end

function AuctionScreen:onGuiSetupFinished()
    AuctionLogger.info("AuctionScreen", "onGuiSetupFinished")
    AuctionScreen:superClass().onGuiSetupFinished(self)

    if self.listAuctions then
        self.listAuctions:setDataSource(self)
        self.listAuctions:setDelegate(self)
        AuctionLogger.info("AuctionScreen", "listAuctions dataSource+delegate set")
    end
end

function AuctionScreen:initialize()
    AuctionLogger.info("AuctionScreen", "initialize")
    AuctionScreen:superClass().initialize(self)

    -- Setup filter tab backgrounds
    if self.filterBtns then
        for i, tab in pairs(self.filterBtns) do
            if tab then
                local bg = tab:getDescendantByName("background")
                if bg then
                    bg.getIsSelected = function()
                        return i == self:getFilterState()
                    end
                end
                tab.getIsSelected = function()
                    return i == self:getFilterState()
                end
            end
        end
    end

    -- Menu buttons
    self.btnBack = {
        inputAction = InputAction.MENU_BACK
    }

    self.btnCreate = {
        text = self.i18n:getText("ah_createAuction", AuctionHouse.modName),
        inputAction = InputAction.MENU_ACTIVATE,
        callback = function() self:onClickCreateAuction() end
    }

    self.btnClose = {
        text = self.i18n:getText("ah_close", AuctionHouse.modName),
        inputAction = InputAction.MENU_CANCEL,
        callback = function()
            if g_inGameMenu then g_inGameMenu:exitMenu() end
        end
    }

    self.btnCancel = {
        text = self.i18n:getText("ah_cancelAuction", AuctionHouse.modName),
        inputAction = InputAction.MENU_EXTRA_1,
        disabled = true,
        callback = function() self:onClickCancelAuction() end
    }

    self.btnNextPage = {
        inputAction = InputAction.MENU_PAGE_NEXT,
        text = self.i18n:getText("ui_ingameMenuNext"),
        callback = function() self:onPageNext() end
    }
    self.btnPrevPage = {
        inputAction = InputAction.MENU_PAGE_PREV,
        text = self.i18n:getText("ui_ingameMenuPrev"),
        callback = function() self:onPagePrevious() end
    }

    self.menuButtonInfo = { self.btnBack, self.btnNextPage, self.btnPrevPage, self.btnCreate, self.btnCancel, self.btnClose }

    -- Listen for data changes
    if g_auctionManager then
        g_auctionManager:addListener(function()
            AuctionLogger.info("AuctionScreen", "data change notification received")
            self:refreshAuctionList()
        end)
        AuctionLogger.info("AuctionScreen", "listener registered with AuctionManager")
    end

    AuctionLogger.info("AuctionScreen", "initialization complete")
end

function AuctionScreen:getFilterState()
    if self.filterPaging then
        return self.filterPaging:getState()
    end
    return self.currentFilter or AuctionScreen.FILTER.ALL
end

function AuctionScreen:onFrameOpen()
    AuctionLogger.info("AuctionScreen", "onFrameOpen")
    AuctionScreen:superClass().onFrameOpen(self)

    -- Set icon using standard game slice for correct selected-state rendering
    if self.headerIcon then
        self.headerIcon:setImageSlice(nil, "gui.icon_ingameMenu_finances")
        AuctionLogger.info("AuctionScreen", "header icon set via game slice")
    end

    -- Setup filter paging
    if self.filterPaging then
        local filterKeys = { "ah_filterAll", "ah_filterMine" }
        local texts = {}
        for _, key in ipairs(filterKeys) do
            table.insert(texts, self.i18n:getText(key, AuctionHouse.modName))
        end
        self.filterPaging:setTexts(texts)
        self.filterPaging:setState(self.currentFilter, true)
    end
    if self.filterBox then
        self.filterBox:invalidateLayout()
    end

    self.timeAccum = 0
    self:refreshAuctionList()

    self:setMenuButtonInfoDirty()
    AuctionLogger.info("AuctionScreen", "onFrameOpen complete")
end

function AuctionScreen:onFrameClose()
    AuctionLogger.info("AuctionScreen", "onFrameClose")
    AuctionScreen:superClass().onFrameClose(self)
end

function AuctionScreen:update(dt)
    AuctionScreen:superClass().update(self, dt)

    self.timeAccum = (self.timeAccum or 0) + dt
    if self.timeAccum >= 1000 then
        self.timeAccum = 0
        self:refreshTimers()
    end
end

-- Filter click handlers

function AuctionScreen:onClickFilterAll()
    self.currentFilter = AuctionScreen.FILTER.ALL
    if self.filterPaging then self.filterPaging:setState(AuctionScreen.FILTER.ALL, true) end
    self:refreshAuctionList()
    AuctionLogger.info("AuctionScreen", "filter set to ALL")
end

function AuctionScreen:onClickFilterMine()
    self.currentFilter = AuctionScreen.FILTER.MINE
    if self.filterPaging then self.filterPaging:setState(AuctionScreen.FILTER.MINE, true) end
    self:refreshAuctionList()
    AuctionLogger.info("AuctionScreen", "filter set to MINE")
end

function AuctionScreen:onClickFilterPaging()
    if self.filterPaging then
        self.currentFilter = self.filterPaging:getState()
    end
    self:refreshAuctionList()
    AuctionLogger.info("AuctionScreen", "filter paging changed to: " .. tostring(self.currentFilter))
end

-- Data loading

function AuctionScreen:loadAuctions()
    self.auctions = {}
    if g_auctionManager then
        self.auctions = g_auctionManager:getAuctions() or {}
        AuctionLogger.info("AuctionScreen", "loaded " .. #self.auctions .. " auctions from manager")
    else
        AuctionLogger.warning("AuctionScreen", "g_auctionManager is nil")
    end
end

function AuctionScreen:getFilteredAuctions()
    if self.currentFilter == AuctionScreen.FILTER.MINE then
        local farmId = AuctionUI.getLocalFarmInfo()
        local filtered = {}
        for _, auction in ipairs(self.auctions) do
            if auction.sellerId == farmId then
                table.insert(filtered, auction)
            end
        end
        return filtered
    end
    return self.auctions
end

-- List refresh

function AuctionScreen:refreshAuctionList()
    AuctionLogger.info("AuctionScreen", "refreshAuctionList")
    self:loadAuctions()
    self.filteredAuctions = self:getFilteredAuctions()

    self:clearDetail()

    if self.listAuctions then
        self.listAuctions:reloadData()
    end

    local hasAuctions = #self.filteredAuctions > 0
    if self.emptyListText then
        self.emptyListText:setVisible(not hasAuctions)
    end

    self:updateSliderVisibility()

    self.btnCancel.disabled = true
    self:setMenuButtonInfoDirty()

    AuctionLogger.info("AuctionScreen", "refreshAuctionList complete, showing " .. #self.filteredAuctions .. " auctions")
end

function AuctionScreen:updateSliderVisibility()
    if self.listSliderBox and self.listAuctions then
        local maxVisible = math.floor(560 / 36)
        self.listSliderBox:setVisible(#self.filteredAuctions > maxVisible)
    end
end

-- Periodic refresh of time-left displays without losing selection
function AuctionScreen:refreshTimers()
    if self.listAuctions then
        self.listAuctions:reloadData()
    end
    if self.selectedAuctionIndex ~= nil then
        local auction = self.filteredAuctions[self.selectedAuctionIndex]
        if auction ~= nil then
            self:updateDetailTime(auction)
        end
    end
end

-- Detail panel

function AuctionScreen:clearDetail()
    AuctionLogger.info("AuctionScreen", "clearDetail")
    self.selectedAuctionIndex = nil
    if self.detailTitle then
        self.detailTitle:setText(self.i18n:getText("ah_detailNoSelection", AuctionHouse.modName))
        self.detailTitle:setVisible(true)
    end
    if self.detailSeller then self.detailSeller:setText("") end
    if self.detailStarting then self.detailStarting:setText("") end
    if self.detailCurrent then self.detailCurrent:setText("") end
    if self.detailBidder then self.detailBidder:setText("") end
    if self.detailTime then self.detailTime:setText("") end
    if self.bidRow then self.bidRow:setVisible(false) end
    if self.detailVBox then
        self.detailVBox:invalidateLayout()
    end
end

function AuctionScreen:updateDetailTime(auction)
    if self.detailTime == nil or auction == nil then return end
    local missionTime = 0
    if g_currentMission ~= nil then
        missionTime = g_currentMission.time or 0
    end
    local timeLeft = AuctionUI.formatTimeLeft(auction.endTime, missionTime)
    self.detailTime:setText(self.i18n:getText("ah_timeLeft", AuctionHouse.modName) .. " " .. timeLeft)
end

function AuctionScreen:showDetail(auction)
    if auction == nil then
        self:clearDetail()
        return
    end
    AuctionLogger.info("AuctionScreen", "showDetail for auction: " .. tostring(auction.itemName))

    if self.detailTitle then
        self.detailTitle:setText(auction.itemName or "")
        self.detailTitle:setVisible(true)
    end
    if self.detailSeller then
        self.detailSeller:setText(self.i18n:getText("ah_seller", AuctionHouse.modName) .. " " .. (auction.sellerName or "?"))
    end
    if self.detailStarting then
        self.detailStarting:setText(self.i18n:getText("ah_startingBid", AuctionHouse.modName) .. " " .. AuctionUI.formatMoney(auction.startingBid))
    end
    if self.detailCurrent then
        self.detailCurrent:setText(self.i18n:getText("ah_currentBid", AuctionHouse.modName) .. " " .. AuctionUI.formatMoney(auction.currentBid))
    end
    if self.detailBidder then
        local bidder = auction.highestBidderName
        if bidder == nil or bidder == "" then
            bidder = self.i18n:getText("ah_noBidsYet", AuctionHouse.modName)
        end
        self.detailBidder:setText(self.i18n:getText("ah_highestBidder", AuctionHouse.modName) .. " " .. bidder)
    end

    self:updateDetailTime(auction)

    local farmId = AuctionUI.getLocalFarmInfo()
    local isOwnAuction = (auction.sellerId == farmId)

    if self.bidRow then
        self.bidRow:setVisible(not isOwnAuction)
    end
    if self.bidInput then
        self.bidInput:setText(tostring((auction.currentBid or 0) + AuctionManager.MIN_BID_INCREMENT))
    end

    if self.detailVBox then
        self.detailVBox:invalidateLayout()
    end
end

-- SmoothList DataSource/Delegate

function AuctionScreen:getNumberOfSections(list)
    return 1
end

function AuctionScreen:getNumberOfItemsInSection(list, section)
    return #self.filteredAuctions
end

function AuctionScreen:getTitleForSectionHeader(list, section)
    return nil
end

function AuctionScreen:getSectionHeaderHeight(list, section)
    return 0
end

function AuctionScreen:getCellTypeForItemInSection(list, section, index)
    return "auctionListItem"
end

function AuctionScreen:populateCellForItemInSection(list, section, index, cell)
    local auction = self.filteredAuctions[index]
    if auction == nil then return end

    local cellTitle = cell:getDescendantByName("cellTitle")
    if cellTitle then
        cellTitle:setText(auction.itemName or "")
    end

    local cellBid = cell:getDescendantByName("cellBid")
    if cellBid then
        cellBid:setText(AuctionUI.formatMoney(auction.currentBid))
    end

    local cellTime = cell:getDescendantByName("cellTime")
    if cellTime then
        local missionTime = 0
        if g_currentMission ~= nil then
            missionTime = g_currentMission.time or 0
        end
        cellTime:setText(AuctionUI.formatTimeLeft(auction.endTime, missionTime))
    end

    local cellSeller = cell:getDescendantByName("cellSeller")
    if cellSeller then
        cellSeller:setText(auction.sellerName or "")
    end
end

function AuctionScreen:onListSelectionChanged(list, section, index)
    AuctionLogger.info("AuctionScreen", "onListSelectionChanged section=" .. tostring(section) .. " index=" .. tostring(index))
    if list ~= self.listAuctions then return end

    if index >= 1 and index <= #self.filteredAuctions then
        self.selectedAuctionIndex = index
        local auction = self.filteredAuctions[index]
        self:showDetail(auction)

        local farmId = AuctionUI.getLocalFarmInfo()
        self.btnCancel.disabled = (auction.sellerId ~= farmId)
    else
        self.selectedAuctionIndex = nil
        self:clearDetail()
        self.btnCancel.disabled = true
    end
    self:setMenuButtonInfoDirty()
end

-- Button handlers

function AuctionScreen:onClickCreateAuction()
    AuctionLogger.info("AuctionScreen", "onClickCreateAuction")
    if self.createAuctionDialog == nil then
        AuctionLogger.warning("AuctionScreen", "createAuctionDialog is nil")
        return
    end

    self.createAuctionDialog:setCallback(function(vehicleId, startingBid, durationMins)
        local farmId, playerName = AuctionUI.getLocalFarmInfo()
        AuctionLogger.info("AuctionScreen", "CreateAuction callback: vehicleId=" .. tostring(vehicleId) .. " startingBid=" .. tostring(startingBid) .. " duration=" .. tostring(durationMins))
        AuctionEvent.sendCreateRequest(farmId, playerName, vehicleId, startingBid, durationMins)
        AuctionUI.showNotification(self.i18n:getText("ah_auctionRequested", AuctionHouse.modName))
    end)

    self.createAuctionDialog:resetUI()
    AuctionLogger.info("AuctionScreen", "showing AuctionCreateDialog")
    g_gui:showDialog("AuctionCreateDialog")
    AuctionLogger.info("AuctionScreen", "showDialog call returned")
end

function AuctionScreen:onClickCancelAuction()
    AuctionLogger.info("AuctionScreen", "onClickCancelAuction")
    if self.selectedAuctionIndex == nil then return end
    local auction = self.filteredAuctions[self.selectedAuctionIndex]
    if auction == nil then return end

    local farmId, playerName = AuctionUI.getLocalFarmInfo()
    AuctionEvent.sendCancelRequest(farmId, playerName, auction.id)
    AuctionUI.showNotification(self.i18n:getText("ah_cancelRequested", AuctionHouse.modName))
end

function AuctionScreen:onClickPlaceBid()
    AuctionLogger.info("AuctionScreen", "onClickPlaceBid")
    if self.selectedAuctionIndex == nil or self.bidInput == nil then return end
    local auction = self.filteredAuctions[self.selectedAuctionIndex]
    if auction == nil then return end

    local amount = tonumber(self.bidInput:getText())
    if amount == nil then
        AuctionUI.showError(self.i18n:getText("ah_error_invalidAmount", AuctionHouse.modName))
        return
    end

    local farmId, playerName = AuctionUI.getLocalFarmInfo()
    AuctionEvent.sendBidRequest(farmId, playerName, auction.id, math.floor(amount))
    AuctionUI.showNotification(self.i18n:getText("ah_bidRequested", AuctionHouse.modName))
end

-- Menu button info

function AuctionScreen:getMenuButtonInfo()
    if self.menuButtonInfo == nil then return {} end
    return self.menuButtonInfo
end

function AuctionScreen:copyAttributes(src)
    AuctionScreen:superClass().copyAttributes(self, src)
    self.i18n = src.i18n
    self.messageCenter = src.messageCenter
end

function AuctionScreen:delete()
    AuctionLogger.info("AuctionScreen", "delete")
    self.auctions = nil
    self.filteredAuctions = nil
    self.menuButtonInfo = nil
    self.createAuctionDialog = nil
    AuctionScreen:superClass().delete(self)
end
