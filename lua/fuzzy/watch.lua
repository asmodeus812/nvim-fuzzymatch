local M = {}

local watchers = {}

local function normalize_cwd(cwd)
    if type(cwd) == "function" then
        cwd = cwd()
    end
    if type(cwd) ~= "string" or #cwd == 0 then
        return nil
    end
    return vim.fs.normalize(cwd)
end

local function notify(entry, ...)
    for _, callback in pairs(entry.subscribers) do
        pcall(callback, ...)
    end
end

local function start_watchdirs(entry, cwd)
    -- if not vim._watch or type(vim._watch.watchdirs) ~= "function" then
    -- return
    -- end
    local ok, stop = pcall(vim._watch.watchdirs, cwd, {
        recursive = true,
        debounce = 100,
    }, function(fullpath, change_type)
        notify(entry, fullpath, change_type)
    end)
    if ok then
        entry.cancel = stop
    end
end

local function start_fs_event(entry, cwd)
    if not vim.loop or type(vim.loop.new_fs_event) ~= "function" then
        return
    end
    local handle = vim.loop.new_fs_event()
    if not handle then
        return
    end
    local ok = pcall(handle.start, handle, cwd, {}, function(err, fullpath, change_type)
        if err then
            return
        end
        notify(entry, fullpath, change_type)
    end)
    if ok then
        entry.cancel = function()
            pcall(handle.stop, handle)
            pcall(handle.close, handle)
        end
    else
        pcall(handle.close, handle)
    end
end

function M.subscribe(cwd, callback)
    local normalized = normalize_cwd(cwd)
    if not normalized or type(callback) ~= "function" then
        return function() end
    end
    local entry = watchers[normalized]
    if not entry then
        entry = { cancel = nil, subscribers = {} }
        watchers[normalized] = entry
        start_watchdirs(entry, normalized)
        if not entry.cancel then
            start_fs_event(entry, normalized)
        end
    end
    local id = tostring(callback) .. tostring(vim.loop.hrtime())
    entry.subscribers[id] = callback

    return function()
        if not entry.subscribers[id] then
            return
        end
        entry.subscribers[id] = nil
        if entry.cancel and next(entry.subscribers) == nil then
            pcall(entry.cancel)
            entry.cancel = nil
            watchers[normalized] = nil
        end
    end
end

return M
