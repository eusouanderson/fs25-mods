AuctionEvent = {}
local AuctionEvent_mt = Class(AuctionEvent, Event)

InitEventClass(AuctionEvent, "AuctionEvent")
AuctionLogger.info("AuctionEvent", "Event class initialized")

AuctionEvent.TYPE_SYNC   = 1
AuctionEvent.TYPE_CREATE = 2
AuctionEvent.TYPE_BID    = 3
AuctionEvent.TYPE_CANCEL = 4

function AuctionEvent.emptyNew()
    return Event.new(AuctionEvent_mt)
end

function AuctionEvent.new(eventType, data)
    local self = AuctionEvent.emptyNew()
    self.eventType = eventType
    self.data = data
    return self
end

function AuctionEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.eventType)

    if self.eventType == AuctionEvent.TYPE_SYNC then
        local auctions = self.data or {}
        streamWriteUInt16(streamId, #auctions)
        for _, auction in ipairs(auctions) do
            AuctionEvent.writeAuction(streamId, auction)
        end
    elseif self.eventType == AuctionEvent.TYPE_CREATE then
        streamWriteInt32(streamId, self.data.sellerId)
        streamWriteString(streamId, self.data.sellerName)
        streamWriteInt32(streamId, self.data.vehicleId)
        streamWriteInt32(streamId, self.data.startingBid)
        streamWriteInt32(streamId, self.data.durationMins)
    elseif self.eventType == AuctionEvent.TYPE_BID then
        streamWriteInt32(streamId, self.data.bidderId)
        streamWriteString(streamId, self.data.bidderName)
        streamWriteInt32(streamId, self.data.auctionId)
        streamWriteInt32(streamId, self.data.amount)
    elseif self.eventType == AuctionEvent.TYPE_CANCEL then
        streamWriteInt32(streamId, self.data.requesterId)
        streamWriteString(streamId, self.data.requesterName)
        streamWriteInt32(streamId, self.data.auctionId)
    end
end

function AuctionEvent:readStream(streamId, connection)
    self.eventType = streamReadUInt8(streamId)

    if self.eventType == AuctionEvent.TYPE_SYNC then
        local count = streamReadUInt16(streamId)
        local auctions = {}
        for _ = 1, count do
            table.insert(auctions, AuctionEvent.readAuction(streamId))
        end
        self.data = auctions
    elseif self.eventType == AuctionEvent.TYPE_CREATE then
        self.data = {
            sellerId     = streamReadInt32(streamId),
            sellerName   = streamReadString(streamId),
            vehicleId    = streamReadInt32(streamId),
            startingBid  = streamReadInt32(streamId),
            durationMins = streamReadInt32(streamId),
        }
    elseif self.eventType == AuctionEvent.TYPE_BID then
        self.data = {
            bidderId   = streamReadInt32(streamId),
            bidderName = streamReadString(streamId),
            auctionId  = streamReadInt32(streamId),
            amount     = streamReadInt32(streamId),
        }
    elseif self.eventType == AuctionEvent.TYPE_CANCEL then
        self.data = {
            requesterId   = streamReadInt32(streamId),
            requesterName = streamReadString(streamId),
            auctionId     = streamReadInt32(streamId),
        }
    end

    self:run(connection)
end

function AuctionEvent:run(connection)
    if g_server ~= nil and connection ~= nil and not connection:getIsServer() then
        -- Server received a request from a client: validate and apply
        if g_auctionManager == nil then
            AuctionLogger.warning("AuctionEvent", "g_auctionManager is nil, cannot handle client request")
            return
        end

        if self.eventType == AuctionEvent.TYPE_CREATE then
            g_auctionManager:createAuction(self.data.sellerId, self.data.sellerName, self.data.vehicleId, self.data.startingBid, self.data.durationMins)
        elseif self.eventType == AuctionEvent.TYPE_BID then
            g_auctionManager:placeBid(self.data.auctionId, self.data.bidderId, self.data.bidderName, self.data.amount)
        elseif self.eventType == AuctionEvent.TYPE_CANCEL then
            g_auctionManager:cancelAuction(self.data.auctionId, self.data.requesterId, self.data.requesterName)
        end
        return
    end

    -- Client (or single-player) applying a server broadcast
    if g_auctionManager ~= nil then
        if self.eventType == AuctionEvent.TYPE_SYNC then
            g_auctionManager:onReceiveSync(self.data)
        end
    else
        AuctionLogger.warning("AuctionEvent", "g_auctionManager is nil, cannot apply event")
    end
end

function AuctionEvent.writeAuction(streamId, auction)
    streamWriteInt32(streamId, auction.id)
    streamWriteInt32(streamId, auction.vehicleId or 0)
    streamWriteString(streamId, auction.itemName or "")
    streamWriteInt32(streamId, auction.sellerId or 0)
    streamWriteString(streamId, auction.sellerName or "")
    streamWriteInt32(streamId, auction.startingBid or 0)
    streamWriteInt32(streamId, auction.currentBid or 0)
    streamWriteInt32(streamId, auction.highestBidderId or 0)
    streamWriteString(streamId, auction.highestBidderName or "")
    streamWriteFloat32(streamId, auction.startTime or 0)
    streamWriteFloat32(streamId, auction.endTime or 0)
    streamWriteString(streamId, auction.status or "ACTIVE")
end

function AuctionEvent.readAuction(streamId)
    return {
        id                = streamReadInt32(streamId),
        vehicleId         = streamReadInt32(streamId),
        itemName          = streamReadString(streamId),
        sellerId          = streamReadInt32(streamId),
        sellerName        = streamReadString(streamId),
        startingBid       = streamReadInt32(streamId),
        currentBid        = streamReadInt32(streamId),
        highestBidderId   = streamReadInt32(streamId),
        highestBidderName = streamReadString(streamId),
        startTime         = streamReadFloat32(streamId),
        endTime           = streamReadFloat32(streamId),
        status            = streamReadString(streamId),
    }
end

function AuctionEvent.sendSync(auctions)
    AuctionLogger.info("AuctionEvent", "Sending sync with " .. #auctions .. " auctions")
    if g_server ~= nil then
        g_server:broadcastEvent(AuctionEvent.new(AuctionEvent.TYPE_SYNC, auctions))
    end
end

function AuctionEvent.sendCreateRequest(sellerId, sellerName, vehicleId, startingBid, durationMins)
    if g_server ~= nil then
        if g_auctionManager ~= nil then
            g_auctionManager:createAuction(sellerId, sellerName, vehicleId, startingBid, durationMins)
        end
    elseif g_client ~= nil then
        local conn = g_client:getServerConnection()
        if conn then
            conn:sendEvent(AuctionEvent.new(AuctionEvent.TYPE_CREATE, {
                sellerId = sellerId,
                sellerName = sellerName,
                vehicleId = vehicleId,
                startingBid = startingBid,
                durationMins = durationMins,
            }))
        end
    end
end

function AuctionEvent.sendBidRequest(bidderId, bidderName, auctionId, amount)
    if g_server ~= nil then
        if g_auctionManager ~= nil then
            g_auctionManager:placeBid(auctionId, bidderId, bidderName, amount)
        end
    elseif g_client ~= nil then
        local conn = g_client:getServerConnection()
        if conn then
            conn:sendEvent(AuctionEvent.new(AuctionEvent.TYPE_BID, {
                bidderId = bidderId,
                bidderName = bidderName,
                auctionId = auctionId,
                amount = amount,
            }))
        end
    end
end

function AuctionEvent.sendCancelRequest(requesterId, requesterName, auctionId)
    if g_server ~= nil then
        if g_auctionManager ~= nil then
            g_auctionManager:cancelAuction(auctionId, requesterId, requesterName)
        end
    elseif g_client ~= nil then
        local conn = g_client:getServerConnection()
        if conn then
            conn:sendEvent(AuctionEvent.new(AuctionEvent.TYPE_CANCEL, {
                requesterId = requesterId,
                requesterName = requesterName,
                auctionId = auctionId,
            }))
        end
    end
end
