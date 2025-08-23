local table_pool = { tables = {}, used = {} }
for i = 1, 16, 1 do table.insert(table_pool.tables, i, {}) end

local M = {
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
    assert(size >= 0)
    if size > #tbl then
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

function M.time_execution(func, ...)
    local start_time = vim.loop.hrtime()
    local ok, result = pcall(func, ...)
    local end_time = vim.loop.hrtime()
    local duration_ms = (end_time - start_time) / 1e6

    vim.notify(string.format("Elapsed time: %.3f ms", duration_ms))
    assert(ok, string.format("Execution error: %s", result))
    return result
end

function M.debounce_callback(wait, callback)
    local debounce_timer = nil
    return function(args)
        if debounce_timer and not debounce_timer:is_closing() then
            debounce_timer:close()
            debounce_timer = nil
        end
        debounce_timer = vim.defer_fn(function()
            callback(args)
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
