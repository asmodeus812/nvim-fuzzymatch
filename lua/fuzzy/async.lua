local utils = require("fuzzy.utils")

--- @class Async
--- Provides simple coroutine-based async job handling with callback and scheduling support for cooperative concurrency in Neovim. Handles running, cancellation, errors, and callback registration for asynchronous routines.
--- @field private callbacks table List of callback functions to be invoked after completion
--- @field private running boolean Indicates whether the Async job is still running
--- @field private thread thread Coroutine object executing the async function
local Async = {}
Async.__index = Async

--- Creates a new Async object wrapping the given function in a coroutine.
--- @param fn function Function to run in the coroutine context
--- @return Async
function Async.new(fn)
    local self = setmetatable({}, Async)
    self.callbacks = {}
    self.running = true
    self.thread = coroutine.create(fn)
    return self
end

--- Wraps a function for execution as an Async coroutine.
--- @param fn function Function to wrap
--- @return function Returns a function, which when called, creates an Async object
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

--- Yield coroutine execution, compatible with Async and other coroutines.
--- @param ... any Passed through to coroutine.yield
--- @return any Any yielded values
function Async.yield(...)
    if coroutine.running() == nil then
        error('Trying to yield from outside coroutine')
        return ...
    end
    return coroutine.yield(...)
end

--- Yields with an 'abort' marker for cooperative cancellation.
function Async.kill()
    return Async.yield('abort')
end

--- Marks this async as done, sets result/reason, and notifies callbacks.
--- @param result any
--- @param reason string|nil
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

--- Steps/resumes coroutine execution once, handles errors, cancellation, or marks as done.
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

--- Returns true if the async job is still running (not done).
--- @return boolean
function Async:is_running()
    return self.running ~= false
end

--- Returns stop reason if present (e.g., 'abort', 'cancel', or error).
--- @return string|nil
function Async:stop_reason()
    return self.reason
end

--- Cancels the async, marking it as done with the reason 'cancel'.
function Async:cancel()
    self:_done(nil, "cancel")
end

--- Aborts the async, marking it done with 'abort'.
function Async:abort()
    self:_done(nil, "abort")
end

--- Registers a callback for when the async completes, or calls it immediately if already done (unless aborted).
--- @param callback function Function to call on completion
function Async:await(callback)
    assert(type(callback) == "function")
    if self.running ~= false then
        table.insert(self.callbacks, callback)
    elseif self.reason ~= "abort" then
        utils.safe_call(callback, self.result, self.reason)
    end
end

--- Synchronously waits for the async to complete, with optional timeout in ms.
--- @param timeout number|nil Milliseconds to wait
--- @return any Result of the coroutine, or error if not completed
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
