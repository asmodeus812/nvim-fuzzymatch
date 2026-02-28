---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "changes" }

function M.run()
    helpers.run_test_case("changes", function()
        local buf = helpers.create_named_buffer("changes.txt", { "one", "two" })
        vim.api.nvim_set_current_buf(buf)
        local change_list = {
            { lnum = 2, col = 1 },
        }
        helpers.with_mock(vim.fn, "getchangelist", function()
            return { change_list, 1 }
        end, function()
            local changes_picker = require("fuzzy.pickers.changes")
            local picker = changes_picker.open_changes_picker({
                preview = false,
                icons = false,
                prompt_debounce = 0,
            })
            helpers.wait_for_list(picker)
            helpers.wait_for_line_contains(picker, "changes.txt")
            helpers.wait_for_line_contains(picker, ":")
            picker:close()
        end)

        vim.api.nvim_buf_delete(buf, { force = true })
    end)
end

return M
