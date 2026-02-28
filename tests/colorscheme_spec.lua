---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "colorscheme" }

function M.run()
    helpers.run_test_case("colorscheme", function()
        helpers.with_mock(vim.fn, "getcompletion", function(_, _)
            return { "colorscheme-a" }
        end, function()
            local colors_picker = require("fuzzy.pickers.colorscheme")
            local picker = colors_picker.open_colorscheme_picker({
                preview = false,
                live_preview = false,
                prompt_debounce = 0,
            })
            helpers.wait_for(function()
                return helpers.get_entries(picker) ~= nil
            end, 1500)
            local prompt_input = picker.select._options.prompt_input
            assert(type(prompt_input) == "function")
            --- @cast prompt_input fun(string)
            prompt_input("colorscheme-a")
            helpers.wait_for_line_contains(picker, "colorscheme-a")
            picker:close()
        end)
    end)
end

return M
