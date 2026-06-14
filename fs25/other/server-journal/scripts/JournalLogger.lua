JournalLogger = {}

function JournalLogger._format(source, message)
    return "[" .. source .. "] " .. tostring(message)
end

function JournalLogger.info(source, message, ...)
    if select("#", ...) > 0 then
        message = string.format(message, ...)
    end
    Logging.info("Journal | " .. source .. " | " .. message)
end

function JournalLogger.warning(source, message, ...)
    if select("#", ...) > 0 then
        message = string.format(message, ...)
    end
    Logging.warning("Journal | " .. source .. " | " .. message)
end

function JournalLogger.error(source, message, ...)
    if select("#", ...) > 0 then
        message = string.format(message, ...)
    end
    Logging.error("Journal | " .. source .. " | " .. message)
end