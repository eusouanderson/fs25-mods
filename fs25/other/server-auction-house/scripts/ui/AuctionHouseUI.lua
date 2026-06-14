-- Server Auction House - UI Controller
-- FS25 ScreenElement pattern

AuctionHouseUI = {}
local AuctionHouseUI_mt = Class(AuctionHouseUI, ScreenElement)

AuctionHouseUI.CONTROLS = {
    TITLE_TEXT         = "titleText",
    LIST_PANEL         = "listPanel",
    DETAIL_PANEL       = "detailPanel",
    CREATE_PANEL       = "createPanel",
    NO_AUCTION_TEXT    = "noAuctionText",
    ITEM_TITLE         = "itemTitle",
    ITEM_SELLER        = "itemSeller",
    ITEM_STARTING      = "itemStarting",
    ITEM_CURRENT       = "itemCurrent",
    ITEM_BIDDER        = "itemBidder",
    ITEM_TIMELEFT      = "itemTimeLeft",
    BID_INPUT          = "bidInput",
    BID_BUTTON         = "bidButton",
    CANCEL_BUTTON      = "cancelButton",
    CREATE_BUTTON      = "createButton",
    BACK_BUTTON        = "backButton",
    VEHICLE_LIST       = "vehicleList",
    PRICE_INPUT        = "priceInput",
    DURATION_INPUT     = "durationInput",
    CONFIRM_CREATE_BTN = "confirmCreateBtn",
    CREATE_BACK_BTN    = "createBackBtn",
}

function AuctionHouseUI:new(modRef)
    local self = AuctionHouseUI:superClass().new(nil, AuctionHouseUI_mt)
    self.mod = modRef
    self.selectedAuction = nil
    self.availableVehicles = {}
    return self
end

function AuctionHouseUI:onCreate()
end

function AuctionHouseUI:onLoad()
    AuctionHouseUI:superClass().onLoad(self)
    self:registerControls(AuctionHouseUI.CONTROLS)
end

function AuctionHouseUI:onGuiSetupFinished()
    AuctionHouseUI:superClass().onGuiSetupFinished(self)
end

function AuctionHouseUI:onOpen()
    AuctionHouseUI:superClass().onOpen(self)

    self.selectedAuction = nil

    if self.createPanel then
        self.createPanel:setVisible(false)
    end
    if self.detailPanel then
        self.detailPanel:setVisible(true)
    end

    self:refreshUI()
end

function AuctionHouseUI:onClose()
    AuctionHouseUI:superClass().onClose(self)
end

function AuctionHouseUI:refreshUI()
    if self.mod == nil then return end

    local activeAuction = self.mod:getActiveAuction()

    if self.noAuctionText then
        self.noAuctionText:setVisible(activeAuction == nil)
    end
    if self.detailPanel then
        self.detailPanel:setVisible(activeAuction ~= nil)
    end

    if activeAuction then
        self.selectedAuction = activeAuction
        self:updateDetailPanel(activeAuction)
    end
end

function AuctionHouseUI:updateDetailPanel(auction)
    if auction == nil then return end

    if self.itemTitle then
        self.itemTitle:setText(auction.itemName or "")
    end
    if self.itemSeller then
        self.itemSeller:setText(auction.seller or "")
    end
    if self.itemStarting then
        self.itemStarting:setText("$" .. tostring(auction.startingBid or 0))
    end
    if self.itemCurrent then
        self.itemCurrent:setText("$" .. tostring(auction.currentBid or 0))
    end
    if self.itemBidder then
        local bidder = auction.highestBidder or "Nenhum"
        self.itemBidder:setText(bidder)
    end
    if self.bidInput then
        self.bidInput:setText(tostring((auction.currentBid or 0) + 1000))
    end
end

function AuctionHouseUI:updateTimer()
    if self.selectedAuction == nil or self.selectedAuction.status ~= "ACTIVE" then return end
    if self.itemTimeLeft == nil or self.mod == nil then return end

    local remainingMs = self.selectedAuction.endTime - self.mod.mission.missionInfo.time
    if remainingMs > 0 then
        local totalSecs = math.floor(remainingMs / 1000)
        local mins = math.floor(totalSecs / 60)
        local secs = totalSecs % 60
        self.itemTimeLeft:setText(string.format("%02d:%02d", mins, secs))
    else
        self.itemTimeLeft:setText("00:00")
    end
end

function AuctionHouseUI:loadPlayerVehicles()
    self.availableVehicles = {}

    if self.mod == nil or self.mod.mission == nil or self.mod.mission.player == nil then return end

    local playerName = self.mod.mission.player:getName() or ""
    local farmId = self.mod.mission.playerManager:getPlayerFarmId(playerName)
    if farmId == nil or farmId == 0 then return end

    for _, v in pairs(self.mod.mission.vehicles) do
        if v.configFileName ~= nil and v.ownerFarmId == farmId then
            if not self.mod:isVehicleInAuction(v) then
                table.insert(self.availableVehicles, {
                    id = v.id,
                    name = v:getName()
                })
            end
        end
    end

    if self.vehicleList then
        local names = {}
        for _, veh in ipairs(self.availableVehicles) do
            table.insert(names, veh.name)
        end
        if #names > 0 then
            self.vehicleList:setTexts(names)
        end
    end
end

-- Button handlers

function AuctionHouseUI:onBidClick()
    if self.selectedAuction == nil or self.bidInput == nil or self.mod == nil then return end

    local bidVal = tonumber(self.bidInput:getText())
    if bidVal == nil then return end

    local playerName = ""
    if self.mod.mission and self.mod.mission.player then
        playerName = self.mod.mission.player:getName() or ""
    end

    self.mod:requestPlaceBid(playerName, bidVal)
    self:onBackClick()
end

function AuctionHouseUI:onCreateClick()
    if self.detailPanel then
        self.detailPanel:setVisible(false)
    end
    if self.createPanel then
        self.createPanel:setVisible(true)
        self:loadPlayerVehicles()
    end
end

function AuctionHouseUI:onConfirmCreateClick()
    if self.vehicleList == nil or self.priceInput == nil or self.durationInput == nil or self.mod == nil then return end

    local selectedIdx = self.vehicleList:getSelectedIdx()
    if selectedIdx == nil or selectedIdx < 1 then return end

    local vehicleData = self.availableVehicles[selectedIdx]
    if vehicleData == nil then return end

    local startPrice = tonumber(self.priceInput:getText()) or 5000
    local duration = tonumber(self.durationInput:getText()) or 5

    local playerName = ""
    if self.mod.mission and self.mod.mission.player then
        playerName = self.mod.mission.player:getName() or ""
    end

    self.mod:requestNewAuction(playerName, vehicleData.id, startPrice, duration)
    self:onBackClick()
end

function AuctionHouseUI:onCancelAuctionClick()
    if self.selectedAuction == nil or self.mod == nil then return end

    local playerName = ""
    if self.mod.mission and self.mod.mission.player then
        playerName = self.mod.mission.player:getName() or ""
    end

    self.mod:requestCancelAuction(playerName)
    self:onBackClick()
end

function AuctionHouseUI:onBackClick()
    g_gui:showGui(nil)
end

function AuctionHouseUI:onCreateBackClick()
    if self.createPanel then
        self.createPanel:setVisible(false)
    end
    if self.detailPanel then
        self.detailPanel:setVisible(true)
    end
end

function AuctionHouseUI:update(dt)
    AuctionHouseUI:superClass().update(self, dt)
    self:updateTimer()
end

function AuctionHouseUI:copyAttributes(src)
    AuctionHouseUI:superClass().copyAttributes(self, src)
    self.mod = src.mod
end
