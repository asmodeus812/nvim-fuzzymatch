---@diagnostic disable: invisible
local helpers = require("script.test_utils")

local M = { name = "helptags" }

function M.run()
    helpers.run_test_case("helptags_basic", function()
        helpers.with_mock(vim.fn, "getcompletion", function(_, _)
            return { "help-tag" }
        end, function()
            local help_picker = require("fuzzy.pickers.helptags")
            local picker = help_picker.open_helptags_picker({
                preview = false,
                prompt_debounce = 0,
            })
            helpers.wait_for_stream(picker)
            helpers.type_query(picker, "help-tag")
            helpers.wait_for_stream(picker)
            helpers.wait_for_match(picker)
            helpers.wait_for_line_contains(picker, "help-tag")
            picker:close()
        end)
    end)

    helpers.run_test_case("helptags_action", function()
        helpers.with_mock(vim.fn, "getcompletion", function()
            return { "help-tag" }
        end, function()
            helpers.with_cmd_capture(function(calls)
                local help_picker = require("fuzzy.pickers.helptags")
                local picker = help_picker.open_helptags_picker({
                    preview = false,
                    prompt_debounce = 0,
                })
                helpers.wait_for_stream(picker)
                helpers.wait_for_list(picker)
                helpers.wait_for_entries(picker)
                local map = picker.select._options.mappings
                map["<cr>"](picker.select)
                local saw_help = false
                for _, call in ipairs(calls) do
                    local arg = call.args and call.args[1] or nil
                    if type(arg) == "table" and arg.cmd == "help" then
                        saw_help = true
                    end
                end
                helpers.assert_ok(saw_help, "help cmd")
            end)
        end)
    end)
end

return M
