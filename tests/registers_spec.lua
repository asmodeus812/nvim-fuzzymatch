---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "registers" }

function M.run()
    helpers.run_test_case("registers", function()
        vim.fn.setreg("a", string.rep("x", 100))
        local registers_picker = require("fuzzy.pickers.registers")
        local picker = registers_picker.open_registers_picker({
            prompt_debounce = 0,
        })
        helpers.wait_for_list(picker)
        helpers.wait_for_line_contains(picker, "[a]")
        helpers.wait_for_line_contains(picker, "...")
        picker:close()
    end)

    helpers.run_test_case("registers_action", function()
        local set_calls = {}
        helpers.with_mock_map(vim.fn, {
            getreginfo = function(name)
                return {
                    regcontents = { "value-" .. name },
                    regtype = "v",
                }
            end,
            setreg = function(name, contents, regtype)
                set_calls[#set_calls + 1] = {
                    name = name,
                    contents = contents,
                    regtype = regtype,
                }
            end,
        }, function()
            local registers_picker = require("fuzzy.pickers.registers")
            local picker = registers_picker.open_registers_picker({
                prompt_debounce = 0,
            })
            helpers.wait_for_list(picker)
            helpers.wait_for_entries(picker)
            local action = picker.select._options.mappings["<cr>"]
            action(picker.select)
            helpers.assert_ok(#set_calls > 0, "setreg")
            helpers.eq(set_calls[1].name, "\"", "target register")
            picker:close()
        end)
    end)
end

return M
