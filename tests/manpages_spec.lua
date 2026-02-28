---@diagnostic disable: invisible
local helpers = require("tests.helpers")
local util = require("fuzzy.pickers.util")

local M = { name = "manpages" }

function M.run()
    helpers.run_test_case("manpages", function()
        helpers.with_mock_map(util, {
            pick_first_command = function()
                return "apropos"
            end,
        }, function()
            helpers.with_mock(vim, "system", function()
                return {
                    wait = function()
                        return {
                            code = 0,
                            stdout = table.concat({
                                "printf (3) - formatted output conversion",
                                "ls (1) - list directory contents",
                            }, "\n"),
                        }
                    end,
                }
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
                prompt_input("printf")
                helpers.wait_for_line_contains(picker, "printf(3)")
                picker:close()
            end)
        end)
    end)

    helpers.run_test_case("manpages_action", function()
        helpers.with_mock_map(util, {
            pick_first_command = function()
                return "apropos"
            end,
        }, function()
            helpers.with_mock(vim, "system", function()
                return {
                    wait = function()
                        return {
                            code = 0,
                            stdout = "manpage (1) - test",
                        }
                    end,
                }
            end, function()
                helpers.with_cmd_capture(function(calls)
                    local man_picker = require("fuzzy.pickers.manpages")
                    local picker = man_picker.open_manpages_picker({
                        preview = false,
                        prompt_debounce = 0,
                    })
                    helpers.wait_for_list(picker)
                    helpers.wait_for_entries(picker)
                    local action = picker.select._options.mappings["<cr>"]
                    action(picker.select)
                    helpers.assert_ok(#calls > 0, "man cmd")
                    helpers.close_picker(picker)
                end)
            end)
        end)
    end)
end

return M
