local utils = require("fuzzy.utils")

local Async = {}
Async.__index = Async

function Async.new(fn)
    local self = setmetatable({}, Async)
    self.callbacks = {}
    self.running = true
    self.thread = coroutine.create(fn)
    return self
end

function Async.wrap(fn)
    return function(...)
        local args = utils.table_pack(...)
        return Async.new(function()
            local ok, res = pcall(fn, utils.table_unpack(args))
            if not ok and res and #res > 0 then
                vim.api.nvim_err_writeln(res)
            end
            return res
        end)
    end
end

function Async.yield(...)
    if coroutine.running() == nil then
        error('Trying to yield from outside coroutine')
        return ...
    end
    return coroutine.yield(...)
end

function Async.kill()
    return Async.yield('abort')
end

function Async:_done(result, reason)
    if self.running then
        self.running = false
        self.result = result
        self.reason = reason
    end
    if not self.reason or self.reason ~= "abort" then
        for _, callback in ipairs(self.callbacks) do
            utils.safe_call(callback, result, reason)
        end
    end
    self.callbacks = {}
    return self
end

function Async:_step()
    local ok, reason = coroutine.resume(self.thread)
    if not ok then
        return self:_done(nil, reason)
    elseif reason == "abort" then
        return self:_done(nil, "abort")
    elseif coroutine.status(self.thread) == "dead" then
        return self:_done(reason)
    end
    return self
end

function Async:is_running()
    return self.running ~= false
end

function Async:stop_reason()
    return self.reason
end

function Async:cancel()
    self:_done(nil, "cancel")
end

function Async:abort()
    self:_done(nil, "abort")
end

function Async:await(callback)
    assert(type(callback) == "function")
    if self.running then
        table.insert(self.callbacks, callback)
    else
        utils.safe_call(callback, self.result, self.reason)
    end
end

function Async:wait(timeout)
    local done = vim.wait(timeout or utils.MAX_TIMEOUT, function()
        return self.running == false
    end, 25, true)

    if not done then
        self:cancel()
    end
    return self.reason and error(self.reason) or self.result
end

return Async
