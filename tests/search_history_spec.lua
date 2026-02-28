---@diagnostic disable: invisible
local helpers = require("tests.helpers")
local M = { name = "search_history" }

function M.run()
    helpers.run_test_case("search_history", function()
        helpers.with_mock_map(vim.fn, {
            histnr = function()
                return 2
            end,
            histget = function(_, index)
                if index == 2 then
                    return "needle-two"
                end
                return "needle"
            end,
        }, function()
            local history_picker = require("fuzzy.pickers.search_history")
            local picker = history_picker.open_search_history({
                preview = false,
                prompt_debounce = 0,
            })
            helpers.wait_for_list(picker)
            helpers.wait_for_line_contains(picker, "needle")
            helpers.wait_for_line_contains(picker, "needle-two")
            picker:close()
        end)
    end)

    helpers.run_test_case("search_history_action", function()
        local set_calls = {}
        helpers.with_mock(vim.fn, "setreg", function(name, value)
            set_calls[#set_calls + 1] = { name = name, value = value }
        end, function()
            helpers.with_mock_map(vim.fn, {
                histnr = function()
                    return 1
                end,
                histget = function()
                    return "needle"
                end,
            }, function()
                local history_picker = require("fuzzy.pickers.search_history")
                local picker = history_picker.open_search_history({
                    preview = false,
                    prompt_debounce = 0,
                })
                helpers.wait_for_list(picker)
                helpers.wait_for_entries(picker)
                local action = picker.select._options.mappings["<cr>"]
                action(picker.select)
                helpers.eq(set_calls[1].name, "/", "register")
                helpers.eq(set_calls[1].value, "needle", "value")
                helpers.close_picker(picker)
            end)
        end)
    end)
end

return M
