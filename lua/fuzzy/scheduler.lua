--- @class Scheduler
--- Provides cooperative stateless scheduling for Async objects using a simple event queue and a time budget.
--- @field private _queue table Internal event queue for scheduled Async objects
--- @field private _budget number Time budget (in microseconds) allotted for async execution
--- @field private _executor uv_check_t libuv check handle used for driving the scheduler
--- @field trace? fun(event: string, data: table) Optional debug hook for scheduler lifecycle events
local Scheduler = {}
Scheduler.__index = Scheduler

local function trace(event, data)
    if Scheduler.trace then
        Scheduler.trace(event, data)
    end
end

--- Creates a new Scheduler instance and initializes the async queue.
--- @param opts table|nil Optional: {async_budget=number}
--- @return Scheduler
function Scheduler.new(opts)
    assert(not Scheduler._queue)
    opts = vim.tbl_deep_extend("force", {
        async_budget = 1 * 1e6,
    }, opts or {})

    Scheduler._queue = {}
    Scheduler._budget = assert(opts.async_budget)
    Scheduler._executor = assert(vim.uv.new_check())
    Scheduler.trace = opts.trace

    trace("scheduler_new", { budget = Scheduler._budget })
    return Scheduler
end

--- Processes the Scheduler's queue for up to the async budget or until the queue is empty.
function Scheduler.step()
    local budget = 1 * 1e6
    local start = vim.uv.hrtime()

    while #Scheduler._queue > 0 and vim.uv.hrtime() - start < budget do
        local async = table.remove(Scheduler._queue, 1)
        async:_step()
        if async:is_running() then
            table.insert(Scheduler._queue, async)
        end
    end

    if #Scheduler._queue == 0 then
        trace("scheduler_idle", { budget = budget })
        return Scheduler._executor:stop()
    end
end

--- Adds an Async object to the queue and starts execution if not already active.
--- @param async Async Async object to add to the scheduler
function Scheduler.add(async)
    assert(async and async._step)
    if not Scheduler._executor then
        Scheduler.new({})
    end
    table.insert(Scheduler._queue, async)
    if not Scheduler._executor:is_active() then
        local wrapped = vim.schedule_wrap(Scheduler.step)
        Scheduler._executor:start(assert(wrapped))
        trace("scheduler_start", { queued = #Scheduler._queue })
    end
end

--- Returns an Async object from the queue for the given thread if present, or nil.
--- @param thread thread The coroutine thread to find
--- @return Async|nil
function Scheduler.get(thread)
    for _, async in ipairs(Scheduler._queue or {}) do
        if assert(async.thread) == assert(thread) then
            return async
        end
    end
    return nil
end

--- Stop and close the scheduler executor.
function Scheduler.close()
    if Scheduler._executor and not vim.uv.is_closing(Scheduler._executor) then
        pcall(Scheduler._executor.stop, Scheduler._executor)
        pcall(Scheduler._executor.close, Scheduler._executor)
    end
    Scheduler._executor = nil
    Scheduler._queue = nil
    Scheduler._budget = nil
end

return Scheduler
