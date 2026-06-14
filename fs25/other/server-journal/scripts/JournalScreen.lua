-- Server Journal - InGameMenu page
-- Follows FS25_Invoices UI pattern (InvoicesFrame)

JournalScreen = {}
local JournalScreen_mt = Class(JournalScreen, TabbedMenuFrameElement)

JournalScreen.FILTER = {
    ALL     = 1,
    JOB     = 2,
    SALE    = 3,
    FREIGHT = 4,
    RP      = 5
}

JournalScreen.CONTROLS = {
    HEADER_ICON       = "headerIcon",
    HEADER_TITLE      = "headerTitleText",
    LIST_POSTS        = "listPosts",
    LIST_SLIDER_BOX   = "listSliderBox",
    EMPTY_LIST_TEXT   = "emptyListText",
    DETAIL_PANEL      = "detailPanel",
    DETAIL_VBOX       = "detailVBox",
    DETAIL_TITLE      = "detailTitle",
    DETAIL_AUTHOR     = "detailAuthor",
    DETAIL_CATEGORY   = "detailCategory",
    DETAIL_PAYMENT    = "detailPayment",
    DETAIL_DATE       = "detailDate",
    DETAIL_DESC_LABEL  = "detailDescLabel",
    DETAIL_DESCRIPTION = "detailDescription",
    FILTER_BOX        = "filterBox",
    FILTER_PAGING     = "filterPaging",
    CONTENT_AREA      = "contentArea",
    LIST_PANEL        = "listPanel",
    FILTER_BTNS       = "filterBtns",
}

function JournalScreen.new(i18n, messageCenter)
    JournalLogger.info("JournalScreen", "new")
    local self = JournalScreen:superClass().new(nil, JournalScreen_mt)

    self.name = "JournalScreen"
    self.i18n = i18n or g_i18n
    self.messageCenter = messageCenter or g_messageCenter

    self.currentFilter = JournalScreen.FILTER.ALL
    self.posts = {}
    self.filteredPosts = {}
    self.selectedPostIndex = nil
    self.createPostDialog = nil

    JournalLogger.info("JournalScreen", "instance created")
    return self
end

function JournalScreen:setCreatePostDialog(dialog)
    self.createPostDialog = dialog
    JournalLogger.info("JournalScreen", "createPostDialog set")
end

function JournalScreen:onGuiSetupFinished()
    JournalLogger.info("JournalScreen", "onGuiSetupFinished")
    JournalScreen:superClass().onGuiSetupFinished(self)

    if self.listPosts then
        self.listPosts:setDataSource(self)
        self.listPosts:setDelegate(self)
        JournalLogger.info("JournalScreen", "listPosts dataSource+delegate set")
    end
end

function JournalScreen:initialize()
    JournalLogger.info("JournalScreen", "initialize")
    JournalScreen:superClass().initialize(self)

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
        text = self.i18n:getText("journal_createPost", Journal.modName),
        inputAction = InputAction.MENU_ACTIVATE,
        callback = function() self:onClickCreatePost() end
    }

    self.btnClose = {
        text = self.i18n:getText("journal_close", Journal.modName),
        inputAction = InputAction.MENU_CANCEL,
        callback = function()
            if g_inGameMenu then g_inGameMenu:exitMenu() end
        end
    }

    self.btnDelete = {
        text = self.i18n:getText("journal_postDelete", Journal.modName),
        inputAction = InputAction.MENU_EXTRA_1,
        disabled = true,
        callback = function() self:onClickDelete() end
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

    self.menuButtonInfo = { self.btnBack, self.btnNextPage, self.btnPrevPage, self.btnCreate, self.btnDelete, self.btnClose }

    -- Listen for data changes
    if Journal.manager then
        Journal.manager:addListener(function()
            JournalLogger.info("JournalScreen", "data change notification received")
            self:refreshPostList()
        end)
        JournalLogger.info("JournalScreen", "listener registered with JournalManager")
    end

    JournalLogger.info("JournalScreen", "initialization complete")
end

function JournalScreen:getFilterState()
    if self.filterPaging then
        return self.filterPaging:getState()
    end
    return self.currentFilter or JournalScreen.FILTER.ALL
end

function JournalScreen:onFrameOpen()
    JournalLogger.info("JournalScreen", "onFrameOpen")
    JournalScreen:superClass().onFrameOpen(self)

    -- Set icon using standard game slice for correct selected-state rendering
    if self.headerIcon then
        self.headerIcon:setImageSlice(nil, "gui.icon_ingameMenu_contracts")
        JournalLogger.info("JournalScreen", "header icon set via game slice")
    end

    -- Setup filter paging
    if self.filterPaging then
        local filterKeys = { "journal_filterAll", "journal_filterJob", "journal_filterSale", "journal_filterFreight", "journal_filterRP" }
        local texts = {}
        for _, key in ipairs(filterKeys) do
            table.insert(texts, self.i18n:getText(key, Journal.modName))
        end
        self.filterPaging:setTexts(texts)
        self.filterPaging:setState(self.currentFilter, true)
    end
    if self.filterBox then
        self.filterBox:invalidateLayout()
    end

    -- Refresh data
    self:loadPosts()
    self:refreshPostList()

    self:setMenuButtonInfoDirty()
    JournalLogger.info("JournalScreen", "onFrameOpen complete")
end

function JournalScreen:onFrameClose()
    JournalLogger.info("JournalScreen", "onFrameClose")
    JournalScreen:superClass().onFrameClose(self)
end

-- Filter click handlers
function JournalScreen:onClickFilterAll()
    self.currentFilter = JournalScreen.FILTER.ALL
    if self.filterPaging then self.filterPaging:setState(JournalScreen.FILTER.ALL, true) end
    self:refreshPostList()
    self:setMenuButtonInfoDirty()
    JournalLogger.info("JournalScreen", "filter set to ALL")
end

function JournalScreen:onClickFilterJob()
    self.currentFilter = JournalScreen.FILTER.JOB
    if self.filterPaging then self.filterPaging:setState(JournalScreen.FILTER.JOB, true) end
    self:refreshPostList()
    self:setMenuButtonInfoDirty()
    JournalLogger.info("JournalScreen", "filter set to JOB")
end

function JournalScreen:onClickFilterSale()
    self.currentFilter = JournalScreen.FILTER.SALE
    if self.filterPaging then self.filterPaging:setState(JournalScreen.FILTER.SALE, true) end
    self:refreshPostList()
    self:setMenuButtonInfoDirty()
    JournalLogger.info("JournalScreen", "filter set to SALE")
end

function JournalScreen:onClickFilterFreight()
    self.currentFilter = JournalScreen.FILTER.FREIGHT
    if self.filterPaging then self.filterPaging:setState(JournalScreen.FILTER.FREIGHT, true) end
    self:refreshPostList()
    self:setMenuButtonInfoDirty()
    JournalLogger.info("JournalScreen", "filter set to FREIGHT")
end

function JournalScreen:onClickFilterRP()
    self.currentFilter = JournalScreen.FILTER.RP
    if self.filterPaging then self.filterPaging:setState(JournalScreen.FILTER.RP, true) end
    self:refreshPostList()
    self:setMenuButtonInfoDirty()
    JournalLogger.info("JournalScreen", "filter set to RP")
end

function JournalScreen:onClickFilterPaging()
    if self.filterPaging then
        self.currentFilter = self.filterPaging:getState()
    end
    self:refreshPostList()
    self:setMenuButtonInfoDirty()
    JournalLogger.info("JournalScreen", "filter paging changed to: " .. tostring(self.currentFilter))
end

-- Data loading

function JournalScreen:loadPosts()
    JournalLogger.info("JournalScreen", "loadPosts")
    self.posts = {}
    if Journal.manager then
        self.posts = Journal.manager:getPosts() or {}
        JournalLogger.info("JournalScreen", "loaded " .. #self.posts .. " posts from manager")
    else
        JournalLogger.warning("JournalScreen", "Journal.manager is nil")
    end
end

function JournalScreen:getFilteredPosts()
    if self.currentFilter == JournalScreen.FILTER.ALL then
        return self.posts
    end
    local filterKey = self:getFilterKey()
    local filtered = {}
    for _, post in ipairs(self.posts) do
        if post.category == filterKey then
            table.insert(filtered, post)
        end
    end
    return filtered
end

function JournalScreen:getFilterKey()
    local map = {
        [JournalScreen.FILTER.ALL]     = "all",
        [JournalScreen.FILTER.JOB]     = "job",
        [JournalScreen.FILTER.SALE]    = "sale",
        [JournalScreen.FILTER.FREIGHT] = "freight",
        [JournalScreen.FILTER.RP]      = "rp",
    }
    return map[self.currentFilter] or "all"
end

-- List refresh

function JournalScreen:refreshPostList()
    JournalLogger.info("JournalScreen", "refreshPostList")
    self:loadPosts()
    self.filteredPosts = self:getFilteredPosts()

    self:clearDetail()

    if self.listPosts then
        self.listPosts:reloadData()
    end

    -- Show/hide empty state
    local hasPosts = #self.filteredPosts > 0
    if self.emptyListText then
        self.emptyListText:setVisible(not hasPosts)
    end

    self:updateSliderVisibility()

    -- Update button states
    self.btnDelete.disabled = true
    self:setMenuButtonInfoDirty()

    JournalLogger.info("JournalScreen", "refreshPostList complete, showing " .. #self.filteredPosts .. " posts")
end

function JournalScreen:updateSliderVisibility()
    if self.listSliderBox and self.listPosts then
        local maxVisible = math.floor(535 / 36)
        self.listSliderBox:setVisible(#self.filteredPosts > maxVisible)
    end
end

-- Detail panel

function JournalScreen:clearDetail()
    JournalLogger.info("JournalScreen", "clearDetail")
    self.selectedPostIndex = nil
    if self.detailTitle then
        self.detailTitle:setText(self.i18n:getText("journal_detailNoSelection", Journal.modName))
        self.detailTitle:setVisible(true)
    end
    if self.detailAuthor then self.detailAuthor:setText("") end
    if self.detailCategory then self.detailCategory:setText("") end
    if self.detailPayment then self.detailPayment:setText("") end
    if self.detailDate then self.detailDate:setText("") end
    if self.detailDescLabel then self.detailDescLabel:setVisible(false) end
    if self.detailDescription then
        self.detailDescription:setText("")
        self.detailDescription:setVisible(false)
    end
    if self.detailVBox then
        self.detailVBox:invalidateLayout()
    end
end

function JournalScreen:showDetail(post)
    if post == nil then
        self:clearDetail()
        return
    end
    JournalLogger.info("JournalScreen", "showDetail for post: " .. tostring(post.title))

    if self.detailTitle then
        self.detailTitle:setText(post.title or "")
        self.detailTitle:setVisible(true)
    end
    if self.detailAuthor then
        self.detailAuthor:setText(self.i18n:getText("journal_by", Journal.modName) .. " " .. (post.authorName or "?"))
        self.detailAuthor:setVisible(true)
    end
    if self.detailCategory then
        local catKey = JournalUI.CATEGORY_KEYS[post.category]
        local catText = catKey and self.i18n:getText(catKey, Journal.modName) or post.category or ""
        self.detailCategory:setText(self.i18n:getText("journal_category", Journal.modName) .. " " .. catText)
        self.detailCategory:setVisible(true)
    end
    if self.detailPayment then
        local payment = post.payment or 0
        local moneyStr = g_i18n:formatMoney(payment, 0, true, false)
        self.detailPayment:setText(self.i18n:getText("journal_payment", Journal.modName) .. " " .. moneyStr)
        self.detailPayment:setVisible(true)
    end
    if self.detailDate then
        local ca = post.createdAt or {}
        local dateStr = ""
        if type(ca) == "table" and (ca.year or 0) > 0 then
            dateStr = string.format("Dia %d Per.%d Ano %d %02d:%02d",
                ca.day or 0, ca.period or 0, ca.year or 1, ca.hour or 0, ca.minute or 0)
        end
        self.detailDate:setText(self.i18n:getText("journal_posted", Journal.modName) .. " " .. dateStr)
        self.detailDate:setVisible(true)
    end
    if self.detailDescription then
        local desc = post.description or ""
        self.detailDescription:setText(desc)
        if self.detailDescLabel then
            self.detailDescLabel:setVisible(desc ~= "")
        end
        self.detailDescription:setVisible(desc ~= "")
    end
    if self.detailVBox then
        self.detailVBox:invalidateLayout()
    end
end

-- SmoothList DataSource/Delegate

function JournalScreen:getNumberOfSections(list)
    return 1
end

function JournalScreen:getNumberOfItemsInSection(list, section)
    return #self.filteredPosts
end

function JournalScreen:getTitleForSectionHeader(list, section)
    return nil
end

function JournalScreen:getSectionHeaderHeight(list, section)
    return 0
end

function JournalScreen:getCellTypeForItemInSection(list, section, index)
    return "journalPostListItem"
end

function JournalScreen:populateCellForItemInSection(list, section, index, cell)
    local post = self.filteredPosts[index]
    if post == nil then return end

    local cellTitle = cell:getDescendantByName("cellTitle")
    if cellTitle then
        cellTitle:setText(post.title or "")
    end

    local cellCategory = cell:getDescendantByName("cellCategory")
    if cellCategory then
        local catKey = JournalUI.CATEGORY_KEYS[post.category]
        local catText = catKey and self.i18n:getText(catKey, Journal.modName) or post.category or ""
        cellCategory:setText(catText)
    end

    local cellAuthor = cell:getDescendantByName("cellAuthor")
    if cellAuthor then
        cellAuthor:setText(post.authorName or "")
    end
end

function JournalScreen:onListSelectionChanged(list, section, index)
    JournalLogger.info("JournalScreen", "onListSelectionChanged section=" .. tostring(section) .. " index=" .. tostring(index))
    if list ~= self.listPosts then return end

    if index >= 1 and index <= #self.filteredPosts then
        self.selectedPostIndex = index
        local post = self.filteredPosts[index]
        self:showDetail(post)
        self.btnDelete.disabled = false
    else
        self.selectedPostIndex = nil
        self:clearDetail()
        self.btnDelete.disabled = true
    end
    self:setMenuButtonInfoDirty()
end

-- Button handlers

function JournalScreen:onClickCreatePost()
    JournalLogger.info("JournalScreen", "onClickCreatePost")
    if self.createPostDialog == nil then
        JournalLogger.warning("JournalScreen", "createPostDialog is nil")
        return
    end

    local playerName = ""
    local playerId = 0
    if g_currentMission and g_currentMission.player then
        playerName = g_currentMission.player:getName() or ""
        playerId = g_currentMission.player:getId() or 0
    elseif g_localPlayer then
        playerId = g_localPlayer.farmId or 0
        playerName = tostring(playerId)
    end

    self.createPostDialog:setCallback(function(title, description, category, payment)
        JournalLogger.info("JournalScreen", "CreatePost callback: title=" .. tostring(title) .. " cat=" .. tostring(category))
        if Journal.manager == nil then
            JournalLogger.warning("JournalScreen", "Journal.manager nil on create")
            return
        end

        if g_server ~= nil then
            Journal.manager:addPost(playerId, playerName, title, description, category, payment)
            JournalUI.showNotification(self.i18n:getText("journal_postCreated", Journal.modName))
        elseif g_client ~= nil then
            local conn = g_client:getServerConnection()
            if conn then
                conn:sendEvent(JournalEvent.new(JournalEvent.TYPE_CREATE, {
                    id = -1,
                    authorId = playerId,
                    authorName = playerName,
                    title = title,
                    description = description,
                    category = category,
                    payment = payment or 0,
                    createdAt = "",
                }))
                JournalUI.showNotification(self.i18n:getText("journal_postRequested", Journal.modName))
            else
                JournalUI.showError("No server connection")
            end
        end
    end)

    self.createPostDialog:resetUI()
    g_gui:showDialog("JournalCreatePostDialog")
end

function JournalScreen:onClickDelete()
    JournalLogger.info("JournalScreen", "onClickDelete")
    if self.selectedPostIndex == nil then return end
    local post = self.filteredPosts[self.selectedPostIndex]
    if post == nil then return end

    if Journal.manager == nil then
        JournalLogger.warning("JournalScreen", "Journal.manager nil on delete")
        return
    end

    if g_server ~= nil then
        Journal.manager:removePost(post.id)
        JournalUI.showNotification(self.i18n:getText("journal_deleted", Journal.modName))
    elseif g_client ~= nil then
        local conn = g_client:getServerConnection()
        if conn then
            conn:sendEvent(JournalEvent.new(JournalEvent.TYPE_DELETE, { id = post.id }))
            JournalUI.showNotification(self.i18n:getText("journal_deleted", Journal.modName))
        end
    end
end

-- Menu button info

function JournalScreen:getMenuButtonInfo()
    if self.menuButtonInfo == nil then return {} end
    return self.menuButtonInfo
end

function JournalScreen:copyAttributes(src)
    JournalScreen:superClass().copyAttributes(self, src)
    self.i18n = src.i18n
    self.messageCenter = src.messageCenter
end

function JournalScreen:delete()
    JournalLogger.info("JournalScreen", "delete")
    self.posts = nil
    self.filteredPosts = nil
    self.menuButtonInfo = nil
    self.createPostDialog = nil
    JournalScreen:superClass().delete(self)
end
