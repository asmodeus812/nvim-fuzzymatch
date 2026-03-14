--- @class Pool
--- @field tables table[] Idle pooled tables
--- @field used table<table, boolean>
--- @field meta table<table, table>
--- @field max_idle number|nil
--- @field max_tables number|nil
--- @field prune_interval number
--- @field last_prune number
--- @field prune_timer uv_timer_t|nil
--- @field now fun(): number
--- @field prime_min number
--- @field prime_max number
--- @field trace? fun(event: string, data: table)
local Pool = {}
Pool.__index = Pool

local function next_power_two(value)
    local n = 1
    while n < value do
        n = n * 2
    end
    return n
end

local function clamp(value, min, max)
    if value < min then
        return min
    end
    if value > max then
        return max
    end
    return value
end

local function trace(event, data)
    if type(Pool.trace) == "function" then
        Pool.trace(event, data)
    end
end

local function resize_table(tbl, size, value)
    if size == nil or size < 0 then
        return tbl
    end

    local current = #tbl
    if size > current then
        for i = current + 1, size do
            tbl[i] = value
        end
    elseif size < current then
        for i = current, size + 1, -1 do
            tbl[i] = nil
        end
    end
    return tbl
end

local function pooled_size(size)
    if not size or size <= 0 then
        return 0
    end
    if Pool.prime_max and size > Pool.prime_max then
        return Pool.prime_max
    end
    if Pool.prime_min and size >= Pool.prime_min then
        return clamp(
            next_power_two(size),
            Pool.prime_min,
            Pool.prime_max or size
        )
    end
    return size
end

local function make_table(size)
    local tbl = {}
    if size and size > 0 then
        resize_table(tbl, size, false)
    end
    return tbl
end

local function push_idle(tbl)
    Pool.tables[#Pool.tables + 1] = tbl
    local meta = Pool.meta[tbl] or {}
    meta.last_used = Pool.now()
    Pool.meta[tbl] = meta
end

local function prime_tables(min_size, max_size)
    if not min_size or not max_size or min_size <= 0 or max_size < min_size then
        return
    end

    local size = next_power_two(min_size)
    while size <= max_size do
        push_idle(make_table(size))
        size = size * 2
    end
end

local function pop_largest()
    local index
    local largest = -1
    for i, tbl in ipairs(Pool.tables) do
        local size = #tbl
        if size > largest then
            largest = size
            index = i
        end
    end
    if not index then
        return nil
    end
    return table.remove(Pool.tables, index)
end

local function pop_fitting(size)
    local index
    local best_size
    for i, tbl in ipairs(Pool.tables) do
        local tbl_size = #tbl
        if tbl_size >= size and (best_size == nil or tbl_size < best_size) then
            best_size = tbl_size
            index = i
        end
    end
    if not index then
        return nil
    end
    return table.remove(Pool.tables, index)
end

--- Create a new pool instance.
--- @param opts table|nil
--- @return Pool
function Pool.new(opts)
    assert(not Pool.tables)
    local self = Pool
    opts = opts or {}

    self.used = {}
    self.meta = {}
    self.tables = {}

    self.now = opts.now or function()
        return vim.uv.hrtime() / 1e6
    end
    self.trace = opts.trace or nil

    self.max_idle = opts.max_idle or 300000
    self.max_tables = opts.max_tables or 64

    self.prime_min = opts.prime_min or 8192
    self.prime_max = opts.prime_max or 524288

    self.last_prune = 0
    self.prune_timer = assert(vim.uv.new_timer())
    self.prune_interval = opts.prune_interval or 30000
    self.prune_timer:start(self.prune_interval, self.prune_interval, function()
        Pool.last_prune = Pool.now()
        Pool.prune(Pool.last_prune)
    end)

    if opts.prime ~= false then
        prime_tables(
            self.prime_min,
            self.prime_max
        )
    end
    return self
end

--- Obtain a table from the pool, optionally specifying a minimum size.
--- @param size integer|nil
--- @return table
function Pool.obtain(size)
    assert(not size or size >= 0)

    local tbl, normalized = nil, 0
    if size then
        normalized = pooled_size(size)
        tbl = pop_fitting(normalized)
    end
    if not tbl then tbl = pop_largest() end

    if not tbl then
        tbl = make_table(normalized)
        trace("obtain_alloc", {
            requested = size,
            actual = #tbl,
            target = normalized,
            tables = #Pool.tables,
        })
    else
        trace("obtain_reuse", {
            requested = size,
            actual = #tbl,
            target = normalized,
            tables = #Pool.tables,
        })
    end

    Pool.used[tbl] = true
    local meta = Pool.meta[tbl] or {}
    meta.last_used = Pool.now()
    Pool.meta[tbl] = meta
    return tbl
end

--- Return a table to the pool, making it available for reuse.
--- @param tbl table
--- @return table
function Pool._return(tbl)
    assert(Pool.used[tbl])
    Pool.used[tbl] = nil

    local original = #tbl
    local target = pooled_size(original)
    if target ~= original then
        resize_table(tbl, target, false)
        trace("return_normalize", {
            actual = original,
            target = target,
            tables = #Pool.tables,
        })
    end

    push_idle(tbl)
    trace("return", {
        actual = #tbl,
        tables = #Pool.tables,
    })

    if #Pool.tables > Pool.max_tables then
        Pool.prune(Pool.now())
    end

    return tbl
end

--- Attach a table to the pool as tracked (but not returned yet).
--- @param tbl table
--- @return table
function Pool.attach(tbl)
    assert(not Pool.used[tbl])
    Pool.used[tbl] = true
    Pool.meta[tbl] = Pool.meta[tbl] or {
        last_used = Pool.now(),
    }
    trace("attach", {
        actual = #tbl,
        tables = #Pool.tables,
    })
    return tbl
end

--- Detach a table from the pool (no longer tracked).
--- @param tbl table
--- @return table
function Pool.detach(tbl)
    assert(Pool.used[tbl])
    Pool.used[tbl] = nil
    trace("detach", {
        actual = #tbl,
        tables = #Pool.tables,
    })
    return tbl
end

--- Check whether a table is tracked by the pool (in use or idle).
--- @param tbl table
--- @return boolean
function Pool.is_pooled(tbl)
    return Pool.used[tbl] == true or Pool.meta[tbl] ~= nil
end

function Pool.prune(now)
    if #Pool.tables == 0 then
        return
    end

    local max_idle = Pool.max_idle
    if max_idle and max_idle > 0 then
        for i = #Pool.tables, 1, -1 do
            local tbl = Pool.tables[i]
            local meta = Pool.meta[tbl]
            if meta and (now - meta.last_used) > max_idle then
                table.remove(Pool.tables, i)
                Pool.meta[tbl] = nil
                trace("prune_idle", {
                    actual = #tbl,
                    tables = #Pool.tables,
                })
            end
        end
    end

    local max_tables = Pool.max_tables
    if max_tables and max_tables > 0 and #Pool.tables > max_tables then
        table.sort(Pool.tables, function(a, b)
            local meta_a = Pool.meta[a]
            local meta_b = Pool.meta[b]
            local age_a = meta_a and meta_a.last_used or 0
            local age_b = meta_b and meta_b.last_used or 0
            return age_a < age_b
        end)

        while #Pool.tables > max_tables do
            local tbl = table.remove(Pool.tables, 1)
            Pool.meta[tbl] = nil
            trace("prune_max_tables", {
                actual = #tbl,
                tables = #Pool.tables,
                max_tables = max_tables,
            })
        end
    end
end

--- Stop and close the prune timer.
function Pool.close()
    if Pool.prune_timer and not vim.uv.is_closing(Pool.prune_timer) then
        pcall(Pool.prune_timer.stop, Pool.prune_timer)
        pcall(Pool.prune_timer.close, Pool.prune_timer)
    end
    Pool.prune_timer = nil
end

return Pool
