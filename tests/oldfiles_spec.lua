---@diagnostic disable: invisible
local helpers = require("script.test_utils")
local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

local M = { name = "oldfiles" }

function M.run()
    helpers.run_test_case("oldfiles_basic", function()
        local dir_path = helpers.create_temp_dir()
        local file_path = vim.fs.joinpath(dir_path, "old.txt")
        helpers.write_file(file_path, "old\n")

        local other_dir_path = helpers.create_temp_dir()
        local other_file_path = vim.fs.joinpath(other_dir_path, "other.txt")
        helpers.write_file(other_file_path, "other\n")
        vim.v.oldfiles = { file_path, other_file_path }

        local oldfiles_picker = require("fuzzy.pickers.oldfiles")
        local picker = oldfiles_picker.open_oldfiles_picker({
            cwd = dir_path,
            preview = false,
            icons = false,
            prompt_debounce = 0,
            stat_file = true,
            cwd_only = true,
        })

        helpers.wait_for_stream(picker)
        helpers.wait_for_list(picker)
        helpers.wait_for_line_contains(picker, "old.txt")
        helpers.assert_line_missing(helpers.get_list_lines(picker), "other.txt", "cwd only")
        picker:close()
    end)

    helpers.run_test_case("oldfiles_cwd_content_arg", function()
        local captured_content = nil
        local captured = nil
        helpers.with_mock(Picker, "new", function(opts)
            captured = opts
            captured_content = opts.content
            return { _options = opts, open = function() end }
        end, function()
            require("fuzzy.pickers.oldfiles").open_oldfiles_picker({
                preview = false,
                icons = false,
            })
        end)
        helpers.assert_ok(captured and captured_content, "content missing")
        local dir_a = helpers.create_temp_dir()
        local dir_b = helpers.create_temp_dir()
        local path_a = vim.fs.joinpath(dir_a, "a.txt")
        local path_b = vim.fs.joinpath(dir_b, "b.txt")
        helpers.write_file(path_a, "a")
        helpers.write_file(path_b, "b")
        vim.v.oldfiles = { path_a, path_b }

        local entries = {}
        captured_content(function(entry)
            if entry ~= nil then
                entries[#entries + 1] = entry
            end
        end, { items = vim.v.oldfiles or {} }, dir_a)

        local filenames = {}
        for _, entry in ipairs(entries) do
            filenames[#filenames + 1] = entry.filename
        end
        helpers.assert_list_contains(filenames, path_a, "cwd entry missing")
        helpers.assert_list_missing(filenames, path_b, "other entry present")
    end)

    helpers.run_test_case("oldfiles_filter_cursor_clamp", function()
        local dir_path = helpers.create_temp_dir()
        local file_a = vim.fs.joinpath(dir_path, "alpha.txt")
        local file_b = vim.fs.joinpath(dir_path, "beta.txt")
        helpers.write_file(file_a, "alpha\n")
        helpers.write_file(file_b, "beta\n")
        vim.v.oldfiles = { file_a, file_b }

        local oldfiles_picker = require("fuzzy.pickers.oldfiles")
        local picker = oldfiles_picker.open_oldfiles_picker({
            preview = false,
            icons = false,
            prompt_debounce = 0,
            stat_file = true,
        })
        helpers.wait_for_stream(picker)
        helpers.wait_for_list(picker)
        helpers.wait_for_entries(picker)
        local select = picker.select
        select:move_down()
        select:list({ { filename = file_a } }, nil)
        helpers.wait_for(function()
            return vim.api.nvim_win_get_cursor(select.list_window)[1] == 1
        end, 1500)
        local cursor = vim.api.nvim_win_get_cursor(select.list_window)
        helpers.eq(cursor[1], 1, "cursor clamped")
        picker:close()
    end)

    helpers.run_test_case("oldfiles_filter_preview_no_index_error", function()
        local dir_path = helpers.create_temp_dir()
        local file_a = vim.fs.joinpath(dir_path, "alpha.txt")
        local file_b = vim.fs.joinpath(dir_path, "beta.txt")
        local file_c = vim.fs.joinpath(dir_path, "gamma.txt")
        local file_d = vim.fs.joinpath(dir_path, "delta.txt")
        helpers.write_file(file_a, "alpha\n")
        helpers.write_file(file_b, "beta\n")
        helpers.write_file(file_c, "gamma\n")
        helpers.write_file(file_d, "delta\n")

        vim.v.oldfiles = { file_a, file_b, file_c, file_d }
        helpers.assert_ok(#vim.v.oldfiles >= 4, "oldfiles not populated")

        vim.v.errmsg = ""
        local emitted = {}
        local captured_content = nil
        local original_new = Picker.new
        local picker = nil
        helpers.with_mock(Picker, "new", function(opts)
            captured_content = opts.content
            local original_content = opts.content
            opts.content = function(stream, args, cwd)
                return original_content(function(entry)
                    if entry ~= nil then
                        emitted[#emitted + 1] = entry
                    end
                    return stream(entry)
                end, args, cwd)
            end
            return original_new(opts)
        end, function()
            local oldfiles_picker = require("fuzzy.pickers.oldfiles")
            picker = oldfiles_picker.open_oldfiles_picker({
                preview = true,
                icons = false,
                prompt_debounce = 0,
                stat_file = true,
                cwd = dir_path,
            })
        end)
        helpers.assert_ok(picker ~= nil, "picker missing")
        helpers.wait_for_stream(picker)
        helpers.wait_for_list(picker)
        helpers.assert_ok(captured_content ~= nil, "oldfiles content missing")
        local manual_entries = {}
        local context = picker:context()
        captured_content(function(entry)
            if entry ~= nil then
                manual_entries[#manual_entries + 1] = entry
            end
        end, context.args, context.cwd)
        helpers.assert_ok(#manual_entries >= 4, "oldfiles manual count")
        helpers.assert_ok(#emitted >= 4, "oldfiles emitted count")
        local display_opts = {
            cwd = dir_path,
            filename_only = false,
            path_shorten = nil,
            home_to_tilde = true,
        }
        for _, entry in ipairs(emitted) do
            helpers.assert_ok(type(entry) == "table", "oldfiles emitted type")
            helpers.assert_ok(entry.filename ~= nil, "oldfiles emitted filename")
        end
        local display_a = util.format_display_path(file_a, display_opts)
        local display_b = util.format_display_path(file_b, display_opts)
        helpers.assert_ok(helpers.wait_for_line_contains(picker, display_a), "oldfiles list alpha")
        helpers.assert_ok(helpers.wait_for_line_contains(picker, display_b), "oldfiles list beta")
        helpers.type_query(picker, "alpha")
        helpers.wait_for_match(picker)
        helpers.wait_for_list(picker)
        helpers.assert_ok(helpers.wait_for_line_contains(picker, "alpha.txt"), "oldfiles filter alpha")
        vim.wait(80, function()
            return true
        end, 10)
        helpers.assert_ok(
            not tostring(vim.v.errmsg):find("index out of range", 1, true),
            "no index out of range while filtering oldfiles with preview"
        )
        picker:close()
    end)

    helpers.run_test_case("oldfiles_excludes_directories", function()
        local dir_path = helpers.create_temp_dir()
        local nested_dir = vim.fs.joinpath(dir_path, "nested")
        vim.fn.mkdir(nested_dir, "p")
        local file_path = vim.fs.joinpath(dir_path, "file.txt")
        helpers.write_file(file_path, "data")
        vim.v.oldfiles = { nested_dir, file_path }

        local oldfiles_picker = require("fuzzy.pickers.oldfiles")
        local picker = oldfiles_picker.open_oldfiles_picker({
            preview = false,
            icons = false,
            prompt_debounce = 0,
            stat_file = true,
        })

        helpers.wait_for_stream(picker)
        helpers.wait_for_list(picker)
        helpers.wait_for_line_contains(picker, "file.txt")
        helpers.assert_line_missing(helpers.get_list_lines(picker), "nested", "dir excluded")
        picker:close()
    end)
end

return M
