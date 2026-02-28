local M = {}

local function termcodes(keys)
    return vim.api.nvim_replace_termcodes(keys, true, false, true)
end

local function feed(keys)
    vim.api.nvim_feedkeys(termcodes(keys), "n", false)
end

function M.assert_ok(condition, message)
    assert(condition, message or "assert failed")
end

function M.eq(actual, expected, message)
    if not vim.deep_equal(actual, expected) then
        error(message or "value mismatch")
    end
end

function M.wait_for(fn, timeout)
    local ok = vim.wait(timeout or 2000, fn, 10)
    return ok
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

function M.reset_state()
    if vim.wo then
        pcall(function() vim.wo.winfixbuf = false end)
    end
    pcall(vim.cmd, "silent! only")
    pcall(vim.cmd, "enew")
end

function M.open_buffers_picker(opts)
    local buffers_picker = require("fuzzy.pickers.buffers")
    local picker = buffers_picker.open_buffers_picker(opts or {})
    M.wait_for(function()
        return picker and picker.select and picker.select:isopen()
    end, 2000)
    return picker
end

function M.type_query(picker, text)
    M.assert_ok(picker and picker.select, "picker not available")
    picker.select:position_prompt(text)
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

function M.wait_for_list(picker)
    return M.wait_for(function()
        local lines = M.get_list_lines(picker)
        return lines and #lines > 0
    end, 2000)
end

function M.wait_for_line_contains(picker, text)
    return M.wait_for(function()
        local lines = M.get_list_lines(picker)
        for _, line in ipairs(lines or {}) do
            if line:find(text, 1, true) then
                return true
            end
        end
        return false
    end, 2000)
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

function M.create_temp_dir()
    local base_dir = vim.uv.os_tmpdir()
    local dir_name = table.concat({ "fuzzy-tests-", tostring(vim.uv.hrtime()) })
    local full_path = vim.fs.joinpath(base_dir, dir_name)
    vim.uv.fs_mkdir(full_path, 448)
    return full_path
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
    vim.uv.chdir(dir_path)
    local ok, err = pcall(callback)
    vim.uv.chdir(prev_cwd)
    if not ok then
        error(err)
    end
end

function M.run_test_case(name, callback)
    M.reset_state()
    local ok, err = pcall(callback)
    if not ok then
        error(string.format("%s: %s", name, err))
    end
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

function M.is_window_valid(window_id)
    return window_id and vim.api.nvim_win_is_valid(window_id) or false
end

function M.is_buffer_valid(buffer_number)
    return buffer_number and vim.api.nvim_buf_is_valid(buffer_number) or false
end

function M.get_buffer_line_count(buffer_number)
    if not buffer_number or not vim.api.nvim_buf_is_valid(buffer_number) then
        return 0
    end
    return vim.api.nvim_buf_line_count(buffer_number)
end

function M.count_table_entries(value)
    return vim.tbl_count(value or {})
end

function M.assert_line_contains(lines, text, message)
    for _, line in ipairs(lines or {}) do
        if line:find(text, 1, true) then
            return
        end
    end
    error(message or "missing text")
end

function M.assert_line_missing(lines, text, message)
    for _, line in ipairs(lines or {}) do
        if line:find(text, 1, true) then
            error(message or "unexpected text")
        end
    end
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
    if picker and picker.select and picker.select.close then
        picker:close()
    end
end

function M.feed(keys)
    feed(keys)
end

return M
