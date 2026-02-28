---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "blines" }

function M.run()
    helpers.run_test_case("blines", function()
        local buf = helpers.create_named_buffer("blines.txt", {
            "first",
            "second",
        })
        vim.api.nvim_set_current_buf(buf)

        local blines_picker = require("fuzzy.pickers.blines")
        local picker = blines_picker.open_blines_picker({
            preview = false,
            prompt_debounce = 0,
        })
        helpers.wait_for_list(picker)
        helpers.wait_for_line_contains(picker, "first")

        local prompt_input = picker.select._options.prompt_input
        assert(type(prompt_input) == "function")
        --- @cast prompt_input fun(string)
        prompt_input("second")
        helpers.wait_for_line_contains(picker, "second")
        picker:close()

        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    helpers.run_test_case("blines_word_visual", function()
        local buf = helpers.create_named_buffer("blines_word.txt", {
            "alpha",
        })
        vim.api.nvim_set_current_buf(buf)

        helpers.with_mock(vim.fn, "expand", function()
            return "alpha"
        end, function()
            local picker = require("fuzzy.pickers.blines").open_buffer_lines_word({
                preview = false,
                prompt_debounce = 0,
            })
            helpers.wait_for(function()
                return helpers.get_query(picker) == "alpha"
            end, 1500)
            helpers.wait_for_prompt_cursor(picker)
            picker:close()
        end)

        helpers.with_mock(require("fuzzy.utils"), "get_visual_text", function()
            return "alpha"
        end, function()
            local picker = require("fuzzy.pickers.blines").open_buffer_lines_visual({
                preview = false,
                prompt_debounce = 0,
            })
            helpers.wait_for(function()
                return helpers.get_query(picker) == "alpha"
            end, 1500)
            helpers.wait_for_prompt_cursor(picker)
            picker:close()
        end)

        vim.api.nvim_buf_delete(buf, { force = true })
    end)
end

return M
