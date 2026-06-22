JournalSettings = {}

JournalSettings.maxPostsPerPlayer = 5
JournalSettings.autoCleanupDays = 7
JournalSettings.chatAnnouncements = true

function JournalSettings.loadDefaultsIfMissing()
    if g_currentMission == nil then return end
    g_currentMission.journalSettings = g_currentMission.journalSettings or {}
    local s = g_currentMission.journalSettings
    if s.maxPostsPerPlayer == nil then s.maxPostsPerPlayer = JournalSettings.maxPostsPerPlayer end
    if s.autoCleanupDays == nil then s.autoCleanupDays = JournalSettings.autoCleanupDays end
    if s.chatAnnouncements == nil then s.chatAnnouncements = JournalSettings.chatAnnouncements end
end

function JournalSettings.saveToXMLFile()
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end
    if g_currentMission.missionInfo == nil then return end

    local savegameDirectory = g_currentMission.missionInfo.savegameDirectory
    if savegameDirectory == nil then
        savegameDirectory = ('%ssavegame%d'):format(getUserProfileAppPath(), g_currentMission.missionInfo.savegameIndex)
    end
    
    local path = savegameDirectory .. "/server_journal_settings.xml"
    local xmlFile = createXMLFile("journalSettings", path, "journalSettings")
    if xmlFile ~= 0 then
        local s = g_currentMission.journalSettings or {}
        setXMLInt(xmlFile, "journalSettings.maxPostsPerPlayer", s.maxPostsPerPlayer or JournalSettings.maxPostsPerPlayer)
        setXMLInt(xmlFile, "journalSettings.autoCleanupDays", s.autoCleanupDays or JournalSettings.autoCleanupDays)
        setXMLBool(xmlFile, "journalSettings.chatAnnouncements", s.chatAnnouncements ~= false)
        saveXMLFile(xmlFile, path)
        delete(xmlFile)
        JournalLogger.info("JournalSettings", "Settings saved to XML")
    end
end

function JournalSettings.loadFromXMLFile()
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end
    if g_currentMission.missionInfo == nil then return end

    local savegameDirectory = g_currentMission.missionInfo.savegameDirectory
    if savegameDirectory == nil then
        savegameDirectory = ('%ssavegame%d'):format(getUserProfileAppPath(), g_currentMission.missionInfo.savegameIndex)
    end

    local path = savegameDirectory .. "/server_journal_settings.xml"
    if not fileExists(path) then
        JournalSettings.loadDefaultsIfMissing()
        return
    end

    local xmlFile = loadXMLFile("journalSettings", path)
    if xmlFile ~= 0 then
        g_currentMission.journalSettings = g_currentMission.journalSettings or {}
        local s = g_currentMission.journalSettings
        s.maxPostsPerPlayer = getXMLInt(xmlFile, "journalSettings.maxPostsPerPlayer") or JournalSettings.maxPostsPerPlayer
        s.autoCleanupDays = getXMLInt(xmlFile, "journalSettings.autoCleanupDays") or JournalSettings.autoCleanupDays
        s.chatAnnouncements = getXMLBool(xmlFile, "journalSettings.chatAnnouncements")
        if s.chatAnnouncements == nil then s.chatAnnouncements = JournalSettings.chatAnnouncements end
        delete(xmlFile)
        JournalLogger.info("JournalSettings", "Settings loaded from XML")
    end
end
