---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "lines" }

function M.run()
    helpers.run_test_case("lines", function()
        local buf_one = helpers.create_named_buffer("line_one.txt", {
            "alpha line",
            "beta line",
        })
        local buf_two = helpers.create_named_buffer("line_two.txt", {
            "gamma line",
        })
        vim.api.nvim_set_current_buf(buf_one)

        local lines_picker = require("fuzzy.pickers.lines")
        local picker = lines_picker.open_lines_picker({
            preview = false,
            show_unlisted = true,
            show_unloaded = true,
            prompt_debounce = 0,
        })

        helpers.wait_for_list(picker)
        helpers.wait_for_line_contains(picker, "alpha line")
        helpers.wait_for_line_contains(picker, "gamma line")

        local prompt_input = picker.select._options.prompt_input
        assert(type(prompt_input) == "function")
        --- @cast prompt_input fun(string)
        prompt_input("gamma")
        helpers.wait_for_line_contains(picker, "gamma line")
        picker:close()

        vim.api.nvim_buf_delete(buf_two, { force = true })
        vim.api.nvim_buf_delete(buf_one, { force = true })
    end)

    helpers.run_test_case("lines_ignore_current", function()
        local buf_one = helpers.create_named_buffer("line_ignore.txt", {
            "ignore me",
        })
        local buf_two = helpers.create_named_buffer("line_keep.txt", {
            "keep me",
        })
        vim.api.nvim_set_current_buf(buf_one)

        local lines_picker = require("fuzzy.pickers.lines")
        local picker = lines_picker.open_lines_picker({
            preview = false,
            show_unlisted = true,
            show_unloaded = true,
            ignore_current_buffer = true,
            prompt_debounce = 0,
        })

        helpers.wait_for_list(picker)
        helpers.assert_line_missing(helpers.get_list_lines(picker), "ignore me", "ignore current")
        helpers.wait_for_line_contains(picker, "keep me")
        picker:close()

        vim.api.nvim_buf_delete(buf_two, { force = true })
        vim.api.nvim_buf_delete(buf_one, { force = true })
    end)

    helpers.run_test_case("lines_word_visual", function()
        local buf = helpers.create_named_buffer("line_word.txt", {
            "alpha line",
        })
        vim.api.nvim_set_current_buf(buf)

        helpers.with_mock(vim.fn, "expand", function()
            return "alpha"
        end, function()
            local lines_picker = require("fuzzy.pickers.lines")
            local picker = lines_picker.open_lines_word({
                preview = false,
                show_unlisted = true,
                show_unloaded = true,
                prompt_debounce = 0,
            })
            helpers.wait_for(function()
                return helpers.get_query(picker) == "alpha"
            end, 1500)
            helpers.wait_for_prompt_cursor(picker)
            picker:close()
        end)

        helpers.with_mock(require("fuzzy.utils"), "get_visual_text", function()
            return "line"
        end, function()
            local lines_picker = require("fuzzy.pickers.lines")
            local picker = lines_picker.open_lines_visual({
                preview = false,
                show_unlisted = true,
                show_unloaded = true,
                prompt_debounce = 0,
            })
            helpers.wait_for(function()
                return helpers.get_query(picker) == "line"
            end, 1500)
            helpers.wait_for_prompt_cursor(picker)
            picker:close()
        end)

        vim.api.nvim_buf_delete(buf, { force = true })
    end)
end

return M
