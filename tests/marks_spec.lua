---@diagnostic disable: invisible
local helpers = require("script.test_utils")

local M = { name = "marks" }

function M.run()
    helpers.run_test_case("marks", function()
        local dir_path = helpers.create_temp_dir()
        local file_path = vim.fs.joinpath(dir_path, "marks.txt")
        helpers.write_file(file_path, "mark one\nmark two\n")
        local buf = helpers.create_named_buffer(file_path, {
            "mark one",
            "mark two",
        })
        vim.api.nvim_set_current_buf(buf)
        vim.api.nvim_buf_set_mark(buf, "a", 1, 0, {})
        local buffer_mark_list = {
            { mark = "a", pos = { buf, 1, 0, 0 }, file = "" },
        }
        helpers.with_mock(vim.fn, "getmarklist", function(bufnr)
            if bufnr == 0 then
                return buffer_mark_list
            end
            return {}
        end, function()
            local marks_picker = require("fuzzy.pickers.marks")
            local picker = marks_picker.open_marks_picker({
                preview = false,
                icons = false,
                prompt_debounce = 0,
            })
            helpers.wait_for_list(picker)
            helpers.wait_for_line_contains(picker, "[a]")
            helpers.wait_for_line_contains(picker, "marks.txt")
            helpers.wait_for_list_extmarks(picker)
            local extmarks = helpers.get_list_extmarks(picker)
            helpers.assert_has_hl(extmarks, "Identifier", "marks prefix hl")
            helpers.assert_has_hl(extmarks, "Directory", "marks path hl")
            helpers.assert_has_hl(extmarks, "Number", "marks line hl")
            picker:close()
        end)

        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    helpers.run_test_case("marks_include_global_only", function()
        local dir_path = helpers.create_temp_dir()
        local file_path = vim.fs.joinpath(dir_path, "marks.txt")
        helpers.write_file(file_path, "mark one\nmark two\n")
        local buf = helpers.create_named_buffer(file_path, {
            "mark one",
            "mark two",
        })
        vim.api.nvim_set_current_buf(buf)
        local buffer_mark_list = {
            { mark = "a", pos = { buf, 1, 0, 0 }, file = file_path },
        }
        local global_mark_list = {
            { mark = "A", pos = { buf, 2, 0, 0 }, file = file_path },
        }
        helpers.with_mock(vim.fn, "getmarklist", function(bufnr)
            if bufnr == 0 then
                return buffer_mark_list
            end
            return global_mark_list
        end, function()
            local marks_picker = require("fuzzy.pickers.marks")
            local picker = marks_picker.open_marks_picker({
                preview = false,
                icons = false,
                include_local = false,
                include_global = true,
                prompt_debounce = 0,
            })
            helpers.wait_for_list(picker)
            helpers.wait_for_line_contains(picker, "[A]")
            helpers.assert_line_missing(
                helpers.get_list_lines(picker),
                "[a]",
                "local marks excluded"
            )
            picker:close()
        end)
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    helpers.run_test_case("marks_filter_pattern", function()
        local dir_path = helpers.create_temp_dir()
        local file_path = vim.fs.joinpath(dir_path, "marks.txt")
        helpers.write_file(file_path, "mark one\nmark two\n")
        local buf = helpers.create_named_buffer(file_path, {
            "mark one",
            "mark two",
        })
        vim.api.nvim_set_current_buf(buf)
        local buffer_mark_list = {
            { mark = "a", pos = { buf, 1, 0, 0 }, file = file_path },
        }
        local global_mark_list = {
            { mark = "B", pos = { buf, 2, 0, 0 }, file = file_path },
        }
        helpers.with_mock(vim.fn, "getmarklist", function(bufnr)
            if bufnr == 0 then
                return buffer_mark_list
            end
            return global_mark_list
        end, function()
            local marks_picker = require("fuzzy.pickers.marks")
            local picker = marks_picker.open_marks_picker({
                preview = false,
                icons = false,
                include_local = true,
                include_global = true,
                marks = "^[a]$",
                prompt_debounce = 0,
            })
            helpers.wait_for_list(picker)
            helpers.wait_for_line_contains(picker, "[a]")
            helpers.assert_line_missing(
                helpers.get_list_lines(picker),
                "[B]",
                "pattern filtered global marks"
            )
            picker:close()
        end)
        vim.api.nvim_buf_delete(buf, { force = true })
    end)
end

return M
