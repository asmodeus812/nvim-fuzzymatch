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

    helpers.run_test_case("colorscheme_action", function()
        helpers.with_mock(vim.fn, "getcompletion", function()
            return { "colorscheme-a" }
        end, function()
            helpers.with_cmd_capture(function(calls)
                local colors_picker = require("fuzzy.pickers.colorscheme")
                local picker = colors_picker.open_colorscheme_picker({
                    preview = false,
                    live_preview = false,
                    prompt_debounce = 0,
                })
                helpers.wait_for_list(picker)
                helpers.wait_for_entries(picker)
                local action = picker.select._options.mappings["<cr>"]
                action(picker.select)
                local found = false
                for _, call in ipairs(calls) do
                    if call.kind == "colorscheme" and call.args[1] == "colorscheme-a" then
                        found = true
                        break
                    end
                end
                helpers.assert_ok(found, "apply")
                helpers.close_picker(picker)
            end)
        end)
    end)
end

return M
