AuctionBotManager = {}

AuctionBotManager.tickTimer = 0
AuctionBotManager.TICK_INTERVAL = 8000 -- Check every 8 seconds

AuctionBotManager.MAX_BOT_AUCTIONS = 3
AuctionBotManager.CREATE_CHANCE = 0.15 -- 15% chance to create a bot auction if under limit

-- Modo desenvolvedor: força duração máxima de 1 minuto para testar rapidamente
-- Em produção, mude para false para usar duração aleatória normal (3-15 min)
AuctionBotManager.DEV_MODE = true

AuctionBotManager._botsPreviouslyEnabled = nil

AuctionBotManager.BOTS = {
    { id = -100, defaultName = "Pedro", profile = "CONSERVATIVE" }, -- Conservador
    { id = -101, defaultName = "Lucas", profile = "COMPETITIVE" }, -- Competitivo
    { id = -102, defaultName = "Carlos", profile = "AGGRESSIVE" }, -- Agressivo
    { id = -103, defaultName = "Mateus", profile = "RANDOM" }, -- Aleatório
    { id = -104, defaultName = "Júlia", profile = "CONSERVATIVE" }, -- Conservador
    { id = -105, defaultName = "Fernanda", profile = "COMPETITIVE" }, -- Competitivo
    { id = -106, defaultName = "Bruno", profile = "AGGRESSIVE" }, -- Agressivo
    { id = -107, defaultName = "Amanda", profile = "RANDOM" }, -- Aleatório
    { id = -108, defaultName = "Anderson", profile = "BRAIN" }, -- CEREBRO
}

function AuctionBotManager.isBotId(id)
    return id ~= nil and id < 0
end

function AuctionBotManager.getBotName(bot)
    if bot == nil then return "" end
    local key = "ah_bot_name_" .. tostring(math.abs(bot.id))
    if g_i18n ~= nil and g_i18n:hasText(key, AuctionHouse.modName) then
        return g_i18n:getText(key, AuctionHouse.modName)
    end
    return bot.defaultName or "Bot"
end

-- Generates a stable maximum price valuation for a given bot-auction pair
function AuctionBotManager.getBotLimit(bot, auction)
    local storePrice = auction.storePrice or auction.currentBid
    local seed = bot.id + auction.id
    math.randomseed(seed)
    
    local multiplier = 1.0
    if bot.profile == "CONSERVATIVE" then
        multiplier = 0.50 + math.random() * 0.20 -- 50% to 70% of store value
    elseif bot.profile == "COMPETITIVE" then
        multiplier = 0.80 + math.random() * 0.25 -- 80% to 105% of store value
    elseif bot.profile == "AGGRESSIVE" then
        multiplier = 0.95 + math.random() * 0.30 -- 95% to 125% of store value
    elseif bot.profile == "RANDOM" then
        multiplier = 0.40 + math.random() * 0.75 -- 40% to 115% of store value
    end
    
    -- Reset seed to avoid affecting game mechanics
    if g_currentMission ~= nil then
        math.randomseed(g_currentMission.time or 1)
    end
    
    return math.floor(storePrice * multiplier)
end

-- Decides whether a bot should place a bid in this tick
function AuctionBotManager.shouldBotBid(bot, auction, serverTime)
    local nextBid = auction.currentBid + AuctionManager.MIN_BID_INCREMENT
    local limit = AuctionBotManager.getBotLimit(bot, auction)
    
    if nextBid > limit then
        return false -- Too expensive for this bot
    end
    
    local timeLeft = auction.endTime - serverTime
    if timeLeft <= 0 then
        return false -- Already expired
    end
    
    local chance = 0.0
    if bot.profile == "CONSERVATIVE" then
        if timeLeft < 30000 then
            return false -- Conservative bots give up early (scared of last second bid wars)
        end
        chance = 0.15
    elseif bot.profile == "COMPETITIVE" then
        chance = 0.25
    elseif bot.profile == "AGGRESSIVE" then
        if timeLeft < 45000 then
            chance = 0.80 -- Aggressive bots love sniping close to the end
        else
            chance = 0.20
        end
    elseif bot.profile == "RANDOM" then
        chance = math.random() * 0.40 -- Unpredictable chance up to 40%
    end
    
    return math.random() < chance
end

-- Determines how much a bot will bid
function AuctionBotManager.calculateBidAmount(bot, auction)
    local minRequired = auction.currentBid + AuctionManager.MIN_BID_INCREMENT
    local limit = AuctionBotManager.getBotLimit(bot, auction)
    
    if minRequired > limit then
        return nil
    end
    
    local extra = 0
    if bot.profile == "COMPETITIVE" then
        if math.random() < 0.20 then
            extra = math.random(1, 3) * 1000
        end
    elseif bot.profile == "AGGRESSIVE" then
        if math.random() < 0.50 then
            extra = math.random(2, 8) * 1000
        end
    elseif bot.profile == "RANDOM" then
        extra = math.random(0, 5) * 1000
    end
    
    local amount = minRequired + extra
    if amount > limit then
        amount = limit
    end
    if amount < minRequired then
        amount = minRequired
    end
    
    return math.floor(amount)
end

-- Fetches a random store item representing a vehicle, implement, or equipment
function AuctionBotManager.getRandomStoreItem()
    if g_storeManager == nil then
        AuctionLogger.warning("AuctionBotManager", "getRandomStoreItem: g_storeManager is nil")
        return nil
    end
    
    local items = nil
    if g_storeManager.getItems ~= nil then
        items = g_storeManager:getItems()
    else
        items = g_storeManager.items
    end
    
    if items == nil then
        AuctionLogger.warning("AuctionBotManager", "getRandomStoreItem: no items found in storeManager")
        return nil
    end

    local validItems = {}
    for _, item in pairs(items) do
        if item.xmlFilename ~= nil and item.price ~= nil and item.price > 1000 and item.name ~= nil then
            if not item.isPlaceable and item.xmlFilename:find("/placeables/") == nil then
                local cat = item.categoryName or ""
                if cat ~= "handtools" and cat ~= "placeables" and cat ~= "wood" and cat ~= "objects" and cat ~= "pallets" and cat ~= "bags" and cat ~= "bigbags" and cat ~= "misc" and cat ~= "decoration" and cat ~= "animals" then
                    table.insert(validItems, item)
                end
            end
        end
    end

    AuctionLogger.info("AuctionBotManager", "getRandomStoreItem: found %d valid items out of %d total", #validItems, #items or 0)

    if #validItems == 0 then
        return nil
    end

    return validItems[math.random(1, #validItems)]
end

-- Autonomously spawns a vehicle in the world for a player who won a bot auction
-- Returns true if spawn was initiated, false if setup failed (no refund handled here)
function AuctionBotManager.spawnVehicleForPlayer(xmlFilename, playerFarmId, itemName)
    local x, y, z = 0, 0, 0
    local ry = 0

    if g_currentMission.shopSpawnPlaces ~= nil and #g_currentMission.shopSpawnPlaces > 0 then
        local spawnPlace = g_currentMission.shopSpawnPlaces[1]
        if spawnPlace.position then
            x, y, z = spawnPlace.position[1], spawnPlace.position[2], spawnPlace.position[3]
        end
        if spawnPlace.rotation then
            ry = spawnPlace.rotation[2]
        end
    else
        for _, player in pairs(g_currentMission.players or {}) do
            if player.farmId == playerFarmId and player.rootNode ~= 0 then
                local px, py, pz = getWorldTranslation(player.rootNode)
                if px then
                    x, y, z = px, py + 1, pz
                    break
                end
            end
        end
    end

    AuctionLogger.info("AuctionBotManager", ">>> INICIANDO SPAWN do veículo '%s' (XML=%s) na posição (%.1f, %.1f, %.1f) para farmId=%d", tostring(itemName), tostring(xmlFilename), x, y, z, playerFarmId)

    -- Validate store item BEFORE creating VehicleLoadingData to avoid silent failure
    local storeItem = nil
    if g_storeManager ~= nil then
        storeItem = AuctionManager.getStoreItemByXMLFilename(xmlFilename)
    end

    local data = VehicleLoadingData.new()

    if storeItem ~= nil then
        AuctionLogger.info("AuctionBotManager", ">>> Store item encontrado para XML='%s': name='%s' storeItem.xmlFilename='%s' (price=%d) — usando setStoreItem", tostring(xmlFilename), tostring(itemName), tostring(storeItem.xmlFilename), storeItem.price or 0)
        if storeItem.xmlFilename ~= xmlFilename then
            AuctionLogger.warning("AuctionBotManager", ">>> ATENÇÃO: storeItem.xmlFilename ('%s') DIFERE do xmlFilename solicitado ('%s')!", tostring(storeItem.xmlFilename), tostring(xmlFilename))
        end
        data:setStoreItem(storeItem)
    else
        AuctionLogger.warning("AuctionBotManager", ">>> Store item NÃO encontrado para XML '%s' — tentando setFilename como fallback", tostring(xmlFilename))
        data:setFilename(xmlFilename)
    end

    if not data.isValid then
        AuctionLogger.error("AuctionBotManager", ">>> FALHA CRÍTICA: VehicleLoadingData inválido (store item não encontrado) para '%s' (XML='%s') — spawn abortado, nenhum callback será disparado!", tostring(itemName), tostring(xmlFilename))
        return false
    end

    data:setPosition(x, y, z)
    data:setRotation(0, ry, 0)
    data:setOwnerFarmId(playerFarmId)
    data:setPropertyState(VehiclePropertyState.OWNED)

    AuctionLogger.info("AuctionBotManager", ">>> VehicleLoadingData configurado — chamando load() assíncrono para '%s' (XML='%s')", tostring(itemName), tostring(xmlFilename))

    data:load(function(callbackTarget, vehicles, loadingState, callbackArgs)
        AuctionLogger.info("AuctionBotManager", ">>> CALLBACK do load() disparou para '%s': loadingState=%s, #vehicles=%d", tostring(itemName), tostring(loadingState), #vehicles)
        if loadingState == VehicleLoadingState.OK then
            if #vehicles == 0 then
                AuctionLogger.error("AuctionBotManager", ">>> FALHA SILENCIOSA: load() retornou OK mas #vehicles=0 para '%s' (XML=%s) — storeItem provalvemente inválido!", tostring(itemName), tostring(xmlFilename))
                return
            end
            for _, vehicle in ipairs(vehicles) do
                local vehicleId = vehicle.id or 0
                local vehicleName = ""
                if vehicle.getName ~= nil then
                    vehicleName = vehicle:getName()
                end
                local configFileName = ""
                if vehicle.configFileName ~= nil then
                    configFileName = vehicle.configFileName
                end
                AuctionLogger.info("AuctionBotManager", ">>> Veículo carregado: name='%s' id=%d configFileName='%s' farmId=%d", vehicleName, vehicleId, configFileName, playerFarmId)
                if configFileName ~= xmlFilename then
                    AuctionLogger.warning("AuctionBotManager", ">>> ATENÇÃO: vehicle.configFileName ('%s') DIFERE do xmlFilename esperado ('%s')!", tostring(configFileName), tostring(xmlFilename))
                end
                vehicle:addToPhysics()
                g_currentMission.vehicleSystem:addVehicle(vehicle)
                AuctionLogger.info("AuctionBotManager", ">>> VEÍCULO ENTREGUE: '%s' (id=%d) spawnado com sucesso para farmId=%d — XML='%s'", vehicleName, vehicleId, playerFarmId, configFileName)
            end
        else
            AuctionLogger.error("AuctionBotManager", ">>> FALHA NO SPAWN do veículo '%s' (XML=%s): loadingState=%s", tostring(itemName), tostring(xmlFilename), tostring(loadingState))
        end
    end, nil, nil)

    return true
end

-- Selects a bot, store item, and generates a new auction
function AuctionBotManager.createRandomBotAuction()
    if g_auctionManager == nil then return end
    
    local item = AuctionBotManager.getRandomStoreItem()
    if item == nil then
        AuctionLogger.warning("AuctionBotManager", "Could not find a valid store item to auction")
        return
    end

    -- Create starting bid at a randomized discount (50% to 85% of retail price)
    local discountFactor = math.random(50, 85) / 100
    local startingBid = math.floor((item.price * discountFactor) / 100) * 100
    
    -- Pick a random bot
    local bot = AuctionBotManager.BOTS[math.random(1, #AuctionBotManager.BOTS)]
    local botName = AuctionBotManager.getBotName(bot)
    
    -- Random duration between 3 to 15 minutes (DEV_MODE: max 1 min)
    local durationMins
    if AuctionBotManager.DEV_MODE then
        durationMins = math.random(1, 1)
    else
        durationMins = math.random(3, 15)
    end

    AuctionLogger.info("AuctionBotManager", "Creating automated auction: bot=%s, item=%s, startingBid=%d, duration=%dmins (DEV_MODE=%s)", botName, item.name, startingBid, durationMins, tostring(AuctionBotManager.DEV_MODE))
    
    -- Call custom creation wrapper in AuctionManager
    g_auctionManager:createBotAuction(bot.id, botName, item.name, item.xmlFilename, startingBid, durationMins, item.price)
end

function AuctionBotManager.checkCreateAuction()
    if g_auctionManager == nil then return end
    
    local activeBotAuctionsCount = 0
    local activeAuctions = g_auctionManager:getActiveAuctions()
    for _, auction in ipairs(activeAuctions) do
        if AuctionBotManager.isBotId(auction.sellerId) then
            activeBotAuctionsCount = activeBotAuctionsCount + 1
        end
    end
    
    AuctionLogger.info("AuctionBotManager", "checkCreateAuction: %d active bot auctions (max %d)", activeBotAuctionsCount, AuctionBotManager.MAX_BOT_AUCTIONS)
    
    if activeBotAuctionsCount < AuctionBotManager.MAX_BOT_AUCTIONS then
        if math.random() < AuctionBotManager.CREATE_CHANCE then
            AuctionBotManager.createRandomBotAuction()
        else
            AuctionLogger.info("AuctionBotManager", "checkCreateAuction: chance roll failed, will retry next tick")
        end
    else
        AuctionLogger.info("AuctionBotManager", "checkCreateAuction: at max bot auctions, skipping creation")
    end
end

function AuctionBotManager.processBids()
    if g_auctionManager == nil or g_currentMission == nil then return end
    
    local activeAuctions = g_auctionManager:getActiveAuctions()
    local serverTime = g_currentMission.time
    
    AuctionLogger.info("AuctionBotManager", "processBids: scanning %d active auctions", #activeAuctions)
    
    for _, auction in ipairs(activeAuctions) do
        local bot = AuctionBotManager.BOTS[math.random(1, #AuctionBotManager.BOTS)]
        
        -- Bots cannot bid on their own auctions or bid if they already hold the highest bid
        if bot.id ~= auction.sellerId and bot.id ~= auction.highestBidderId then
            if AuctionBotManager.shouldBotBid(bot, auction, serverTime) then
                local bidAmount = AuctionBotManager.calculateBidAmount(bot, auction)
                if bidAmount ~= nil then
                    local botName = AuctionBotManager.getBotName(bot)
                    AuctionLogger.info("AuctionBotManager", "Bot %s is placing a bid of %d on auction %d (%s)", botName, bidAmount, auction.id, auction.itemName)
                    g_auctionManager:placeBid(auction.id, bot.id, botName, bidAmount)
                end
            end
        end
    end
end

function AuctionBotManager.update(dt)
    if not g_server then
        return
    end
    if g_currentMission == nil then
        return
    end
    
    local botsEnabled = true
    if g_currentMission.auctionSettings ~= nil then
        botsEnabled = g_currentMission.auctionSettings.auctionHouseBotsEnabled ~= false
    end
    if AuctionBotManager._botsPreviouslyEnabled == nil then
        AuctionBotManager._botsPreviouslyEnabled = botsEnabled
    end
    if not botsEnabled then
        if AuctionBotManager._botsPreviouslyEnabled then
            AuctionLogger.info("AuctionBotManager", "Bots desativados — limpando leilões de bots")
            if g_auctionManager ~= nil then
                g_auctionManager:cancelBotAuctions()
            end
            AuctionBotManager._botsPreviouslyEnabled = false
        end
        return
    end
    AuctionBotManager._botsPreviouslyEnabled = true
    AuctionBotManager.tickTimer = AuctionBotManager.tickTimer + dt
    if AuctionBotManager.tickTimer >= AuctionBotManager.TICK_INTERVAL then
        AuctionLogger.info("AuctionBotManager", "=== Bot tick fired (timer=%d >= interval=%d) ===", AuctionBotManager.tickTimer, AuctionBotManager.TICK_INTERVAL)
        AuctionBotManager.tickTimer = 0
        
        -- Run bot routines on safe try/catch
        pcall(AuctionBotManager.checkCreateAuction)
        pcall(AuctionBotManager.processBids)
    end
end
