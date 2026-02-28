---@diagnostic disable: invisible
local helpers = require("tests.helpers")
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
            end, 1500)
            helpers.wait_for_line_contains(picker, "list 1")
            picker:close()
        end)
    end)

    helpers.run_test_case("loclist_stack_action", function()
        helpers.with_cmd_capture(function(calls)
            helpers.with_mock(vim.fn, "execute", function(command_name)
                if command_name == "lhistory" then
                    return "  list 3  Loclist-3\n"
                end
                return ""
            end, function()
                local stack_picker = require("fuzzy.pickers.loclist_stack")
                local picker = stack_picker.open_loclist_stack({
                    preview = false,
                    prompt_debounce = 0,
                })
                helpers.wait_for_list(picker)
                helpers.wait_for_entries(picker)
                local action = picker.select._options.mappings["<cr>"]
                --- @cast action fun(self: any)
                action(picker.select)
                helpers.assert_ok(#calls > 0, "cmd calls")
                helpers.close_picker(picker)
            end)
        end)
    end)
end

return M
