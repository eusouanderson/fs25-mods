JournalUI = {}

JournalUI.CATEGORIES = { "all", "job", "sale", "freight", "rp" }

JournalUI.CATEGORY_KEYS = {
    all = "journal_filterAll",
    job = "journal_filterJob",
    sale = "journal_filterSale",
    freight = "journal_filterFreight",
    rp = "journal_filterRP",
}

function JournalUI.getCategoryLabel(category)
    local key = JournalUI.CATEGORY_KEYS[category]
    if key and g_i18n ~= nil then
        local t = g_i18n:getText(key)
        if t and t ~= "" then return t end
    end
    return category or ""
end

function JournalUI.showNotification(text)
    JournalLogger.info("JournalUI", "Notification: " .. text)
    if g_currentMission ~= nil then
        pcall(function()
            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, text)
        end)
    end
end

function JournalUI.showError(text)
    JournalLogger.info("JournalUI", "Error: " .. text)
    if g_currentMission ~= nil then
        pcall(function()
            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_ERROR, text)
        end)
    end
end

function JournalUI.safeSet(element, method, ...)
    if element == nil then
        return false
    end
    local fn = element[method]
    if fn == nil then
        JournalLogger.warning("JournalUI", "Method " .. method .. " not found on element")
        return false
    end
    local ok, err = pcall(fn, element, ...)
    if not ok then
        JournalLogger.warning("JournalUI", "Method " .. method .. " failed: " .. tostring(err))
    end
    return ok
end

function JournalUI.createTextBox(parent, name, text, posX, posY, sizeX, sizeY)
    local ok, element = pcall(TextElement.new)
    if not ok or element == nil then
        JournalLogger.error("JournalUI", "Failed to create TextElement: " .. tostring(element))
        return nil
    end
    JournalUI.safeSet(element, "setText", text)
    JournalUI.safeSet(element, "setPosition", posX, posY)
    JournalUI.safeSet(element, "setSize", sizeX, sizeY)
    if parent ~= nil then
        pcall(parent.addElement, parent, element)
    end
    return element
end

function JournalUI.createButton(parent, name, text, posX, posY, sizeX, sizeY, onClick)
    local ok, element = pcall(ButtonElement.new)
    if not ok or element == nil then
        JournalLogger.error("JournalUI", "Failed to create ButtonElement: " .. tostring(element))
        return nil
    end
    JournalUI.safeSet(element, "setText", text)
    JournalUI.safeSet(element, "setPosition", posX, posY)
    JournalUI.safeSet(element, "setSize", sizeX, sizeY)
    if onClick ~= nil then
        element.onClickCallback = onClick
    end
    if parent ~= nil then
        pcall(parent.addElement, parent, element)
    end
    return element
end

function JournalUI.createFrame(parent, name, posX, posY, sizeX, sizeY)
    local ok, frame = pcall(FrameElement.new)
    if not ok or frame == nil then
        JournalLogger.error("JournalUI", "Failed to create FrameElement: " .. tostring(frame))
        return nil
    end
    JournalUI.safeSet(frame, "setPosition", posX, posY)
    JournalUI.safeSet(frame, "setSize", sizeX, sizeY)
    if parent ~= nil then
        pcall(parent.addElement, parent, frame)
    end
    return frame
end