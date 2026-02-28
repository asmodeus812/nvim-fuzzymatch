--- @class Pool
--- A pool class to efficiently reuse tables of varying sizes with light pruning.
--- @field tables table
--- @field used table
--- @field meta table
--- @field max_idle number|nil Maximum idle time in milliseconds before a pooled table is discarded
--- @field max_tables number|nil Maximum number of pooled tables to keep, older idle tables are discarded
--- @field prune_interval number Prune interval in milliseconds for the background cleanup timer
--- @field last_prune number Last prune timestamp in milliseconds
--- @field prune_timer uv_timer_t|nil Timer used to run periodic pruning
--- @field now fun(): number Returns a millisecond timestamp
local Pool = {}
Pool.__index = Pool

--- Create a new pool instance.
--- @param opts table|nil
---   opts.max_idle: Maximum idle time in milliseconds before a pooled table is discarded
---   opts.max_tables: Maximum number of pooled tables to keep
---   opts.prune_interval: Timer interval in milliseconds
---   opts.now: Optional time provider returning milliseconds
--- @return Pool
function Pool.new(opts)
    assert(not Pool.tables)
    local self = Pool
    opts = opts or {}
    self.tables = {}
    self.used = {}
    self.meta = {}
    self.max_idle = opts.max_idle
    self.max_tables = opts.max_tables
    self.prune_interval = opts.prune_interval or 30000
    self.last_prune = 0
    self.now = opts.now or function()
        return vim.uv.hrtime() / 1e6
    end
    self.prune_timer = vim.uv.new_timer()
    self.prune_timer:start(self.prune_interval, self.prune_interval, function()
        Pool.last_prune = Pool.now()
        Pool.prune(Pool.last_prune)
    end)
    return self
end

--- Obtain a table from the pool, optionally specifying a minimum size.
--- @param size integer|nil Minimum size needed
--- @return table Guaranteed table instance
function Pool.obtain(size)
    local tbl
    local now = Pool.now()
    assert(not size or size >= 0)
    if #Pool.tables > 0 then
        if size and size > 0 then
            for i = 1, #Pool.tables do
                if #Pool.tables[i] >= size then
                    tbl = table.remove(Pool.tables, i)
                    break
                end
            end
        end
        if not tbl then
            tbl = table.remove(Pool.tables)
        end
        Pool.used[tbl] = true
        local meta = Pool.meta[tbl]
        if not meta then
            Pool.meta[tbl] = {
                size = #tbl,
                last_used = now,
            }
        else
            meta.size = #tbl
            meta.last_used = now
        end
        return tbl
    end
    tbl = {}
    Pool.used[tbl] = true
    Pool.meta[tbl] = {
        size = 0,
        last_used = now,
    }
    return tbl
end

--- Return a table to the pool, making it available for reuse.
--- @param tbl table Table to release
--- @return table The same table
function Pool._return(tbl)
    assert(Pool.used[tbl])
    Pool.used[tbl] = nil
    table.insert(Pool.tables, tbl)
    local meta = Pool.meta[tbl]
    if not meta then
        Pool.meta[tbl] = { size = #tbl, last_used = Pool.now() }
    else
        meta.size = #tbl
        meta.last_used = Pool.now()
    end
    table.sort(Pool.tables, function(a, b)
        return #a < #b
    end)
    return tbl
end

--- Attach a table to the pool as tracked (but not returned yet).
--- @param tbl table Table to attach
function Pool.attach(tbl)
    assert(not Pool.used[tbl])
    Pool.used[tbl] = true
    if not Pool.meta[tbl] then
        Pool.meta[tbl] = { size = #tbl, last_used = Pool.now() }
    end
    return tbl
end

--- Detach a table from the pool (no longer tracked).
--- @param tbl table Table to detach
function Pool.detach(tbl)
    assert(Pool.used[tbl])
    Pool.used[tbl] = nil
    return tbl
end

--- Fill a table with a specified value (in-place).
--- @param tbl table Table to fill
--- @param value any Value to assign to all entries
function Pool.fill(tbl, value)
    for i = 1, #tbl do
        tbl[i] = value
    end
    if #tbl > 0 then
        assert(tbl[1] == tbl[#tbl])
    end
    return tbl
end

--- Resize a table to the specified size.
--- @param tbl table Table to resize
--- @param size integer|nil New size (or nil for no change)
--- @param default any Fill with this value if expanding
function Pool.resize(tbl, size, default)
    assert(not size or size >= 0)
    if not size then
        return tbl
    elseif size > #tbl then
        for i = #tbl + 1, size do
            tbl[i] = default
        end
        return tbl
    elseif size < #tbl then
        for i = size + 1, #tbl do
            tbl[i] = nil
        end
        return tbl
    elseif size == 0 then
        for i = 1, #tbl do
            tbl[i] = nil
        end
        return tbl
    end
    return tbl
end

--- Remove all elements from a table matching a value.
--- @param tbl table The table
--- @param o any Value to remove
--- @return boolean True if any were removed
function Pool.remove(tbl, o)
    assert(tbl and #tbl >= 0)
    local removed = false
    for i = #tbl, 1, -1 do
        if tbl[i] == o then
            table.remove(tbl, i)
            removed = true
        end
    end
    return removed
end

--- Prime the pool with tables of several different sizes. Only missing sizes are added.
--- @param sizes integer[] List of sizes to prime with
function Pool.prime(sizes)
    assert(type(sizes) == "table")
    for _, size in ipairs(sizes) do
        assert(type(size) == "number" and size > 0)
        local found = false
        for _, tbl in ipairs(Pool.tables) do
            if #tbl == size then
                found = true
                break
            end
        end
        if not found then
            local t = {}
            for i = 1, size do t[i] = false end
            table.insert(Pool.tables, t)
            Pool.meta[t] = {
                size = size,
                last_used = Pool.now(),
            }
        end
    end
    table.sort(Pool.tables, function(a, b)
        return #a < #b
    end)
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
        end
        table.sort(Pool.tables, function(a, b)
            return #a < #b
        end)
    end
end

return Pool
