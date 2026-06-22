JournalEvent = {}
local JournalEvent_mt = Class(JournalEvent, Event)

InitEventClass(JournalEvent, "JournalEvent")
JournalLogger.info("JournalEvent", "Event class initialized")

JournalEvent.TYPE_CREATE = 1
JournalEvent.TYPE_DELETE = 2
JournalEvent.TYPE_SYNC = 3

function JournalEvent.emptyNew()
    return Event.new(JournalEvent_mt)
end

function JournalEvent.new(eventType, postData)
    local self = JournalEvent.emptyNew()
    self.eventType = eventType
    self.postData = postData
    return self
end

function JournalEvent:writeStream(streamId, connection)
    JournalLogger.info("JournalEvent", "Writing stream, type=" .. self.eventType)
    streamWriteUInt8(streamId, self.eventType)
    if self.eventType == JournalEvent.TYPE_SYNC then
        local count = #self.postData
        JournalLogger.info("JournalEvent", "Writing sync with " .. count .. " posts")
        streamWriteUInt16(streamId, count)
        for _, post in ipairs(self.postData) do
            JournalEvent.writePost(streamId, post)
        end
    elseif self.eventType == JournalEvent.TYPE_DELETE then
        streamWriteInt32(streamId, self.postData.id)
    elseif self.postData ~= nil then
        JournalEvent.writePost(streamId, self.postData)
    end
end

function JournalEvent:readStream(streamId, connection)
    self.eventType = streamReadUInt8(streamId)
    JournalLogger.info("JournalEvent", "Reading stream, type=" .. self.eventType)
    if self.eventType == JournalEvent.TYPE_SYNC then
        local count = streamReadUInt16(streamId)
        JournalLogger.info("JournalEvent", "Reading sync with " .. count .. " posts")
        self.postData = {}
        for _ = 1, count do
            table.insert(self.postData, JournalEvent.readPost(streamId))
        end
    elseif self.eventType == JournalEvent.TYPE_CREATE then
        self.postData = JournalEvent.readPost(streamId)
    elseif self.eventType == JournalEvent.TYPE_DELETE then
        self.postData = { id = streamReadInt32(streamId) }
    end
    self:run(connection)
end

function JournalEvent:run(connection)
    JournalLogger.info("JournalEvent", "Running event type=" .. self.eventType .. ", server=" .. tostring(g_server ~= nil) .. ", isServerConn=" .. tostring(connection ~= nil and connection:getIsServer()))
    if g_server ~= nil and connection ~= nil and not connection:getIsServer() then
        JournalLogger.info("JournalEvent", "Server received from client, validating")
        if self.eventType == JournalEvent.TYPE_CREATE then
            local authorId = self.postData.authorId
            local authorName = self.postData.authorName
            if g_currentMission ~= nil and g_currentMission.userManager ~= nil then
                local user = g_currentMission.userManager:getUserByConnection(connection)
                if user ~= nil then
                    authorId = user.userId or authorId
                    authorName = user.nickname or authorName
                end
            end
            g_journalManager:addPost(
                authorId,
                authorName,
                self.postData.title,
                self.postData.description,
                self.postData.category,
                self.postData.payment
            )
        elseif self.eventType == JournalEvent.TYPE_DELETE then
            local requesterId = nil
            local isAdmin = false
            if g_currentMission ~= nil and g_currentMission.userManager ~= nil then
                local user = g_currentMission.userManager:getUserByConnection(connection)
                if user ~= nil then
                    requesterId = user.userId
                    isAdmin = g_currentMission:getIsMasterUser(user.userId)
                end
            end
            g_journalManager:removePost(self.postData.id, requesterId, isAdmin)
        end
        return
    end
    if g_journalManager ~= nil then
        JournalLogger.info("JournalEvent", "Applying event to local manager")
        if self.eventType == JournalEvent.TYPE_CREATE then
            g_journalManager:onReceiveCreate(self.postData)
        elseif self.eventType == JournalEvent.TYPE_DELETE then
            g_journalManager:onReceiveDelete(self.postData.id)
        elseif self.eventType == JournalEvent.TYPE_SYNC then
            g_journalManager:onReceiveSync(self.postData)
        end
    else
        JournalLogger.warning("JournalEvent", "g_journalManager is nil, cannot apply event")
    end
end

function JournalEvent.writePost(streamId, post)
    streamWriteInt32(streamId, post.id)
    streamWriteInt32(streamId, post.authorId)
    streamWriteString(streamId, post.authorName)
    streamWriteString(streamId, post.title)
    streamWriteString(streamId, post.description)
    streamWriteString(streamId, post.category)
    streamWriteInt32(streamId, post.payment)
    local ca = post.createdAt or {}
    streamWriteUInt8(streamId, ca.day or 0)
    streamWriteUInt8(streamId, ca.period or 0)
    streamWriteUInt16(streamId, ca.year or 1)
    streamWriteUInt8(streamId, ca.hour or 0)
    streamWriteUInt8(streamId, ca.minute or 0)
    streamWriteInt32(streamId, ca.currentDay or 0)
end

function JournalEvent.readPost(streamId)
    local post = {
        id        = streamReadInt32(streamId),
        authorId  = streamReadInt32(streamId),
        authorName = streamReadString(streamId),
        title     = streamReadString(streamId),
        description = streamReadString(streamId),
        category  = streamReadString(streamId),
        payment   = streamReadInt32(streamId),
        createdAt = {
            day    = streamReadUInt8(streamId),
            period = streamReadUInt8(streamId),
            year   = streamReadUInt16(streamId),
            hour   = streamReadUInt8(streamId),
            minute = streamReadUInt8(streamId),
            currentDay = streamReadInt32(streamId),
        },
    }
    JournalLogger.info("JournalEvent", "Read post id=" .. post.id .. " title=" .. post.title)
    return post
end

function JournalEvent.sendCreate(postData)
    JournalLogger.info("JournalEvent", "Sending create event for post id=" .. postData.id)
    if g_server ~= nil then
        g_server:broadcastEvent(JournalEvent.new(JournalEvent.TYPE_CREATE, postData))
    elseif g_client ~= nil then
        local conn = g_client:getServerConnection()
        if conn then
            conn:sendEvent(JournalEvent.new(JournalEvent.TYPE_CREATE, postData))
        end
    end
end

function JournalEvent.sendDelete(postId)
    JournalLogger.info("JournalEvent", "Sending delete event for post id=" .. postId)
    local postData = { id = postId }
    if g_server ~= nil then
        g_server:broadcastEvent(JournalEvent.new(JournalEvent.TYPE_DELETE, postData))
    elseif g_client ~= nil then
        local conn = g_client:getServerConnection()
        if conn then
            conn:sendEvent(JournalEvent.new(JournalEvent.TYPE_DELETE, postData))
        end
    end
end

function JournalEvent.sendSync(posts)
    JournalLogger.info("JournalEvent", "Sending sync with " .. #posts .. " posts")
    if g_server ~= nil then
        g_server:broadcastEvent(JournalEvent.new(JournalEvent.TYPE_SYNC, posts))
    end
end
