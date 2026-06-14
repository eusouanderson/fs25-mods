-- ==========================================================================
-- Server Auction House - SyncAuctionsEvent
-- Author: Antigravity
-- Farming Simulator 25 (FS25) Compatible Event
-- ==========================================================================

SyncAuctionsEvent = {}
local SyncAuctionsEvent_mt = Class(SyncAuctionsEvent, Event)

InitEventClass(SyncAuctionsEvent, "SyncAuctionsEvent")

function SyncAuctionsEvent:emptyNew()
    local self = Event:new(SyncAuctionsEvent_mt)
    return self
end

function SyncAuctionsEvent:new(auctionsList)
    local self = SyncAuctionsEvent:emptyNew()
    self.auctions = auctionsList or {}
    return self
end

function SyncAuctionsEvent:readStream(streamId, connection)
    local count = streamReadInt32(streamId)
    self.auctions = {}
    
    for i = 1, count do
        local id = streamReadString(streamId)
        local auction = {
            id = id,
            itemName = streamReadString(streamId),
            vehicleId = streamReadInt32(streamId),
            seller = streamReadString(streamId),
            farmId = streamReadInt32(streamId),
            startingBid = streamReadInt32(streamId),
            currentBid = streamReadInt32(streamId),
            duration = streamReadFloat32(streamId),
            startTime = streamReadFloat32(streamId),
            endTime = streamReadFloat32(streamId),
            status = streamReadString(streamId)
        }
        
        local hasBidder = streamReadBool(streamId)
        if hasBidder then
            auction.highestBidder = streamReadString(streamId)
        else
            auction.highestBidder = nil
        end
        
        self.auctions[id] = auction
    end
    
    self:run(connection)
end

function SyncAuctionsEvent:writeStream(streamId, connection)
    local count = 0
    for _ in pairs(self.auctions) do
        count = count + 1
    end
    
    streamWriteInt32(streamId, count)
    
    for id, a in pairs(self.auctions) do
        streamWriteString(streamId, a.id)
        streamWriteString(streamId, a.itemName)
        streamWriteInt32(streamId, a.vehicleId)
        streamWriteString(streamId, a.seller)
        streamWriteInt32(streamId, a.farmId)
        streamWriteInt32(streamId, a.startingBid)
        streamWriteInt32(streamId, a.currentBid)
        streamWriteFloat32(streamId, a.duration)
        streamWriteFloat32(streamId, a.startTime)
        streamWriteFloat32(streamId, a.endTime)
        streamWriteString(streamId, a.status)
        
        if a.highestBidder ~= nil then
            streamWriteBool(streamId, true)
            streamWriteString(streamId, a.highestBidder)
        else
            streamWriteBool(streamId, false)
        end
    end
end

function SyncAuctionsEvent:run(connection)
    if g_serverAuctionHouse ~= nil then
        g_serverAuctionHouse.auctions = self.auctions
        if g_serverAuctionHouse.ui ~= nil and g_gui:getIsGuiVisible() then
            g_serverAuctionHouse.ui:refreshUI()
        end
    end
end
