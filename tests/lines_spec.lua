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
        prompt_input("gamma")
        helpers.wait_for_line_contains(picker, "gamma line")
        picker:close()

        vim.api.nvim_buf_delete(buf_two, { force = true })
        vim.api.nvim_buf_delete(buf_one, { force = true })
    end)
end

return M
