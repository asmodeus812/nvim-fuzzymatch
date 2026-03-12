---@diagnostic disable: invisible
local helpers = require("script.test_utils")
local util = require("fuzzy.pickers.util")
local Picker = require("fuzzy.picker")

local M = { name = "grep" }

function M.run()
    helpers.run_test_case("grep_basic", function()
        local has_rg = util.command_is_available("rg")
        local has_grep = util.command_is_available("grep")
        if not has_rg and not has_grep then
            return
        end

        local dir_path = helpers.create_temp_dir()
        helpers.write_file(vim.fs.joinpath(dir_path, "alpha.txt"), {
            "first line",
            "needle match",
            "last line",
        })

        helpers.with_cwd(dir_path, function()
            local grep_picker = require("fuzzy.pickers.grep")
            local picker = grep_picker.open_grep_picker({
                cwd = dir_path,
                preview = false,
                icons = false,
                prompt_debounce = 0,
                rg_glob = false,
                rg_opts = has_rg and table.concat({
                    "--column",
                    "--line-number",
                    "--no-heading",
                    "--color=never",
                    "--smart-case",
                }, " ") or nil,
                grep_opts = has_grep and "-n -H -r --line-buffered" or nil,
                watch = true,
            })

            helpers.type_query(picker, "needle")
            helpers.wait_for_stream(picker)
            helpers.wait_for_match(picker)
            helpers.wait_for_list(picker)
            helpers.wait_for_line_contains(picker, "alpha.txt")
            helpers.wait_for_line_contains(picker, "needle match")

            helpers.type_query(picker, "first")
            helpers.wait_for_stream(picker)
            helpers.wait_for_match(picker)
            helpers.wait_for_line_contains(picker, "first line")
            picker:close()
        end)
    end)

    helpers.run_test_case("grep_cancel_reopen_refresh", function()
        local has_rg = util.command_is_available("rg")
        local has_grep = util.command_is_available("grep")
        if not has_rg and not has_grep then
            return
        end

        local dir_path = helpers.create_temp_dir()
        local file_path = vim.fs.joinpath(dir_path, "alpha.txt")
        helpers.write_file(file_path, {
            "first line",
            "middle line",
            "last line",
        })

        helpers.with_cwd(dir_path, function()
            local grep_picker = require("fuzzy.pickers.grep")
            local picker = grep_picker.open_grep_picker({
                cwd = dir_path,
                preview = false,
                icons = false,
                prompt_debounce = 0,
                rg_glob = false,
                rg_opts = has_rg and table.concat({
                    "--column",
                    "--line-number",
                    "--no-heading",
                    "--color=never",
                    "--smart-case",
                }, " ") or nil,
                grep_opts = has_grep and "-n -H -r --line-buffered" or nil,
            })

            helpers.type_query(picker, "middle")
            helpers.wait_for_stream(picker)
            helpers.wait_for_match(picker)
            helpers.wait_for_list(picker)
            helpers.wait_for_line_contains(picker, "middle line")
            helpers.wait_for_stream(picker)
            helpers.trigger_action(picker, "<esc>")
            helpers.wait_for_picker_closed(picker)

            picker:open()
            helpers.type_query(picker, "middle")
            helpers.wait_for_stream(picker)
            helpers.wait_for_match(picker)
            helpers.wait_for_list(picker)
            helpers.wait_for_line_contains(picker, "middle line")
            helpers.assert_ok(helpers.wait_for(function()
                local lines = helpers.get_list_lines(picker)
                local has_middle = false
                local has_needle = false
                for _, line in ipairs(lines or {}) do
                    if line:find("middle line", 1, true) then
                        has_middle = true
                    elseif line:find("needle match", 1, true) then
                        has_needle = true
                    end
                end
                return has_middle and not has_needle
            end, 1500), "cancel reopen list")
            local reopen_lines = helpers.get_list_lines(picker)
            helpers.assert_line_contains(reopen_lines, "middle line", "cancel reopen list")

            local tick_state = util.dir_watch_state(dir_path)
            local before_version = tick_state.tick
            helpers.write_file(file_path, {
                "first line",
                "middle line",
                "needle match",
                "last line",
            })
            helpers.wait_for(function()
                return tick_state.tick ~= before_version
            end, 1500)

            helpers.trigger_action(picker, "<esc>")
            helpers.wait_for_picker_closed(picker)

            picker:open()
            helpers.type_query(picker, "needle")
            helpers.wait_for_stream(picker)
            helpers.wait_for_match(picker)
            helpers.wait_for_line_contains(picker, "needle match")
            picker:close()
        end)
    end)

    helpers.run_test_case("grep_cancel_reopen_refresh_nowatch", function()
        local has_rg = util.command_is_available("rg")
        local has_grep = util.command_is_available("grep")
        if not has_rg and not has_grep then
            return
        end

        local dir_path = helpers.create_temp_dir()
        local file_path = vim.fs.joinpath(dir_path, "alpha.txt")
        helpers.write_file(file_path, {
            "first line",
            "middle line",
            "last line",
        })

        helpers.with_cwd(dir_path, function()
            local grep_picker = require("fuzzy.pickers.grep")
            local picker = grep_picker.open_grep_picker({
                cwd = dir_path,
                preview = false,
                icons = false,
                prompt_debounce = 0,
                rg_glob = false,
                rg_opts = has_rg and table.concat({
                    "--column",
                    "--line-number",
                    "--no-heading",
                    "--color=never",
                    "--smart-case",
                }, " ") or nil,
                grep_opts = has_grep and "-n -H -r --line-buffered" or nil,
                watch = false,
            })

            helpers.type_query(picker, "middle")
            helpers.wait_for_stream(picker)
            helpers.wait_for_match(picker)
            helpers.wait_for_list(picker)
            helpers.wait_for_line_contains(picker, "middle line")
            helpers.wait_for_stream(picker)
            helpers.trigger_action(picker, "<esc>")
            helpers.wait_for_picker_closed(picker)

            picker:open()
            helpers.type_query(picker, "middle")
            helpers.wait_for_stream(picker)
            helpers.wait_for_match(picker)
            helpers.wait_for_list(picker)
            helpers.wait_for_line_contains(picker, "middle line")

            helpers.write_file(file_path, {
                "first line",
                "middle line",
                "needle match",
                "last line",
            })

            helpers.trigger_action(picker, "<esc>")
            helpers.wait_for_picker_closed(picker)
            picker:open()
            helpers.type_query(picker, "needle")
            helpers.wait_for_stream(picker)
            helpers.wait_for_match(picker)
            helpers.wait_for_line_contains(picker, "needle match")
            picker:close()
        end)
    end)

    helpers.run_test_case("grep_glob_args", function()
        local captured = nil
        helpers.with_mock(Picker, "new", function(opts)
            captured = opts
            return {
                _options = opts,
                open = function() end,
            }
        end, function()
            helpers.with_mock(util, "pick_first_command", function()
                return "rg"
            end, function()
                local grep_picker = require("fuzzy.pickers.grep")
                grep_picker.open_grep_picker({
                    rg_glob = true,
                    rg_opts = "--line-number",
                    preview = false,
                    icons = false,
                    prompt_debounce = 0,
                })
                local args = captured.interactive("needle -- *.lua", { "--line-number" })
                helpers.assert_list_contains(args, "--iglob=*.lua", "glob arg")
            end)
        end)
    end)

    helpers.run_test_case("grep_cmd_args", function()
        local captured = nil
        helpers.with_mock(Picker, "new", function(opts)
            captured = opts
            return {
                _options = opts,
                open = function() end,
            }
        end, function()
            helpers.with_mock(util, "pick_first_command", function()
                return "grep"
            end, function()
                local grep_picker = require("fuzzy.pickers.grep")
                grep_picker.open_grep_picker({
                    preview = false,
                    icons = false,
                    prompt_debounce = 0,
                })
                local args = captured.interactive("needle", { "-n", "-H", "-r", "--line-buffered" })
                helpers.eq(args[#args], ".", "grep path")
            end)
        end)
    end)
end

return M
