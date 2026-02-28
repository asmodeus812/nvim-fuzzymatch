---@diagnostic disable: invisible
local helpers = require("tests.helpers")
local M = { name = "quickfix_stack" }

function M.run()
    helpers.run_test_case("quickfix_stack", function()
        helpers.with_mock(vim.fn, "execute", function(command_name)
            if command_name == "chistory" then
                return "  list 1  Quickfix-1\n  list 2  Quickfix-2\n"
            end
            return ""
        end, function()
            local stack_picker = require("fuzzy.pickers.quickfix_stack")
            local picker = stack_picker.open_quickfix_stack({
                preview = false,
                prompt_debounce = 0,
            })
            helpers.wait_for(function()
                return helpers.get_entries(picker) ~= nil
            end, 1500)
            helpers.wait_for_line_contains(picker, "list 1")
            picker:close()
        end)
    end)
end

return M
