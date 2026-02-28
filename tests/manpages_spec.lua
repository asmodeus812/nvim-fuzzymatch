---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "manpages" }

function M.run()
    helpers.run_test_case("manpages", function()
        helpers.with_mock(vim.fn, "getcompletion", function(_, _)
            return { "manpage" }
        end, function()
            local man_picker = require("fuzzy.pickers.manpages")
            local picker = man_picker.open_manpages_picker({
                preview = false,
                prompt_debounce = 0,
            })
            helpers.wait_for(function()
                return helpers.get_entries(picker) ~= nil
            end, 1500)
            local prompt_input = picker.select._options.prompt_input
            assert(type(prompt_input) == "function")
            --- @cast prompt_input fun(string)
            prompt_input("manpage")
            helpers.wait_for_line_contains(picker, "manpage")
            picker:close()
        end)
    end)
end

return M
