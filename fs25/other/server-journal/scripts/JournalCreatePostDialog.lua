-- Server Journal - Create Post Dialog
-- Follows FS25_Invoices dialog pattern

JournalCreatePostDialog = {}
local JournalCreatePostDialog_mt = Class(JournalCreatePostDialog, MessageDialog)

JournalCreatePostDialog.CONTROLS = {
    DIALOG_TITLE      = "dialogTitle",
    TITLE_INPUT       = "titleInput",
    DESCRIPTION_INPUT = "descriptionInput",
    PAYMENT_INPUT     = "paymentInput",
    CAT_JOB           = "catJob",
    CAT_SALE          = "catSale",
    CAT_FREIGHT       = "catFreight",
    CAT_RP            = "catRP",
    YES_BUTTON        = "yesButton",
    BACK_BUTTON       = "backButton",
}

function JournalCreatePostDialog.new(target, customMt)
    JournalLogger.info("JournalCreatePostDialog", "new")
    local self = MessageDialog.new(target, customMt or JournalCreatePostDialog_mt)
    self.selectedCategory = "job"
    self.callbackFunc = nil
    self._activeInput = nil
    JournalLogger.info("JournalCreatePostDialog", "instance created")
    return self
end

function JournalCreatePostDialog:onCreate()
    JournalLogger.info("JournalCreatePostDialog", "onCreate")
end

function JournalCreatePostDialog:onLoad()
    JournalLogger.info("JournalCreatePostDialog", "onLoad")
    JournalCreatePostDialog:superClass().onLoad(self)
    self:registerControls(JournalCreatePostDialog.CONTROLS)
    JournalLogger.info("JournalCreatePostDialog", "controls registered")
end

function JournalCreatePostDialog:onGuiSetupFinished()
    JournalLogger.info("JournalCreatePostDialog", "onGuiSetupFinished")
    JournalCreatePostDialog:superClass().onGuiSetupFinished(self)
    self:hookInputCapture()
end

function JournalCreatePostDialog:onOpen()
    JournalLogger.info("JournalCreatePostDialog", "onOpen")
    JournalCreatePostDialog:superClass().onOpen(self)
    self:resetUI()
    if self.titleInput then
        FocusManager:setFocus(self.titleInput)
        JournalLogger.info("JournalCreatePostDialog", "focus set to titleInput")
    end
end

function JournalCreatePostDialog:onClose()
    JournalLogger.info("JournalCreatePostDialog", "onClose")
    JournalCreatePostDialog:superClass().onClose(self)
end

function JournalCreatePostDialog:resetUI()
    JournalLogger.info("JournalCreatePostDialog", "resetUI")
    if self.titleInput then
        self.titleInput:setText("")
    end
    if self.descriptionInput then
        self.descriptionInput:setText("")
    end
    if self.paymentInput then
        self.paymentInput:setText("")
    end
    self.selectedCategory = "job"
    self:updateCategoryHighlights()
    self:disableAcceptButtonIfNeeded()
end

function JournalCreatePostDialog:setCallback(callbackFunc)
    self.callbackFunc = callbackFunc
    JournalLogger.info("JournalCreatePostDialog", "callback set")
end

-- Input capture hook (prevent MENU_CANCEL from closing while editing)
function JournalCreatePostDialog:hookInputCapture()
    self._activeInput = nil
    local inputs = {self.titleInput, self.descriptionInput, self.paymentInput}
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
    JournalLogger.info("JournalCreatePostDialog", "input capture hooks installed")
end

function JournalCreatePostDialog:inputEvent(action, value, direction, isAnalog, isMouse, deviceCategory, bindingName)
    if action == InputAction.MENU_CANCEL and self._activeInput ~= nil then
        return true
    end
    return JournalCreatePostDialog:superClass().inputEvent(self, action, value, direction, isAnalog, isMouse, deviceCategory, bindingName)
end

-- Button handlers

function JournalCreatePostDialog:onClickOk()
    JournalLogger.info("JournalCreatePostDialog", "onClickOk")

    local title = ""
    if self.titleInput then
        title = self.titleInput.text or ""
    end
    local description = ""
    if self.descriptionInput then
        description = self.descriptionInput.text or ""
    end
    local paymentStr = ""
    if self.paymentInput then
        paymentStr = self.paymentInput.text or ""
    end
    local payment = tonumber(paymentStr) or 0

    -- Trim whitespace
    title = title:match("^%s*(.-)%s*$") or title
    description = description:match("^%s*(.-)%s*$") or description

    JournalLogger.info("JournalCreatePostDialog", "title='" .. title .. "' desc='" .. description .. "' cat=" .. self.selectedCategory)

    if title == "" or description == "" then
        JournalLogger.warning("JournalCreatePostDialog", "required fields empty")
        JournalUI.showError(g_i18n:getText("journal_dialogRequired", Journal.modName))
        return
    end

    self:close()

    if self.callbackFunc ~= nil then
        JournalLogger.info("JournalCreatePostDialog", "calling callback")
        self.callbackFunc(title, description, self.selectedCategory, payment)
    end
end

function JournalCreatePostDialog:onClickCancel()
    JournalLogger.info("JournalCreatePostDialog", "onClickCancel")
    self:close()
end

-- Category selection

function JournalCreatePostDialog:onClickJob()
    JournalLogger.info("JournalCreatePostDialog", "category: job")
    self.selectedCategory = "job"
    self:updateCategoryHighlights()
end

function JournalCreatePostDialog:onClickSale()
    JournalLogger.info("JournalCreatePostDialog", "category: sale")
    self.selectedCategory = "sale"
    self:updateCategoryHighlights()
end

function JournalCreatePostDialog:onClickFreight()
    JournalLogger.info("JournalCreatePostDialog", "category: freight")
    self.selectedCategory = "freight"
    self:updateCategoryHighlights()
end

function JournalCreatePostDialog:onClickRP()
    JournalLogger.info("JournalCreatePostDialog", "category: rp")
    self.selectedCategory = "rp"
    self:updateCategoryHighlights()
end

function JournalCreatePostDialog:updateCategoryHighlights()
    JournalLogger.info("JournalCreatePostDialog", "updateCategoryHighlights: " .. self.selectedCategory)
    local catMap = {
        job     = self.catJob,
        sale    = self.catSale,
        freight = self.catFreight,
        rp      = self.catRP,
    }
    for cat, btn in pairs(catMap) do
        if btn ~= nil then
            local selected = (cat == self.selectedCategory)
            if btn.setSelected then
                pcall(btn.setSelected, btn, selected)
            end
            if btn.setDisabled then
                pcall(btn.setDisabled, btn, selected)
            end
        end
    end
end

-- Text input callbacks

function JournalCreatePostDialog:onTextChanged(element, text)
    JournalLogger.info("JournalCreatePostDialog", "onTextChanged for " .. tostring(element and element.id or "?"))
    if element == self.paymentInput then
        local filtered = string.gsub(text or "", "[^0-9]", "")
        if filtered ~= text then
            element:setText(filtered)
            return
        end
    end
    self:disableAcceptButtonIfNeeded()
end

function JournalCreatePostDialog:onEnterPressed(element)
    JournalLogger.info("JournalCreatePostDialog", "onEnterPressed for " .. tostring(element and element.id or "?"))
    if element == self.titleInput and self.descriptionInput then
        FocusManager:setFocus(self.descriptionInput)
    elseif element == self.descriptionInput and self.paymentInput then
        FocusManager:setFocus(self.paymentInput)
    elseif element == self.paymentInput then
        self:onClickOk()
    end
end

function JournalCreatePostDialog:disableAcceptButtonIfNeeded()
    local title = ""
    if self.titleInput then
        title = self.titleInput.text or ""
    end
    local description = ""
    if self.descriptionInput then
        description = self.descriptionInput.text or ""
    end
    local disabled = (title == "" or description == "")
    if self.yesButton then
        self.yesButton:setDisabled(disabled)
    end
end
