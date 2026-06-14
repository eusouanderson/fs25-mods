JournalStorage = {}

local SAVE_FILE = "journal.xml"
local SAVE_KEY = "journal"

function JournalStorage.getSavegamePath()
    local saveDir = ""
    if g_currentMission ~= nil and g_currentMission.missionInfo ~= nil then
        saveDir = g_currentMission.missionInfo.savegameDirectory or ""
    end
    if saveDir == "" then
        saveDir = getUserProfileAppPath() .. "savegame" .. tostring(g_currentMission ~= nil and g_currentMission.missionInfo.savegameIndex or 1)
    end
    local path = saveDir .. "/" .. SAVE_FILE
    JournalLogger.info("JournalStorage", "Savegame path: " .. path)
    return path
end

function JournalStorage.load()
    JournalLogger.info("JournalStorage", "Loading posts from savegame")
    local posts = {}
    local nextId = 1
    local path = JournalStorage.getSavegamePath()

    local xmlFile = loadXMLFile(SAVE_FILE, path)
    if xmlFile == 0 then
        JournalLogger.info("JournalStorage", "No save file found at " .. path)
        return posts, nextId
    end

    nextId = math.max(1, getXMLInt(xmlFile, SAVE_KEY .. "#nextId") or 1)
    JournalLogger.info("JournalStorage", "nextId = " .. nextId)

    local i = 0
    while true do
        local key = string.format("%s.post(%d)", SAVE_KEY, i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end
        local ca = key .. ".createdAt"
        local post = {
            id          = getXMLInt(xmlFile, key .. "#id"),
            authorId    = getXMLInt(xmlFile, key .. "#authorId"),
            authorName  = getXMLString(xmlFile, key .. "#authorName") or "",
            title       = getXMLString(xmlFile, key .. "#title") or "",
            description = getXMLString(xmlFile, key .. "#description") or "",
            category    = getXMLString(xmlFile, key .. "#category") or "job",
            payment     = getXMLInt(xmlFile, key .. "#payment") or 0,
            createdAt   = {
                day    = getXMLInt(xmlFile, ca .. "#day") or 0,
                period = getXMLInt(xmlFile, ca .. "#period") or 0,
                year   = getXMLInt(xmlFile, ca .. "#year") or 1,
                hour   = getXMLInt(xmlFile, ca .. "#hour") or 0,
                minute = getXMLInt(xmlFile, ca .. "#minute") or 0,
            },
        }
        table.insert(posts, post)
        i = i + 1
    end

    delete(xmlFile)
    JournalLogger.info("JournalStorage", "Loaded " .. #posts .. " posts from savegame")
    return posts, nextId
end

function JournalStorage.save(posts, nextId)
    JournalLogger.info("JournalStorage", "Saving " .. #posts .. " posts to savegame (nextId=" .. nextId .. ")")
    local path = JournalStorage.getSavegamePath()
    local xmlFile = createXMLFile(SAVE_FILE, path, SAVE_KEY)
    if xmlFile == 0 then
        JournalLogger.error("JournalStorage", "Failed to create save file at " .. path)
        return
    end

    setXMLInt(xmlFile, SAVE_KEY .. "#nextId", nextId)

    for i, post in ipairs(posts) do
        local key = string.format("%s.post(%d)", SAVE_KEY, i - 1)
        setXMLInt(xmlFile, key .. "#id", post.id)
        setXMLInt(xmlFile, key .. "#authorId", post.authorId)
        setXMLString(xmlFile, key .. "#authorName", post.authorName)
        setXMLString(xmlFile, key .. "#title", post.title)
        setXMLString(xmlFile, key .. "#description", post.description)
        setXMLString(xmlFile, key .. "#category", post.category)
        setXMLInt(xmlFile, key .. "#payment", post.payment)
        local ca = post.createdAt or {}
        local caKey = key .. ".createdAt"
        setXMLInt(xmlFile, caKey .. "#day",    ca.day or 0)
        setXMLInt(xmlFile, caKey .. "#period", ca.period or 0)
        setXMLInt(xmlFile, caKey .. "#year",   ca.year or 1)
        setXMLInt(xmlFile, caKey .. "#hour",   ca.hour or 0)
        setXMLInt(xmlFile, caKey .. "#minute", ca.minute or 0)
    end

    local ok = saveXMLFile(xmlFile, path)
    delete(xmlFile)
    if ok then
        JournalLogger.info("JournalStorage", "Save successful")
    else
        JournalLogger.error("JournalStorage", "Failed to save XML file")
    end
end
