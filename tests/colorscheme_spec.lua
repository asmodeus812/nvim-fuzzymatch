---@diagnostic disable: invisible
local helpers = require("script.test_utils")

local M = { name = "colorscheme" }

function M.run()
    helpers.run_test_case("colorscheme", function()
        helpers.with_mock(vim.fn, "getcompletion", function(_, _)
            return { "colorscheme-a" }
        end, function()
            local colors_picker = require("fuzzy.pickers.colorscheme")
            local picker = colors_picker.open_colorscheme_picker({
                preview = false,
                prompt_debounce = 0,
            })
            helpers.wait_for_stream(picker)
            helpers.type_query(picker, "colorscheme-a")
            helpers.wait_for_stream(picker)
            helpers.wait_for_match(picker)
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
                    prompt_debounce = 0,
                })
                helpers.wait_for_stream(picker)
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

    helpers.run_test_case("colorscheme_preview", function()
        helpers.with_mock(vim.fn, "getcompletion", function()
            return { "colorscheme-a", "colorscheme-b" }
        end, function()
            helpers.with_cmd_capture(function(calls)
                local colors_picker = require("fuzzy.pickers.colorscheme")
                local picker = colors_picker.open_colorscheme_picker({
                    preview = true,
                    prompt_debounce = 0,
                })
                helpers.wait_for_stream(picker)
                helpers.wait_for_list(picker)
                helpers.wait_for_entries(picker)

                local function count_calls(name)
                    local total = 0
                    for _, call in ipairs(calls) do
                        if call.kind == "colorscheme" and call.args[1] == name then
                            total = total + 1
                        end
                    end
                    return total
                end

                helpers.wait_for(function()
                    return count_calls("colorscheme-a") >= 1
                end, 1500)
                picker.select:move_down()
                helpers.wait_for(function()
                    return count_calls("colorscheme-b") >= 1
                end, 1500)
                picker.select:move_up()
                helpers.wait_for(function()
                    return count_calls("colorscheme-a") >= 2
                end, 1500)
                picker:close()
            end)
        end)
    end)
end

return M
