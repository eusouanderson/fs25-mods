-- ==========================================================================
-- Server Auction House - PlaceBidEvent
-- Author: Antigravity
-- Farming Simulator 25 (FS25) Compatible Event
-- ==========================================================================

PlaceBidEvent = {}
local PlaceBidEvent_mt = Class(PlaceBidEvent, Event)

InitEventClass(PlaceBidEvent, "PlaceBidEvent")

function PlaceBidEvent:emptyNew()
    local self = Event:new(PlaceBidEvent_mt)
    return self
end

function PlaceBidEvent:new(bidder, amount)
    local self = PlaceBidEvent:emptyNew()
    self.bidder = bidder
    self.amount = amount
    return self
end

function PlaceBidEvent:readStream(streamId, connection)
    self.bidder = streamReadString(streamId)
    self.amount = streamReadInt32(streamId)
    self:run(connection)
end

function PlaceBidEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.bidder)
    streamWriteInt32(streamId, self.amount)
end

function PlaceBidEvent:run(connection)
    if not connection:getIsServer() then
        -- Run on server to validate and process bid
        if g_serverAuctionHouse ~= nil then
            g_serverAuctionHouse:placeBidServer(self.bidder, self.amount)
        end
    end
end
