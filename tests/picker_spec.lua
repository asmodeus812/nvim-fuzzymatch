---@diagnostic disable: invisible
local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local helpers = require("script.test_utils")

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
        actions = {
            ["<cr>"] = Select.default_select,
        },
    })
    helpers.assert_ok(picker:options() ~= nil, "picker options")
    helpers.eq(picker:options().prompt_query, "be", "picker options reference")

    picker:open()
    helpers.wait_for_list(picker)
    helpers.wait_for_line_contains(picker, "alpha")
    helpers.wait_for(function()
        return picker.select and picker.select._state.entries
            and #picker.select._state.entries == 3
    end, 1500)

    helpers.eq(#picker.select._state.entries, 3, "entries")
    local lines = helpers.get_list_lines(picker)
    helpers.assert_ok(#lines > 0, "list empty")
    helpers.assert_line_contains(lines, "alpha", "missing")

    helpers.type_query(picker, "gam")
    helpers.wait_for(function()
        return picker.select:query():find("gam", 1, true) ~= nil
    end, 1500)

    helpers.type_query(picker, "<c-u>")
    helpers.wait_for(function()
        return picker.select:query() == ""
    end, 1500)

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
    helpers.wait_for(function()
        return stream_picker.select
            and stream_picker.select._state.entries
            and #stream_picker.select._state.entries == 3
    end, 1500)

    local stream_lines = helpers.get_list_lines(stream_picker)
    helpers.assert_line_contains(stream_lines, "ONE", "display")
    helpers.assert_line_contains(stream_lines, "TWO", "display")

    stream_picker:close()

    helpers.run_test_case("interactive_no_open_rerun", function()
        with_stream_count(function()
            local interactive_picker = Picker.new({
                content = "rg",
                preview = false,
                context = {
                    args = { "--test" },
                    cwd = vim.loop.cwd,
                    interactive = function(_, ctx)
                        return ctx.args
                    end,
                },
            })
            interactive_picker:open()
            helpers.wait_for(function()
                return interactive_picker.select and interactive_picker.select:isopen()
            end, 1500)
            helpers.eq(interactive_picker._test_stream_count(), 0, "interactive open should not start stream")
            interactive_picker._state.context.args = { "--test-open" }
            interactive_picker:hide()
            interactive_picker:open()
            helpers.wait_for(function()
                return interactive_picker.select and interactive_picker.select:isopen()
            end, 1500)
            helpers.eq(interactive_picker._test_stream_count(), 0, "interactive reopen should not start stream")
            interactive_picker:close()
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
        picker._test_buf = helpers.create_named_buffer("", { "buf" }, true)
    end, function(_, after, picker)
        helpers.assert_list_contains(after.args.buffers_list, after.args.buf, "buffers args buf")
        helpers.assert_list_contains(after.args.buffers_list, picker._test_buf, "buffers args list")
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
        helpers.assert_list_contains(after.args.buffers, picker._test_buf, "lines buffers")
        helpers.assert_list_contains(after.args.buffers, after.args.current_buf, "lines current_buf")
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
        helpers.assert_ok(after.args.line_count > before.args.line_count, "blines line_count")
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
        helpers.assert_ok(after.args.tick > before.args.tick, "changes tick")
        helpers.assert_ok(#after.args.items >= #before.args.items, "changes items")
    end)

    run_rerun_case("rerun_quickfix", function()
        return require("fuzzy.pickers.quickfix").open_quickfix_picker({
            preview = false,
            icons = false,
            prompt_debounce = 0,
        })
    end, function()
        vim.fn.setqflist({}, "r", {
            title = "QF",
            items = { { filename = "a", lnum = 1, col = 1, text = "a" } },
        })
    end, function(_, after)
        helpers.eq(#after.args.items, 1, "quickfix items")
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
        vim.fn.setloclist(wid, {}, "r", {
            title = "LL",
            items = { { filename = "a", lnum = 1, col = 1, text = "a" } },
        })
    end, function(_, after)
        helpers.eq(#after.args.items, 1, "loclist items")
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
                local after = get_last_args(picker)
                helpers.assert_ok(
                    picker._test_stream_count() > count_before,
                    "content should re-run"
                )
                helpers.assert_ok(#after.args.items >= 1, "jumps items")
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
    end, function(_, after)
        local found = false
        for _, entry in ipairs(after.args.items or {}) do
            if entry.name == "a" and entry.linecount and entry.linecount > 0 then
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
    end, function(_, after)
        local found = false
        for _, mode_entry in ipairs(after.args.items or {}) do
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
    end, function(before, after)
        helpers.assert_ok(#after.args.items > #before.args.items, "tabs args")
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
    end, function()
        vim.v.oldfiles = { "one", "two" }
    end, function(_, after)
        helpers.assert_list_contains(after.args.items, "two", "oldfiles args")
    end)

    run_rerun_case("rerun_search_history", function()
        return require("fuzzy.pickers.search_history").open_search_history({
            preview = false,
            prompt_debounce = 0,
        })
    end, function()
        vim.fn.histadd("search", "needle")
    end, function(_, after)
        helpers.assert_list_contains(after.args.items, "needle", "search history args")
    end)

    run_rerun_case("rerun_command_history", function()
        return require("fuzzy.pickers.command_history").open_command_history({
            preview = false,
            prompt_debounce = 0,
        })
    end, function()
        vim.fn.histadd("cmd", "echo rerun")
    end, function(_, after)
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
    end, function(before, after)
        helpers.assert_ok(after.args.history_text ~= before.args.history_text, "quickfix stack args")
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
                local after = get_last_args(picker)
                helpers.assert_ok(
                    picker._test_stream_count() > count_before,
                    "content should re-run"
                )
                helpers.assert_ok(after.args.history_text ~= before.args.history_text, "loclist stack args")
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
