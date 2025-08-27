local table_pool = { tables = {}, used = {} }
for i = 1, 16, 1 do table.insert(table_pool.tables, i, {}) end

local M = {
    MAX_TIMEOUT = 2 ^ 31 - 1,
    EMPTY_STRING = "",
    EMPTY_TABLE = {}
}

function M.obtain_table(size)
    if #table_pool.tables > 0 then
        local tbl
        assert(not size or size >= 0)
        if size and size > 0 then
            local tables = table_pool.tables
            for i = 1, #tables, 1 do
                if #tables[i] >= size then
                    tbl = table.remove(tables, i)
                    break
                end
            end
        end
        if not tbl then
            tbl = table.remove(table_pool.tables)
        end
        table_pool.used[tbl] = true
        return tbl
    else
        local tbl = {}
        table_pool.used[tbl] = true
        return tbl
    end
end

function M.return_table(tbl)
    assert(table_pool.used[tbl])
    table_pool.used[tbl] = nil
    table.insert(table_pool.tables, tbl)
    table.sort(table_pool.tables, function(a, b)
        return #a < #b
    end)
    return tbl
end

function M.detach_table(tbl)
    assert(table_pool.used[tbl])
    table_pool.used[tbl] = nil
    return tbl
end

function M.attach_table(tbl)
    assert(not table_pool.used[tbl])
    table_pool.used[tbl] = true
    return tbl
end

function M.fill_table(tbl, value)
    if value == nil or #tbl == 0 then
        return tbl
    end
    for i = 1, #tbl, 1 do
        tbl[i] = value
    end
    assert(tbl[1] == tbl[#tbl])
    return tbl
end

function M.resize_table(tbl, size, default)
    assert(not size or size >= 0)
    if not size then
        return tbl
    elseif size > #tbl then
        for i = #tbl + 1, size, 1 do
            tbl[i] = default
        end
        return tbl
    elseif size < #tbl then
        for i = size + 1, #tbl, 1 do
            tbl[i] = nil
        end
        return tbl
    elseif size == 0 then
        for i = 1, #tbl, 1 do
            tbl[i] = nil
        end
        return tbl
    end
    return tbl
end

function M.compare_tables(t1, t2, visited)
    visited = visited or {}

    -- If both are the same object, they're equal
    if t1 == t2 then return true end

    -- Check if types are different
    if type(t1) ~= type(t2) then return false end

    -- Handle non-table types
    if type(t1) ~= "table" then
        return t1 == t2
    end

    -- Prevent infinite recursion on circular references
    if visited[t1] and visited[t1][t2] then return true end
    visited[t1] = visited[t1] or {}
    visited[t1][t2] = true

    -- Check if both are empty tables
    if next(t1) == nil and next(t2) == nil then return true end

    -- Check table size by counting elements
    local count1, count2 = 0, 0
    for _ in pairs(t1) do count1 = count1 + 1 end
    for _ in pairs(t2) do count2 = count2 + 1 end
    if count1 ~= count2 then return false end

    -- Recursively compare all key-value pairs
    for k, v1 in pairs(t1) do
        local v2 = t2[k]

        -- Check if key exists in both tables
        if v2 == nil then return false end

        -- Recursively compare values
        if not M.compare_tables(v1, v2, visited) then
            return false
        end
    end

    -- Also check that t2 doesn't have extra keys not in t1
    for k in pairs(t2) do
        if t1[k] == nil then return false end
    end

    return true
end

function M.time_execution(func, ...)
    local start_time = vim.loop.hrtime()

    local func_info = debug.getinfo(func, "nS")
    local func_name = func_info.name or "anonymous"
    local func_defined = func_info.short_src .. ":" .. func_info.linedefined

    local ok, result = pcall(func, ...)
    local end_time = vim.loop.hrtime()
    local duration_ms = (end_time - start_time) / 1e6

    vim.notify(string.format("[%s] Elapsed time: %.3f ms (defined at %s)",
        func_name, duration_ms, func_defined))
    assert(ok, string.format("Execution error: %s", result))
    return result
end

function M.debounce_callback(wait, callback)
    if assert(wait) and wait == 0 then
        return callback
    end
    local debounce_timer = nil
    return function(...)
        if debounce_timer and not debounce_timer:is_closing() then
            debounce_timer:close()
            debounce_timer = nil
        end
        local args = { ... }
        debounce_timer = vim.defer_fn(function()
            callback(unpack(args))
        end, wait)
    end
end

function M.safe_call(callback, ...)
    if callback ~= nil and type(callback) == "function" then
        local ok, res = pcall(callback, ...)
        if not ok and res and #res > 0 then
            vim.notify(res, vim.log.levels.ERROR)
            return nil, nil
        else
            return ok, res
        end
    end
    return nil, nil
end

return M
