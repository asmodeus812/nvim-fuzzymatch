local TEMPLATE = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'

local table_pool = { tables = {}, used = {} }
for i = 1, 16, 1 do table.insert(table_pool.tables, i, {}) end

math.randomseed(os.clock())
local random = math.random

--- @class Utils
--- A collection of utility functions and constants for various operations.
local M = {
    --- maximum timeout value for operations, set to the maximum positive 32-bit integer
    MAX_TIMEOUT = 2 ^ 31 - 1,
    --- An empty string constant, useful for avoiding repeated allocations
    EMPTY_STRING = "",
    --- An empty table constant, useful for avoiding repeated allocations
    EMPTY_TABLE = {},
}

--- Obtain a table from the pool, optionally specifying a minimum size, to look for a table of at least that size If no such table is
--- found, a new table is created
--- @param size integer|nil Minimum size of the table to obtain
--- @return table The obtained table
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

--- Return a table to the pool, making it available for reuse. The table becomes valid for reuse after this call, and can be pulled from
--- the pool by using the obtain_table function.
--- @param tbl table The table to return to the pool
--- @return table The same table that was returned to the pool
function M.return_table(tbl)
    assert(table_pool.used[tbl])
    table_pool.used[tbl] = nil
    table.insert(table_pool.tables, tbl)
    table.sort(table_pool.tables, function(a, b)
        return #a < #b
    end)
    return tbl
end

--- Detach a table from the pool without returning it, making it no longer tracked by the pool. The table becomes the caller's
--- responsibility after this call, and will not be reused by the pool.
--- @param tbl table The table to detach from the pool
function M.detach_table(tbl)
    assert(table_pool.used[tbl])
    table_pool.used[tbl] = nil
    return tbl
end

--- Attach a table to the pool, making it tracked by the pool. The table is not returned to the pool yet, but can be returned later
--- using the return_table function.
--- @param tbl table The table to attach to the pool
function M.attach_table(tbl)
    assert(not table_pool.used[tbl])
    table_pool.used[tbl] = true
    return tbl
end

--- Fill a table with a specified value. If the value is nil or the table is empty, the table is returned unchanged. The function
--- asserts that the first and last elements of the table are equal after filling.
--- @param tbl table The table to fill
--- @param value any The value to fill the table with
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

--- Resize a table to a specified size, filling new elements with a default value if the table is expanded, or removing elements if the
--- table is shrunk. If the size is nil, the table is returned unchanged.
--- @param tbl table The table to resize
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

--- Deeply compare two tables for equality, handling nested tables and circular references. The function returns true if the tables are
--- equal, and false otherwise.
--- @param t1 table The first table to compare
--- @param t2 table The second table to compare
--- @param visited? table|nil A table to track visited tables during recursion (used internally)
--- @return boolean True if the tables are equal, false otherwise
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

--- Removes all elements form a table matching by value. If at least one element is removed, the function returns true, otherwise false.
--- @param tbl table The table to remove the element from
--- @param o any The element to remove by value
function M.table_remove(tbl, o)
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

--- Measure and log the execution time of a function, including its name and definition location. The function is called with the provided arguments, and any errors during execution are propagated.
--- @param func function The function to measure
--- @param ... any Arguments to pass to the function
--- @return any The result of the function call
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

--- Print the current stack trace to the Neovim message area, starting from the caller of this function. Each stack frame includes the
--- function name, source file, and line number. Anonymous functions are labeled as "anonymous", and missing information is indicated as
--- "unknown".
function M.print_stacktrace()
    local level = 2 -- Start from caller of this function
    vim.print("Stacktrace:")

    while true do
        local info = debug.getinfo(level, "nSl")
        if not info then break end

        local func_name = info.name or "anonymous"
        local source = info.short_src or "unknown"
        local line = info.currentline or 0

        vim.print(string.format(
            "- [%d] %s @ %s:%d",
            level - 1,
            func_name,
            source,
            line
        ))
        level = level + 1
    end
end

--- Create a debounced version of a callback function, which delays its execution until after a specified wait time has elapsed since
--- the last time it was invoked. If the wait time is 0, the original callback is returned.
--- @param wait integer The wait time in milliseconds
--- @param callback function The callback function to debounce
--- @return function The debounced callback function
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

--- Safely call a callback function with provided arguments, catching any errors and notifying the user if an error occurs. If the
--- @param callback function|nil The callback function to call
--- @param ... any Arguments to pass to the callback function
--- @return boolean|nil, any|nil True if the call was successful, False if an error occurred, or nil if the callback was nil or not a
--- function
function M.safe_call(callback, ...)
    if callback ~= nil and type(callback) == "function" then
        local ok, res = pcall(callback, ...)
        if not ok and res and #res > 0 then
            vim.notify(res, vim.log.levels.ERROR)
        end
        return ok, res
    end
    return nil, nil
end

--- Generate a UUID based on a template, from a random seeded set of alpha-numeric symbols and
--- @return string the generated UUID string.
function M.generate_uuid()
    return random and string.gsub(TEMPLATE, '[xy]', function(c)
        local v = (c == 'x') and random(0, 0xf) or random(8, 0xb)
        return string.format('%x', v)
    end)
end

--- Check if a given window ID corresponds to a quickfix or location list window. The function returns true for quickfix windows, false otherwise
--- @param bufnr integer The buffer number to check
--- @param bufinfo table Optional buffer info table to use instead of fetching it
function M.is_quickfix(bufnr, bufinfo)
    bufinfo = bufinfo or (vim.api.nvim_buf_is_valid(bufnr) and M.get_bufinfo(bufnr))
    if bufinfo and bufinfo.variables
        and bufinfo.variables.current_syntax == "qf"
        and not vim.tbl_isempty(bufinfo.windows)
    then
        -- TODO: finish this implementation !!
        return M.win_is_qf(bufinfo.windows[1])
    end
    return false
end

--- Get the buffer info for a given buffer number using the 'fuzzymatch#getbufinfo' Vim function. The function returns a table containing the buffer number and its associated info.
--- @param buf integer The buffer number to get info for
--- @return table A table containing the buffer number and its associated info
function M.get_bufinfo(buf)
    return {
        bufnr = buf,
        info = vim.fn["fuzzymatch#getbufinfo"](buf)
    }
end

--- Get the buffer name for a given buffer number, handling special cases for quickfix and location list buffers. If the buffer is invalid, nil is returned.
--- If the buffer has no name, a placeholder name is returned based on whether it is a quickfix/location list or an unnamed buffer.
--- @param bufnr integer The buffer number to get the name for
--- @param bufinfo table Optional buffer info table to use instead of fetching it
--- @return string|nil The buffer name, or nil if the buffer is invalid
function M.get_bufname(bufnr, bufinfo)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end
    if bufinfo and bufinfo.name and #bufinfo.name > 0 then
        return bufinfo.name
    end
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    if #bufname == 0 then
        local is_qf = M.is_quickfix(bufnr, bufinfo)
        if is_qf then
            bufname = is_qf == 1 and "[Quickfix List]" or "[Location List]"
        else
            bufname = "[No Name]"
        end
    end
    assert(#bufname > 0)
    return bufname
end

return M
