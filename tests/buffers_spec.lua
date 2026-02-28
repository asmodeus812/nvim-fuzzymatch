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
    local cwd_dir = helpers.create_temp_dir()
    local other_dir = helpers.create_temp_dir()
    local cwd_path = vim.fs.joinpath(cwd_dir, "cwd.txt")
    local other_path = vim.fs.joinpath(other_dir, "other.txt")
    local cwd_buf = helpers.create_named_buffer(cwd_path, { "cwd buffer" }, true)
    local other_buf = helpers.create_named_buffer(other_path, { "other buffer" }, true)
    local display = {
        [bufs.buf1] = vim.fs.basename(vim.api.nvim_buf_get_name(bufs.buf1)),
        [bufs.buf2] = vim.fs.basename(vim.api.nvim_buf_get_name(bufs.buf2)),
        [bufs.buf3] = vim.fs.basename(vim.api.nvim_buf_get_name(bufs.buf3)),
        [cwd_buf] = vim.fs.basename(vim.api.nvim_buf_get_name(cwd_buf)),
        [other_buf] = vim.fs.basename(vim.api.nvim_buf_get_name(other_buf)),
    }

    run_test_case("default", {
        sort_lastused = true,
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

    run_test_case("cwd", {
        show_unlisted = true,
        show_unloaded = true,
        preview = false,
        icons = false,
        cwd = cwd_dir,
    }, {
        include = { cwd_buf },
        exclude = { other_buf },
        display = display,
    })

    helpers.run_test_case("cwd_uses_content_arg", function()
        local Picker = require("fuzzy.picker")
        local captured = nil
        helpers.with_mock(Picker, "new", function(opts)
            captured = opts
            return { _options = opts, open = function() end }
        end, function()
            require("fuzzy.pickers.buffers").open_buffers_picker({
                show_unlisted = true,
                show_unloaded = true,
                preview = false,
                icons = false,
                cwd = "/should/not/use",
            })
        end)
        helpers.assert_ok(captured and captured.content, "content missing")
        local entries = {}
        captured.content(function(entry)
            if entry ~= nil then
                entries[#entries + 1] = entry
            end
        end, { tab = vim.api.nvim_get_current_tabpage() }, cwd_dir)
        local found_cwd = false
        local found_other = false
        for _, entry in ipairs(entries) do
            local bufnr = type(entry) == "table" and entry.bufnr or entry
            if bufnr == cwd_buf then
                found_cwd = true
            elseif bufnr == other_buf then
                found_other = true
            end
        end
        helpers.assert_ok(found_cwd, "cwd entry missing")
        helpers.assert_ok(not found_other, "other entry present")
    end)

    helpers.run_test_case("include_special_true", function()
        local term_buf = helpers.create_named_buffer("", { "special" }, true)
        vim.bo[term_buf].buftype = "nofile"
        local picker = helpers.open_buffers_picker({
            show_unlisted = true,
            show_unloaded = true,
            include_special = true,
            preview = false,
            icons = false,
        })
        helpers.wait_for_list(picker)
        assert_entries_include(picker, term_buf)
        helpers.close_picker(picker)
        vim.api.nvim_buf_delete(term_buf, { force = true })
    end)

    helpers.run_test_case("include_special_table", function()
        local term_buf = helpers.create_named_buffer("", { "special a" }, true)
        vim.bo[term_buf].buftype = "nofile"
        local quickfix_buf = helpers.create_named_buffer("", { "special b" }, true)
        vim.bo[quickfix_buf].buftype = "prompt"
        local picker = helpers.open_buffers_picker({
            show_unlisted = true,
            show_unloaded = true,
            include_special = { "nofile" },
            preview = false,
            icons = false,
        })
        helpers.wait_for_list(picker)
        assert_entries_include(picker, term_buf)
        assert_entries_exclude(picker, quickfix_buf)
        helpers.close_picker(picker)
        vim.api.nvim_buf_delete(term_buf, { force = true })
        vim.api.nvim_buf_delete(quickfix_buf, { force = true })
    end)

end

return M
