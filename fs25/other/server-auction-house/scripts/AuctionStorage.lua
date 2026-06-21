AuctionStorage = {}

local SAVE_FILE = "server_auctions.xml"
local SAVE_KEY = "auctions"

function AuctionStorage.getSavegamePath()
    local saveDir = ""
    if g_currentMission ~= nil and g_currentMission.missionInfo ~= nil then
        saveDir = g_currentMission.missionInfo.savegameDirectory or ""
    end
    if saveDir == "" then
        saveDir = getUserProfileAppPath() .. "savegame" .. tostring(g_currentMission ~= nil and g_currentMission.missionInfo.savegameIndex or 1)
    end
    local path = saveDir .. "/" .. SAVE_FILE
    AuctionLogger.info("AuctionStorage", "Savegame path: " .. path)
    return path
end

function AuctionStorage.load()
    AuctionLogger.info("AuctionStorage", "Loading auctions from savegame")
    local auctions = {}
    local nextId = 1
    local path = AuctionStorage.getSavegamePath()

    local xmlFile = loadXMLFile(SAVE_FILE, path)
    if xmlFile == 0 then
        AuctionLogger.info("AuctionStorage", "No save file found at " .. path)
        return auctions, nextId
    end

    nextId = math.max(1, getXMLInt(xmlFile, SAVE_KEY .. "#nextId") or 1)
    AuctionLogger.info("AuctionStorage", "nextId = " .. nextId)

    local i = 0
    while true do
        local key = string.format("%s.auction(%d)", SAVE_KEY, i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end
        local auction = {
            id                 = getXMLInt(xmlFile, key .. "#id"),
            vehicleId          = getXMLInt(xmlFile, key .. "#vehicleId") or 0,
            xmlFilename        = getXMLString(xmlFile, key .. "#xmlFilename"),
            itemName           = getXMLString(xmlFile, key .. "#itemName") or "",
            sellerId           = getXMLInt(xmlFile, key .. "#sellerId") or 0,
            sellerName         = getXMLString(xmlFile, key .. "#sellerName") or "",
            startingBid        = getXMLInt(xmlFile, key .. "#startingBid") or 0,
            currentBid         = getXMLInt(xmlFile, key .. "#currentBid") or 0,
            highestBidderId    = getXMLInt(xmlFile, key .. "#highestBidderId") or 0,
            highestBidderName  = getXMLString(xmlFile, key .. "#highestBidderName") or "",
            startTime          = getXMLFloat(xmlFile, key .. "#startTime") or 0,
            endTime            = getXMLFloat(xmlFile, key .. "#endTime") or 0,
            status             = getXMLString(xmlFile, key .. "#status") or "ACTIVE",
            storePrice         = getXMLInt(xmlFile, key .. "#storePrice") or 0,
        }
        table.insert(auctions, auction)
        i = i + 1
    end

    delete(xmlFile)
    AuctionLogger.info("AuctionStorage", "Loaded " .. #auctions .. " auctions from savegame")
    return auctions, nextId
end

function AuctionStorage.save(auctions, nextId)
    AuctionLogger.info("AuctionStorage", "Saving " .. #auctions .. " auctions to savegame (nextId=" .. nextId .. ")")
    local path = AuctionStorage.getSavegamePath()
    local xmlFile = createXMLFile(SAVE_FILE, path, SAVE_KEY)
    if xmlFile == 0 then
        AuctionLogger.error("AuctionStorage", "Failed to create save file at " .. path)
        return
    end

    setXMLInt(xmlFile, SAVE_KEY .. "#nextId", nextId)

    for i, auction in ipairs(auctions) do
        local key = string.format("%s.auction(%d)", SAVE_KEY, i - 1)
        setXMLInt(xmlFile, key .. "#id", auction.id)
        setXMLInt(xmlFile, key .. "#vehicleId", auction.vehicleId or 0)
        if auction.xmlFilename then
            setXMLString(xmlFile, key .. "#xmlFilename", auction.xmlFilename)
        end
        setXMLString(xmlFile, key .. "#itemName", auction.itemName or "")
        setXMLInt(xmlFile, key .. "#sellerId", auction.sellerId or 0)
        setXMLString(xmlFile, key .. "#sellerName", auction.sellerName or "")
        setXMLInt(xmlFile, key .. "#startingBid", auction.startingBid or 0)
        setXMLInt(xmlFile, key .. "#currentBid", auction.currentBid or 0)
        setXMLInt(xmlFile, key .. "#highestBidderId", auction.highestBidderId or 0)
        setXMLString(xmlFile, key .. "#highestBidderName", auction.highestBidderName or "")
        setXMLFloat(xmlFile, key .. "#startTime", auction.startTime or 0)
        setXMLFloat(xmlFile, key .. "#endTime", auction.endTime or 0)
        setXMLString(xmlFile, key .. "#status", auction.status or "ACTIVE")
        if auction.storePrice then
            setXMLInt(xmlFile, key .. "#storePrice", auction.storePrice)
        end
    end

    local ok = saveXMLFile(xmlFile, path)
    delete(xmlFile)
    if ok then
        AuctionLogger.info("AuctionStorage", "Save successful")
    else
        AuctionLogger.error("AuctionStorage", "Failed to save XML file")
    end
end
