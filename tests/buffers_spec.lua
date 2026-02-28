---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "buffers" }

local function setup_buffers()
    helpers.reset_state()
    local path1 = helpers.create_temp_path("/tmp/fuzzy-buf-")
    local path2 = helpers.create_temp_path("/tmp/fuzzy-alt-")
    local path3 = helpers.create_temp_path("/tmp/fuzzy-hidden-")

    local buf1 = helpers.create_named_buffer(path1, {
        "buffer one",
        "line two",
    }, true)
    local buf2 = helpers.create_named_buffer(path2, {
        "buffer two",
        "line two",
    }, true)
    local buf3 = helpers.create_named_buffer(path3, {
        "hidden buffer",
    }, false)

    vim.api.nvim_set_current_buf(buf1)
    vim.api.nvim_set_current_buf(buf2)
    vim.api.nvim_set_current_buf(buf1)

    return {
        buf1 = buf1,
        buf2 = buf2,
        buf3 = buf3,
    }
end

local function assert_entries_include(picker, buf)
    local entries = helpers.get_entries(picker) or {}
    local found = false
    for _, entry in ipairs(entries) do
        if entry == buf or (type(entry) == "table" and entry.bufnr == buf) then
            found = true
            break
        end
    end
    helpers.assert_ok(found, "missing entry")
end

local function assert_entries_exclude(picker, buf)
    local entries = helpers.get_entries(picker) or {}
    for _, entry in ipairs(entries) do
        if entry == buf or (type(entry) == "table" and entry.bufnr == buf) then
            error("unexpected entry")
        end
    end
end

local function run_test_case(name, opts, expectations)
    local picker = helpers.open_buffers_picker(opts)
    helpers.assert_ok(picker ~= nil, table.concat({ "picker nil: ", name }))
    helpers.wait_for_list(picker)

    if expectations.query then
        helpers.type_query(picker, expectations.query)
        helpers.wait_for(function()
            return helpers.get_query(picker) == expectations.query
        end, 1500)
        helpers.eq(helpers.get_query(picker), expectations.query, "query")
    end

    local lines = helpers.get_list_lines(picker)

    if expectations.include then
        for _, buf in ipairs(expectations.include) do
            assert_entries_include(picker, buf)
            if expectations.display then
                helpers.assert_line_contains(
                    lines,
                    expectations.display[buf],
                    "display"
                )
            end
        end
    end

    if expectations.exclude then
        for _, buf in ipairs(expectations.exclude) do
            assert_entries_exclude(picker, buf)
            if expectations.display then
                helpers.assert_line_missing(
                    lines,
                    expectations.display[buf],
                    "display"
                )
            end
        end
    end

    helpers.close_picker(picker)
end

function M.run()
    local bufs = setup_buffers()
    local display = {
        [bufs.buf1] = vim.fs.basename(vim.api.nvim_buf_get_name(bufs.buf1)),
        [bufs.buf2] = vim.fs.basename(vim.api.nvim_buf_get_name(bufs.buf2)),
        [bufs.buf3] = vim.fs.basename(vim.api.nvim_buf_get_name(bufs.buf3)),
    }

    run_test_case("default", {
        sort_lastused = true,
        no_term_buffers = true,
        ignore_current_buffer = false,
        show_unlisted = true,
        show_unloaded = true,
        preview = false,
        icons = false,
    }, {
        include = { bufs.buf1, bufs.buf2 },
        display = display,
    })

    run_test_case("ignore_current", {
        ignore_current_buffer = true,
        show_unlisted = true,
        show_unloaded = true,
        preview = false,
        icons = false,
    }, {
        exclude = { vim.api.nvim_get_current_buf() },
        include = { bufs.buf2 },
        display = display,
    })

    run_test_case("unlisted", {
        show_unlisted = false,
        show_unloaded = true,
        preview = false,
        icons = false,
    }, {
        exclude = { bufs.buf3 },
        display = display,
    })

    run_test_case("listed", {
        show_unlisted = true,
        show_unloaded = true,
        preview = false,
        icons = false,
    }, {
        include = { bufs.buf3 },
        display = display,
    })

    run_test_case("query", {
        show_unlisted = true,
        show_unloaded = true,
        preview = false,
        icons = false,
    }, {
        query = "buffer one",
        display = display,
    })
end

return M
