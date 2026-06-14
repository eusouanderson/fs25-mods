-- Server Auction House - Create Auction Dialog
-- Follows FS25_ServerJournal's JournalCreatePostDialog pattern

AuctionCreateDialog = {}
local AuctionCreateDialog_mt = Class(AuctionCreateDialog, MessageDialog)

AuctionCreateDialog.DEFAULT_STARTING_BID = "50000"
AuctionCreateDialog.DEFAULT_DURATION = "5"

AuctionCreateDialog.CONTROLS = {
    DIALOG_TITLE         = "dialogTitle",
    VEHICLE_LIST         = "vehicleList",
    VEHICLE_SLIDER_BOX   = "vehicleSliderBox",
    EMPTY_VEHICLES_TEXT  = "emptyVehiclesText",
    STARTING_BID_INPUT   = "startingBidInput",
    DURATION_INPUT       = "durationInput",
    YES_BUTTON           = "yesButton",
    BACK_BUTTON          = "backButton",
}

function AuctionCreateDialog.new(target, customMt)
    AuctionLogger.info("AuctionCreateDialog", "new")
    local self = MessageDialog.new(target, customMt or AuctionCreateDialog_mt)
    self.vehicles = {}
    self.selectedVehicleIndex = nil
    self.callbackFunc = nil
    self._activeInput = nil
    AuctionLogger.info("AuctionCreateDialog", "instance created")
    return self
end

function AuctionCreateDialog:onCreate()
    AuctionLogger.info("AuctionCreateDialog", "onCreate")
end

function AuctionCreateDialog:onLoad()
    AuctionLogger.info("AuctionCreateDialog", "onLoad")
    AuctionCreateDialog:superClass().onLoad(self)
    self:registerControls(AuctionCreateDialog.CONTROLS)
    AuctionLogger.info("AuctionCreateDialog", "controls registered")
end

function AuctionCreateDialog:onGuiSetupFinished()
    AuctionLogger.info("AuctionCreateDialog", "onGuiSetupFinished")
    AuctionCreateDialog:superClass().onGuiSetupFinished(self)

    if self.vehicleList then
        self.vehicleList:setDataSource(self)
        self.vehicleList:setDelegate(self)
        AuctionLogger.info("AuctionCreateDialog", "vehicleList dataSource+delegate set")
    end

    self:hookInputCapture()
end

function AuctionCreateDialog:onOpen()
    AuctionLogger.info("AuctionCreateDialog", "onOpen")
    AuctionCreateDialog:superClass().onOpen(self)
    self:resetUI()
end

function AuctionCreateDialog:onClose()
    AuctionLogger.info("AuctionCreateDialog", "onClose")
    AuctionCreateDialog:superClass().onClose(self)
end

function AuctionCreateDialog:resetUI()
    AuctionLogger.info("AuctionCreateDialog", "resetUI")

    if self.startingBidInput then
        self.startingBidInput:setText(AuctionCreateDialog.DEFAULT_STARTING_BID)
    end
    if self.durationInput then
        self.durationInput:setText(AuctionCreateDialog.DEFAULT_DURATION)
    end

    self:loadVehicles()

    if self.vehicleList then
        self.vehicleList:reloadData()
    end

    local hasVehicles = #self.vehicles > 0
    if self.emptyVehiclesText then
        self.emptyVehiclesText:setVisible(not hasVehicles)
    end
    if self.vehicleList then
        self.vehicleList:setVisible(hasVehicles)
    end

    self:disableAcceptButtonIfNeeded()
end

function AuctionCreateDialog:setCallback(callbackFunc)
    self.callbackFunc = callbackFunc
    AuctionLogger.info("AuctionCreateDialog", "callback set")
end

-- Load the local player's own vehicles that are not already in an auction
function AuctionCreateDialog:loadVehicles()
    AuctionLogger.info("AuctionCreateDialog", "loadVehicles")
    self.vehicles = {}
    self.selectedVehicleIndex = nil

    if g_currentMission == nil then
        return
    end

    local farmId = AuctionUI.getLocalFarmInfo()
    if farmId == nil or farmId == 0 then
        return
    end

    if g_currentMission.vehicleSystem == nil or g_currentMission.vehicleSystem.vehicles == nil then
        AuctionLogger.warning("AuctionCreateDialog", "vehicleSystem.vehicles is nil")
        return
    end

    AuctionLogger.info("AuctionCreateDialog", "scanning " .. #g_currentMission.vehicleSystem.vehicles .. " vehicles for farmId=" .. tostring(farmId))

    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        if vehicle.configFileName ~= nil and vehicle:getOwnerFarmId() == farmId then
            local inAuction = (g_auctionManager ~= nil) and g_auctionManager:isVehicleInAuction(vehicle.id)
            if not inAuction then
                table.insert(self.vehicles, {
                    id = vehicle.id,
                    name = vehicle:getName() or "?",
                })
            end
        end
    end

    AuctionLogger.info("AuctionCreateDialog", "found " .. #self.vehicles .. " available vehicles")
end

-- Input capture hook (prevent MENU_CANCEL from closing while editing)
function AuctionCreateDialog:hookInputCapture()
    self._activeInput = nil
    local inputs = {self.startingBidInput, self.durationInput}
    for _, input in ipairs(inputs) do
        if input ~= nil then
            local origFn = input.setCaptureInput
            local selfRef = self
            local inputRef = input
            input.setCaptureInput = function(inputSelf, isCapturing)
                if origFn then
                    origFn(inputSelf, isCapturing)
                end
                if isCapturing then
                    selfRef._activeInput = inputRef
                elseif selfRef._activeInput == inputRef then
                    selfRef._activeInput = nil
                end
            end
        end
    end
    AuctionLogger.info("AuctionCreateDialog", "input capture hooks installed")
end

function AuctionCreateDialog:inputEvent(action, value, direction, isAnalog, isMouse, deviceCategory, bindingName)
    if action == InputAction.MENU_CANCEL and self._activeInput ~= nil then
        return true
    end
    return AuctionCreateDialog:superClass().inputEvent(self, action, value, direction, isAnalog, isMouse, deviceCategory, bindingName)
end

-- SmoothList DataSource/Delegate

function AuctionCreateDialog:getNumberOfSections(list)
    return 1
end

function AuctionCreateDialog:getNumberOfItemsInSection(list, section)
    return #self.vehicles
end

function AuctionCreateDialog:getTitleForSectionHeader(list, section)
    return nil
end

function AuctionCreateDialog:getSectionHeaderHeight(list, section)
    return 0
end

function AuctionCreateDialog:getCellTypeForItemInSection(list, section, index)
    return "auctionDialogVehicleItem"
end

function AuctionCreateDialog:populateCellForItemInSection(list, section, index, cell)
    local vehicle = self.vehicles[index]
    if vehicle == nil then return end

    local cellName = cell:getDescendantByName("cellVehicleName")
    if cellName then
        cellName:setText(vehicle.name or "")
    end
end

function AuctionCreateDialog:onListSelectionChanged(list, section, index)
    AuctionLogger.info("AuctionCreateDialog", "onListSelectionChanged index=" .. tostring(index))
    if list ~= self.vehicleList then return end

    if index >= 1 and index <= #self.vehicles then
        self.selectedVehicleIndex = index
    else
        self.selectedVehicleIndex = nil
    end
    self:disableAcceptButtonIfNeeded()
end

-- Text input callbacks

function AuctionCreateDialog:onTextChanged(element, text)
    AuctionLogger.info("AuctionCreateDialog", "onTextChanged for " .. tostring(element and element.id or "?"))
    local filtered = string.gsub(text or "", "[^0-9]", "")
    if filtered ~= text then
        element:setText(filtered)
        return
    end
    self:disableAcceptButtonIfNeeded()
end

function AuctionCreateDialog:onEnterPressed(element)
    AuctionLogger.info("AuctionCreateDialog", "onEnterPressed for " .. tostring(element and element.id or "?"))
    if element == self.startingBidInput and self.durationInput then
        FocusManager:setFocus(self.durationInput)
    elseif element == self.durationInput then
        self:onClickOk()
    end
end

function AuctionCreateDialog:disableAcceptButtonIfNeeded()
    local disabled = (self.selectedVehicleIndex == nil) or (#self.vehicles == 0)
    if self.yesButton then
        self.yesButton:setDisabled(disabled)
    end
end

-- Button handlers

function AuctionCreateDialog:onClickOk()
    AuctionLogger.info("AuctionCreateDialog", "onClickOk")

    if self.selectedVehicleIndex == nil then
        AuctionUI.showError(g_i18n:getText("ah_dialogSelectVehicle", AuctionHouse.modName))
        return
    end

    local vehicle = self.vehicles[self.selectedVehicleIndex]
    if vehicle == nil then return end

    local startingBidStr = ""
    if self.startingBidInput then
        startingBidStr = self.startingBidInput.text or ""
    end
    local durationStr = ""
    if self.durationInput then
        durationStr = self.durationInput.text or ""
    end

    local startingBid = tonumber(startingBidStr) or tonumber(AuctionCreateDialog.DEFAULT_STARTING_BID)
    local durationMins = tonumber(durationStr) or tonumber(AuctionCreateDialog.DEFAULT_DURATION)

    AuctionLogger.info("AuctionCreateDialog", "vehicle=" .. vehicle.name .. " startingBid=" .. tostring(startingBid) .. " duration=" .. tostring(durationMins))

    self:close()

    if self.callbackFunc ~= nil then
        self.callbackFunc(vehicle.id, startingBid, durationMins)
    end
end

function AuctionCreateDialog:onClickCancel()
    AuctionLogger.info("AuctionCreateDialog", "onClickCancel")
    self:close()
end
