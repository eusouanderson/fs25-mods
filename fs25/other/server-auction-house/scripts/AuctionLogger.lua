AuctionLogger = {}

function AuctionLogger._format(source, message)
    return "[" .. source .. "] " .. tostring(message)
end

function AuctionLogger.info(source, message, ...)
    if select("#", ...) > 0 then
        message = string.format(message, ...)
    end
    Logging.info("AuctionHouse | " .. source .. " | " .. message)
end

function AuctionLogger.warning(source, message, ...)
    if select("#", ...) > 0 then
        message = string.format(message, ...)
    end
    Logging.warning("AuctionHouse | " .. source .. " | " .. message)
end

function AuctionLogger.error(source, message, ...)
    if select("#", ...) > 0 then
        message = string.format(message, ...)
    end
    Logging.error("AuctionHouse | " .. source .. " | " .. message)
end
