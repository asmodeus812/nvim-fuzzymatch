---@diagnostic disable: invisible
local Select = require("fuzzy.select")
local helpers = require("script.test_utils")

local M = { name = "select" }

local function new_select(opts)
    return Select.new(opts or {})
end

local function get_toggle_signs(select)
    local buf = select.list_buffer
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return {}, {}
    end
    local placed = vim.fn.sign_getplaced(buf, { group = "list_toggle_entry_group" })
    local signs = placed and placed[1] and placed[1].signs or {}
    local ids = {}
    for _, sign in ipairs(signs or {}) do
        ids[#ids + 1] = sign.id
    end
    table.sort(ids)
    return ids, signs
end

local function expected_visible_ids(select, total, excluded)
    local position = vim.api.nvim_win_get_cursor(select.list_window)
    local height = vim.api.nvim_win_get_height(select.list_window)
    local cursor = select._state.cursor
    local start = math.max(1, cursor[1] - (position[1] - 1))
    local finish = math.min(total, cursor[1] + (height - position[1]))
    local ids = {}
    for i = start, finish do
        if not (excluded and excluded[i]) then
            ids[#ids + 1] = i
        end
    end
    return ids
end

local function run_action_case()
    local select = new_select({
        prompt_list = true,
        prompt_input = true,
        preview = false,
        list_offset = 1,
    })

    select:open()
    local height = helpers.is_window_valid(select.list_window)
        and vim.api.nvim_win_get_height(select.list_window) or 10
    local entries = {}
    local total = height + 8
    for i = 1, total do
        entries[i] = "item-" .. i
    end
    select:list(entries)
    helpers.wait_for(function()
        return select._state.entries and #select._state.entries == total
    end, 1500)
    helpers.wait_for(function()
        local lines = helpers.get_buffer_lines(select.list_buffer)
        return lines and #lines > 0
    end, 1500)
    helpers.wait_for(function()
        return helpers.get_buffer_line_count(select.list_buffer) >= height
    end, 1500)
    select:list(nil, nil)

    select:move_down()
    helpers.eq(select._state.cursor[1], 2, "move down")
    select:move_up()
    helpers.eq(select._state.cursor[1], 1, "move up")

    select:move_bot()
    helpers.assert_ok(
        select._state.cursor[1] >= 1 and select._state.cursor[1] <= total,
        "move bot"
    )
    select:move_top()
    helpers.assert_ok(
        select._state.cursor[1] >= 1 and select._state.cursor[1] <= total,
        "move top"
    )

    select:toggle_entry()
    helpers.assert_ok(select._state.toggled.entries["1"] ~= nil, "toggle entry")
    select:toggle_down()
    helpers.eq(select._state.cursor[1], 2, "toggle down")
    select:toggle_up()
    helpers.assert_ok(select._state.toggled.entries["2"] ~= nil, "toggle up")
    helpers.eq(select._state.cursor[1], 1, "toggle up")

    select:toggle_all()
    helpers.assert_ok(select._state.toggled.all, "toggle all")
    select:toggle_clear()
    helpers.eq(helpers.count_table_entries(select._state.toggled.entries), 0, "toggle clear")
    helpers.assert_ok(select._state.toggled.all == false, "toggle clear")

    helpers.assert_ok(select.prompt_buffer ~= nil, "prompt buffer")
    select:toggle_list()
    helpers.assert_ok(select._state.toggled.all, "toggle list")
    select:toggle_list()
    helpers.assert_ok(select._state.toggled.all == false, "toggle list")

    select:close()
end

local function run_toggle_signs_case()
    local select = new_select({
        prompt_list = true,
        prompt_input = true,
        preview = false,
    })

    select:open()
    select:list({ "one", "two", "three" })
    helpers.wait_for(function()
        return select._state.entries and #select._state.entries == 3
    end, 1500)

    local sign_name = string.format("list_toggle_entry_sign_%d", select.list_buffer)
    local defined = vim.fn.sign_getdefined(sign_name)
    helpers.assert_ok(defined and #defined == 1, "toggle sign defined")

    select:toggle_entry()
    helpers.wait_for(function()
        local ids = get_toggle_signs(select)
        return vim.tbl_contains(ids, 1)
    end, 1500)

    local ids = get_toggle_signs(select)
    helpers.assert_list_contains(ids, 1, "toggle sign for first entry")

    select:move_down()
    select:move_down()
    select:toggle_entry()
    helpers.wait_for(function()
        local next_ids = get_toggle_signs(select)
        return vim.tbl_contains(next_ids, 3)
    end, 1500)

    local next_ids = get_toggle_signs(select)
    helpers.assert_list_contains(next_ids, 3, "toggle sign for third entry")

    select:close()
end


local function run_select_action_case()
    local select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = false,
    })

    local selected = nil
    select:open()
    select:list({ "one", "two", "three" })
    helpers.wait_for(function()
        return select._state.entries and #select._state.entries == 3
    end, 1500)

    select:select_entry(function(list)
        selected = list
        return false
    end)
    helpers.assert_ok(selected and #selected == 1, "select entry")
    helpers.assert_ok(select:isopen() == false, "closed")

    select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = false,
    })
    selected = nil
    select:open()
    select:list({ "one", "two", "three" })
    helpers.wait_for(function()
        return select._state.entries and #select._state.entries == 3
    end, 1500)

    select:select_next(function(list)
        selected = list
        return false
    end)
    helpers.assert_ok(selected and #selected == 1, "select next")
    helpers.assert_ok(select:isopen() == false, "closed")

    select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = false,
    })
    selected = nil
    select:open()
    select:list({ "one", "two", "three" })
    helpers.wait_for(function()
        return select._state.entries and #select._state.entries == 3
    end, 1500)
    select:list(nil, nil)

    select:select_prev(function(list)
        selected = list
        return false
    end)
    helpers.assert_ok(selected and #selected == 1, "select prev")
    helpers.assert_ok(select:isopen() == false, "closed")

    select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = false,
    })
    select:open()
    select:list({ "one", "two" })
    helpers.wait_for(function()
        return select._state.entries and #select._state.entries == 2
    end, 1500)

    select:select_horizontal(function() return false end)
    helpers.assert_ok(select:isopen() == false, "closed")

    select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = false,
    })
    select:open()
    select:list({ "one", "two" })
    helpers.wait_for(function()
        return select._state.entries and #select._state.entries == 2
    end, 1500)

    select:select_vertical(function() return false end)
    helpers.assert_ok(select:isopen() == false, "closed")

    select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = false,
    })
    select:open()
    select:list({ "one", "two" })
    helpers.wait_for(function()
        return select._state.entries and #select._state.entries == 2
    end, 1500)

    select:select_tab(function() return false end)
    helpers.assert_ok(select:isopen() == false, "closed")

    select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = false,
    })
    select:open()
    select:list({ "one", "two" })
    helpers.wait_for(function()
        return select._state.entries and #select._state.entries == 2
    end, 1500)

    select:send_quickfix(function() return false end)
    helpers.assert_ok(select:isopen() == false, "closed")

    select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = false,
    })
    select:open()
    select:list({ "one", "two" })
    helpers.wait_for(function()
        return select._state.entries and #select._state.entries == 2
    end, 1500)

    select:send_locliset(function() return false end)
    helpers.assert_ok(select:isopen() == false, "closed")
end

local function run_toggle_selection_case()
    local select = new_select({
        prompt_list = true,
        prompt_input = true,
        preview = false,
    })

    select:open()
    select:list({ "one", "two", "three" })
    helpers.wait_for(function()
        return select._state.entries and #select._state.entries == 3
    end, 1500)

    select:toggle_entry()
    select:move_down()
    select:toggle_entry()

    local selected = nil
    select:select_entry(function(list)
        selected = list
        return false
    end)
    helpers.assert_ok(selected and #selected == 2, "select toggled entries")
    helpers.assert_list_contains(selected, "one", "select toggled entries")
    helpers.assert_list_contains(selected, "two", "select toggled entries")
    helpers.assert_ok(select:isopen() == false, "closed")
end

local function run_toggle_quickfix_case()
    local select = new_select({
        prompt_list = true,
        prompt_input = true,
        preview = false,
        quickfix_open = function() end,
    })

    select:open()
    select:list({ "file-1", "file-2", "file-3", "file-4" })
    helpers.wait_for(function()
        return select._state.entries and #select._state.entries == 4
    end, 1500)

    select:toggle_entry()
    select:move_down()
    select:move_down()
    select:toggle_entry()

    local qf_args = nil
    helpers.with_mock(vim.fn, "setqflist", function(_, _, args)
        qf_args = args
    end, function()
        select:send_quickfix()
    end)

    helpers.assert_ok(qf_args ~= nil, "quickfix args")
    helpers.eq(qf_args.title, "[Fuzzymatch]", "quickfix title")
    helpers.assert_ok(qf_args.items and #qf_args.items == 2, "quickfix items")

    local filenames = vim.tbl_map(function(item)
        return item.filename
    end, qf_args.items)
    helpers.assert_list_contains(filenames, "file-1", "quickfix items")
    helpers.assert_list_contains(filenames, "file-3", "quickfix items")
    helpers.assert_ok(select:isopen() == false, "closed")
end

local function run_basic_case()
    local select = new_select({
        prompt_list = true,
        prompt_input = true,
        preview = false,
        display = "text",
    })
    helpers.assert_ok(select:options() ~= nil, "select options")
    helpers.eq(select:options().display, "text", "select options reference")

    select:open()
    select:list({
        { text = "one" },
        { text = "two" },
        { text = "three" },
    })

    helpers.wait_for(function()
        return select._state.entries
            and #select._state.entries == 3
    end, 1500)

    helpers.eq(#select._state.entries, 3, "entries")
    helpers.wait_for(function()
        local lines = helpers.get_buffer_lines(select.list_buffer)
        for _, line in ipairs(lines or {}) do
            if line:find("one", 1, true) then
                return true
            end
        end
        return false
    end, 1500)

    helpers.eq(select:query(), "", "query")



    select:close()
end

local function run_toggle_case()
    local select = new_select({
        prompt_list = true,
        prompt_input = true,
        preview = false,
    })

    select:open()
    select:list({ "one", "two", "three" })
    helpers.wait_for(function()
        return select._state.entries
            and #select._state.entries == 3
    end, 1500)

    select:toggle_entry()
    helpers.assert_ok(
        select._state.toggled.entries["1"] ~= nil,
        "toggle"
    )

    select:toggle_all()
    helpers.assert_ok(select._state.toggled.all, "toggle all")

    select:toggle_clear()
    helpers.assert_ok(select._state.toggled.all == false, "toggle clear")
    helpers.eq(
        helpers.count_table_entries(select._state.toggled.entries),
        0,
        "toggle clear"
    )

    select:close()
end

local function run_toggle_scroll_case()
    local select = new_select({
        prompt_list = true,
        prompt_input = true,
        preview = false,
        list_offset = 1,
    })

    select:open()
    local list_ready = helpers.wait_for(function()
        return helpers.is_window_valid(select.list_window)
    end, 1500)
    helpers.assert_ok(list_ready, "list window ready")

    local height = vim.api.nvim_win_get_height(select.list_window)
    local total = (height * 3) + 2
    local entries = {}
    for i = 1, total do
        entries[i] = "item-" .. i
    end
    select:list(entries)
    helpers.wait_for(function()
        return select._state.entries and #select._state.entries == total
    end, 1500)

    select:toggle_entry()
    for _ = 1, height + 1 do
        select:move_down()
    end
    select:toggle_entry()

    select:toggle_all()
    helpers.wait_for(function()
        local ids = get_toggle_signs(select)
        return #ids > 0
    end, 1500)

    local expected_ids = expected_visible_ids(select, total)
    local ids = get_toggle_signs(select)
    helpers.eq(ids, expected_ids, "toggle all signs")

    select:toggle_clear()
    helpers.wait_for(function()
        local cleared = get_toggle_signs(select)
        return #cleared == 0
    end, 1500)

    local cleared = get_toggle_signs(select)
    helpers.eq(#cleared, 0, "toggle clear signs")

    select:close()
end

local function run_toggle_all_exclusion_case()
    local select = new_select({
        prompt_list = true,
        prompt_input = true,
        preview = false,
    })

    select:open()
    select:list({ "alpha", "beta", "gamma", "delta", "epsilon" })
    helpers.wait_for(function()
        return select._state.entries and #select._state.entries == 5
    end, 1500)

    select:toggle_all()
    helpers.assert_ok(select._state.toggled.all, "toggle all")

    select:move_down()
    select:toggle_entry()

    helpers.wait_for(function()
        local ids = get_toggle_signs(select)
        return #ids > 0
    end, 1500)

    local excluded = { [2] = true }
    local expected_ids = expected_visible_ids(select, 5, excluded)
    local ids = get_toggle_signs(select)
    helpers.eq(ids, expected_ids, "toggle all exclusion")

    select:toggle_clear()
    helpers.assert_ok(select._state.toggled.all == false, "toggle clear")
    helpers.eq(helpers.count_table_entries(select._state.toggled.entries), 0, "toggle clear")

    select:close()
end

local function run_toggle_all_quickfix_case()
    local select = new_select({
        prompt_list = true,
        prompt_input = true,
        preview = false,
        quickfix_open = function() end,
    })

    select:open()
    select:list({ "one", "two", "three", "four" })
    helpers.wait_for(function()
        return select._state.entries and #select._state.entries == 4
    end, 1500)

    select:toggle_all()
    select:move_down()
    select:toggle_entry()

    local qf_args = nil
    helpers.with_mock(vim.fn, "setqflist", function(_, _, args)
        qf_args = args
    end, function()
        select:send_quickfix()
    end)

    helpers.assert_ok(qf_args ~= nil, "quickfix args")
    helpers.assert_ok(qf_args.items and #qf_args.items == 3, "quickfix items")

    local filenames = vim.tbl_map(function(item)
        return item.filename
    end, qf_args.items)
    helpers.assert_list_missing(filenames, "two", "quickfix exclusion")
    helpers.assert_list_contains(filenames, "one", "quickfix inclusion")
    helpers.assert_list_contains(filenames, "three", "quickfix inclusion")
    helpers.assert_list_contains(filenames, "four", "quickfix inclusion")
    helpers.assert_ok(select:isopen() == false, "closed")
end

local function run_selection_command_case()
    local select = new_select({
        prompt_list = true,
        prompt_input = true,
        preview = false,
    })

    select:open()
    select:list({ "file-a", "file-b", "file-c" })
    helpers.wait_for(function()
        return select._state.entries and #select._state.entries == 3
    end, 1500)

    helpers.with_cmd_capture(function(calls)
        select:select_entry()
        helpers.assert_ok(#calls == 1, "select entry call count")
        helpers.eq(calls[1].kind, "edit", "select entry edit")
    end)
    helpers.assert_ok(select:isopen() == false, "closed")

    select = new_select({
        prompt_list = true,
        prompt_input = true,
        preview = false,
    })
    select:open()
    select:list({ "file-a", "file-b", "file-c" })
    helpers.wait_for(function()
        return select._state.entries and #select._state.entries == 3
    end, 1500)

    helpers.with_cmd_capture(function(calls)
        select:select_horizontal()
        helpers.assert_ok(#calls == 1, "select horizontal call count")
        helpers.eq(calls[1].kind, "split", "select horizontal split")
    end)
    helpers.assert_ok(select:isopen() == false, "closed")

    select = new_select({
        prompt_list = true,
        prompt_input = true,
        preview = false,
    })
    select:open()
    select:list({ "file-a", "file-b", "file-c" })
    helpers.wait_for(function()
        return select._state.entries and #select._state.entries == 3
    end, 1500)

    helpers.with_cmd_capture(function(calls)
        select:select_vertical()
        helpers.assert_ok(#calls == 1, "select vertical call count")
        helpers.eq(calls[1].kind, "split", "select vertical split")
    end)
    helpers.assert_ok(select:isopen() == false, "closed")

    select = new_select({
        prompt_list = true,
        prompt_input = true,
        preview = false,
    })
    select:open()
    select:list({ "file-a", "file-b", "file-c" })
    helpers.wait_for(function()
        return select._state.entries and #select._state.entries == 3
    end, 1500)

    helpers.with_cmd_capture(function(calls)
        select:select_tab()
        helpers.assert_ok(#calls == 1, "select tab call count")
        helpers.eq(calls[1].kind, "tabedit", "select tab")
    end)
    helpers.assert_ok(select:isopen() == false, "closed")

    select = new_select({
        prompt_list = true,
        prompt_input = true,
        preview = false,
    })
    select:open()
    select:list({ "file-a", "file-b", "file-c" })
    helpers.wait_for(function()
        return select._state.entries and #select._state.entries == 3
    end, 1500)

    select:toggle_entry()
    select:move_down()
    select:toggle_entry()

    helpers.with_cmd_capture(function(calls)
        select:select_vertical()
        helpers.eq(#calls, 2, "select vertical multi")
        helpers.eq(calls[1].kind, "split", "select vertical multi")
        helpers.eq(calls[2].kind, "split", "select vertical multi")
    end)
    helpers.assert_ok(select:isopen() == false, "closed")
end

local function run_prompt_case()
    local select = new_select({
        prompt_list = false,
        prompt_input = true,
        preview = false,
    })

    select:open()
    local prompt_ready = helpers.wait_for(function()
        return helpers.is_window_valid(select.prompt_window)
    end, 1500)
    helpers.assert_ok(prompt_ready, "prompt window")
    vim.api.nvim_buf_set_lines(select.prompt_buffer, 0, 1, false, { "hello" })
    local query = select:_prompt_getquery()
    select:_prompt_input(query, select._options.prompt_input)
    select._state.query = query
    helpers.wait_for(function()
        return select:query() == "hello"
    end, 1500)
    helpers.eq(select:query(), "hello", "prompt query")
    vim.api.nvim_buf_set_lines(select.prompt_buffer, 0, 1, false, { "" })
    query = select:_prompt_getquery()
    select:_prompt_input(query, select._options.prompt_input)
    select._state.query = query
    helpers.eq(select:query(), "", "prompt delete")
    select:close()
end

local function run_prompt_sync_results_case()
    local select = new_select({
        prompt_list = true,
        prompt_input = function(query)
            if query == "sync" then
                return { "alpha", "beta" }
            end
            if query == "sync-pos" then
                return {
                    entries = { "gamma", "delta" },
                    positions = {},
                }
            end
        end,
        preview = false,
    })

    select:open()
    local list_ready = helpers.wait_for(function()
        return helpers.is_window_valid(select.list_window)
    end, 1500)
    helpers.assert_ok(list_ready, "prompt sync list window")

    select:_prompt_input("sync", select._options.prompt_input)
    helpers.wait_for(function()
        return select._state.entries and #select._state.entries == 2
    end, 1500)
    helpers.eq(select._state.entries[1], "alpha", "prompt sync entries")

    select:_prompt_input("sync-pos", select._options.prompt_input)
    helpers.wait_for(function()
        return select._state.entries and #select._state.entries == 2
    end, 1500)
    helpers.eq(select._state.entries[1], "gamma", "prompt sync entries+positions")

    select:close()
end

local function run_preview_case()
    local preview = Select.CustomPreview.new(function(entry)
        return {
            "preview: " .. tostring(entry),
            "line two",
        }, "lua", ""
    end)

    local select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = preview,
    })

    select:open()
    select:list({ "alpha", "beta" })
    helpers.wait_for(function()
        return select.preview_window
            and helpers.is_window_valid(select.preview_window)
    end, 1500)

    helpers.wait_for(function()
        local preview_buffer = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local preview_lines = helpers.get_buffer_lines(preview_buffer)
        for _, line in ipairs(preview_lines or {}) do
            if line:find("preview: alpha", 1, true) then
                return true
            end
        end
        return false
    end, 1500)
    local preview_buffer = select.preview_window
        and vim.api.nvim_win_get_buf(select.preview_window)
    local preview_lines = helpers.get_buffer_lines(preview_buffer)
    helpers.assert_line_contains(preview_lines, "preview: alpha", "preview")
    helpers.eq(#preview.buffers, 1, "custom preview buffers")

    select:move_down()
    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local lines = helpers.get_buffer_lines(buf)
        for _, line in ipairs(lines or {}) do
            if line:find("preview: beta", 1, true) then
                return true
            end
        end
        return false
    end, 1500)
    helpers.eq(#preview.buffers, 2, "custom preview new buffer")

    select:move_up()
    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local lines = helpers.get_buffer_lines(buf)
        for _, line in ipairs(lines or {}) do
            if line:find("preview: alpha", 1, true) then
                return true
            end
        end
        return false
    end, 1500)
    helpers.eq(#preview.buffers, 2, "custom preview reuse buffer")

    local preview_window = select.preview_window
    select:toggle_preview()
    helpers.assert_ok(helpers.is_window_valid(preview_window) == false, "preview")
    select:toggle_preview()
    helpers.assert_ok(
        helpers.is_window_valid(select.preview_window),
        "preview"
    )

    if helpers.is_window_valid(select.preview_window) then
        select:line_down()
        select:line_up()
        select:page_down()
        select:page_up()
        select:half_down()
        select:half_up()
    end

    vim.wait(50, function() return true end, 10)
    select:close()
    preview:clean()
end

local function run_buffer_preview_case()
    local dir = helpers.create_temp_dir()
    local filename = vim.fs.joinpath(dir, "alpha.txt")
    local ignored = vim.fs.joinpath(dir, "image.png")
    helpers.write_file(filename, { "alpha", "beta" })
    helpers.write_file(ignored, { "binary" })

    local preview = Select.BufferPreview.new()
    local select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = preview,
    })

    select:open()
    select:list({ filename, ignored })
    helpers.wait_for(function()
        return select.preview_window
            and helpers.is_window_valid(select.preview_window)
    end, 1500)

    helpers.wait_for(function()
        local preview_buffer = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local preview_lines = helpers.get_buffer_lines(preview_buffer)
        return vim.tbl_contains(preview_lines or {}, "alpha")
    end, 1500)

    select:move_down()
    helpers.wait_for(function()
        local preview_buffer = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local preview_lines = helpers.get_buffer_lines(preview_buffer)
        for _, line in ipairs(preview_lines or {}) do
            if line:find("ignored", 1, true) then
                return true
            end
        end
        return false
    end, 1500)

    select:move_up()
    helpers.wait_for(function()
        local preview_buffer = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local preview_lines = helpers.get_buffer_lines(preview_buffer)
        return vim.tbl_contains(preview_lines or {}, "alpha")
    end, 1500)

    select:close()
    preview:clean()
end

local function run_command_preview_case()
    local dir = helpers.create_temp_dir()
    local first = vim.fs.joinpath(dir, "first.txt")
    local second = vim.fs.joinpath(dir, "second.txt")
    helpers.write_file(first, { "alpha", "beta" })
    helpers.write_file(second, { "gamma" })

    local preview = Select.CommandPreview.new("cat")
    local select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = preview,
    })

    select:open()
    select:list({ first, second })
    helpers.wait_for(function()
        return select.preview_window
            and helpers.is_window_valid(select.preview_window)
    end, 1500)

    helpers.wait_for(function()
        local preview_buffer = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local preview_lines = helpers.get_buffer_lines(preview_buffer)
        return vim.tbl_contains(preview_lines or {}, "alpha")
    end, 1500)
    helpers.eq(#preview.buffers, 1, "command preview buffers")

    select:move_down()
    helpers.wait_for(function()
        local preview_buffer = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local preview_lines = helpers.get_buffer_lines(preview_buffer)
        return vim.tbl_contains(preview_lines or {}, "gamma")
    end, 1500)
    helpers.eq(#preview.buffers, 2, "command preview new buffer")

    select:move_up()
    helpers.wait_for(function()
        local preview_buffer = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local preview_lines = helpers.get_buffer_lines(preview_buffer)
        return vim.tbl_contains(preview_lines or {}, "alpha")
    end, 1500)
    helpers.eq(#preview.buffers, 2, "command preview reuse buffer")

    select:close()
    preview:clean()
end

local function run_decorator_case()
    local decor_a = Select.Decorator.new()
    function decor_a:decorate()
        return "A", "String"
    end

    local decor_b = Select.Decorator.new()
    function decor_b:decorate()
        return "B", "String"
    end

    local decor_nil = Select.Decorator.new()
    function decor_nil:decorate()
        return nil, nil
    end
    local decor_false = Select.Decorator.new()
    function decor_false:decorate()
        return false, nil
    end

    local combine = Select.CombineDecorator.new({ decor_false, decor_a, decor_b }, "Constant", ":")
    local chain = Select.ChainDecorator.new({ decor_nil, decor_b })

    local select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = false,
        decorators = { combine, chain },
    })

    select:open()
    select:list({ "one", "two" })
    helpers.wait_for(function()
        local lines = helpers.get_buffer_lines(select.list_buffer)
        return lines and #lines >= 2
    end, 1500)

    local lines = helpers.get_buffer_lines(select.list_buffer)
    helpers.assert_ok(lines[1]:find("A:B", 1, true) ~= nil, "combine decorator")
    helpers.assert_ok(lines[1]:find("A:B B", 1, true) ~= nil, "chain decorator")

    select:close()
end

local function run_converter_case()
    local first_conv = Select.first(function(entry)
        return entry.value
    end)
    local last_conv = Select.last(function(entry)
        return entry.value
    end)
    local all_conv = Select.all(function(entry)
        return entry.value
    end)

    local entries = {
        { value = "one" },
        { value = "two" },
    }

    helpers.eq(first_conv(entries), "one", "first")
    helpers.eq(last_conv(entries), "two", "last")
    helpers.eq(all_conv(entries)[1], "one", "all")

    local buf = helpers.create_named_buffer("converter.txt", { "line" })
    local conv = Select.default_converter("converter.txt")
    helpers.eq(conv.filename, "converter.txt", "default converter string")

    local conv_buf = Select.default_converter(buf)
    helpers.eq(conv_buf.bufnr, buf, "default converter bufnr")
end

function M.run()
    run_action_case()
    run_toggle_signs_case()
    run_select_action_case()
    run_toggle_selection_case()
    run_basic_case()
    run_toggle_quickfix_case()
    run_toggle_case()
    run_toggle_scroll_case()
    run_toggle_all_exclusion_case()
    run_toggle_all_quickfix_case()
    run_selection_command_case()
    run_prompt_case()
    run_prompt_sync_results_case()
    run_preview_case()
    run_buffer_preview_case()
    run_command_preview_case()
    run_decorator_case()
    run_converter_case()
end

return M
