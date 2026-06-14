-- ==========================================================================
-- Server Auction House - NewAuctionEvent
-- Author: Antigravity
-- Farming Simulator 25 (FS25) Compatible Event
-- ==========================================================================

NewAuctionEvent = {}
local NewAuctionEvent_mt = Class(NewAuctionEvent, Event)

InitEventClass(NewAuctionEvent, "NewAuctionEvent")

function NewAuctionEvent:emptyNew()
    local self = Event:new(NewAuctionEvent_mt)
    return self
end

function NewAuctionEvent:new(player, vehicleId, startPrice, durationMins)
    local self = NewAuctionEvent:emptyNew()
    self.player = player
    self.vehicleId = vehicleId
    self.startPrice = startPrice
    self.durationMins = durationMins
    return self
end

function NewAuctionEvent:readStream(streamId, connection)
    self.player = streamReadString(streamId)
    -- In FS25 vehicles are referenced by ID
    self.vehicleId = streamReadInt32(streamId)
    self.startPrice = streamReadInt32(streamId)
    self.durationMins = streamReadInt32(streamId)
    self:run(connection)
end

function NewAuctionEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.player)
    streamWriteInt32(streamId, self.vehicleId)
    streamWriteInt32(streamId, self.startPrice)
    streamWriteInt32(streamId, self.durationMins)
end

function NewAuctionEvent:run(connection)
    if not connection:getIsServer() then
        -- We are on the server, process the client's request
        if g_serverAuctionHouse ~= nil then
            g_serverAuctionHouse:createAuctionServer(
                self.player, 
                self.vehicleId, 
                self.startPrice, 
                self.durationMins
            )
        end
    end
end
