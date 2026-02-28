---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "oldfiles" }

function M.run()
    helpers.run_test_case("oldfiles", function()
        local dir_path = helpers.create_temp_dir()
        local file_path = vim.fs.joinpath(dir_path, "old.txt")
        helpers.write_file(file_path, "old\n")

        local other_dir_path = helpers.create_temp_dir()
        local other_file_path = vim.fs.joinpath(other_dir_path, "other.txt")
        helpers.write_file(other_file_path, "other\n")

        local ok = pcall(function()
            vim.v.oldfiles = { file_path, other_file_path }
        end)
        if not ok then
            return
        end
        if not vim.v.oldfiles or #vim.v.oldfiles == 0 then
            return
        end

        local oldfiles_picker = require("fuzzy.pickers.oldfiles")
        local picker = oldfiles_picker.open_oldfiles_picker({
            cwd = dir_path,
            preview = false,
            icons = false,
            prompt_debounce = 0,
            stat_file = true,
            cwd_only = true,
        })

        helpers.wait_for_list(picker)
        helpers.wait_for_line_contains(picker, "old.txt")
        helpers.assert_line_missing(helpers.get_list_lines(picker), "other.txt", "cwd only")
        picker:close()
    end)

    helpers.run_test_case("oldfiles_cwd_content_arg", function()
        local Picker = require("fuzzy.picker")
        local captured = nil
        helpers.with_mock(Picker, "new", function(opts)
            captured = opts
            return { _options = opts, open = function() end }
        end, function()
            require("fuzzy.pickers.oldfiles").open_oldfiles_picker({
                preview = false,
                icons = false,
                cwd = "/should/not/use",
            })
        end)
        helpers.assert_ok(captured and captured.content, "content missing")
        local dir_a = helpers.create_temp_dir()
        local dir_b = helpers.create_temp_dir()
        local path_a = vim.fs.joinpath(dir_a, "a.txt")
        local path_b = vim.fs.joinpath(dir_b, "b.txt")
        helpers.write_file(path_a, "a")
        helpers.write_file(path_b, "b")
        vim.v.oldfiles = { path_a, path_b }

        local entries = {}
        captured.content(function(entry)
            if entry ~= nil then
                entries[#entries + 1] = entry
            end
        end, nil, dir_a)

        helpers.assert_list_contains(entries, path_a, "cwd entry missing")
        helpers.assert_list_missing(entries, path_b, "other entry present")
    end)

    helpers.run_test_case("oldfiles_filter_cursor_clamp", function()
        local dir_path = helpers.create_temp_dir()
        local file_a = vim.fs.joinpath(dir_path, "alpha.txt")
        local file_b = vim.fs.joinpath(dir_path, "beta.txt")
        helpers.write_file(file_a, "alpha\n")
        helpers.write_file(file_b, "beta\n")

        local ok = pcall(function()
            vim.v.oldfiles = { file_a, file_b }
        end)
        if not ok then
            return
        end
        if not vim.v.oldfiles or #vim.v.oldfiles == 0 then
            return
        end

        local oldfiles_picker = require("fuzzy.pickers.oldfiles")
        local picker = oldfiles_picker.open_oldfiles_picker({
            preview = false,
            icons = false,
            prompt_debounce = 0,
            stat_file = true,
        })
        helpers.wait_for_list(picker)
        helpers.wait_for_entries(picker)
        local select = picker.select
        select._state.cursor = { 2, 0 }
        select:list({ file_a }, nil)
        helpers.wait_for(function()
            return select._state.cursor[1] == 1
        end, 1500)
        local cursor = picker.select._state.cursor
        helpers.eq(cursor[1], 1, "cursor clamped")
        picker:close()
    end)

    helpers.run_test_case("oldfiles_filter_preview_no_index_error", function()
        local dir_path = helpers.create_temp_dir()
        local file_a = vim.fs.joinpath(dir_path, "alpha.txt")
        local file_b = vim.fs.joinpath(dir_path, "beta.txt")
        helpers.write_file(file_a, "alpha\n")
        helpers.write_file(file_b, "beta\n")

        local ok = pcall(function()
            vim.v.oldfiles = { file_a, file_b }
        end)
        if not ok then
            return
        end
        if not vim.v.oldfiles or #vim.v.oldfiles == 0 then
            return
        end

        vim.v.errmsg = ""
        local oldfiles_picker = require("fuzzy.pickers.oldfiles")
        local picker = oldfiles_picker.open_oldfiles_picker({
            preview = true,
            icons = false,
            prompt_debounce = 0,
            stat_file = true,
        })
        helpers.wait_for_entries(picker)
        helpers.type_query(picker, "alpha")
        helpers.wait_for_line_contains(picker, "alpha.txt")
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

        local ok = pcall(function()
            vim.v.oldfiles = { nested_dir, file_path }
        end)
        if not ok then
            return
        end
        if not vim.v.oldfiles or #vim.v.oldfiles == 0 then
            return
        end

        local oldfiles_picker = require("fuzzy.pickers.oldfiles")
        local picker = oldfiles_picker.open_oldfiles_picker({
            preview = false,
            icons = false,
            prompt_debounce = 0,
            stat_file = true,
        })

        helpers.wait_for_list(picker)
        helpers.wait_for_line_contains(picker, "file.txt")
        helpers.assert_line_missing(helpers.get_list_lines(picker), "nested", "dir excluded")
        picker:close()
    end)
end

return M
