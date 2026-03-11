local M = {}
M._counts = {
    total = 0,
    spec = {},
    current = nil,
}

function M.count_table_entries(value)
    return vim.tbl_count(value or {})
end

function M.eq(actual, expected, message)
    if not vim.deep_equal(actual, expected) then
        error(message or "value mismatch")
    end
end

function M.setup_global_state()
    vim.o.swapfile = false
    vim.o.backup = false
    vim.o.writebackup = false
    vim.o.undofile = false
    vim.o.undodir = ""
    vim.o.directory = ""
    vim.o.shadafile = "NONE"
    vim.o.shada = ""
    vim.o.updatecount = 0
    vim.o.hidden = true
    vim.o.showmode = false
end

function M.setup_runtime()
    local cwd = vim.uv.cwd()
    vim.opt.rtp:prepend(cwd)
    local ok, fuzzy = pcall(require, "fuzzy")
    if ok and fuzzy and fuzzy.setup then
        fuzzy.setup({ override_select = false })
    end

    local ok_scheduler, Scheduler = pcall(require, "fuzzy.scheduler")
    if ok_scheduler and Scheduler and Scheduler.new then
        pcall(Scheduler.new, {})
    end
end

function M.open_buffers_picker(opts)
    local buffers_picker = require("fuzzy.pickers.buffers")
    local picker = buffers_picker.open_buffers_picker(opts or {})
    M.wait_for(function() return picker:isopen() end)
    return picker
end

function M.reset_state()
    pcall(function()
        local ok, registry = pcall(require, "fuzzy.registry")
        if ok and registry and registry.items then
            for picker, _ in pairs(registry.items) do
                if picker and picker.close then
                    picker:close()
                end
            end
        end
    end)
    pcall(function()
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            vim.api.nvim_set_option_value("winfixbuf", false, { win = win })
        end
    end)
    pcall(function()
        vim.cmd("silent! only")
        vim.cmd("enew")
    end)
end

function M.assert_ok(condition, message)
    assert(condition, message or "assert failed")
end

function M.assert_has_hl(extmarks, hl_name, label)
    local seen = {}
    for _, mark in ipairs(extmarks or {}) do
        local details = mark[4] or {}
        local name = details.hl_name or details.hl_group
        if name then
            seen[name] = true
        end
        if name == hl_name then
            return true
        end
    end
    local seen_list = {}
    for name, _ in pairs(seen) do
        seen_list[#seen_list + 1] = name
    end
    table.sort(seen_list)
    error((label or ("missing hl: " .. tostring(hl_name)))
        .. " (seen: " .. table.concat(seen_list, ", ") .. ")")
end

function M.create_named_buffer(name, lines, listed)
    local buf = vim.api.nvim_create_buf(listed ~= false, false)
    if name and #name > 0 then
        vim.api.nvim_buf_set_name(buf, name)
    end
    if lines and #lines > 0 then
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    end
    return buf
end

function M.create_temp_path(prefix)
    local pattern = prefix .. "XXXXXX"
    local fd, path = vim.uv.fs_mkstemp(pattern)
    if fd then
        vim.uv.fs_close(fd)
    end
    return path
end

function M.create_temp_dir()
    local base_dir = vim.uv.os_tmpdir()
    local dir_name = table.concat({ "fuzzy-tests-", tostring(vim.uv.hrtime()) })
    local full_path = vim.fs.joinpath(base_dir, dir_name)
    vim.uv.fs_mkdir(full_path, 448)
    return full_path
end

function M.type_query(picker, text)
    M.assert_ok(picker and picker.select, "picker not available")
    local select = picker.select
    local ready = M.wait_for(function()
        local buf = select and select.prompt_buffer or nil
        return buf and vim.api.nvim_buf_is_valid(buf)
    end, 1500)
    if not ready then
        return
    end
    local buf = select.prompt_buffer
    local next_text = text
    if text == "<c-u>" then
        next_text = ""
    end
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { next_text })
    vim.api.nvim_exec_autocmds({ "TextChangedI", "TextChangedP" }, {
        buffer = buf,
    })
    if next_text ~= "" then
        M.wait_for_prompt_text(picker, next_text)
    else
        M.wait_for(function()
            return (select:query() or "") == ""
        end, 1500)
    end
end

function M.get_query(picker)
    M.assert_ok(picker and picker.select, "picker not available")
    return picker.select:query()
end

function M.get_entries(picker)
    M.assert_ok(picker and picker.select, "picker not available")
    return picker.select._state.entries
end

function M.get_list_lines(picker)
    M.assert_ok(picker and picker.select, "picker not available")
    local buf = picker.select.list_buffer
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return {}
    end
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

function M.get_list_extmarks(picker, namespace)
    M.assert_ok(picker and picker.select, "picker not available")
    local buf = picker.select.list_buffer
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return {}
    end
    local namespaces = vim.api.nvim_get_namespaces()
    local ns = namespaces[namespace or "list_textline_namespace"]
    M.assert_ok(ns ~= nil, "namespace missing")
    return vim.api.nvim_buf_get_extmarks(
        buf,
        ns,
        0,
        -1,
        { details = true, hl_name = true }
    )
end

function M.wait_for(fn, timeout)
    timeout = timeout or 1500
    local mul = tonumber(
        vim.env.FUZZY_TEST_TIMEOUT_MULT or "1"
    )
    timeout = math.floor(timeout * mul)
    local ok = vim.wait(timeout, fn, 50)
    return ok
end

function M.wait_for_list_extmarks(picker, namespace, timeout)
    return M.wait_for(function()
        local extmarks = M.get_list_extmarks(picker, namespace)
        return extmarks and #extmarks > 0
    end, timeout or 1500)
end

function M.wait_for_list(picker, timeout)
    return M.wait_for(function()
        local lines = M.get_list_lines(picker)
        return lines and #lines > 0
    end, timeout or 1500)
end

function M.wait_for_entries(picker, timeout)
    return M.wait_for(function()
        local entries = M.get_entries(picker)
        return entries and #entries > 0
    end, timeout or 1500)
end

function M.wait_for_stream(picker, timeout)
    M.assert_ok(picker and picker.stream, "picker stream missing")
    local wait_timeout = timeout or 1500
    return picker.stream:wait(wait_timeout)
end

function M.wait_for_match(picker, timeout)
    M.assert_ok(picker and picker.match, "picker match missing")
    local wait_timeout = timeout or 1500
    return picker.match:wait(wait_timeout)
end

function M.wait_for_prompt_cursor(picker, timeout)
    return M.wait_for(function()
        local select = picker and picker.select or nil
        local win = select and select.prompt_window or nil
        if not win or not vim.api.nvim_win_is_valid(win) then
            return false
        end
        local query = assert(select):query() or ""
        local cursor = vim.api.nvim_win_get_cursor(win)
        return cursor[1] == 1
            and cursor[2] == vim.str_byteindex(query, #query)
    end, timeout or 1500)
end

function M.wait_for_prompt_text(picker, text, timeout)
    return M.wait_for(function()
        local select = picker and assert(picker.select)
        local buf = select.prompt_buffer or -1
        if not vim.api.nvim_buf_is_valid(buf) then
            return false
        end
        local lines = vim.api.nvim_buf_get_lines(buf, 0, 1, false)
        if lines and (lines[1] or ""):find(text, 1, true) == nil then
            return false
        end
        local query = select.query and select:query() or nil
        return query and query:find(text, 1, true) ~= nil
    end, timeout or 1500)
end

function M.wait_for_line_contains(picker, text, timeout)
    return M.wait_for(function()
        local lines = M.get_list_lines(picker)
        return M._line_contains(lines, text)
    end, timeout or 1500)
end

function M.write_file(file_path, text_value)
    local content_text = ""
    if type(text_value) == "table" then
        content_text = table.concat(text_value, "\n")
    elseif text_value ~= nil then
        content_text = tostring(text_value)
    end
    local fd = assert(vim.uv.fs_open(file_path, "w", 420))
    vim.uv.fs_write(fd, content_text)
    vim.uv.fs_close(fd)
end

function M.with_cwd(dir_path, callback)
    local prev_cwd = vim.uv.cwd()
    assert(prev_cwd)
    vim.uv.chdir(dir_path)
    local ok, err = pcall(callback)
    vim.uv.chdir(prev_cwd)
    if not ok then
        error(err)
    end
end

function M.run_test_case(name, callback)
    print(string.format("case: %s", tostring(name)))
    local current = M._counts.current or "unknown"
    M._counts.total = M._counts.total + 1
    M._counts.spec[current] = (M._counts.spec[current] or 0) + 1
    M.reset_state()
    local ok, err = pcall(callback)
    M.reset_state()
    if not ok then
        error(string.format("%s: %s", name, err))
    end
end

function M.start_spec(name)
    M._counts.current = tostring(name or "unknown")
    M._counts.spec[M._counts.current] = M._counts.spec[M._counts.current] or 0
end

function M.finish_spec(name)
    local spec_name = tostring(name or M._counts.current or "unknown")
    M._counts.current = nil
    return M._counts.spec[spec_name] or 0
end

function M.total_cases()
    return M._counts.total or 0
end

function M.with_mock(target, key, value, callback)
    local original = target[key]
    target[key] = value
    local ok, err = pcall(callback)
    target[key] = original
    if not ok then
        error(err)
    end
end

function M.with_mock_map(target, value_map, callback)
    local original_map = {}
    for key, value in pairs(value_map) do
        original_map[key] = target[key]
        target[key] = value
    end
    local ok, err = pcall(callback)
    for key, value in pairs(original_map) do
        target[key] = value
    end
    if not ok then
        error(err)
    end
end

function M.with_cmd_capture(callback)
    local calls = {}
    local original = vim.cmd
    local stub = {
        copen = function(...)
            calls[#calls + 1] = { kind = "copen", args = { ... } }
        end,
        lopen = function(...)
            calls[#calls + 1] = { kind = "lopen", args = { ... } }
        end,
        colorscheme = function(...)
            calls[#calls + 1] = { kind = "colorscheme", args = { ... } }
        end,
        normal = function(...)
            calls[#calls + 1] = { kind = "normal", args = { ... } }
        end,
        startinsert = function(...)
            calls[#calls + 1] = { kind = "startinsert", args = { ... } }
        end,
        stopinsert = function(...)
            calls[#calls + 1] = { kind = "stopinsert", args = { ... } }
        end,
        edit = function(...)
            calls[#calls + 1] = { kind = "edit", args = { ... } }
        end,
        redraw = function(...)
            calls[#calls + 1] = { kind = "redraw", args = { ... } }
        end,
    }
    setmetatable(stub, {
        __call = function(_, cmd)
            calls[#calls + 1] = { kind = "cmd", args = { cmd } }
        end,
        __index = function(_, key)
            return function(...)
                calls[#calls + 1] = { kind = tostring(key), args = { ... } }
            end
        end,
    })
    vim.cmd = stub
    local ok, err = pcall(callback, calls)
    vim.cmd = original
    if not ok then
        error(err)
    end
end

function M.is_window_valid(window_id)
    return window_id and vim.api.nvim_win_is_valid(window_id) or false
end

function M.is_buffer_valid(buffer_number)
    return buffer_number and vim.api.nvim_buf_is_valid(buffer_number) or false
end

function M.get_lines(buf, start, finish)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return {}
    end
    return vim.api.nvim_buf_get_lines(buf, start or 0, finish or -1, false)
end

function M.get_buffer_lines(buffer_number, start, finish)
    return M.get_lines(buffer_number, start, finish)
end

function M.get_buffer_line_count(buffer_number)
    if not buffer_number or not vim.api.nvim_buf_is_valid(buffer_number) then
        return 0
    end
    return vim.api.nvim_buf_line_count(buffer_number)
end

function M.assert_line_contains(lines, text, message)
    if M._line_contains(lines, text) then
        return
    end
    error(message or "missing text")
end

function M.assert_line_missing(lines, text, message)
    if M._line_contains(lines, text) then
        error(message or "unexpected text")
    end
end

function M._line_contains(lines, text)
    for _, line in ipairs(lines or {}) do
        if line:find(text, 1, true) then
            return true
        end
    end
    return false
end

function M.assert_list_contains(list, value, message)
    for _, item in ipairs(list or {}) do
        if item == value then
            return
        end
    end
    error(message or "missing value")
end

function M.assert_list_missing(list, value, message)
    for _, item in ipairs(list or {}) do
        if item == value then
            error(message or "unexpected value")
        end
    end
end

function M.close_picker(picker)
    if picker and picker.select then
        picker:close()
    end
end

return M
