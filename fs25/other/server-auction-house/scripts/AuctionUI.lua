AuctionUI = {}

AuctionUI.STATUS_KEYS = {
    ACTIVE = "ah_statusActive",
    ENDED  = "ah_statusEnded",
}

function AuctionUI.getStatusLabel(status)
    local key = AuctionUI.STATUS_KEYS[status]
    if key and g_i18n ~= nil then
        local t = g_i18n:getText(key)
        if t and t ~= "" then return t end
    end
    return status or ""
end

function AuctionUI.formatMoney(amount)
    amount = amount or 0
    if g_i18n ~= nil then
        local ok, text = pcall(function() return g_i18n:formatMoney(amount, 0, true, true) end)
        if ok and text then
            return text
        end
    end
    return string.format("%d", amount)
end

-- endTime/currentTime are mission time in milliseconds
function AuctionUI.formatTimeLeft(endTime, currentTime)
    local remaining = math.max(0, math.floor((endTime or 0) - (currentTime or 0)))
    local totalSeconds = math.floor(remaining / 1000)
    local minutes = math.floor(totalSeconds / 60)
    local seconds = totalSeconds % 60
    return string.format("%02d:%02d", minutes, seconds)
end

function AuctionUI.showNotification(text)
    AuctionLogger.info("AuctionUI", "Notification: " .. tostring(text))
    if g_currentMission ~= nil then
        pcall(function()
            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, text)
        end)
    end
end

function AuctionUI.showError(text)
    AuctionLogger.info("AuctionUI", "Error: " .. tostring(text))
    if g_currentMission ~= nil then
        pcall(function()
            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_ERROR, text)
        end)
    end
end

-- Returns the local player's farm id and display name
function AuctionUI.getLocalFarmInfo()
    local farmId = 0
    local playerName = ""
    if g_currentMission ~= nil then
        farmId = g_currentMission:getFarmId() or 0
        if g_currentMission.player ~= nil then
            playerName = g_currentMission.player:getName() or ""
        end
    end
    return farmId, playerName
end

function AuctionUI.safeSet(element, method, ...)
    if element == nil then
        return false
    end
    local fn = element[method]
    if fn == nil then
        AuctionLogger.warning("AuctionUI", "Method " .. method .. " not found on element")
        return false
    end
    local ok, err = pcall(fn, element, ...)
    if not ok then
        AuctionLogger.warning("AuctionUI", "Method " .. method .. " failed: " .. tostring(err))
    end
    return ok
end
