AuctionManager = {}
local AuctionManager_mt = Class(AuctionManager)

AuctionManager.MIN_BID_INCREMENT = 1000
AuctionManager.MIN_DURATION_MINUTES = 1
AuctionManager.MAX_DURATION_MINUTES = 120
AuctionManager.CHAT_SENDER = "Leiloeiro"
AuctionManager.MONEY_TYPE = MoneyType.SHOP_VEHICLE_BUY

function AuctionManager:init()
    AuctionLogger.info("AuctionManager", "Initializing")
    self.auctions = {}
    self.nextId = 1
    self.isLoaded = false
    self.listeners = {}
    AuctionLogger.info("AuctionManager", "Initialized")
end

function AuctionManager:loadFromSavegame()
    AuctionLogger.info("AuctionManager", "Loading from savegame")
    local auctions, nextId = AuctionStorage.load()
    self.auctions = auctions
    self.nextId = nextId
    self.isLoaded = true
    AuctionLogger.info("AuctionManager", "Loaded " .. #self.auctions .. " auctions, nextId=" .. self.nextId)
end

function AuctionManager:saveToSavegame()
    AuctionLogger.info("AuctionManager", "Saving to savegame")
    AuctionStorage.save(self.auctions, self.nextId)
end

function AuctionManager:syncToClients()
    AuctionLogger.info("AuctionManager", "Syncing " .. #self.auctions .. " auctions to clients")
    AuctionEvent.sendSync(self.auctions)
end

function AuctionManager:cleanup()
    AuctionLogger.info("AuctionManager", "cleanup")
    self.auctions = {}
    self.listeners = {}
end

function AuctionManager:getAuctions()
    return self.auctions
end

function AuctionManager:getActiveAuctions()
    local active = {}
    for _, auction in ipairs(self.auctions) do
        if auction.status == "ACTIVE" then
            table.insert(active, auction)
        end
    end
    return active
end

function AuctionManager:getAuctionById(id)
    for _, auction in ipairs(self.auctions) do
        if auction.id == id then
            return auction
        end
    end
    return nil
end

function AuctionManager:isVehicleInAuction(vehicleId)
    for _, auction in ipairs(self.auctions) do
        if auction.status == "ACTIVE" and auction.vehicleId == vehicleId then
            return true
        end
    end
    return false
end

function AuctionManager.getVehicleById(vehicleId)
    if g_currentMission == nil or g_currentMission.vehicleSystem == nil then
        return nil
    end
    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles or {}) do
        if vehicle.id == vehicleId then
            return vehicle
        end
    end
    return nil
end

function AuctionManager:broadcastChat(message)
    if g_currentMission ~= nil then
        g_currentMission:addChatMessage(message, AuctionManager.CHAT_SENDER, 0)
    end
end

-- Server-authoritative: create a new auction for the seller's vehicle
function AuctionManager:createAuction(sellerId, sellerName, vehicleId, startingBid, durationMins)
    if g_server == nil then
        return
    end
    AuctionLogger.info("AuctionManager", "createAuction by=" .. tostring(sellerName) .. " vehicleId=" .. tostring(vehicleId))

    if sellerId == nil or sellerId <= 0 then
        AuctionLogger.warning("AuctionManager", "createAuction: invalid sellerId")
        return
    end

    local vehicle = AuctionManager.getVehicleById(vehicleId)
    if vehicle == nil or vehicle:getOwnerFarmId() ~= sellerId then
        self:broadcastChat(g_i18n:getText("ah_error_noVehicle", AuctionHouse.modName))
        AuctionLogger.warning("AuctionManager", "createAuction: vehicle not found or not owned by seller (vehicle=" .. tostring(vehicle) .. ")")
        return
    end

    if self:isVehicleInAuction(vehicleId) then
        self:broadcastChat(g_i18n:getText("ah_error_vehicleInAuction", AuctionHouse.modName))
        AuctionLogger.warning("AuctionManager", "createAuction: vehicle already in auction")
        return
    end

    startingBid = math.max(1, math.floor(startingBid or 0))
    durationMins = math.floor(durationMins or AuctionManager.MIN_DURATION_MINUTES)
    durationMins = math.max(AuctionManager.MIN_DURATION_MINUTES, math.min(AuctionManager.MAX_DURATION_MINUTES, durationMins))

    local missionTime = g_currentMission.missionInfo.time
    local auction = {
        id = self.nextId,
        vehicleId = vehicleId,
        itemName = vehicle:getName(),
        sellerId = sellerId,
        sellerName = sellerName,
        startingBid = startingBid,
        currentBid = startingBid,
        highestBidderId = 0,
        highestBidderName = "",
        startTime = missionTime,
        endTime = missionTime + (durationMins * 60000),
        status = "ACTIVE",
    }

    self.nextId = self.nextId + 1
    table.insert(self.auctions, auction)
    AuctionLogger.info("AuctionManager", "Auction created id=" .. auction.id .. " item=" .. auction.itemName)

    self:saveToSavegame()
    AuctionEvent.sendSync(self.auctions)
    self:notifyListeners()
    self:broadcastChat(string.format(g_i18n:getText("ah_global_auctionStarted", AuctionHouse.modName), sellerName, auction.itemName, tostring(startingBid)))
end

-- Server-authoritative: place a bid on an active auction
function AuctionManager:placeBid(auctionId, bidderId, bidderName, amount)
    if g_server == nil then
        return
    end
    AuctionLogger.info("AuctionManager", "placeBid auctionId=" .. tostring(auctionId) .. " by=" .. tostring(bidderName) .. " amount=" .. tostring(amount))

    local auction = self:getAuctionById(auctionId)
    if auction == nil or auction.status ~= "ACTIVE" then
        self:broadcastChat(g_i18n:getText("ah_error_noAuction", AuctionHouse.modName))
        return
    end

    if bidderId == auction.sellerId then
        self:broadcastChat(g_i18n:getText("ah_error_selfBid", AuctionHouse.modName))
        return
    end

    amount = math.floor(amount or 0)
    local minRequired = auction.currentBid + AuctionManager.MIN_BID_INCREMENT
    if amount < minRequired then
        self:broadcastChat(g_i18n:getText("ah_error_minBid", AuctionHouse.modName) .. " " .. tostring(minRequired))
        return
    end

    local farm = g_farmManager:getFarmById(bidderId)
    if farm == nil or farm.money < amount then
        self:broadcastChat(g_i18n:getText("ah_error_noFunds", AuctionHouse.modName))
        return
    end

    auction.currentBid = amount
    auction.highestBidderId = bidderId
    auction.highestBidderName = bidderName

    self:saveToSavegame()
    AuctionEvent.sendSync(self.auctions)
    self:notifyListeners()
    self:broadcastChat(string.format(g_i18n:getText("ah_global_newBid", AuctionHouse.modName), bidderName, tostring(amount), auction.itemName))
end

-- Server-authoritative: cancel an auction (seller or system only)
function AuctionManager:cancelAuction(auctionId, requesterId, requesterName)
    if g_server == nil then
        return
    end
    AuctionLogger.info("AuctionManager", "cancelAuction auctionId=" .. tostring(auctionId) .. " by=" .. tostring(requesterName))

    local index, auction = nil, nil
    for i, a in ipairs(self.auctions) do
        if a.id == auctionId then
            index, auction = i, a
            break
        end
    end

    if auction == nil then
        AuctionLogger.warning("AuctionManager", "cancelAuction: auction not found id=" .. tostring(auctionId))
        return
    end

    if auction.sellerId ~= requesterId and requesterId ~= 0 then
        self:broadcastChat(g_i18n:getText("ah_error_notOwner", AuctionHouse.modName))
        return
    end

    table.remove(self.auctions, index)
    self:saveToSavegame()
    AuctionEvent.sendSync(self.auctions)
    self:notifyListeners()
    self:broadcastChat(string.format(g_i18n:getText("ah_global_cancelled", AuctionHouse.modName), auction.itemName))
end

-- Server-authoritative: resolve an expired auction (transfer vehicle + funds)
function AuctionManager:resolveAuction(auction)
    auction.status = "ENDED"
    AuctionLogger.info("AuctionManager", "resolveAuction id=" .. auction.id .. " highestBidderId=" .. tostring(auction.highestBidderId))

    if auction.highestBidderId ~= nil and auction.highestBidderId > 0 then
        local vehicle = AuctionManager.getVehicleById(auction.vehicleId)
        if vehicle ~= nil then
            vehicle:setOwnerFarmId(auction.highestBidderId)

            local buyerFarm = g_farmManager:getFarmById(auction.highestBidderId)
            local sellerFarm = g_farmManager:getFarmById(auction.sellerId)

            if buyerFarm ~= nil then
                buyerFarm:changeBalance(-auction.currentBid, AuctionManager.MONEY_TYPE)
            end
            if sellerFarm ~= nil then
                sellerFarm:changeBalance(auction.currentBid, AuctionManager.MONEY_TYPE)
            end

            self:broadcastChat(string.format(g_i18n:getText("ah_global_ended", AuctionHouse.modName), auction.highestBidderName, auction.itemName, tostring(auction.currentBid)))
        else
            self:broadcastChat(g_i18n:getText("ah_global_vehicleNotFound", AuctionHouse.modName))
        end
    else
        self:broadcastChat(string.format(g_i18n:getText("ah_global_noBids", AuctionHouse.modName), auction.itemName))
    end
end

-- Server-authoritative: check for expired auctions and resolve them
function AuctionManager:update(dt)
    if g_server == nil then
        return
    end
    if g_currentMission == nil or g_currentMission.missionInfo == nil then
        return
    end

    local serverTime = g_currentMission.missionInfo.time
    local hasChanges = false
    local toRemove = {}

    for i, auction in ipairs(self.auctions) do
        if auction.status == "ACTIVE" and serverTime >= auction.endTime then
            self:resolveAuction(auction)
            table.insert(toRemove, i)
            hasChanges = true
        end
    end

    for i = #toRemove, 1, -1 do
        table.remove(self.auctions, toRemove[i])
    end

    if hasChanges then
        self:saveToSavegame()
        AuctionEvent.sendSync(self.auctions)
        self:notifyListeners()
    end
end

function AuctionManager:onReceiveSync(auctions)
    AuctionLogger.info("AuctionManager", "onReceiveSync with " .. #auctions .. " auctions")
    self.auctions = auctions
    self:notifyListeners()
end

function AuctionManager:addListener(callback)
    table.insert(self.listeners, callback)
    AuctionLogger.info("AuctionManager", "Listener added, total=" .. #self.listeners)
end

function AuctionManager:removeListener(callback)
    for i, cb in ipairs(self.listeners) do
        if cb == callback then
            table.remove(self.listeners, i)
            AuctionLogger.info("AuctionManager", "Listener removed, total=" .. #self.listeners)
            return
        end
    end
end

function AuctionManager:notifyListeners()
    AuctionLogger.info("AuctionManager", "Notifying " .. #self.listeners .. " listeners")
    for _, callback in ipairs(self.listeners) do
        callback(self.auctions)
    end
end
