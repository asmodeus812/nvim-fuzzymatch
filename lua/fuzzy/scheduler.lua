local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler.new(opts)
    assert(not Scheduler._queue)
    opts = vim.tbl_deep_extend("force", {
        async_budget = 1 * 1e6,
    }, opts or {})

    Scheduler._queue = {}
    Scheduler._budget = assert(opts.async_budget)
    Scheduler._executor = assert(vim.uv.new_check())

    return Scheduler
end

function Scheduler.step()
    local budget = 1 * 1e6
    local start = vim.uv.hrtime()

    while #Scheduler._queue > 0 and vim.uv.hrtime() - start < budget do
        local async = table.remove(Scheduler._queue, 1)
        if async:is_running() then
            table.insert(Scheduler._queue, async:_step())
        end
    end

    if #Scheduler._queue == 0 then
        return Scheduler._executor:stop()
    end
end

function Scheduler.add(async)
    assert(async and async._step)
    table.insert(Scheduler._queue, async)
    if not Scheduler._executor:is_active() then
        local wrapped = vim.schedule_wrap(Scheduler.step)
        Scheduler._executor:start(assert(wrapped))
    end
end

function Scheduler.get(thread)
    for _, async in ipairs(Scheduler._queue or {}) do
        if assert(async.thread) == assert(thread) then
            return async
        end
    end
    return nil
end

return Scheduler
