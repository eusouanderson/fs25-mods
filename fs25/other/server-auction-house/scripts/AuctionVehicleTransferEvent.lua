AuctionVehicleTransferEvent = {}
local AuctionVehicleTransferEvent_mt = Class(AuctionVehicleTransferEvent, Event)

InitEventClass(AuctionVehicleTransferEvent, "AuctionVehicleTransferEvent")

function AuctionVehicleTransferEvent.emptyNew()
    return Event.new(AuctionVehicleTransferEvent_mt)
end

function AuctionVehicleTransferEvent.new(vehicle, previousOwnerFarmId, newOwnerFarmId)
    local self = AuctionVehicleTransferEvent.emptyNew()
    self.vehicle = vehicle
    self.previousOwnerFarmId = previousOwnerFarmId
    self.newOwnerFarmId = newOwnerFarmId
    return self
end

function AuctionVehicleTransferEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, NetworkUtil.getObjectId(self.vehicle))
    streamWriteInt32(streamId, self.previousOwnerFarmId or 0)
    streamWriteInt32(streamId, self.newOwnerFarmId or 0)
end

function AuctionVehicleTransferEvent:readStream(streamId, connection)
    local vehicleNetId = streamReadInt32(streamId)
    self.vehicle = NetworkUtil.getObject(vehicleNetId)
    self.previousOwnerFarmId = streamReadInt32(streamId)
    self.newOwnerFarmId = streamReadInt32(streamId)
    self:run(connection)
end

function AuctionVehicleTransferEvent:run(connection)
    local vehicle = self.vehicle
    if vehicle == nil then
        AuctionLogger.warning("AuctionVehicleTransferEvent", "vehicle not resolved from network (previousOwner=%d, newOwner=%d)", self.previousOwnerFarmId or 0, self.newOwnerFarmId or 0)
        return
    end

    local vehicleName = ""
    if vehicle.getName ~= nil then
        vehicleName = vehicle:getName()
    end
    local vehicleId = vehicle.id or 0

    AuctionLogger.info("AuctionVehicleTransferEvent", ">>> TRANSFERINDO veículo '%s' (id=%d, netId=%d): farmId=%d -> farmId=%d", vehicleName, vehicleId, NetworkUtil.getObjectId(vehicle), self.previousOwnerFarmId, self.newOwnerFarmId)
    vehicle:setOwnerFarmId(self.newOwnerFarmId, true)
    AuctionLogger.info("AuctionVehicleTransferEvent", ">>> Transferência concluída: veículo '%s' agora pertence à farmId=%d", vehicleName, self.newOwnerFarmId)
end
