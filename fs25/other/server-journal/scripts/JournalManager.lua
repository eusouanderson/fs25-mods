JournalManager = {}
local JournalManager_mt = Class(JournalManager)

function JournalManager:init()
    JournalLogger.info("JournalManager", "Initializing")
    self.posts = {}
    self.nextId = 1
    self.isLoaded = false
    self.listeners = {}
    JournalLogger.info("JournalManager", "Initialized")
end

function JournalManager:loadFromSavegame()
    JournalLogger.info("JournalManager", "Loading from savegame")
    local posts, nextId = JournalStorage.load()
    self.posts = posts
    self.nextId = nextId
    self.isLoaded = true
    JournalLogger.info("JournalManager", "Loaded " .. #self.posts .. " posts, nextId=" .. self.nextId)
end

function JournalManager:saveToSavegame()
    JournalLogger.info("JournalManager", "Saving to savegame")
    JournalStorage.save(self.posts, self.nextId)
end

function JournalManager:addPost(authorId, authorName, title, description, category, payment)
    JournalLogger.info("JournalManager", "addPost called by=" .. authorName .. " title=" .. title)
    if g_server == nil then
        JournalLogger.warning("JournalManager", "Only server can add posts directly")
        return nil
    end
    local createdAt = {day=0, period=0, year=1, hour=0, minute=0}
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env ~= nil then
        local dayInPeriod = 0
        if env.getDayInPeriodFromDay then
            dayInPeriod = env:getDayInPeriodFromDay(env.currentDay or 0)
        end
        createdAt = {
            day    = dayInPeriod,
            period = env.currentPeriod or 0,
            year   = (env.currentYear or 1) + 1,
            hour   = env.currentHour or 0,
            minute = math.floor(((env.dayTime or 0) / 60000) % 60),
        }
    end

    local post = {
        id = self.nextId,
        authorId = authorId,
        authorName = authorName,
        title = title,
        description = description,
        category = category,
        payment = payment or 0,
        createdAt = createdAt,
    }
    self.nextId = self.nextId + 1
    table.insert(self.posts, post)
    JournalLogger.info("JournalManager", "Post created id=" .. post.id)
    self:saveToSavegame()
    JournalEvent.sendCreate(post)
    self:notifyListeners()
    return post
end

function JournalManager:removePost(id)
    JournalLogger.info("JournalManager", "removePost called for id=" .. id)
    if g_server == nil then
        JournalLogger.warning("JournalManager", "Only server can remove posts directly")
        return false
    end
    for i, post in ipairs(self.posts) do
        if post.id == id then
            table.remove(self.posts, i)
            JournalLogger.info("JournalManager", "Post " .. id .. " removed")
            self:saveToSavegame()
            JournalEvent.sendDelete(id)
            self:notifyListeners()
            return true
        end
    end
    JournalLogger.warning("JournalManager", "Post " .. id .. " not found for removal")
    return false
end

function JournalManager:getPosts()
    JournalLogger.info("JournalManager", "getPosts called, returning " .. #self.posts .. " posts")
    return self.posts
end

function JournalManager:getPostsByCategory(category)
    local filtered = {}
    for _, post in ipairs(self.posts) do
        if post.category == category then
            table.insert(filtered, post)
        end
    end
    JournalLogger.info("JournalManager", "getPostsByCategory " .. category .. " = " .. #filtered .. " posts")
    return filtered
end

function JournalManager:syncToClients()
    JournalLogger.info("JournalManager", "Syncing " .. #self.posts .. " posts to clients")
    JournalEvent.sendSync(self.posts)
end

function JournalManager:onReceiveCreate(postData)
    JournalLogger.info("JournalManager", "onReceiveCreate id=" .. postData.id .. " title=" .. postData.title)
    local exists = false
    for _, post in ipairs(self.posts) do
        if post.id == postData.id then
            exists = true
            JournalLogger.warning("JournalManager", "Duplicate post id " .. postData.id .. " ignored")
            break
        end
    end
    if not exists then
        table.insert(self.posts, postData)
        if postData.id >= self.nextId then
            self.nextId = postData.id + 1
        end
        JournalLogger.info("JournalManager", "Post accepted, total=" .. #self.posts)
        self:notifyListeners()
    end
end

function JournalManager:onReceiveDelete(postId)
    JournalLogger.info("JournalManager", "onReceiveDelete id=" .. postId)
    for i, post in ipairs(self.posts) do
        if post.id == postId then
            table.remove(self.posts, i)
            JournalLogger.info("JournalManager", "Post deleted, total=" .. #self.posts)
            self:notifyListeners()
            return
        end
    end
    JournalLogger.warning("JournalManager", "Post " .. postId .. " not found for deletion")
end

function JournalManager:onReceiveSync(posts)
    JournalLogger.info("JournalManager", "onReceiveSync with " .. #posts .. " posts")
    self.posts = posts
    self:notifyListeners()
end

function JournalManager:addListener(callback)
    table.insert(self.listeners, callback)
    JournalLogger.info("JournalManager", "Listener added, total=" .. #self.listeners)
end

function JournalManager:removeListener(callback)
    for i, cb in ipairs(self.listeners) do
        if cb == callback then
            table.remove(self.listeners, i)
            JournalLogger.info("JournalManager", "Listener removed, total=" .. #self.listeners)
            return
        end
    end
end

function JournalManager:notifyListeners()
    JournalLogger.info("JournalManager", "Notifying " .. #self.listeners .. " listeners")
    for _, callback in ipairs(self.listeners) do
        callback(self.posts)
    end
end
