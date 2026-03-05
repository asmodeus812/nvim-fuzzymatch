---@diagnostic disable: invisible
local helpers = require("script.test_utils")
local util = require("fuzzy.pickers.util")
local Picker = require("fuzzy.picker")

local M = { name = "files" }

function M.run()
    helpers.run_test_case("files", function()
        helpers.with_mock(util, "command_is_available", function(command_name)
            if command_name == "rg" or command_name == "fd" then
                return false
            end
            return true
        end, function()
            local ok, err = pcall(function()
                local cmd = util.pick_first_command({ "rg", "fd", "find" })
                if not cmd or cmd ~= "find" then
                    return
                end

                local dir_path = helpers.create_temp_dir()
                local sub_path = vim.fs.joinpath(dir_path, "sub")
                vim.uv.fs_mkdir(sub_path, 448)
                helpers.write_file(vim.fs.joinpath(dir_path, "alpha.txt"), "alpha\n")
                helpers.write_file(vim.fs.joinpath(sub_path, "beta.txt"), "beta\n")

                helpers.with_cwd(dir_path, function()
                    local files_picker = require("fuzzy.pickers.files")
                    local picker = files_picker.open_files_picker({
                        cwd = dir_path,
                        preview = false,
                        icons = false,
                        prompt_debounce = 0,
                        stream_step = 1000,
                        match_step = 1000,
                    })

                    helpers.wait_for_list(picker)
                    helpers.wait_for(function()
                        local entry_list = helpers.get_entries(picker) or {}
                        return #entry_list >= 2
                    end, 1500)
                    helpers.wait_for_line_contains(picker, "alpha.txt")
                    helpers.wait_for_line_contains(picker, "beta.txt")

                    local prompt_input = picker.select._options.prompt_input
                    assert(type(prompt_input) == "function")
                    --- @cast prompt_input fun(string)
                    prompt_input("beta")
                    helpers.wait_for(function()
                        return picker.select:query():find("beta", 1, true) ~= nil
                    end, 1500)
                    helpers.wait_for_line_contains(picker, "beta.txt")
                    helpers.assert_line_missing(helpers.get_list_lines(picker), "alpha.txt", "filter")
                    picker:close()
                end)
            end)
            if not ok then
                error(err)
            end
        end)
    end)

    helpers.run_test_case("files_cancel_reopen_refresh", function()
        helpers.with_mock(util, "command_is_available", function(command_name)
            if command_name == "rg" or command_name == "fd" then
                return false
            end
            return true
        end, function()
            local dir_path = helpers.create_temp_dir()
            helpers.write_file(vim.fs.joinpath(dir_path, "alpha.txt"), "alpha\n")
            helpers.write_file(vim.fs.joinpath(dir_path, "beta.txt"), "beta\n")

            helpers.with_cwd(dir_path, function()
                local files_picker = require("fuzzy.pickers.files")
                local picker = files_picker.open_files_picker({
                    cwd = dir_path,
                    preview = false,
                    icons = false,
                    prompt_debounce = 0,
                    stream_step = 1000,
                    match_step = 1000,
                    watch = true,
                })

                helpers.wait_for_list(picker)
                helpers.wait_for_line_contains(picker, "alpha.txt")
                helpers.wait_for_line_contains(picker, "beta.txt")
                helpers.wait_for_stream(picker)
                local cancel = picker:_cancel_prompt()
                cancel(picker.select)

                picker:open()
                helpers.wait_for_list(picker)
                helpers.wait_for_line_contains(picker, "alpha.txt")
                helpers.wait_for_line_contains(picker, "beta.txt")
                local reopen_lines = helpers.get_list_lines(picker)
                helpers.assert_line_contains(reopen_lines, "alpha.txt", "cancel reopen list")
                helpers.assert_line_contains(reopen_lines, "beta.txt", "cancel reopen list")
                helpers.assert_line_missing(reopen_lines, "gamma.txt", "cancel reopen list")

                local tick_state = util.dir_watch_state(dir_path)
                local before_version = tick_state.tick
                local alpha_path = vim.fs.joinpath(dir_path, "alpha.txt")
                local beta_path = vim.fs.joinpath(dir_path, "beta.txt")
                local gamma_path = vim.fs.joinpath(dir_path, "gamma.txt")
                local delta_path = vim.fs.joinpath(dir_path, "delta.txt")

                helpers.write_file(gamma_path, "gamma\n")
                assert(vim.uv.fs_rename(beta_path, delta_path))
                assert(vim.uv.fs_unlink(alpha_path))

                helpers.wait_for(function()
                    return tick_state.tick ~= before_version
                end, 1500)

                local cancel_after = picker:_cancel_prompt()
                cancel_after(picker.select)
                picker:open()
                helpers.wait_for_line_contains(picker, "gamma.txt")
                helpers.wait_for_line_contains(picker, "delta.txt")
                helpers.wait_for_stream(picker)
                local updated_lines = helpers.get_list_lines(picker)
                helpers.assert_line_missing(updated_lines, "alpha.txt", "remove alpha")
                helpers.assert_line_missing(updated_lines, "beta.txt", "rename beta")
                picker:close()
            end)
        end)
    end)

    helpers.run_test_case("files_cancel_reopen_refresh_nowatch", function()
        helpers.with_mock(util, "command_is_available", function(command_name)
            if command_name == "rg" or command_name == "fd" then
                return false
            end
            return true
        end, function()
            local dir_path = helpers.create_temp_dir()
            helpers.write_file(vim.fs.joinpath(dir_path, "alpha.txt"), "alpha\n")
            helpers.write_file(vim.fs.joinpath(dir_path, "beta.txt"), "beta\n")

            helpers.with_cwd(dir_path, function()
                local files_picker = require("fuzzy.pickers.files")
                local picker = files_picker.open_files_picker({
                    cwd = dir_path,
                    preview = false,
                    icons = false,
                    prompt_debounce = 0,
                    stream_step = 1000,
                    match_step = 1000,
                    watch = false,
                })

                helpers.wait_for_list(picker)
                helpers.wait_for_line_contains(picker, "alpha.txt")
                helpers.wait_for_line_contains(picker, "beta.txt")
                helpers.wait_for_stream(picker)
                local cancel = picker:_cancel_prompt()
                cancel(picker.select)

                picker:open()
                helpers.wait_for_list(picker)
                helpers.wait_for_line_contains(picker, "alpha.txt")
                helpers.wait_for_line_contains(picker, "beta.txt")

                local alpha_path = vim.fs.joinpath(dir_path, "alpha.txt")
                local beta_path = vim.fs.joinpath(dir_path, "beta.txt")
                local gamma_path = vim.fs.joinpath(dir_path, "gamma.txt")
                local delta_path = vim.fs.joinpath(dir_path, "delta.txt")

                helpers.write_file(gamma_path, "gamma\n")
                assert(vim.uv.fs_rename(beta_path, delta_path))
                assert(vim.uv.fs_unlink(alpha_path))

                local cancel_after = picker:_cancel_prompt()
                cancel_after(picker.select)
                picker:open()
                helpers.wait_for_line_contains(picker, "gamma.txt")
                helpers.wait_for_line_contains(picker, "delta.txt")
                helpers.wait_for_stream(picker)
                local updated_lines = helpers.get_list_lines(picker)
                helpers.assert_line_missing(updated_lines, "alpha.txt", "remove alpha")
                helpers.assert_line_missing(updated_lines, "beta.txt", "rename beta")
                picker:close()
            end)
        end)
    end)

    helpers.run_test_case("files_rg_args", function()
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
                local files_picker = require("fuzzy.pickers.files")
                files_picker.open_files_picker({
                    hidden = false,
                    follow = true,
                    no_ignore = true,
                    no_ignore_vcs = true,
                    preview = false,
                    icons = false,
                })
                local args = captured.context.args
                helpers.assert_list_contains(args, "--files", "rg args")
                helpers.assert_list_contains(args, "--follow", "rg args")
                helpers.assert_list_contains(args, "--no-ignore", "rg args")
                helpers.assert_list_contains(args, "--no-ignore-vcs", "rg args")
            end)
        end)
    end)

    helpers.run_test_case("files_preview_is_previewer", function()
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
                local files_picker = require("fuzzy.pickers.files")
                files_picker.open_files_picker({
                    preview = true,
                    icons = false,
                })
                helpers.assert_ok(type(captured.preview) == "table", "previewer type")
                helpers.assert_ok(
                    type(captured.preview.preview) == "function"
                        or type(getmetatable(captured.preview).__index.preview) == "function",
                    "previewer method"
                )
            end)
        end)
    end)
end

return M
