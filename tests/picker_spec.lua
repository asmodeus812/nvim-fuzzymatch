---@diagnostic disable: invisible
local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local helpers = require("script.test_utils")
local util = require("fuzzy.pickers.util")

local M = { name = "picker" }

local function with_stream_count(callback)
    local original_new = Picker.new
    helpers.with_mock(Picker, "new", function(opts)
        local content_last = {
            args = nil,
            cwd = nil,
            env = nil,
        }
        if type(opts.content) == "function" then
            local original_content = opts.content
            opts.content = function(stream_callback, args, cwd, env)
                content_last.args = args
                content_last.cwd = cwd
                content_last.env = env
                return original_content(stream_callback, args, cwd, env)
            end
        end
        local picker = original_new(opts)
        if opts and opts._test_skip_command then
            picker._test_skip_command = true
        end
        local count = 0
        local original_start = picker.stream.start
        picker.stream.start = function(self, cmd, start_opts)
            count = count + 1
            if type(cmd) == "string" and type(start_opts) == "table" then
                picker._test_last_args = start_opts.args
                picker._test_last_cwd = start_opts.cwd
                picker._test_last_env = start_opts.env
                if start_opts.callback then
                    start_opts.callback({}, {})
                end
                self.results = self.results or {}
                return
            end
            return original_start(self, cmd, start_opts)
        end
        picker._test_stream_count = function()
            return count
        end
        picker._test_content_last = content_last
        return picker
    end, callback)
end

local function get_last_args(picker)
    if picker._test_content_last and picker._test_content_last.args ~= nil then
        return {
            kind = "function",
            args = picker._test_content_last.args,
            cwd = picker._test_content_last.cwd,
            env = picker._test_content_last.env,
        }
    end
    return {
        kind = "command",
        args = picker._test_last_args,
        cwd = picker._test_last_cwd,
        env = picker._test_last_env,
    }
end

local function get_header_text(prompt_buffer)
    local namespaces = vim.api.nvim_get_namespaces()
    local ns = namespaces["list_header_namespace"]
    helpers.assert_ok(type(ns) == "number", "header namespace")
    local marks = vim.api.nvim_buf_get_extmarks(
        prompt_buffer,
        ns,
        0,
        -1,
        { details = true }
    )
    for _, mark in ipairs(marks or {}) do
        local details = mark[4]
        local virt_lines = details and details.virt_lines
        if virt_lines and virt_lines[1] then
            local line = {}
            for _, chunk in ipairs(virt_lines[1]) do
                line[#line + 1] = chunk[1]
            end
            return table.concat(line)
        end
    end
    return nil
end

local function get_status_text(prompt_buffer)
    local namespaces = vim.api.nvim_get_namespaces()
    local ns = namespaces["list_status_namespace"]
    helpers.assert_ok(type(ns) == "number", "status namespace")
    local marks = vim.api.nvim_buf_get_extmarks(
        prompt_buffer,
        ns,
        0,
        -1,
        { details = true }
    )
    for _, mark in ipairs(marks or {}) do
        local details = mark[4]
        local virt_text = details and details.virt_text
        if virt_text and virt_text[1] then
            local line = {}
            for _, chunk in ipairs(virt_text) do
                line[#line + 1] = chunk[1]
            end
            return table.concat(line)
        end
    end
    return nil
end

local function run_rerun_case(name, open_picker, mutate, assert_args)
    helpers.run_test_case(name, function()
        with_stream_count(function()
            local picker = open_picker()
            helpers.wait_for_stream(picker)
            local before = get_last_args(picker)
            local count_before = picker._test_stream_count()
            mutate(picker)
            picker:hide()
            if picker._test_open_cwd then
                helpers.with_cwd(picker._test_open_cwd, function()
                    picker:open()
                    helpers.wait_for_stream(picker)
                end)
            else
                picker:open()
                helpers.wait_for_stream(picker)
            end
            vim.wait(120, function()
                return true
            end, 10)
            local after = get_last_args(picker)
            helpers.assert_ok(
                picker._test_stream_count() > count_before,
                "content should re-run"
            )
            if assert_args then
                assert_args(before, after, picker)
            end
            helpers.close_picker(picker)
        end)
    end)
end

function M.run()
    local picker = Picker.new({
        content = { "alpha", "beta", "gamma" },
        headers = { { "Picker" } },
        preview = false,
        prompt_query = "be",
        prompt_debounce = 0,
        actions = {
            ["<cr>"] = Select.default_select,
        },
    })
    helpers.assert_ok(picker:options() ~= nil, "picker options")
    helpers.eq(picker:options().prompt_query, "be", "picker options reference")

    picker:open()
    helpers.wait_for_list(picker)
    helpers.wait_for_line_contains(picker, "alpha")
    helpers.assert_ok(helpers.wait_for(function()
        return picker.select and picker.select._state.entries
            and #picker.select._state.entries == 3
    end, 1500), "entries")

    helpers.eq(#picker.select._state.entries, 3, "entries")
    local lines = helpers.get_list_lines(picker)
    helpers.assert_ok(#lines > 0, "list empty")
    helpers.assert_line_contains(lines, "alpha", "missing")

    helpers.type_query(picker, "gam")
    helpers.wait_for_match(picker)

    helpers.assert_ok(helpers.wait_for(function()
        local status = get_status_text(picker.select.prompt_buffer)
        return status and status:find("1/3", 1, true) ~= nil
    end, 1500), "status filtered")

    helpers.type_query(picker, "<c-u>")
    helpers.assert_ok(helpers.wait_for(function()
        return picker.select:query() == ""
    end, 1500), "prompt cleared")
    helpers.assert_ok(helpers.wait_for(function()
        local status = get_status_text(picker.select.prompt_buffer)
        return status and status:find("3/3", 1, true) ~= nil
    end, 1500), "status reset")

    picker:close()

    local stream_picker = Picker.new({
        content = function(cb)
            cb("one")
            cb("two")
            cb("three")
            cb(nil)
        end,
        display = function(entry)
            return string.upper(entry)
        end,
        preview = false,
        actions = {
            ["<cr>"] = Select.default_select,
        },
    })

    stream_picker:open()
    helpers.wait_for_list(stream_picker)
    helpers.wait_for_line_contains(stream_picker, "ONE")
    helpers.assert_ok(helpers.wait_for(function()
        return stream_picker.select
            and stream_picker.select._state.entries
            and #stream_picker.select._state.entries == 3
    end, 1500), "stream entries")

    local stream_lines = helpers.get_list_lines(stream_picker)
    helpers.assert_line_contains(stream_lines, "ONE", "display")
    helpers.assert_line_contains(stream_lines, "TWO", "display")

    stream_picker:close()

    helpers.run_test_case("picker_stream_slow_query_match", function()
        local chunks = {
            { "beta",  "omicron", "lambda" },
            { "delta", "zeta",    "omicron" },
            { "eta",   "theta",   "iota" },
        }
        local expected = {
            beta = true,
            delta = true,
            zeta = true,
            eta = true,
            theta = true,
            iota = true,
        }
        local Async = require("fuzzy.async")
        local state = { sent = 0 }

        local function wait_ms(ms)
            local done = false
            vim.defer_fn(function()
                done = true
            end, ms)
            while not done do
                Async.yield()
            end
        end

        local function wait_for_entries(picker, min_count)
            helpers.assert_ok(helpers.wait_for(function()
                local entries = helpers.get_entries(picker)
                return entries and #entries >= min_count
            end, 1500), "entries count")
        end

        local picker = Picker.new({
            content = function(cb)
                wait_ms(25)
                for _, entry in ipairs(chunks[1]) do
                    cb(entry)
                end
                state.sent = 1
                wait_ms(50)

                for _, entry in ipairs(chunks[2]) do
                    cb(entry)
                end
                state.sent = 2
                wait_ms(50)

                for _, entry in ipairs(chunks[3]) do
                    cb(entry)
                end
                state.sent = 3
                cb(nil)
            end,
            preview = false,
            prompt_debounce = 0,
            stream_debounce = 0,
            stream_step = 3,
            prompt_query = "ta",
            prompt_debounce = 0,
            prompt_debounce = 0,
            actions = {
                ["<cr>"] = Select.default_select,
            },
        })

        picker:open()
        helpers.type_query(picker, "ta")
        helpers.assert_ok(helpers.wait_for(function()
            return picker.select:query() == "ta"
        end, 1500), "prompt query")

        helpers.assert_ok(helpers.wait_for(function()
            return state.sent >= 1
        end, 1500), "chunk 1 sent")
        wait_for_entries(picker, 1)

        helpers.assert_ok(helpers.wait_for(function()
            return state.sent >= 2
        end, 1500), "chunk 2 sent")
        wait_for_entries(picker, 3)

        helpers.assert_ok(helpers.wait_for(function()
            return state.sent >= 3
        end, 1500), "chunk 3 sent")
        wait_for_entries(picker, 6)

        helpers.wait_for_stream(picker)

        local entries = helpers.get_entries(picker) or {}
        helpers.eq(#entries, 6, "ta matches")
        for _, entry in ipairs(entries) do
            helpers.assert_ok(
                type(entry) == "string" and expected[entry] == true,
                "entry matches expected set"
            )
        end
        picker:close()
    end)

    helpers.run_test_case("picker_stream_query_change_resets", function()
        local chunks = {
            { "beta",  "omicron", "lambda" },
            { "delta", "zeta",    "omicron" },
            { "eta",   "theta",   "iota" },
        }
        local Async = require("fuzzy.async")
        local state = { sent = 0, allow_start = false, allow_chunk3 = false }

        local function wait_ms(ms)
            local done = false
            vim.defer_fn(function()
                done = true
            end, ms)
            while not done do
                Async.yield()
            end
        end

        local picker = Picker.new({
            content = function(cb)
                while not state.allow_start do
                    Async.yield()
                end
                wait_ms(10)
                for _, entry in ipairs(chunks[1]) do
                    cb(entry)
                end
                state.sent = 1
                wait_ms(50)

                for _, entry in ipairs(chunks[2]) do
                    cb(entry)
                end
                state.sent = 2
                while not state.allow_chunk3 do
                    Async.yield()
                end
                wait_ms(10)

                for _, entry in ipairs(chunks[3]) do
                    cb(entry)
                end
                state.sent = 3
                cb(nil)
            end,
            preview = false,
            prompt_debounce = 0,
            stream_debounce = 0,
            stream_step = 3,
            prompt_query = "ta",
            actions = {
                ["<cr>"] = Select.default_select,
            },
        })

        picker:open()
        helpers.type_query(picker, "ta")
        helpers.assert_ok(helpers.wait_for(function()
            return picker.select:query() == "ta"
        end, 1500), "prompt query")
        state.allow_start = true

        helpers.assert_ok(helpers.wait_for(function()
            return state.sent >= 2
        end, 1500), "chunk 2 sent")
        helpers.wait_for_match(picker, 1500)
        helpers.assert_ok(helpers.wait_for(function()
            local entries = helpers.get_entries(picker)
            return entries and #entries >= 1
        end, 1500), "entries after chunk 2")

        helpers.type_query(picker, "th")
        helpers.assert_ok(helpers.wait_for(function()
            return picker.select:query() == "th"
        end, 1500), "prompt query")
        state.allow_chunk3 = true

        helpers.wait_for_stream(picker)
        helpers.wait_for_match(picker, 1500)
        helpers.assert_ok(helpers.wait_for(function()
            local entries = helpers.get_entries(picker) or {}
            if #entries < 1 then
                return false
            end
            for _, entry in ipairs(entries) do
                if entry ~= "theta" then
                    return false
                end
            end
            return true
        end, 1500), "th match from later chunk")
        picker:close()
    end)

    helpers.run_test_case("interactive_no_open_rerun", function()
        with_stream_count(function()
            local interactive_picker = Picker.new({
                content = "rg",
                preview = false,
                context = {
                    args = { "--test" },
                    cwd = vim.loop.cwd,
                },
                interactive = function(_, arguments)
                    return arguments
                end,
            })
            interactive_picker:open()
            helpers.assert_ok(helpers.wait_for(function()
                return interactive_picker.select and interactive_picker.select:isopen()
            end, 1500), "interactive open")
            helpers.eq(interactive_picker._test_stream_count(), 0, "interactive open should not start stream")
            interactive_picker._state.context.args = { "--test-open" }
            interactive_picker:hide()
            interactive_picker:open()
            helpers.assert_ok(helpers.wait_for(function()
                return interactive_picker.select and interactive_picker.select:isopen()
            end, 1500), "interactive reopen")
            helpers.eq(interactive_picker._test_stream_count(), 0, "interactive reopen should not start stream")
            interactive_picker:close()
        end)
    end)

    helpers.run_test_case("picker_cancel_preserves_results", function()
        local picker = Picker.new({
            content = function(callback)
                callback("one")
                callback("two")
                callback(nil)
            end,
            preview = false,
            prompt_debounce = 0,
        })
        picker:open()
        helpers.wait_for_stream(picker)
        helpers.assert_ok(picker.stream.results and #picker.stream.results == 2, "stream results")

        local cancel = picker:_cancel_prompt()
        cancel(picker.select)

        helpers.assert_ok(picker.stream.results and #picker.stream.results == 2, "cancel keeps results")
        helpers.assert_ok(picker.select:isopen() == false, "cancel closes select")
    end)

    helpers.run_test_case("picker_close_destroys_results", function()
        local picker = Picker.new({
            content = function(callback)
                callback("one")
                callback("two")
                callback(nil)
            end,
            preview = false,
            prompt_debounce = 0,
        })
        picker:open()
        helpers.wait_for_stream(picker)
        helpers.assert_ok(picker.stream.results and #picker.stream.results == 2, "stream results")

        picker:close()
        helpers.assert_ok(picker.stream.results == nil, "close destroys results")
    end)

    helpers.run_test_case("picker_cwd_header", function()
        local cwd = "/tmp/fuzzy-header-a"
        local header_opts = {
            cwd = function()
                return cwd
            end,
        }
        local picker = Picker.new({
            content = { "alpha" },
            headers = util.build_picker_headers("Picker", header_opts),
            preview = false,
            prompt_debounce = 0,
        })
        picker:open()
        helpers.assert_ok(helpers.wait_for(function()
            return helpers.is_window_valid(picker.select.prompt_window)
        end, 1500), "prompt window")
        local header = get_header_text(picker.select.prompt_buffer)
        helpers.assert_ok(header and header:find("fuzzy-header-a", 1, true), "header cwd a")

        picker:hide()
        cwd = "/tmp/fuzzy-header-b"
        picker:open()
        helpers.assert_ok(helpers.wait_for(function()
            return helpers.is_window_valid(picker.select.prompt_window)
        end, 1500), "prompt window")
        header = get_header_text(picker.select.prompt_buffer)
        helpers.assert_ok(header and header:find("fuzzy-header-b", 1, true), "header cwd b")
        picker:close()
    end)

    helpers.run_test_case("picker_header_actions", function()
        local picker = Picker.new({
            content = { "alpha" },
            headers = { { "Picker" } },
            preview = false,
            prompt_debounce = 0,
            actions = {
                ["<c-x>"] = { Select.noop_select, "close" },
                ["<c-y>"] = { Select.noop_select, "yank" },
            },
        })
        picker:open()
        helpers.assert_ok(helpers.wait_for(function()
            return helpers.is_window_valid(picker.select.prompt_window)
        end, 1500), "prompt window")
        local header = get_header_text(picker.select.prompt_buffer) or ""
        helpers.assert_ok(header:find("Picker", 1, true), "header title")
        helpers.assert_ok(header:find("<c-x>", 1, true), "header action key")
        helpers.assert_ok(header:find("close", 1, true), "header action close")
        helpers.assert_ok(header:find("<c-y>", 1, true), "header action key yank")
        helpers.assert_ok(header:find("yank", 1, true), "header action yank")
        picker:close()
    end)

    helpers.run_test_case("picker_header_custom_blocks", function()
        local picker = Picker.new({
            content = { "alpha" },
            headers = {
                { "Alpha" },
                { function() return "Beta" end },
                { { "Gamma", "SelectHeaderDefault" } },
            },
            preview = false,
            prompt_debounce = 0,
        })
        picker:open()
        helpers.assert_ok(helpers.wait_for(function()
            return helpers.is_window_valid(picker.select.prompt_window)
        end, 1500), "prompt window")
        local header = get_header_text(picker.select.prompt_buffer) or ""
        helpers.assert_ok(header:find("Alpha", 1, true), "header alpha")
        helpers.assert_ok(header:find("Beta", 1, true), "header beta")
        helpers.assert_ok(header:find("Gamma", 1, true), "header gamma")
        picker:close()
    end)

    helpers.run_test_case("picker_header_cwd_truncate", function()
        local long_cwd = "/home/user/projects/very/long/path/for/fuzzymatch"
        local picker = Picker.new({
            content = { "alpha" },
            headers = util.build_picker_headers("Picker", {
                cwd = function()
                    return long_cwd
                end,
            }),
            preview = false,
            prompt_debounce = 0,
        })
        picker:open()
        helpers.assert_ok(helpers.wait_for(function()
            return helpers.is_window_valid(picker.select.prompt_window)
        end, 1500), "prompt window")
        local header = get_header_text(picker.select.prompt_buffer) or ""
        helpers.assert_ok(header:find("/.../", 1, true), "header cwd ellipsis")
        helpers.assert_ok(header:find("fuzzymatch", 1, true), "header cwd tail")
        picker:close()
    end)

    helpers.run_test_case("picker_tick_true_reruns_on_open", function()
        with_stream_count(function()
            local picker = Picker.new({
                content = function(callback)
                    callback("alpha")
                    callback(nil)
                end,
                context = {
                    tick = true,
                },
                preview = false,
                prompt_debounce = 0,
            })
            picker:open()
            helpers.wait_for_stream(picker)
            local count_before = picker._test_stream_count()
            picker:hide()
            picker:open()
            helpers.wait_for_stream(picker)
            helpers.assert_ok(
                picker._test_stream_count() > count_before,
                "tick=true should rerun on open"
            )
            picker:close()
        end)
    end)

    run_rerun_case("rerun_buffers", function()
        return require("fuzzy.pickers.buffers").open_buffers_picker({
            show_unlisted = true,
            show_unloaded = true,
            preview = false,
            icons = false,
            prompt_debounce = 0,
        })
    end, function(picker)
        picker._test_buf = helpers.create_named_buffer("rerun_buffers.txt", { "buf" }, true)
        local win = vim.api.nvim_get_current_win()
        local ok, old = pcall(vim.api.nvim_get_option_value, "winfixbuf", { win = win })
        if ok then
            pcall(vim.api.nvim_set_option_value, "winfixbuf", false, { win = win })
        end
        pcall(vim.api.nvim_set_current_buf, picker._test_buf)
        if ok then
            pcall(vim.api.nvim_set_option_value, "winfixbuf", old, { win = win })
        end
    end, function(before, after, picker)
        local buffers = after.args.buffers_list or after.args.buffers
        helpers.assert_ok(type(buffers) == "table", "buffers args list")
        vim.api.nvim_buf_delete(picker._test_buf, { force = true })
    end)

    run_rerun_case("rerun_lines", function()
        return require("fuzzy.pickers.lines").open_lines_picker({
            show_unlisted = true,
            show_unloaded = true,
            preview = false,
            prompt_debounce = 0,
        })
    end, function(picker)
        picker._test_buf = helpers.create_named_buffer("", { "buf" }, true)
    end, function(_, after, picker)
        helpers.assert_ok(type(after.args.buffers) == "table", "lines buffers")
        vim.api.nvim_buf_delete(picker._test_buf, { force = true })
    end)

    run_rerun_case("rerun_blines", function()
        return require("fuzzy.pickers.blines").open_blines_picker({
            preview = false,
            prompt_debounce = 0,
        })
    end, function(picker)
        local buf = picker._state
            and picker._state._evaluated_context
            and picker._state._evaluated_context.args
            and picker._state._evaluated_context.args.buf
        if buf and vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "extra" })
        end
    end, function(before, after)
        helpers.assert_ok(after.args.line_count >= before.args.line_count, "blines line_count")
    end)

    run_rerun_case("rerun_changes", function()
        return require("fuzzy.pickers.changes").open_changes_picker({
            preview = false,
            icons = false,
            prompt_debounce = 0,
        })
    end, function(picker)
        local buf = picker._state
            and picker._state._evaluated_context
            and picker._state._evaluated_context.args
            and picker._state._evaluated_context.args.buf
        if buf and vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "change" })
        end
    end, function(before, after)
        helpers.assert_ok(after.args.tick >= before.args.tick, "changes tick")
        helpers.assert_ok(#after.args.items >= #before.args.items, "changes items")
    end)

    run_rerun_case("rerun_quickfix", function()
        return require("fuzzy.pickers.quickfix").open_quickfix_picker({
            preview = false,
            icons = false,
            prompt_debounce = 0,
        })
    end, function(picker)
        local dir_path = helpers.create_temp_dir()
        local file_path = vim.fs.joinpath(dir_path, "rerun_quickfix.txt")
        helpers.write_file(file_path, "quickfix\n")
        picker._test_qf_buf = helpers.create_named_buffer(file_path, { "quickfix" }, true)
        vim.fn.setqflist({}, "r", {
            title = "QF",
            items = {
                {
                    bufnr = picker._test_qf_buf,
                    filename = file_path,
                    lnum = 1,
                    col = 1,
                    text = "rerun-quickfix-marker",
                },
            },
        })
    end, function(_, _, picker)
        helpers.assert_ok(helpers.wait_for(function()
            local current = get_last_args(picker)
            for _, entry in ipairs((current.args and current.args.items) or {}) do
                if entry.text == "rerun-quickfix-marker" and entry.bufnr == picker._test_qf_buf then
                    return true
                end
            end
            return false
        end, 1500), "quickfix rerun args ready")
        local after = get_last_args(picker)
        local found = false
        for _, entry in ipairs((after.args and after.args.items) or {}) do
            if entry.text == "rerun-quickfix-marker" and entry.bufnr == picker._test_qf_buf then
                found = true
                break
            end
        end
        helpers.assert_ok(found, "quickfix rerun args")
        if picker._test_qf_buf and vim.api.nvim_buf_is_valid(picker._test_qf_buf) then
            vim.api.nvim_buf_delete(picker._test_qf_buf, { force = true })
        end
    end)

    run_rerun_case("rerun_loclist", function()
        return require("fuzzy.pickers.loclist").open_loclist_picker({
            preview = false,
            icons = false,
            prompt_debounce = 0,
        })
    end, function(picker)
        local wid = picker._state
            and picker._state._evaluated_context
            and picker._state._evaluated_context.args
            and picker._state._evaluated_context.args.wid
            or 0
        local dir_path = helpers.create_temp_dir()
        local file_path = vim.fs.joinpath(dir_path, "rerun_loclist.txt")
        helpers.write_file(file_path, "loclist\n")
        picker._test_ll_buf = helpers.create_named_buffer(file_path, { "loclist" }, true)
        vim.fn.setloclist(wid, {}, "r", {
            title = "LL",
            items = {
                {
                    bufnr = picker._test_ll_buf,
                    filename = file_path,
                    lnum = 1,
                    col = 1,
                    text = "rerun-loclist-marker",
                },
            },
        })
    end, function(_, _, picker)
        helpers.assert_ok(helpers.wait_for(function()
            local current = get_last_args(picker)
            for _, entry in ipairs((current.args and current.args.items) or {}) do
                if entry.text == "rerun-loclist-marker" and entry.bufnr == picker._test_ll_buf then
                    return true
                end
            end
            return false
        end, 1500), "loclist rerun args ready")
        local after = get_last_args(picker)
        local found = false
        for _, entry in ipairs((after.args and after.args.items) or {}) do
            if entry.text == "rerun-loclist-marker" and entry.bufnr == picker._test_ll_buf then
                found = true
                break
            end
        end
        helpers.assert_ok(found, "loclist rerun args")
        if picker._test_ll_buf and vim.api.nvim_buf_is_valid(picker._test_ll_buf) then
            vim.api.nvim_buf_delete(picker._test_ll_buf, { force = true })
        end
    end)

    helpers.run_test_case("rerun_jumps", function()
        with_stream_count(function()
            local toggle = false
            helpers.with_mock(vim.fn, "getjumplist", function()
                if toggle then
                    return { { { bufnr = 1, lnum = 1, col = 1, nr = 1 } }, 1 }
                end
                return { {}, 1 }
            end, function()
                local picker = require("fuzzy.pickers.jumps").open_jumps_picker({
                    preview = false,
                    icons = false,
                    prompt_debounce = 0,
                })
                helpers.wait_for_stream(picker)
                local count_before = picker._test_stream_count()
                toggle = true
                picker:hide()
                picker:open()
                helpers.wait_for_stream(picker)
                helpers.assert_ok(helpers.wait_for(function()
                    local current = get_last_args(picker)
                    for _, item in ipairs((current.args and current.args.items) or {}) do
                        if item.nr == 1 then
                            return true
                        end
                    end
                    return false
                end, 1500), "jumps marker")
                local after = get_last_args(picker)
                helpers.assert_ok(
                    picker._test_stream_count() > count_before,
                    "content should re-run"
                )
                helpers.eq(#(after.args.items or {}), 1, "jumps items")
                helpers.eq(after.args.items[1].nr, 1, "jumps marker nr")
                helpers.close_picker(picker)
            end)
        end)
    end)

    helpers.run_test_case("rerun_marks", function()
        with_stream_count(function()
            local toggle = false
            helpers.with_mock(vim.fn, "getmarklist", function()
                if toggle then
                    return { { mark = "a", pos = { 1, 1, 1, 0 }, file = "" } }
                end
                return {}
            end, function()
                local picker = require("fuzzy.pickers.marks").open_marks_picker({
                    preview = false,
                    icons = false,
                    prompt_debounce = 0,
                })
                helpers.wait_for_stream(picker)
                local count_before = picker._test_stream_count()
                toggle = true
                picker:hide()
                picker:open()
                helpers.wait_for_stream(picker)
                helpers.assert_ok(helpers.wait_for(function()
                    local current = get_last_args(picker)
                    for _, item in ipairs((current.args and current.args.items) or {}) do
                        if item.mark == "a" then
                            return true
                        end
                    end
                    return false
                end, 1500), "marks marker")
                local after = get_last_args(picker)
                helpers.assert_ok(
                    picker._test_stream_count() > count_before,
                    "content should re-run"
                )
                local found = false
                for _, entry in ipairs(after.args.items or {}) do
                    if entry.mark == "a" then
                        found = true
                        break
                    end
                end
                helpers.assert_ok(found, "marks args")
                helpers.close_picker(picker)
            end)
        end)
    end)

    run_rerun_case("rerun_registers", function()
        return require("fuzzy.pickers.registers").open_registers_picker({
            preview = false,
            prompt_debounce = 0,
        })
    end, function()
        vim.fn.setreg("a", "alpha")
    end, function(_, _, picker)
        helpers.assert_ok(helpers.wait_for(function()
            local current = get_last_args(picker)
            for _, entry in ipairs((current.args and current.args.items) or {}) do
                if entry.name == "a" and (entry.linecount or 0) > 0 then
                    return true
                end
            end
            return false
        end, 1500), "registers args ready")
        local after = get_last_args(picker)
        local found = false
        for _, entry in ipairs(after.args.items or {}) do
            if entry.name == "a" and (entry.linecount or 0) > 0 then
                found = true
                break
            end
        end
        helpers.assert_ok(found, "registers args")
    end)

    run_rerun_case("rerun_keymaps", function()
        return require("fuzzy.pickers.keymaps").open_keymaps_picker({
            preview = false,
            prompt_debounce = 0,
        })
    end, function()
        vim.keymap.set("n", "gz", "echo 1", { silent = true })
    end, function(_, _, picker)
        helpers.assert_ok(helpers.wait_for(function()
            local current = get_last_args(picker)
            for _, mode_entry in ipairs((current.args and current.args.items) or {}) do
                for _, sig in ipairs(mode_entry.global_sig or {}) do
                    if sig.lhs == "gz" then
                        return true
                    end
                end
            end
            return false
        end, 1500), "keymaps args ready")
        local after = get_last_args(picker)
        local found = false
        for _, mode_entry in ipairs((after.args and after.args.items) or {}) do
            for _, sig in ipairs(mode_entry.global_sig or {}) do
                if sig.lhs == "gz" then
                    found = true
                    break
                end
            end
            if found then
                break
            end
        end
        helpers.assert_ok(found, "keymaps args")
    end)

    run_rerun_case("rerun_tabs", function()
        return require("fuzzy.pickers.tabs").open_tabs_picker({
            preview = false,
            prompt_debounce = 0,
        })
    end, function(picker)
        vim.cmd("tabnew")
        picker._test_tab_opened = true
    end, function(before, _, picker)
        helpers.assert_ok(helpers.wait_for(function()
            local current = get_last_args(picker)
            return #(current.args and current.args.items or {}) > #(before.args.items or {})
        end, 1500), "tabs args ready")
        local after = get_last_args(picker)
        helpers.assert_ok(#(after.args and after.args.items or {}) > #(before.args.items or {}), "tabs args")
        if #vim.api.nvim_list_tabpages() > 1 then
            pcall(vim.cmd, "tabclose")
        end
    end)

    run_rerun_case("rerun_oldfiles", function()
        return require("fuzzy.pickers.oldfiles").open_oldfiles_picker({
            preview = false,
            icons = false,
            prompt_debounce = 0,
        })
    end, function(picker)
        local dir_path = helpers.create_temp_dir()
        local one = vim.fs.joinpath(dir_path, "oldfile-one.txt")
        local two = vim.fs.joinpath(dir_path, "oldfile-two.txt")
        helpers.write_file(one, "one\n")
        helpers.write_file(two, "two\n")
        picker._test_oldfiles = { one, two }
        vim.v.oldfiles = { one, two }
    end, function(_, _, picker)
        helpers.assert_ok(helpers.wait_for(function()
            local current = get_last_args(picker)
            for _, item in ipairs((current.args and current.args.items) or {}) do
                if item == picker._test_oldfiles[2] then
                    return true
                end
            end
            return false
        end, 1500), "oldfiles args ready")
        local after = get_last_args(picker)
        helpers.assert_list_contains(after.args.items, picker._test_oldfiles[2], "oldfiles args")
    end)

    run_rerun_case("rerun_search_history", function()
        return require("fuzzy.pickers.search_history").open_search_history({
            preview = false,
            prompt_debounce = 0,
        })
    end, function()
        vim.fn.histadd("search", "needle")
    end, function(_, _, picker)
        helpers.assert_ok(helpers.wait_for(function()
            local current = get_last_args(picker)
            for _, item in ipairs((current.args and current.args.items) or {}) do
                if item == "needle" then
                    return true
                end
            end
            return false
        end, 1500), "search history args ready")
        local after = get_last_args(picker)
        helpers.assert_list_contains(after.args.items, "needle", "search history args")
    end)

    run_rerun_case("rerun_command_history", function()
        return require("fuzzy.pickers.command_history").open_command_history({
            preview = false,
            prompt_debounce = 0,
        })
    end, function()
        vim.fn.histadd("cmd", "echo rerun")
    end, function(_, _, picker)
        helpers.assert_ok(helpers.wait_for(function()
            local current = get_last_args(picker)
            for _, item in ipairs((current.args and current.args.items) or {}) do
                if item == "echo rerun" then
                    return true
                end
            end
            return false
        end, 1500), "command history args ready")
        local after = get_last_args(picker)
        helpers.assert_list_contains(after.args.items, "echo rerun", "command history args")
    end)

    run_rerun_case("rerun_quickfix_stack", function()
        return require("fuzzy.pickers.quickfix_stack").open_quickfix_stack({
            preview = false,
            prompt_debounce = 0,
        })
    end, function()
        vim.fn.setqflist({}, "r", { title = "StackA", items = {} })
        vim.fn.setqflist({}, "r", { title = "StackB", items = {} })
    end, function(_, _, picker)
        helpers.assert_ok(helpers.wait_for(function()
            local current = get_last_args(picker)
            local history_text = current.args and current.args.history_text or ""
            return history_text:find("StackB", 1, true) ~= nil
        end, 1500), "quickfix stack args ready")
        local after = get_last_args(picker)
        helpers.assert_ok(after.args.history_text:find("StackB", 1, true) ~= nil, "quickfix stack args")
    end)

    helpers.run_test_case("rerun_loclist_stack", function()
        with_stream_count(function()
            local toggle = false
            local original_execute = vim.fn.execute
            helpers.with_mock(vim.fn, "execute", function(cmd)
                if cmd == "lhistory" then
                    return toggle and "list 2" or "list 1"
                end
                return original_execute(cmd)
            end, function()
                local picker = require("fuzzy.pickers.loclist_stack").open_loclist_stack({
                    preview = false,
                    prompt_debounce = 0,
                })
                helpers.wait_for_stream(picker)
                local before = get_last_args(picker)
                local count_before = picker._test_stream_count()
                toggle = true
                picker:hide()
                picker:open()
                helpers.wait_for_stream(picker)
                helpers.assert_ok(helpers.wait_for(function()
                    local current = get_last_args(picker)
                    local history_text = current.args and current.args.history_text or ""
                    return history_text:find("list 2", 1, true) ~= nil
                end, 1500), "loclist stack args ready")
                local after = get_last_args(picker)
                helpers.assert_ok(
                    picker._test_stream_count() > count_before,
                    "content should re-run"
                )
                helpers.assert_ok(after.args.history_text:find("list 2", 1, true) ~= nil, "loclist stack args")
                helpers.close_picker(picker)
            end)
        end)
    end)

    run_rerun_case("rerun_files_cwd", function()
        return require("fuzzy.pickers.files").open_files_picker({
            cwd = function()
                return vim.loop.cwd()
            end,
            preview = false,
            icons = false,
            prompt_debounce = 0,
        })
    end, function(picker)
        picker._test_open_cwd = helpers.create_temp_dir()
    end, function(before, after, picker)
        helpers.assert_ok(before.cwd ~= after.cwd, "files cwd changed")
        helpers.eq(after.cwd, picker._test_open_cwd, "files cwd args")
    end)

    helpers.run_test_case("rerun_grep_cwd", function()
        with_stream_count(function()
            local dir_a = helpers.create_temp_dir()
            local dir_b = helpers.create_temp_dir()
            local utils = require("fuzzy.utils")
            local picker = require("fuzzy.pickers.grep").open_grep_picker({
                cwd = dir_a,
                preview = false,
                icons = false,
                prompt_debounce = 0,
                prompt_query = "needle",
                prompt_debounce = 0,
                _test_skip_command = true,
            })
            helpers.wait_for_stream(picker)
            local eval_before = picker:_context_evaluate({ "args", "cwd", "env" }, picker)
            picker._state.context.cwd = dir_b
            picker._state.context.args = { "--test" }
            local eval_after = picker:_context_evaluate({ "args", "cwd", "env" }, picker)
            helpers.assert_ok(not utils.compare_tables(eval_before, eval_after), "grep context changed")
            picker:hide()
            picker:open()
            helpers.wait_for_stream(picker)
            local after_cwd = picker._state._evaluated_context.cwd
            helpers.assert_ok(eval_before.cwd ~= after_cwd, "grep cwd changed")
            helpers.eq(after_cwd, dir_b, "grep cwd args")
            helpers.close_picker(picker)
        end)
    end)
end

return M
