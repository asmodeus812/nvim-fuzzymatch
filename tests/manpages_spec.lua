---@diagnostic disable: invisible
local helpers = require("script.test_utils")
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
                helpers.wait_for_stream(picker)
                local prompt_input = picker.select._options.prompt_input
                assert(type(prompt_input) == "function")
                --- @cast prompt_input fun(string)
                prompt_input("printf")
                helpers.wait_for_stream(picker)
                helpers.wait_for_match(picker)
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
                    helpers.wait_for_stream(picker)
                    helpers.wait_for_list(picker)
                    helpers.wait_for_entries(picker)
                    local map = picker.select._options.mappings
                    map["<cr>"](picker.select)
                    local saw_man = false
                    for _, call in ipairs(calls) do
                        local arg = call.args and call.args[1] or nil
                        if type(arg) == "table" and arg.cmd == "Man" then
                            saw_man = true
                        end
                    end
                    helpers.assert_ok(saw_man, "man cmd")
                end)
            end)
        end)
    end)
end

return M
