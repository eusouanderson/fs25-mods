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

    local storePrice = startingBid
    if vehicle ~= nil and vehicle.configFileName ~= nil and g_storeManager ~= nil then
        local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
        if storeItem ~= nil and storeItem.price ~= nil then
            storePrice = storeItem.price
        end
    end

    local missionTime = g_currentMission.time
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
        storePrice = storePrice,
    }

    self.nextId = self.nextId + 1
    table.insert(self.auctions, auction)
    AuctionLogger.info("AuctionManager", "Auction created id=" .. auction.id .. " item=" .. auction.itemName)

    self:saveToSavegame()
    AuctionEvent.sendSync(self.auctions)
    self:notifyListeners()
    self:broadcastChat(string.format(g_i18n:getText("ah_global_auctionStarted", AuctionHouse.modName), sellerName, auction.itemName, tostring(startingBid)))
end

-- Server-authoritative: create a bot/virtual auction (bypass physical vehicle checks)
function AuctionManager:createBotAuction(sellerId, sellerName, itemName, xmlFilename, startingBid, durationMins, storePrice)
    if g_server == nil then
        return
    end
    AuctionLogger.info("AuctionManager", "createBotAuction by=" .. tostring(sellerName) .. " item=" .. tostring(itemName))

    startingBid = math.max(1, math.floor(startingBid or 0))
    durationMins = math.floor(durationMins or AuctionManager.MIN_DURATION_MINUTES)
    durationMins = math.max(AuctionManager.MIN_DURATION_MINUTES, math.min(AuctionManager.MAX_DURATION_MINUTES, durationMins))

    local missionTime = g_currentMission.time
    local auction = {
        id = self.nextId,
        vehicleId = 0,
        xmlFilename = xmlFilename,
        itemName = itemName,
        sellerId = sellerId,
        sellerName = sellerName,
        startingBid = startingBid,
        currentBid = startingBid,
        highestBidderId = 0,
        highestBidderName = "",
        startTime = missionTime,
        endTime = missionTime + (durationMins * 60000),
        status = "ACTIVE",
        storePrice = storePrice or startingBid,
    }

    self.nextId = self.nextId + 1
    table.insert(self.auctions, auction)
    AuctionLogger.info("AuctionManager", "Bot Auction created id=" .. auction.id .. " item=" .. auction.itemName)

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
    if not AuctionBotManager.isBotId(bidderId) and (farm == nil or farm.money < amount) then
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

-- Server-authoritative: cancel an auction (seller only)
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

    if auction.sellerId ~= requesterId then
        self:broadcastChat(g_i18n:getText("ah_error_notOwner", AuctionHouse.modName))
        AuctionLogger.warning("AuctionManager", "cancelAuction: requester " .. tostring(requesterId) .. " is not the seller (" .. tostring(auction.sellerId) .. ")")
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
    AuctionLogger.info("AuctionManager", "=== LEILÃO ENCERRADO id=%d item='%s' winner=%s(value=%d) seller=%s ===", auction.id, auction.itemName, auction.highestBidderName, auction.currentBid, auction.sellerName)

    local buyerIsBot = AuctionBotManager.isBotId(auction.highestBidderId)
    local sellerIsBot = AuctionBotManager.isBotId(auction.sellerId)
    local hasBid = auction.highestBidderId ~= nil and auction.highestBidderId ~= 0

    if hasBid then
        if buyerIsBot and not sellerIsBot then
            AuctionLogger.info("AuctionManager", ">>> [Bot-credita-Jogador] Bot '%s' venceu leilão do jogador '%s' pelo item '%s' (valor=%d)", auction.highestBidderName, auction.sellerName, auction.itemName, auction.currentBid)
            -- Bot wins player auction: remove vehicle from world, pay seller
            local vehicle = AuctionManager.getVehicleById(auction.vehicleId)
            if vehicle ~= nil then
                if vehicle.getAttachedImplements ~= nil then
                    local implements = vehicle:getAttachedImplements()
                    local numImplements = implements ~= nil and #implements or 0
                    if numImplements > 0 then
                        AuctionLogger.info("AuctionManager", ">>> Desacoplando %d implements do veículo %d antes de deletar", numImplements, auction.vehicleId)
                        for i = numImplements, 1, -1 do
                            vehicle:detachImplement(1)
                        end
                    end
                end

                AuctionLogger.info("AuctionManager", ">>> DELETANDO veículo %d ('%s') do mundo (transferido para bot %s)", auction.vehicleId, auction.itemName, auction.highestBidderName)
                vehicle:delete()

                local sellerFarm = g_farmManager:getFarmById(auction.sellerId)
                if sellerFarm ~= nil then
                    sellerFarm:changeBalance(auction.currentBid, AuctionManager.MONEY_TYPE)
                    AuctionLogger.info("AuctionManager", ">>> CREDITANDO jogador farmId=%d em %d (venda do item '%s')", auction.sellerId, auction.currentBid, auction.itemName)
                else
                    AuctionLogger.warning("AuctionManager", ">>> ERRO: sellerFarm not found para farmId=%d", auction.sellerId)
                end
            else
                AuctionLogger.warning("AuctionManager", ">>> ERRO: veículo %d não encontrado no mundo para deletar (já foi removido?)", auction.vehicleId)
            end
            self:broadcastChat(string.format(g_i18n:getText("ah_global_ended", AuctionHouse.modName), auction.highestBidderName, auction.itemName, tostring(auction.currentBid)))

        elseif not buyerIsBot and sellerIsBot then
            AuctionLogger.info("AuctionManager", ">>> [Jogador-ganha-Bot] Jogador '%s' venceu leilão do bot '%s' pelo item '%s' (valor=%d)", auction.highestBidderName, auction.sellerName, auction.itemName, auction.currentBid)
            -- Player wins bot auction: spawn vehicle for player, charge them
            local playerFarmId = auction.highestBidderId
            local playerFarm = g_farmManager:getFarmById(playerFarmId)

            if playerFarm ~= nil then
                playerFarm:changeBalance(-auction.currentBid, AuctionManager.MONEY_TYPE)
                AuctionLogger.info("AuctionManager", ">>> DEBITANDO jogador farmId=%d em %d (compra do item '%s')", playerFarmId, auction.currentBid, auction.itemName)

                if auction.xmlFilename then
                    AuctionLogger.info("AuctionManager", ">>> SPAWNANDO veículo '%s' (XML=%s) para farmId=%d — itemName do leilão='%s'", auction.itemName, auction.xmlFilename, playerFarmId, auction.itemName)
                    AuctionLogger.info("AuctionManager", ">>> CHAMADA: spawnVehicleForPlayer(xmlFilename='%s', farmId=%d, itemName='%s')", auction.xmlFilename, playerFarmId, auction.itemName)
                    local spawnOk = AuctionBotManager.spawnVehicleForPlayer(auction.xmlFilename, playerFarmId, auction.itemName)
                    if not spawnOk then
                        AuctionLogger.error("AuctionManager", ">>> REEMBOLSANDO jogador farmId=%d em %d (spawn falhou para '%s')", playerFarmId, auction.currentBid, auction.itemName)
                        playerFarm:changeBalance(auction.currentBid, AuctionManager.MONEY_TYPE)
                        self:broadcastChat(string.format(g_i18n:getText("ah_global_ended", AuctionHouse.modName), auction.highestBidderName, auction.itemName, tostring(auction.currentBid)) .. " (Delivery failed, refunded)")
                    else
                        self:broadcastChat(string.format(g_i18n:getText("ah_global_ended", AuctionHouse.modName), auction.highestBidderName, auction.itemName, tostring(auction.currentBid)))
                    end
                else
                    AuctionLogger.error("AuctionManager", ">>> ERRO CRÍTICO: jogador venceu leilão de bot mas xmlFilename está nil para item '%s' — dinheiro foi debitado mas veículo não será entregue!", auction.itemName)
                    AuctionLogger.info("AuctionManager", ">>> REEMBOLSANDO jogador farmId=%d em %d (xmlFilename=nil)", playerFarmId, auction.currentBid)
                    playerFarm:changeBalance(auction.currentBid, AuctionManager.MONEY_TYPE)
                    self:broadcastChat(string.format(g_i18n:getText("ah_global_ended", AuctionHouse.modName), auction.highestBidderName, auction.itemName, tostring(auction.currentBid)) .. " (Delivery failed: Missing XML, refunded)")
                end
            else
                AuctionLogger.error("AuctionManager", ">>> ERRO CRÍTICO: playerFarm not found para farmId=%d no leilão %d", playerFarmId, auction.id)
                self:broadcastChat(string.format(g_i18n:getText("ah_global_ended", AuctionHouse.modName), auction.highestBidderName, auction.itemName, tostring(auction.currentBid)) .. " (Farm not found)")
            end

        elseif buyerIsBot and sellerIsBot then
            AuctionLogger.info("AuctionManager", ">>> [Bot-para-Bot] Bot '%s' venceu leilão do bot '%s' pelo item '%s' (valor=%d) — transferência virtual, sem ação necessária", auction.highestBidderName, auction.sellerName, auction.itemName, auction.currentBid)
            self:broadcastChat(string.format(g_i18n:getText("ah_global_ended", AuctionHouse.modName), auction.highestBidderName, auction.itemName, tostring(auction.currentBid)))

        else
            AuctionLogger.info("AuctionManager", ">>> [Jogador-para-Jogador] Jogador '%s' venceu leilão do jogador '%s' pelo item '%s' (valor=%d)", auction.highestBidderName, auction.sellerName, auction.itemName, auction.currentBid)
            -- Player-to-player standard transfer
            local vehicle = AuctionManager.getVehicleById(auction.vehicleId)
            if vehicle ~= nil then
                AuctionLogger.info("AuctionManager", ">>> Veículo %d ('%s') encontrado no mundo — iniciando transferência", auction.vehicleId, auction.itemName)
                -- Detach implements before transfer to avoid permission issues
                if vehicle.getAttachedImplements ~= nil then
                    local implements = vehicle:getAttachedImplements()
                    local numImplements = implements ~= nil and #implements or 0
                    if numImplements > 0 then
                        AuctionLogger.info("AuctionManager", ">>> Desacoplando %d implements do veículo %d antes da transferência", numImplements, auction.vehicleId)
                        for i = numImplements, 1, -1 do
                            vehicle:detachImplement(1)
                        end
                    end
                end

                AuctionLogger.info("AuctionManager", ">>> Transferindo propriedade do veículo %d ('%s'): farmId=%d -> farmId=%d", auction.vehicleId, auction.itemName, auction.sellerId, auction.highestBidderId)
                vehicle:setOwnerFarmId(auction.highestBidderId, true)

                local buyerFarm = g_farmManager:getFarmById(auction.highestBidderId)
                local sellerFarm = g_farmManager:getFarmById(auction.sellerId)

                if buyerFarm ~= nil then
                    buyerFarm:changeBalance(-auction.currentBid, AuctionManager.MONEY_TYPE)
                    AuctionLogger.info("AuctionManager", ">>> DEBITANDO comprador farmId=%d em %d", auction.highestBidderId, auction.currentBid)
                else
                    AuctionLogger.warning("AuctionManager", ">>> ERRO: buyerFarm not found para farmId=%d", auction.highestBidderId)
                end
                if sellerFarm ~= nil then
                    sellerFarm:changeBalance(auction.currentBid, AuctionManager.MONEY_TYPE)
                    AuctionLogger.info("AuctionManager", ">>> CREDITANDO vendedor farmId=%d em %d", auction.sellerId, auction.currentBid)
                else
                    AuctionLogger.warning("AuctionManager", ">>> ERRO: sellerFarm not found para farmId=%d", auction.sellerId)
                end

                if g_server ~= nil then
                    AuctionLogger.info("AuctionManager", ">>> Broadcast do AuctionVehicleTransferEvent para todos os clients")
                    g_server:broadcastEvent(AuctionVehicleTransferEvent.new(vehicle, auction.sellerId, auction.highestBidderId))
                end

                self:broadcastChat(string.format(g_i18n:getText("ah_global_ended", AuctionHouse.modName), auction.highestBidderName, auction.itemName, tostring(auction.currentBid)))
            else
                AuctionLogger.warning("AuctionManager", ">>> ERRO: veículo %d não encontrado no mundo — transferência impossível", auction.vehicleId)
                self:broadcastChat(g_i18n:getText("ah_global_vehicleNotFound", AuctionHouse.modName))
            end
        end
    else
        AuctionLogger.info("AuctionManager", ">>> Leilão %d ('%s') encerrou SEM LANCES — ninguém comprou", auction.id, auction.itemName)
        self:broadcastChat(string.format(g_i18n:getText("ah_global_noBids", AuctionHouse.modName), auction.itemName))
    end
end

-- Server-authoritative: check for expired auctions and resolve them
function AuctionManager:update(dt)
    if g_server == nil then
        return
    end
    if g_currentMission == nil then
        return
    end

    local serverTime = g_currentMission.time
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
