local async = {}
local Scheduler = {}

Scheduler._queue = {}
Scheduler._executor = assert(vim.uv.new_check())

function Scheduler.step()
    local start = vim.uv.hrtime()
    local budget = 5 * 1e6

    while #Scheduler._queue > 0 and vim.uv.hrtime() - start < budget do
        local a = table.remove(Scheduler._queue, 1)
        a:_step()
        if a.running then
            table.insert(Scheduler._queue, a)
        end
    end

    if #Scheduler._queue == 0 then
        return Scheduler._executor:stop()
    end
end

function Scheduler.add(a)
    table.insert(Scheduler._queue, a)
    if not Scheduler._executor:is_active() then
        Scheduler._executor:start(vim.schedule_wrap(Scheduler.step))
    end
end

local Async = {}
Async.__index = Async

function Async.new(fn)
    local self = setmetatable({}, Async)
    self.callbacks = {}
    self.running = true
    self.thread = coroutine.create(fn)
    Scheduler.add(self)
    return self
end

function Async:_done(result, error)
    if self.running then
        self.running = false
        self.result = result
        self.error = error
    end
    for _, callback in ipairs(self.callbacks) do
        callback(result, error)
    end
    self.callbacks = {}
end

function Async:_step()
    local ok, res = coroutine.resume(self.thread)
    if not ok then
        return self:_done(nil, res)
    elseif res == 'abort' then
        return self:_done(nil, 'abort')
    elseif coroutine.status(self.thread) == 'dead' then
        return self:_done(res)
    end
end

function Async:cancel()
    self:_done(nil, 'abort')
end

function Async:await(cb)
    if not cb then
        error('callback is required')
    end
    if self.running then
        table.insert(self.callbacks, cb)
    else
        cb(self.result, self.error)
    end
end

function Async:sync()
    while self.running do
        vim.wait(10)
    end
    return self.error and error(self.error) or self.result
end

function async.wrap(fn)
    return function(...)
        local args = { ... }
        Async.new(function()
            local ok, res = pcall(fn, unpack(args))
            if not ok and res and #res > 0 then
                vim.api.nvim_err_writeln(res)
            end
            return res
        end)
    end
end

function async.yield(...)
    if coroutine.running() == nil then
        error('Trying to yield from outside coroutine')
        return ...
    end
    return coroutine.yield(...)
end

function async.abort()
    return async.yield('abort')
end

return async
