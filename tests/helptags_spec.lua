---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "helptags" }

function M.run()
    helpers.run_test_case("helptags", function()
        helpers.with_mock(vim.fn, "getcompletion", function(_, _)
            return { "help-tag" }
        end, function()
            local help_picker = require("fuzzy.pickers.helptags")
            local picker = help_picker.open_helptags_picker({
                preview = false,
                prompt_debounce = 0,
            })
            helpers.wait_for(function()
                return helpers.get_entries(picker) ~= nil
            end, 2000)
            local prompt_input = picker.select._options.prompt_input
            prompt_input("help-tag")
            helpers.wait_for_line_contains(picker, "help-tag")
            picker:close()
        end)
    end)
end

return M
