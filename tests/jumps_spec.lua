---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "jumps" }

function M.run()
    helpers.run_test_case("jumps", function()
        local buf = helpers.create_named_buffer("jumps.txt", {
            "one",
            "two",
            "three",
        })
        vim.api.nvim_set_current_buf(buf)
        local jump_list = {
            { bufnr = buf, lnum = 2, col = 1, nr = 1 },
        }
        helpers.with_mock(vim.fn, "getjumplist", function()
            return { jump_list, 1 }
        end, function()
            local jumps_picker = require("fuzzy.pickers.jumps")
            local picker = jumps_picker.open_jumps_picker({
                preview = false,
                icons = false,
                prompt_debounce = 0,
            })
            helpers.wait_for_list(picker)
            helpers.wait_for_line_contains(picker, "jumps.txt")
            helpers.wait_for_line_contains(picker, ":")
            picker:close()
        end)

        vim.api.nvim_buf_delete(buf, { force = true })
    end)
end

return M
