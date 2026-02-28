---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "quickfix" }

function M.run()
    helpers.run_test_case("quickfix", function()
        local buf = helpers.create_named_buffer("quickfix.txt", { "alpha", "beta" })
        local item_list = {
            { bufnr = buf, lnum = 1, col = 1, text = "alpha" },
        }
        vim.fn.setqflist({}, "r", { title = "Quickfix", items = item_list })
        local qf_info = vim.fn.getqflist({ items = 1 })
        if not qf_info or not qf_info.items or #qf_info.items == 0 then
            vim.api.nvim_buf_delete(buf, { force = true })
            return
        end
        local qf_picker = require("fuzzy.pickers.quickfix")
        local picker = qf_picker.open_quickfix_picker({
            preview = false,
            icons = false,
            prompt_debounce = 0,
        })
        helpers.wait_for_list(picker)
        helpers.wait_for_line_contains(picker, "quickfix.txt")
        helpers.wait_for_line_contains(picker, "alpha")
        picker:close()
        vim.api.nvim_buf_delete(buf, { force = true })
    end)
end

return M
