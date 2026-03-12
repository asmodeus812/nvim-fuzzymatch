--- @class Pool
--- A global reusable table pool keyed by normalized sizes.
--- @field tables table[] Idle tables sorted by size (legacy/introspection view)
--- @field buckets table<integer, table[]> Idle tables grouped by normalized size
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
--- @field prime_chunk number
--- @field trace? fun(event: string, data: table)
local Pool = {}
Pool.__index = Pool

local DEFAULT_PRUNE_INTERVAL = 30000
local DEFAULT_PRIME_MIN = 16384
local DEFAULT_PRIME_MAX = 524288
local DEFAULT_PRIME_CHUNK = 8192

local function next_power_two(value)
    local n = 1
    while n < value do
        n = n * 2
    end
    return n
end

local function clamp_target_value(value, min, max)
    if value < min then
        return min
    end
    if value > max then
        return max
    end
    return value
end

local function bucket_size(size, min_size, max_size)
    if not size or size <= 0 then
        return nil
    end
    local bucket = next_power_two(size)
    return clamp_target_value(bucket, min_size, max_size)
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
        return bucket_size(size, Pool.prime_min, Pool.prime_max or size)
    end
    return size
end

local function remove_flat(tbl)
    for i = #Pool.tables, 1, -1 do
        if Pool.tables[i] == tbl then
            table.remove(Pool.tables, i)
            return
        end
    end
end

local function push_idle(tbl)
    local size = #tbl
    local bucket = Pool.buckets[size]
    if not bucket then
        bucket = {}
        Pool.buckets[size] = bucket
    end
    bucket[#bucket + 1] = tbl
    Pool.tables[#Pool.tables + 1] = tbl
    table.sort(Pool.tables, function(a, b)
        return #a < #b
    end)
    local meta = Pool.meta[tbl] or {}
    meta.size = size
    meta.last_used = Pool.now()
    Pool.meta[tbl] = meta
end

local function pop_bucket(size)
    local bucket = Pool.buckets[size]
    if not bucket or #bucket == 0 then
        return nil
    end
    local tbl = table.remove(bucket)
    if #bucket == 0 then
        Pool.buckets[size] = nil
    end
    remove_flat(tbl)
    return tbl
end

local function pop_smallest_fit(size)
    local candidate_size = nil
    for _, tbl in ipairs(Pool.tables) do
        local tbl_size = #tbl
        if tbl_size >= size then
            candidate_size = tbl_size
            break
        end
    end
    if candidate_size then
        return pop_bucket(candidate_size)
    end
    return nil
end

local function pop_largest()
    local tbl = Pool.tables[#Pool.tables]
    if not tbl then
        return nil
    end
    return pop_bucket(#tbl)
end

local function make_table(size)
    local tbl = {}
    if size and size > 0 then
        resize_table(tbl, size, false)
    end
    return tbl
end

function Pool._prime_step()
    -- priming removed; retained for compatibility with older tests/tools
end

function Pool._trim_step()
    -- trimming removed; retained for compatibility with older tests/tools
end

--- Create a new pool instance.
--- @param opts table|nil
--- @return Pool
function Pool.new(opts)
    assert(not Pool.tables)
    local self = Pool
    opts = opts or {}

    self.tables = {}
    self.buckets = {}
    self.used = {}
    self.meta = {}

    self.max_idle = opts.max_idle
    self.max_tables = opts.max_tables
    self.last_prune = 0
    self.prune_interval = opts.prune_interval or DEFAULT_PRUNE_INTERVAL
    self.now = opts.now or function()
        return vim.uv.hrtime() / 1e6
    end

    self.prime_min = opts.prime_min or DEFAULT_PRIME_MIN
    self.prime_max = opts.prime_max or DEFAULT_PRIME_MAX
    self.prime_chunk = opts.prime_chunk or DEFAULT_PRIME_CHUNK
    self.trace = opts.trace

    self.prune_timer = vim.uv.new_timer()
    self.prune_timer:start(self.prune_interval, self.prune_interval, function()
        Pool.last_prune = Pool.now()
        Pool.prune(Pool.last_prune)
    end)

    return self
end

--- Obtain a table from the pool, optionally specifying a minimum size.
--- @param size integer|nil
--- @return table
function Pool.obtain(size)
    assert(not size or size >= 0)
    local tbl
    local normalized = pooled_size(size or 0)

    if size and size > 0 then
        tbl = pop_smallest_fit(normalized)
        if not tbl then
            tbl = pop_largest()
        end
    else
        tbl = pop_largest()
    end

    if not tbl then
        tbl = make_table(normalized)
        trace("obtain_alloc", {
            requested = size or 0,
            actual = #tbl,
            target = normalized,
            tables = #Pool.tables,
        })
    else
        trace("obtain_reuse", {
            requested = size or 0,
            actual = #tbl,
            target = normalized,
            tables = #Pool.tables,
        })
    end

    Pool.used[tbl] = true
    local meta = Pool.meta[tbl] or {}
    meta.size = #tbl
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

    if Pool.max_tables == 0 then
        Pool.meta[tbl] = nil
        trace("return_discard", {
            actual = #tbl,
            tables = #Pool.tables,
            max_tables = 0,
        })
        return tbl
    end

    push_idle(tbl)
    trace("return", {
        actual = #tbl,
        tables = #Pool.tables,
    })

    if Pool.max_tables and Pool.max_tables > 0 and #Pool.tables > Pool.max_tables then
        Pool.prune(Pool.now())
    end

    return tbl
end

--- Attach a table to the pool as tracked (but not returned yet).
--- @param tbl table
function Pool.attach(tbl)
    assert(not Pool.used[tbl])
    Pool.used[tbl] = true
    Pool.meta[tbl] = Pool.meta[tbl] or {
        size = #tbl,
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

function Pool.fill(tbl, value)
    for i = 1, #tbl do
        tbl[i] = value
    end
    return tbl
end

function Pool.resize(tbl, size, default)
    return resize_table(tbl, size, default)
end

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
                local bucket = Pool.buckets[#tbl]
                if bucket then
                    for j = #bucket, 1, -1 do
                        if bucket[j] == tbl then
                            table.remove(bucket, j)
                            break
                        end
                    end
                    if #bucket == 0 then
                        Pool.buckets[#tbl] = nil
                    end
                end
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
            local bucket = Pool.buckets[#tbl]
            if bucket then
                for i = #bucket, 1, -1 do
                    if bucket[i] == tbl then
                        table.remove(bucket, i)
                        break
                    end
                end
                if #bucket == 0 then
                    Pool.buckets[#tbl] = nil
                end
            end
            Pool.meta[tbl] = nil
            trace("prune_max_tables", {
                actual = #tbl,
                tables = #Pool.tables,
                max_tables = max_tables,
            })
        end
        table.sort(Pool.tables, function(a, b)
            return #a < #b
        end)
    end
end

return Pool
