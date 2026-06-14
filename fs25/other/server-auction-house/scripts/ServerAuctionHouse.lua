-- Server Auction House - Main Mod Script
-- FS25 rewrite using proper API patterns

ServerAuctionHouse = {}
ServerAuctionHouse.MOD_NAME = g_currentModName
ServerAuctionHouse.MOD_DIR = g_currentModDirectory

source(ServerAuctionHouse.MOD_DIR .. "scripts/events/NewAuctionEvent.lua")
source(ServerAuctionHouse.MOD_DIR .. "scripts/events/PlaceBidEvent.lua")
source(ServerAuctionHouse.MOD_DIR .. "scripts/events/SyncAuctionsEvent.lua")
source(ServerAuctionHouse.MOD_DIR .. "scripts/ui/AuctionHouseUI.lua")

function ServerAuctionHouse:new(mission, i18n, gui)
    local self = {}
    setmetatable(self, {__index = ServerAuctionHouse})
    self.mission = mission
    self.i18n = i18n
    self.gui = gui
    self.auctions = {}
    self.ui = nil
    return self
end

function ServerAuctionHouse.load()
    log("[AuctionHouse] Loading Server Auction House Mod...")
    g_serverAuctionHouse = ServerAuctionHouse:new(g_currentMission, g_i18n, g_gui)
end

function ServerAuctionHouse.loadMapFinished()
    local self = g_serverAuctionHouse
    if self == nil then return end

    log("[AuctionHouse] Map loaded. Initializing UI...")

    self.ui = AuctionHouseUI:new(self)
    g_gui:loadGui(ServerAuctionHouse.MOD_DIR .. "gui/AuctionHouseUI.xml", "AuctionHouseUI", self.ui, false)

    self:loadFromSavegame()

    log("[AuctionHouse] Initialization complete. Press L to open.")
end

function ServerAuctionHouse.update(dt)
    local self = g_serverAuctionHouse
    if self == nil then return end

    if g_server ~= nil then
        local serverTime = self.mission.missionInfo.time
        local hasChanges = false

        for id, auction in pairs(self.auctions) do
            if auction.status == "ACTIVE" and serverTime >= auction.endTime then
                self:resolveAuction(id)
                hasChanges = true
            end
        end

        if hasChanges then
            g_server:broadcastEvent(SyncAuctionsEvent:new(self.auctions))
        end
    end
end

function ServerAuctionHouse:onChatMessageReceived(text, senderPlayerId, senderNickname)
    if text:sub(1, 1) ~= "/" then return end

    local parts = {}
    for part in text:gmatch("%S+") do
        table.insert(parts, part)
    end

    local command = parts[1]:lower()
    if command == "/auction" then
        local sub = parts[2] and parts[2]:lower() or ""
        if sub == "start" then
            local vehicleId = parts[3]
            local startPrice = tonumber(parts[4]) or 10000
            local durationMins = tonumber(parts[5]) or 5
            self:requestNewAuction(senderNickname, vehicleId, startPrice, durationMins)
        elseif sub == "cancel" then
            self:requestCancelAuction(senderNickname)
        end
    elseif command == "/bid" then
        local amount = tonumber(parts[2])
        if amount ~= nil then
            self:requestPlaceBid(senderNickname, amount)
        end
    end
end

function ServerAuctionHouse:onOpenUI()
    g_gui:showGui("AuctionHouseUI")
    if self.ui then
        self.ui:refreshUI()
    end
end

function ServerAuctionHouse:requestNewAuction(player, vehicleId, startPrice, durationMins)
    if g_server == nil then
        g_client:getServerConnection():sendEvent(NewAuctionEvent:new(player, vehicleId, startPrice, durationMins))
    else
        self:createAuctionServer(player, vehicleId, startPrice, durationMins)
    end
end

function ServerAuctionHouse:requestPlaceBid(player, amount)
    if g_server == nil then
        g_client:getServerConnection():sendEvent(PlaceBidEvent:new(player, amount))
    else
        self:placeBidServer(player, amount)
    end
end

function ServerAuctionHouse:requestCancelAuction(player)
    if g_server ~= nil then
        self:cancelAuctionServer(player)
    end
end

function ServerAuctionHouse:createAuctionServer(player, vehicleId, startPrice, durationMins)
    local farmId = self.mission.playerManager:getPlayerFarmId(player)
    if farmId == nil or farmId == 0 then return end

    local auctionId = "AUC_" .. tostring(math.floor(self.mission.missionInfo.time))

    local vehicleName = "Equipment"
    local foundVehicle = nil
    for _, v in pairs(self.mission.vehicles) do
        if v.configFileName ~= nil and v.ownerFarmId == farmId then
            if not self:isVehicleInAuction(v) then
                foundVehicle = v
                vehicleName = v:getName()
                break
            end
        end
    end

    if foundVehicle == nil then
        self:sendServerChatMessage(player, "Erro: Nenhum veiculo disponivel ou de sua propriedade para leiloar.")
        return
    end

    local newAuction = {
        id = auctionId,
        itemName = vehicleName,
        vehicleId = foundVehicle.id,
        seller = player,
        farmId = farmId,
        startingBid = startPrice,
        currentBid = startPrice,
        highestBidder = nil,
        duration = durationMins * 60 * 1000,
        startTime = self.mission.missionInfo.time,
        endTime = self.mission.missionInfo.time + (durationMins * 60 * 1000),
        status = "ACTIVE"
    }

    self.auctions[auctionId] = newAuction

    g_server:broadcastEvent(SyncAuctionsEvent:new(self.auctions))
    self:sendGlobalChatMessage("[Auction] " .. player .. " iniciou leilao de " .. vehicleName .. " por $" .. tostring(startPrice))
end

function ServerAuctionHouse:placeBidServer(bidder, amount)
    local activeAuction = self:getActiveAuction()
    if activeAuction == nil then
        self:sendServerChatMessage(bidder, "Erro: Nenhum leilao ativo no momento.")
        return
    end

    if bidder == activeAuction.seller then
        self:sendServerChatMessage(bidder, "Erro: Voce nao pode dar lances no seu proprio leilao.")
        return
    end

    local minRequired = activeAuction.currentBid + 1000
    if amount < minRequired then
        self:sendServerChatMessage(bidder, "Erro: O lance minimo deve ser $" .. tostring(minRequired))
        return
    end

    local farmId = self.mission.playerManager:getPlayerFarmId(bidder)
    local farm = self.mission.farmManager:getFarmById(farmId)
    if farm == nil or farm.money < amount then
        self:sendServerChatMessage(bidder, "Erro: Fundos insuficientes na conta da fazenda.")
        return
    end

    activeAuction.currentBid = amount
    activeAuction.highestBidder = bidder

    g_server:broadcastEvent(SyncAuctionsEvent:new(self.auctions))
    self:sendGlobalChatMessage("[Leilao] Novo maior lance de " .. bidder .. " de $" .. tostring(amount) .. " em " .. activeAuction.itemName)
end

function ServerAuctionHouse:resolveAuction(auctionId)
    local auction = self.auctions[auctionId]
    if auction == nil then return end

    auction.status = "ENDED"

    if auction.highestBidder ~= nil then
        local buyerFarmId = self.mission.playerManager:getPlayerFarmId(auction.highestBidder)
        local sellerFarmId = auction.farmId

        local vehicle = self:getVehicleById(auction.vehicleId)
        if vehicle ~= nil then
            vehicle:setOwnerFarmId(buyerFarmId)

            local buyerFarm = self.mission.farmManager:getFarmById(buyerFarmId)
            local sellerFarm = self.mission.farmManager:getFarmById(sellerFarmId)

            if buyerFarm ~= nil and sellerFarm ~= nil then
                buyerFarm:changeBalance(-auction.currentBid, "vehicle_purchase")
                sellerFarm:changeBalance(auction.currentBid, "vehicle_sale")
            end

            self:sendGlobalChatMessage("[Leilao] Leilao encerrado! " .. auction.highestBidder .. " arrematou " .. auction.itemName .. " por $" .. tostring(auction.currentBid))
        else
            self:sendGlobalChatMessage("[Leilao] Erro: Veiculo nao localizado. Venda cancelada.")
        end
    else
        self:sendGlobalChatMessage("[Leilao] Leilao de " .. auction.itemName .. " encerrado sem ofertas.")
    end

    self.auctions[auctionId] = nil
end

function ServerAuctionHouse:cancelAuctionServer(player)
    local activeAuction = self:getActiveAuction()
    if activeAuction == nil then return end

    if activeAuction.seller == player or player == "System" then
        self.auctions[activeAuction.id] = nil
        g_server:broadcastEvent(SyncAuctionsEvent:new(self.auctions))
        self:sendGlobalChatMessage("[Leilao] Leilao de " .. activeAuction.itemName .. " foi cancelado pelo vendedor.")
    end
end

function ServerAuctionHouse:getActiveAuction()
    for _, auction in pairs(self.auctions) do
        if auction.status == "ACTIVE" then
            return auction
        end
    end
    return nil
end

function ServerAuctionHouse:isVehicleInAuction(vehicle)
    for _, auction in pairs(self.auctions) do
        if auction.vehicleId == vehicle.id then
            return true
        end
    end
    return false
end

function ServerAuctionHouse:getVehicleById(id)
    for _, v in pairs(self.mission.vehicles) do
        if v.id == id then
            return v
        end
    end
    return nil
end

function ServerAuctionHouse:sendServerChatMessage(player, message)
    g_currentMission:addChatMessage(message, "System", 0)
end

function ServerAuctionHouse:sendGlobalChatMessage(message)
    g_currentMission:addChatMessage(message, "Leiloeiro", 0)
end

function ServerAuctionHouse.onSaveSavegame()
    local self = g_serverAuctionHouse
    if self == nil or g_server == nil then return end

    local xmlPath = self.mission.missionInfo.savegameDirectory .. "/server_auctions.xml"
    local xmlFile = createXMLFile("auctionsXML", xmlPath, "auctions")

    local idx = 0
    for id, a in pairs(self.auctions) do
        local key = string.format("auctions.auction(%d)", idx)
        setXMLString(xmlFile, key .. "#id", a.id)
        setXMLString(xmlFile, key .. "#itemName", a.itemName)
        setXMLInt(xmlFile, key .. "#vehicleId", a.vehicleId)
        setXMLString(xmlFile, key .. "#seller", a.seller)
        setXMLInt(xmlFile, key .. "#farmId", a.farmId)
        setXMLInt(xmlFile, key .. "#startingBid", a.startingBid)
        setXMLInt(xmlFile, key .. "#currentBid", a.currentBid)
        if a.highestBidder ~= nil then
            setXMLString(xmlFile, key .. "#highestBidder", a.highestBidder)
        end
        setXMLFloat(xmlFile, key .. "#duration", a.duration)
        setXMLFloat(xmlFile, key .. "#startTime", a.startTime)
        setXMLFloat(xmlFile, key .. "#endTime", a.endTime)
        setXMLString(xmlFile, key .. "#status", a.status)
        idx = idx + 1
    end

    saveXMLFile(xmlFile)
    delete(xmlFile)
end

function ServerAuctionHouse:loadFromSavegame()
    if g_server == nil then return end

    local xmlPath = self.mission.missionInfo.savegameDirectory .. "/server_auctions.xml"
    if not fileExists(xmlPath) then return end

    local xmlFile = loadXMLFile("auctionsXML", xmlPath)
    local idx = 0
    while true do
        local key = string.format("auctions.auction(%d)", idx)
        if not hasXMLProperty(xmlFile, key) then break end

        local id = getXMLString(xmlFile, key .. "#id")
        local auction = {
            id = id,
            itemName = getXMLString(xmlFile, key .. "#itemName"),
            vehicleId = getXMLInt(xmlFile, key .. "#vehicleId"),
            seller = getXMLString(xmlFile, key .. "#seller"),
            farmId = getXMLInt(xmlFile, key .. "#farmId"),
            startingBid = getXMLInt(xmlFile, key .. "#startingBid"),
            currentBid = getXMLInt(xmlFile, key .. "#currentBid"),
            highestBidder = getXMLString(xmlFile, key .. "#highestBidder"),
            duration = getXMLFloat(xmlFile, key .. "#duration"),
            startTime = getXMLFloat(xmlFile, key .. "#startTime"),
            endTime = getXMLFloat(xmlFile, key .. "#endTime"),
            status = getXMLString(xmlFile, key .. "#status")
        }

        self.auctions[id] = auction
        idx = idx + 1
    end

    delete(xmlFile)
end

-- Key event hook to open auction UI with L key
FSBaseMission.keyEvent = Utils.appendedFunction(FSBaseMission.keyEvent, function(self, key, isDown, symbol, repeated)
    if isDown and not repeated and key == Input.KEY_l then
        if g_serverAuctionHouse then
            g_serverAuctionHouse:onOpenUI()
        end
    end
end)

Mission00.load = Utils.prependedFunction(Mission00.load, ServerAuctionHouse.load)
Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, ServerAuctionHouse.loadMapFinished)
Mission00.update = Utils.appendedFunction(Mission00.update, ServerAuctionHouse.update)
FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, ServerAuctionHouse.onSaveSavegame)
