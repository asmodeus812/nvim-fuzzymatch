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

local function run_display_case()
    local prefix = "A"
    local preview = Select.CustomPreview.new(function(entry)
        return { "preview:" .. tostring(entry.value) }, "lua", ""
    end)
    local select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = preview,
        display = function(entry, index)
            return string.format("%s:%s:%d", prefix, entry.value, index)
        end,
    })

    select:open()
    local entries = {
        { value = "one" },
        { value = "two" },
        { value = "three" },
    }
    select:list(entries)
    helpers.wait_for(function()
        local lines = helpers.get_buffer_lines(select.list_buffer)
        return lines and lines[1] == "A:one:1"
    end, 1500)

    local lines = helpers.get_buffer_lines(select.list_buffer)
    helpers.eq(lines[1], "A:one:1", "display function line 1")
    helpers.eq(lines[2], "A:two:2", "display function line 2")

    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local plines = helpers.get_buffer_lines(buf)
        return plines and plines[1] == "preview:one"
    end, 1500)

    select:move_down()
    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local plines = helpers.get_buffer_lines(buf)
        return plines and plines[1] == "preview:two"
    end, 1500)
    select:move_up()
    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local plines = helpers.get_buffer_lines(buf)
        return plines and plines[1] == "preview:one"
    end, 1500)
    select:toggle_entry()
    helpers.assert_ok(select._state.toggled.entries["1"] ~= nil, "display toggle entry")

    prefix = "B"
    select:list(entries)
    helpers.wait_for(function()
        local next_lines = helpers.get_buffer_lines(select.list_buffer)
        return next_lines and next_lines[1] == "B:one:1"
    end, 1500)

    local next_lines = helpers.get_buffer_lines(select.list_buffer)
    helpers.eq(next_lines[1], "B:one:1", "display function rerender")
    helpers.assert_ok(next_lines[1] ~= "A:one:1", "display function rerender old")

    select:list({
        { value = "alpha" },
        { value = "beta" },
    })
    helpers.wait_for(function()
        local final_lines = helpers.get_buffer_lines(select.list_buffer)
        return final_lines and final_lines[1] == "B:alpha:1"
    end, 1500)
    local final_lines = helpers.get_buffer_lines(select.list_buffer)
    helpers.eq(final_lines[2], "B:beta:2", "display function new entries")
    select:close()

    local property_select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = false,
        display = "label",
    })

    property_select:open()
    property_select:list({
        { label = "alpha" },
        { other = "missing" },
    })
    helpers.wait_for(function()
        local plines = helpers.get_buffer_lines(property_select.list_buffer)
        return plines and #plines >= 2
    end, 1500)

    local plines = helpers.get_buffer_lines(property_select.list_buffer)
    helpers.eq(plines[1], "alpha", "display string property")
    helpers.eq(plines[2], "", "display string missing")

    property_select:list({
        { label = "first" },
        { label = "second" },
    })
    property_select:list({
        { label = "third" },
        { label = "fourth" },
    })
    helpers.wait_for(function()
        local lines_latest = helpers.get_buffer_lines(property_select.list_buffer)
        return lines_latest and lines_latest[1] == "third"
    end, 1500)

    local lines_latest = helpers.get_buffer_lines(property_select.list_buffer)
    helpers.eq(lines_latest[1], "third", "display rerender latest")
    helpers.eq(lines_latest[2], "fourth", "display rerender latest")
    property_select:move_down()
    property_select:move_up()
    property_select:close()
    preview:clean()
end

local function run_display_nil_case()
    local preview = Select.CustomPreview.new(function(entry)
        return { "preview:" .. tostring(entry.value) }, "lua", ""
    end)
    local select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = preview,
        display = function(entry)
            if entry.value == "skip" then
                return nil
            end
            return entry.value
        end,
    })

    select:open()
    select:list({
        { value = "keep" },
        { value = "skip" },
        { value = "keep-2" },
    })
    helpers.wait_for(function()
        local lines = helpers.get_buffer_lines(select.list_buffer)
        return lines and #lines >= 3
    end, 1500)

    local lines = helpers.get_buffer_lines(select.list_buffer)
    helpers.eq(lines[1], "keep", "display nil line 1")
    helpers.eq(lines[2], "", "display nil line 2")
    helpers.eq(lines[3], "keep-2", "display nil line 3")
    select:move_down()
    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local plines = helpers.get_buffer_lines(buf)
        return plines and plines[1] == "preview:skip"
    end, 1500)
    select:toggle_entry()
    helpers.assert_ok(select._state.toggled.entries["2"] ~= nil, "display nil toggle")
    select:move_down()
    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local plines = helpers.get_buffer_lines(buf)
        return plines and plines[1] == "preview:keep-2"
    end, 1500)
    select:close()
    preview:clean()
end

local function run_display_index_case()
    local preview = Select.CustomPreview.new(function(entry)
        return { "preview:" .. tostring(entry.value) }, "lua", ""
    end)
    local select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = preview,
        display = function(entry, index)
            return string.format("%d:%s", index, entry.value)
        end,
    })

    select:open()
    select:list({
        { value = "alpha" },
        { value = "beta" },
    })
    helpers.wait_for(function()
        local lines = helpers.get_buffer_lines(select.list_buffer)
        return lines and lines[1] == "1:alpha"
    end, 1500)

    local lines = helpers.get_buffer_lines(select.list_buffer)
    helpers.eq(lines[1], "1:alpha", "display index line 1")
    helpers.eq(lines[2], "2:beta", "display index line 2")
    select:move_down()
    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local plines = helpers.get_buffer_lines(buf)
        return plines and plines[1] == "preview:beta"
    end, 1500)
    select:move_up()
    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local plines = helpers.get_buffer_lines(buf)
        return plines and plines[1] == "preview:alpha"
    end, 1500)
    select:close()
    preview:clean()
end

local function run_display_decorator_case()
    local seen = {}
    local preview = Select.CustomPreview.new(function(entry)
        return { "preview:" .. tostring(entry.value) }, "lua", ""
    end)
    local decor = Select.Decorator.new()
    function decor:decorate(_, line)
        seen[#seen + 1] = line
        return nil
    end

    local select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = preview,
        decorators = { decor },
        display = function(entry)
            return "decor:" .. entry.value
        end,
    })

    select:open()
    select:list({
        { value = "one" },
        { value = "two" },
    })
    helpers.wait_for(function()
        return #seen >= 2
    end, 1500)

    helpers.assert_list_contains(seen, "decor:one", "display decorator one")
    helpers.assert_list_contains(seen, "decor:two", "display decorator two")
    select:move_down()
    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local plines = helpers.get_buffer_lines(buf)
        return plines and plines[1] == "preview:two"
    end, 1500)
    select:move_up()
    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local plines = helpers.get_buffer_lines(buf)
        return plines and plines[1] == "preview:one"
    end, 1500)
    select:close()
    preview:clean()
end

local function run_display_highlighter_case()
    local seen = {}
    local preview = Select.CustomPreview.new(function(entry)
        return { "preview:" .. tostring(entry.value) }, "lua", ""
    end)
    local highlighter = Select.Highlighter.new()
    function highlighter:highlight(_, line)
        seen[#seen + 1] = line
        return nil
    end

    local select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = preview,
        highlighters = { highlighter },
        display = function(entry)
            return "hl:" .. entry.value
        end,
    })

    select:open()
    select:list({
        { value = "alpha" },
        { value = "beta" },
    })
    helpers.wait_for(function()
        return #seen >= 2
    end, 1500)

    helpers.assert_list_contains(seen, "hl:alpha", "display highlighter alpha")
    helpers.assert_list_contains(seen, "hl:beta", "display highlighter beta")
    select:move_down()
    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local plines = helpers.get_buffer_lines(buf)
        return plines and plines[1] == "preview:beta"
    end, 1500)
    select:move_up()
    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local plines = helpers.get_buffer_lines(buf)
        return plines and plines[1] == "preview:alpha"
    end, 1500)
    select:close()
    preview:clean()
end

local function run_display_positions_case()
    local preview = Select.CustomPreview.new(function(entry)
        return { "preview:" .. tostring(entry.value) }, "lua", ""
    end)
    local select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = preview,
        display = function(entry)
            return "pos:" .. entry.value
        end,
    })

    select:open()
    select:list(
        { { value = "aaa" }, { value = "bbb" } },
        { { 0, 3 }, { 1, 2 } }
    )
    helpers.wait_for(function()
        local lines = helpers.get_buffer_lines(select.list_buffer)
        return lines and lines[1] == "pos:aaa"
    end, 1500)

    local lines = helpers.get_buffer_lines(select.list_buffer)
    helpers.eq(lines[1], "pos:aaa", "display positions line 1")
    helpers.eq(lines[2], "pos:bbb", "display positions line 2")

    local ns = vim.api.nvim_create_namespace("list_highlight_namespace")
    helpers.wait_for(function()
        local extmarks = vim.api.nvim_buf_get_extmarks(
            select.list_buffer,
            ns,
            { 0, 0 },
            { -1, -1 },
            { details = true }
        )
        return extmarks and #extmarks > 0
    end, 1500)

    select:move_down()
    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local plines = helpers.get_buffer_lines(buf)
        return plines and plines[1] == "preview:bbb"
    end, 1500)
    select:move_up()
    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local plines = helpers.get_buffer_lines(buf)
        return plines and plines[1] == "preview:aaa"
    end, 1500)
    select:close()
    preview:clean()
end

local function run_display_rerender_case()
    local preview = Select.CustomPreview.new(function(entry)
        return { "preview:" .. tostring(entry.value) }, "lua", ""
    end)
    local select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = preview,
        display = function(entry)
            return "rr:" .. entry.value
        end,
    })

    select:open()
    select:list({ { value = "first" }, { value = "second" } })
    select:list({ { value = "third" }, { value = "fourth" } })
    helpers.wait_for(function()
        local lines = helpers.get_buffer_lines(select.list_buffer)
        return lines and lines[1] == "rr:third"
    end, 1500)

    local lines = helpers.get_buffer_lines(select.list_buffer)
    helpers.eq(lines[1], "rr:third", "display rerender line 1")
    helpers.eq(lines[2], "rr:fourth", "display rerender line 2")
    select:move_down()
    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local plines = helpers.get_buffer_lines(buf)
        return plines and plines[1] == "preview:fourth"
    end, 1500)
    select:move_up()
    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local plines = helpers.get_buffer_lines(buf)
        return plines and plines[1] == "preview:third"
    end, 1500)
    select:close()
    preview:clean()
end

local function run_display_rapid_case()
    local preview = Select.CustomPreview.new(function(entry)
        return { "preview:" .. tostring(entry.value) }, "lua", ""
    end)
    local select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = preview,
        display = function(entry, index)
            return string.format("rapid:%s:%d", entry.value, index)
        end,
    })

    select:open()

    local final_entries = nil
    local first_entries = nil
    for i = 1, 60 do
        local entries = {
            { value = string.format("v%02d-a", i) },
            { value = string.format("v%02d-b", i) },
            { value = string.format("v%02d-c", i) },
        }
        if i == 1 then
            first_entries = entries
        end
        if i == 60 then
            final_entries = entries
        end
        select:list(entries)
    end

    helpers.wait_for(function()
        local lines = helpers.get_buffer_lines(select.list_buffer)
        return lines and lines[1] == "rapid:v60-a:1"
            and lines[2] == "rapid:v60-b:2"
    end, 1500)

    local lines = helpers.get_buffer_lines(select.list_buffer)
    helpers.eq(lines[1], "rapid:v60-a:1", "display rapid line 1")
    helpers.eq(lines[2], "rapid:v60-b:2", "display rapid line 2")
    helpers.eq(lines[3], "rapid:v60-c:3", "display rapid line 3")
    helpers.assert_ok(lines[1] ~= "rapid:v01-a:1", "display rapid changed")
    helpers.eq(select._state.entries, final_entries, "display rapid final entries")
    select:move_down()
    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local plines = helpers.get_buffer_lines(buf)
        return plines and plines[1] == "preview:v60-b"
    end, 1500)
    select:move_up()
    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local plines = helpers.get_buffer_lines(buf)
        return plines and plines[1] == "preview:v60-a"
    end, 1500)
    select:toggle_entry()
    helpers.assert_ok(select._state.toggled.entries["1"] ~= nil, "display rapid toggle")

    local long_entries = {}
    for i = 1, 25 do
        long_entries[i] = { value = string.format("long-%02d", i) }
    end
    select:list(long_entries)
    helpers.wait_for(function()
        local lines_long = helpers.get_buffer_lines(select.list_buffer)
        return lines_long and lines_long[1] == "rapid:long-01:1"
    end, 1500)

    for _ = 1, 10 do
        select:move_down()
    end
    helpers.wait_for(function()
        return select._state.cursor[1] == 11
    end, 1500)
    helpers.eq(select._state.cursor[1], 11, "display rapid move down")
    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local plines = helpers.get_buffer_lines(buf)
        return plines and plines[1] == "preview:long-11"
    end, 1500)

    for _ = 1, 5 do
        select:move_up()
    end
    helpers.wait_for(function()
        return select._state.cursor[1] == 6
    end, 1500)
    helpers.eq(select._state.cursor[1], 6, "display rapid move up")
    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local plines = helpers.get_buffer_lines(buf)
        return plines and plines[1] == "preview:long-06"
    end, 1500)

    select:close()
    preview:clean()
end

local function run_preview_fallback_case()
    local preview = Select.Preview.new()
    function preview:preview(entry, _)
        if entry.fail then
            return false, entry.msg
        end
        return nil, entry.msg
    end

    local select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = preview,
        display = "label",
    })

    select:open()
    select:list({
        { label = "one", fail = true, msg = "Primary failed" },
        { label = "two", fail = false, msg = "Fallback message" },
    })
    helpers.wait_for(function()
        return select.preview_window
            and helpers.is_window_valid(select.preview_window)
    end, 1500)

    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local plines = helpers.get_buffer_lines(buf)
        return plines and plines[1] == "Primary failed"
    end, 1500)

    select:move_down()
    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local plines = helpers.get_buffer_lines(buf)
        return plines and plines[1] == "Fallback message"
    end, 1500)

    select:close()
end

local function run_preview_success_case()
    local preview = Select.Preview.new()
    function preview:preview(entry, window)
        local buf = vim.api.nvim_win_get_buf(window)
        local oldma = vim.bo[buf].modifiable
        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "ok:" .. tostring(entry.label),
        })
        vim.bo[buf].modifiable = oldma
        return true
    end

    local select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = preview,
        display = "label",
    })

    select:open()
    select:list({
        { label = "alpha" },
        { label = "beta" },
    })
    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local plines = helpers.get_buffer_lines(buf)
        return plines and plines[1] == "ok:alpha"
    end, 1500)

    select:move_down()
    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local plines = helpers.get_buffer_lines(buf)
        return plines and plines[1] == "ok:beta"
    end, 1500)

    select:close()
end

local function run_preview_default_message_case()
    local preview = Select.Preview.new()
    function preview:preview(_)
        return false, nil
    end

    local select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = preview,
        display = "label",
    })

    select:open()
    select:list({ { label = "alpha" } })
    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local plines = helpers.get_buffer_lines(buf)
        return plines and plines[1] == "Unable to preview current entry"
    end, 1500)
    select:close()
end

local function run_preview_error_eventignore_case()
    local preview = Select.Preview.new()
    function preview:preview(_)
        error("Boom")
    end

    local select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = preview,
        display = "label",
    })

    local old_ignore = vim.o.eventignore
    vim.o.eventignore = "BufEnter"

    select:open()
    select:list({ { label = "alpha" } })
    helpers.wait_for(function()
        local buf = select.preview_window
            and vim.api.nvim_win_get_buf(select.preview_window)
        local plines = helpers.get_buffer_lines(buf)
        return plines and plines[1] == "Boom"
    end, 1500)
    helpers.eq(vim.o.eventignore, "BufEnter", "preview error restores eventignore")

    select:close()
    vim.o.eventignore = old_ignore or ""
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
    helpers.type_query({ select = select }, "hello")
    helpers.assert_ok(helpers.wait_for_prompt_text({ select = select }, "hello", 1500), "prompt text")
    helpers.wait_for(function()
        return select:query() == "hello"
    end, 1500)
    helpers.eq(select:query(), "hello", "prompt query")
    helpers.type_query({ select = select }, "<c-u>")
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

    helpers.type_query({ select = select }, "sync")
    helpers.wait_for(function()
        return select._state.entries and #select._state.entries == 2
    end, 1500)
    helpers.eq(select._state.entries[1], "alpha", "prompt sync entries")

    helpers.type_query({ select = select }, "sync-pos")
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
        display = "filename",
    })

    select:open()
    select:list({
        { filename = first },
        { filename = second },
    })
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
        return { { "A", "String" }, { ":", "String" } }
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

    local combine = Select.CombineDecorator.new({ decor_false, decor_a, decor_b }, "Constant")
    local chain = Select.ChainDecorator.new({ decor_nil, decor_b }, "Constant")

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
    helpers.assert_ok(lines[1]:find("A : B", 1, true) ~= nil, "combine decorator")
    helpers.assert_ok(lines[1]:find("A : B B", 1, true) ~= nil, "chain decorator")

    select:close()
end

local function run_wrap_decorator_case()
    local base = Select.Decorator.new()
    function base:decorate()
        return "Alpha", "String"
    end

    local width = Select.WidthDecorator.new(base, 8, "left", " ")
    local trunc = Select.TruncDecorator.new(base, 4, "...")

    local wtext, whl = width:decorate("entry")
    helpers.eq(wtext, "Alpha   ", "width decorator")
    helpers.eq(whl, "String", "width decorator hl passthrough")

    local ttext, thl = trunc:decorate("entry")
    helpers.eq(ttext, "A...", "trunc decorator")
    helpers.eq(thl, "String", "trunc decorator hl passthrough")

    local tab = Select.Decorator.new()
    function tab:decorate()
        return { { "Alpha", "String" }, { "Betamax", "Number" } }
    end

    local tab_trunc = Select.TruncDecorator.new(tab, 4, "...")
    local tparts = tab_trunc:decorate("entry")
    helpers.eq(tparts[1][1], "A...", "trunc table part 1")
    helpers.eq(tparts[1][2], "String", "trunc table hl 1")
    helpers.assert_ok(type(tparts[2][1]) == "string", "trunc table part 2")
    helpers.assert_ok(#tparts[2][1] <= 4, "trunc table part 2")
    helpers.assert_ok(tparts[2][1]:sub(1, 1) == "B", "trunc table part 2")
    helpers.assert_ok(tparts[2][1]:sub(-3) == "...", "trunc table part 2")
    helpers.eq(tparts[2][2], "Number", "trunc table hl 2")
end

local function run_extmark_composite_case()
    local decor = Select.Decorator.new()
    function decor:decorate()
        return { { "A", "String" } }
    end

    local select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = false,
        decorators = { decor },
        highlighters = { Select.LineHighlighter.new("Directory") },
    })

    select:open()
    local entries = {}
    local positions = {}
    for i = 1, 50 do
        entries[i] = string.format("item-%02d", i)
        positions[i] = { 0, 1 }
    end
    select:list(entries, positions)

    local ns_line = vim.api.nvim_create_namespace("list_textline_namespace")
    local ns_match = vim.api.nvim_create_namespace("list_highlight_namespace")
    local ns_decor = vim.api.nvim_create_namespace("list_decorated_namespace")

    local height = vim.api.nvim_win_get_height(select.list_window)
    local function mark_count(ns)
        local extmarks = vim.api.nvim_buf_get_extmarks(
            select.list_buffer,
            ns,
            { 0, 0 },
            { -1, -1 },
            { details = true }
        )
        return extmarks and #extmarks or 0
    end

    helpers.wait_for(function()
        return mark_count(ns_line) == height
            and mark_count(ns_match) == height
            and mark_count(ns_decor) == height
    end, 1500)

    helpers.eq(mark_count(ns_line), height, "line highlights match visible lines")
    helpers.eq(mark_count(ns_match), height, "match highlights match visible lines")
    helpers.eq(mark_count(ns_decor), height, "decorator highlights match visible lines")

    select:close()
end

local function run_extmark_cleanup_case()
    local entries = {}
    local positions = {}
    for i = 1, 50 do
        entries[i] = string.format("item-%02d", i)
        positions[i] = { 0, 1 }
    end

    local ns_match = vim.api.nvim_create_namespace("list_highlight_namespace")
    local ns_decor = vim.api.nvim_create_namespace("list_decorated_namespace")
    local ns_line = vim.api.nvim_create_namespace("list_textline_namespace")

    local function mark_count(select, ns)
        local extmarks = vim.api.nvim_buf_get_extmarks(
            select.list_buffer,
            ns,
            { 0, 0 },
            { -1, -1 },
            { details = true }
        )
        return extmarks and #extmarks or 0
    end

    do
        local select = new_select({
            prompt_list = true,
            prompt_input = false,
            preview = false,
        })

        select:open()
        select:list(entries, positions)

        local height = vim.api.nvim_win_get_height(select.list_window)
        helpers.wait_for(function()
            return mark_count(select, ns_match) == height
        end, 1500)

        for i = 1, #positions do
            positions[i] = {}
        end
        select:list(entries, positions)
        helpers.wait_for(function()
            return mark_count(select, ns_match) == 0
        end, 1500)

        select:close()
    end

    do
        local enabled = true
        local decor = Select.Decorator.new()
        function decor:decorate()
            if not enabled then
                return nil
            end
            return { { "A", "String" } }
        end

        local select = new_select({
            prompt_list = true,
            prompt_input = false,
            preview = false,
            decorators = { decor },
        })

        select:open()
        select:list(entries)

        local height = vim.api.nvim_win_get_height(select.list_window)
        helpers.wait_for(function()
            return mark_count(select, ns_decor) == height
        end, 1500)

        enabled = false
        select:list(entries)
        helpers.wait_for(function()
            return mark_count(select, ns_decor) == 0
        end, 1500)

        select:close()
    end

    do
        local enabled = true
        local highlighter = Select.Highlighter.new()
        function highlighter:highlight(entry, line)
            if not enabled then
                return nil
            end
            return 0, #line, "Directory"
        end

        local select = new_select({
            prompt_list = true,
            prompt_input = false,
            preview = false,
            highlighters = { highlighter },
        })

        select:open()
        select:list(entries)

        local height = vim.api.nvim_win_get_height(select.list_window)
        helpers.wait_for(function()
            return mark_count(select, ns_line) == height
        end, 1500)

        enabled = false
        select:list(entries)
        helpers.wait_for(function()
            return mark_count(select, ns_line) == 0
        end, 1500)

        select:close()
    end
end

local function run_highlighter_multi_case()
    local multi = Select.Highlighter.new()
    function multi:highlight()
        return {
            { 0, 1, "Directory" },
            { 1, 1, "Directory" },
        }
    end

    local select = new_select({
        prompt_list = true,
        prompt_input = false,
        preview = false,
        highlighters = { multi },
    })

    select:open()
    local entries = {}
    for i = 1, 50 do
        entries[i] = string.format("item-%02d", i)
    end
    select:list(entries)

    local ns = vim.api.nvim_create_namespace("list_textline_namespace")
    local height = vim.api.nvim_win_get_height(select.list_window)

    helpers.wait_for(function()
        local extmarks = vim.api.nvim_buf_get_extmarks(
            select.list_buffer,
            ns,
            { 0, 0 },
            { -1, -1 },
            { details = true }
        )
        return extmarks and #extmarks == height * 2
    end, 1500)

    local extmarks = vim.api.nvim_buf_get_extmarks(
        select.list_buffer,
        ns,
        { 0, 0 },
        { -1, -1 },
        { details = true }
    )
    helpers.eq(#extmarks, height * 2, "multi highlighter spans per line")

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
    helpers.run_test_case("select_action", run_action_case)
    helpers.run_test_case("select_toggle_signs", run_toggle_signs_case)
    helpers.run_test_case("select_action_dispatch", run_select_action_case)
    helpers.run_test_case("select_toggle_selection", run_toggle_selection_case)
    helpers.run_test_case("select_basic", run_basic_case)
    helpers.run_test_case("select_display", run_display_case)
    helpers.run_test_case("select_display_nil", run_display_nil_case)
    helpers.run_test_case("select_display_index", run_display_index_case)
    helpers.run_test_case("select_display_decorator", run_display_decorator_case)
    helpers.run_test_case("select_display_highlighter", run_display_highlighter_case)
    helpers.run_test_case("select_display_positions", run_display_positions_case)
    helpers.run_test_case("select_display_rerender", run_display_rerender_case)
    helpers.run_test_case("select_display_rapid", run_display_rapid_case)
    helpers.run_test_case("select_preview_fallback", run_preview_fallback_case)
    helpers.run_test_case("select_preview_success", run_preview_success_case)
    helpers.run_test_case("select_preview_default_message", run_preview_default_message_case)
    helpers.run_test_case("select_preview_error_eventignore", run_preview_error_eventignore_case)
    helpers.run_test_case("select_toggle_quickfix", run_toggle_quickfix_case)
    helpers.run_test_case("select_toggle", run_toggle_case)
    helpers.run_test_case("select_toggle_scroll", run_toggle_scroll_case)
    helpers.run_test_case("select_toggle_all_exclusion", run_toggle_all_exclusion_case)
    helpers.run_test_case("select_toggle_all_quickfix", run_toggle_all_quickfix_case)
    helpers.run_test_case("select_selection_command", run_selection_command_case)
    helpers.run_test_case("select_prompt", run_prompt_case)
    helpers.run_test_case("select_prompt_sync_results", run_prompt_sync_results_case)
    helpers.run_test_case("select_preview_custom", run_preview_case)
    helpers.run_test_case("select_preview_buffer", run_buffer_preview_case)
    helpers.run_test_case("select_preview_command", run_command_preview_case)
    helpers.run_test_case("select_decorator", run_decorator_case)
    helpers.run_test_case("select_wrap_decorator", run_wrap_decorator_case)
    helpers.run_test_case("select_extmark_composite", run_extmark_composite_case)
    helpers.run_test_case("select_extmark_cleanup", run_extmark_cleanup_case)
    helpers.run_test_case("select_highlighter_multi", run_highlighter_multi_case)
    helpers.run_test_case("select_converter", run_converter_case)
end

return M
