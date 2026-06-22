JournalSettingsEvent = {}
local JournalSettingsEvent_mt = Class(JournalSettingsEvent, Event)

InitEventClass(JournalSettingsEvent, "JournalSettingsEvent")
JournalLogger.info("JournalSettingsEvent", "Event class registered")

function JournalSettingsEvent.emptyNew()
    return Event.new(JournalSettingsEvent_mt)
end

function JournalSettingsEvent.new(settings)
    local self = JournalSettingsEvent.emptyNew()
    self.settings = settings
    return self
end

function JournalSettingsEvent:writeStream(streamId, connection)
    local s = self.settings or {
        maxPostsPerPlayer = JournalSettings.maxPostsPerPlayer or 5,
        autoCleanupDays = JournalSettings.autoCleanupDays or 7,
        chatAnnouncements = JournalSettings.chatAnnouncements ~= false
    }
    streamWriteInt32(streamId, s.maxPostsPerPlayer)
    streamWriteInt32(streamId, s.autoCleanupDays)
    streamWriteBool(streamId, s.chatAnnouncements)
end

function JournalSettingsEvent:readStream(streamId, connection)
    self.settings = {
        maxPostsPerPlayer = streamReadInt32(streamId),
        autoCleanupDays = streamReadInt32(streamId),
        chatAnnouncements = streamReadBool(streamId)
    }
    self:run(connection)
end

function JournalSettingsEvent:run(connection)
    if g_server ~= nil and connection ~= nil and not connection:getIsServer() then
        -- Client should not send settings to server unless admin, but let's check
        local user = g_currentMission.userManager:getUserByConnection(connection)
        local isAdmin = user ~= nil and g_currentMission:getIsMasterUser(user.userId)
        if isAdmin then
            g_currentMission.journalSettings = self.settings
            JournalSettings.saveToXMLFile()
            g_server:broadcastEvent(JournalSettingsEvent.new(self.settings), false, connection)
        end
        return
    end

    -- Apply on client
    g_currentMission.journalSettings = self.settings
    JournalLogger.info("JournalSettingsEvent", "Applied settings from server: maxPosts=" .. tostring(self.settings.maxPostsPerPlayer) .. " autoCleanup=" .. tostring(self.settings.autoCleanupDays))
end
