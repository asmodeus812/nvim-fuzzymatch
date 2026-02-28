---@diagnostic disable: invisible
local helpers = require("tests.helpers")
local util = require("fuzzy.pickers.util")

local M = { name = "loclist_stack" }

function M.run()
    helpers.run_test_case("loclist_stack", function()
        helpers.with_mock(vim.fn, "execute", function(command_name)
            if command_name == "lhistory" then
                return "  list 1  Loclist-1\n  list 2  Loclist-2\n"
            end
            return ""
        end, function()
            local stack_picker = require("fuzzy.pickers.loclist_stack")
            local picker = stack_picker.open_loclist_stack({
                preview = false,
                prompt_debounce = 0,
            })
            helpers.wait_for(function()
                return helpers.get_entries(picker) ~= nil
            end, 2000)
            helpers.wait_for_line_contains(picker, "list 1")
            picker:close()
        end)
    end)
end

return M
