local Async = require("fuzzy.async")
local Scheduler = require("fuzzy.scheduler")

--- @class Worker
--- Helpers to coordinate Async jobs without tying callers to Scheduler details.
---
--- Worker.coalesce()
---   Coalesces tasks into a single "latest wins" stream. If multiple tasks are
---   enqueued while a run is active, only the last pending task is kept and
---   executed after the current task yields. This is useful for UI rendering
---   where intermediate renders can be dropped safely.
---
--- Worker.queue()
---   Runs tasks in FIFO order. All enqueued tasks execute, one by one, yielding
---   between tasks to allow cooperative scheduling. This is used for strict
---   ordering requirements such as streaming output processing.
---
--- Both worker types:
---   - enqueue(fn): submit a task.
---   - finalize(fn): enqueue a final task and seal the worker. The final task
---     will run after pending tasks; no further enqueue calls are accepted.
---   - cancel(fn): abort pending work immediately, seal the worker, and run
---     optional cleanup callback.
---   - is_running(): returns whether a worker coroutine is currently active.
---
--- Tracing:
---   Worker.trace = function(event, data) ... end
---   Events include:
---     coalesce_enqueue, coalesce_start, coalesce_idle, coalesce_reschedule,
---     coalesce_finalize, coalesce_cancel,
---     queue_enqueue, queue_start, queue_idle, queue_reschedule,
---     queue_finalize, queue_cancel.
---   `data.enqueue` is provided for idle events and can be used for tests.
local Worker = {}

local function trace(event, data)
    if type(Worker.trace) == "function" then
        Worker.trace(event, data)
    end
end

--- Initialize the worker module and configure tracing.
--- @param opts table|nil
--- @return Worker
function Worker.new(opts)
    opts = opts or {}
    Worker.trace = opts.trace or nil
    return Worker
end

--- Create a coalescing worker.
--- @return table
local function make_coalescer()
    local running = false
    local pending = nil
    local current = nil
    local canceled = false
    local final = nil
    local sealed = false

    --- Internal: start an Async run for the coalescer.
    --- @return Async
    local function run()
        current = Async.new(function()
            while true do
                local fn = pending
                pending = nil
                if not fn then
                    break
                end
                fn()
                Async.yield()
                if canceled then
                    break
                end
            end
            trace("coalesce_idle", {
                running = running,
                pending = pending ~= nil,
                canceled = canceled,
                sealed = sealed,
                final = final ~= nil,
            })
            if not canceled and not pending and final then
                local fn = final
                final = nil
                fn()
            end
            running = false
            if not canceled and pending then
                running = true
                trace("coalesce_reschedule", { pending = true })
                local async = run()
                Scheduler.add(async)
            end
        end)
        return current
    end

    --- Enqueue a task, replacing any pending task.
    --- @param fn function
    --- @return Async|nil
    local function enqueue(fn)
        if sealed then
            return nil
        end
        pending = fn
        trace("coalesce_enqueue", {
            running = running,
            sealed = sealed,
        })
        if running then
            return nil
        end
        running = true
        canceled = false
        trace("coalesce_start", {})
        local async = run()
        Scheduler.add(async)
        return async
    end

    --- Seal the worker and run a final task after pending tasks complete.
    --- @param fn function
    --- @return Async|nil
    local function finalize(fn)
        final = fn
        sealed = true
        trace("coalesce_finalize", {
            running = running,
            sealed = sealed,
        })
        if running then
            return nil
        end
        running = true
        canceled = false
        trace("coalesce_start", {})
        local async = run()
        Scheduler.add(async)
        return async
    end

    --- Cancel any pending work and seal the worker.
    --- @param fn function|nil
    local function cancel(fn)
        canceled = true
        pending = nil
        final = nil
        sealed = true
        trace("coalesce_cancel", {
            running = running,
            sealed = sealed,
        })
        if current then
            current:cancel()
            current = nil
        end
        running = false
        if fn then
            fn()
        end
    end

    --- @return boolean
    local function is_running()
        return current ~= nil and current:is_running()
    end

    return {
        enqueue = enqueue,
        finalize = finalize,
        cancel = cancel,
        is_running = is_running,
    }
end

--- Create a FIFO worker.
--- @return table
local function make_queue()
    local running = false
    local queue = {}
    local current = nil
    local canceled = false
    local sealed = false

    --- Internal: start an Async run for the queue.
    --- @return Async
    local function run()
        current = Async.new(function()
            while true do
                local fn = table.remove(queue, 1)
                if not fn then
                    break
                end
                fn()
                Async.yield()
                if canceled then
                    break
                end
            end
            trace("queue_idle", {
                running = running,
                length = #queue,
                canceled = canceled,
                sealed = sealed,
            })
            running = false
            if not canceled and #queue > 0 then
                running = true
                trace("queue_reschedule", { length = #queue })
                local async = run()
                Scheduler.add(async)
            end
        end)
        return current
    end

    --- Enqueue a task to run in FIFO order.
    --- @param fn function
    --- @return Async|nil
    local function enqueue(fn)
        if sealed then
            return nil
        end
        table.insert(queue, fn)
        trace("queue_enqueue", {
            running = running,
            length = #queue,
            sealed = sealed,
        })
        if running then
            return nil
        end
        running = true
        canceled = false
        trace("queue_start", {})
        local async = run()
        Scheduler.add(async)
        return async
    end

    --- Seal the worker and enqueue a final task to run after all queued tasks.
    --- @param fn function
    --- @return Async|nil
    local function finalize(fn)
        sealed = true
        table.insert(queue, fn)
        trace("queue_finalize", {
            running = running,
            length = #queue,
            sealed = sealed,
        })
        if running then
            return nil
        end
        running = true
        canceled = false
        trace("queue_start", {})
        local async = run()
        Scheduler.add(async)
        return async
    end

    --- Cancel any pending work and seal the worker.
    --- @param fn function|nil
    local function cancel(fn)
        canceled = true
        queue = {}
        sealed = true
        trace("queue_cancel", {
            running = running,
            sealed = sealed,
        })
        if current then
            current:cancel()
            current = nil
        end
        running = false
        if fn then
            fn()
        end
    end

    --- @return boolean
    local function is_running()
        return current ~= nil and current:is_running()
    end

    return {
        enqueue = enqueue,
        finalize = finalize,
        cancel = cancel,
        is_running = is_running,
    }
end

--- Create a coalescing worker instance.
--- @return table
function Worker.coalesce()
    return make_coalescer()
end

--- Create a FIFO worker instance.
--- @return table
function Worker.queue()
    return make_queue()
end

return Worker
