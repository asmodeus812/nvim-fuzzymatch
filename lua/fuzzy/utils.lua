local TEMPLATE = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'

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



--- Fill a table with a specified value. If the value is nil or the table is empty, the table is returned unchanged. The function
--- asserts that the first and last elements of the table are equal after filling.
--- @param tbl table The table to fill
--- @param value any|nil The value to fill the table with
function M.fill_table(tbl, value)
    for i = 1, #tbl, 1 do
        tbl[i] = value
    end
    assert(tbl[1] == tbl[#tbl])
    return tbl
end

--- Resize a table to a specified size, filling new elements with a default value if the table is expanded, or removing elements if the
--- table is shrunk. If the size is nil, the table is returned unchanged.
--- @param tbl table The table to resize
--- @param size integer|nil The desired size of the table, or nil to leave unchanged
--- @param default any|nil The default value to fill new elements with when expanding the table
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

--- Pack variable arguments into a table, including the count of arguments as the 'n' field. This is useful for preserving nil values. To use this
--- @param ... any Variable arguments to pack
--- @return table A table containing the packed arguments and the count in the 'n' field
function M.table_pack(...)
    return { n = select("#", ...), ... }
end

--- Unpack a table that was packed using the table_pack function, returning the original variable arguments. The function uses the 'n' field to determine the number of elements to unpack, ensuring that nil values are preserved.
--- @param tbl table The table to unpack
--- @return ... The unpacked variable arguments
function M.table_unpack(tbl)
    return unpack(assert(tbl), 1, assert(tbl.n))
end

--- Get the current or last visual selection as plain text.
--- Returns nil when no selection is available.
--- @return string|nil
function M.get_visual_text()
    local start_mark_position = vim.fn.getpos("'<")
    local end_mark_position = vim.fn.getpos("'>")
    if not start_mark_position or not end_mark_position then
        return nil
    end
    local start_row_number = start_mark_position[2]
    local start_col_number = start_mark_position[3]
    local end_row_number = end_mark_position[2]
    local end_col_number = end_mark_position[3]
    if start_row_number == 0 or end_row_number == 0 then
        return nil
    end
    if start_row_number > end_row_number
        or (start_row_number == end_row_number
            and start_col_number > end_col_number) then
        start_row_number, end_row_number = end_row_number, start_row_number
        start_col_number, end_col_number = end_col_number, start_col_number
    end
    local line_text_list = vim.api.nvim_buf_get_lines(
        0,
        start_row_number - 1,
        end_row_number,
        false
    )
    if not line_text_list or #line_text_list == 0 then
        return nil
    end
    local visual_mode_value = vim.fn.visualmode()
    if visual_mode_value ~= "V" then
        line_text_list[1] = line_text_list[1]:sub(start_col_number)
        line_text_list[#line_text_list] = line_text_list[#line_text_list]
            :sub(1, end_col_number)
    end
    return table.concat(line_text_list, "\n")
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

--- Print the current stack trace to the Neovim message area, starting from the caller of this function. Each stack frame includes the function name, source file, and line number. Anonymous functions are labeled as "anonymous", and missing information is indicated as "unknown".
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

--- Create a debounced version of a callback function, which delays its execution until after a specified wait time has elapsed since the last time it was invoked. If the wait time is 0, the original callback is returned.
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
        local args = M.table_pack(...)
        debounce_timer = vim.defer_fn(function()
            callback(M.table_unpack(args))
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

--- Check if a window is a quickfix or location list window.
--- @param winid integer
--- @return integer|false 1 for quickfix, 2 for loclist, false otherwise
function M.win_is_qf(winid)
    if not winid or winid == 0 then
        return false
    end
    local info = vim.fn["fuzzymatch#getwininfo"](winid)
    if not info or vim.tbl_isempty(info) then
        return false
    end
    if info.quickfix == 1 then
        return info.loclist == 1 and 2 or 1
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

--- Get the buffer name for a given buffer number, handling special cases for quickfix and location list buffers. If the buffer is invalid, nil is returned. If the buffer has no name, a placeholder name is returned based on whether it is a quickfix/location list or an unnamed buffer.
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
