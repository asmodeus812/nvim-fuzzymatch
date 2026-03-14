---@diagnostic disable: invisible
local helpers = require("script.test_utils")

local M = { name = "registers" }

function M.run()
    helpers.run_test_case("registers_basic", function()
        vim.fn.setreg("a", string.rep("x", 100))
        local registers_picker = require("fuzzy.pickers.registers")
        local picker = registers_picker.open_registers_picker({
            prompt_debounce = 0,
            preview = false,
            filter = "^a$",
        })
        helpers.wait_for_stream(picker)
        helpers.wait_for_list(picker)
        helpers.wait_for_line_contains(picker, "[a]")
        helpers.wait_for_line_contains(picker, "...")
        helpers.wait_for_list_extmarks(picker)
        helpers.wait_for(function()
            local extmarks = helpers.get_list_extmarks(picker)
            local ok_id = pcall(helpers.assert_has_hl, extmarks, "Constant")
            local ok_str = pcall(helpers.assert_has_hl, extmarks, "String")
            return ok_id and ok_str
        end, 1500)
        local extmarks = helpers.get_list_extmarks(picker)
        helpers.assert_has_hl(extmarks, "Constant", "registers prefix hl")
        helpers.assert_has_hl(extmarks, "String", "registers value hl")
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
            helpers.wait_for_stream(picker)
            helpers.wait_for_list(picker)
            helpers.wait_for_entries(picker)
            local action = picker.select:options().mappings["<cr>"]
            action(picker.select)
            helpers.assert_ok(#set_calls > 0, "setreg")
            helpers.eq(set_calls[1].name, "\"", "target register")
            picker:close()
        end)
    end)

    helpers.run_test_case("registers_preview_multiline", function()
        vim.fn.setreg("a", { "one", "two", "three" })
        helpers.with_mock(vim.fn, "getreginfo", function(name)
            if name == "a" then
                return {
                    regcontents = { "one", "two", "three" },
                    regtype = "V",
                }
            end
            return {
                regcontents = { "" },
                regtype = "v",
            }
        end, function()
            local registers_picker = require("fuzzy.pickers.registers")
            local picker = registers_picker.open_registers_picker({
                prompt_debounce = 0,
                preview = true,
                filter = "^a$",
            })
            helpers.wait_for_stream(picker)
            helpers.wait_for_list(picker)
            helpers.wait_for_entries(picker)
            helpers.wait_for(function()
                return picker.select.preview_window
                    and helpers.is_window_valid(picker.select.preview_window)
            end, 1500)
            helpers.assert_ok(
                helpers.wait_for_window_line_contains(
                    picker.select.preview_window, "one", 1500
                ),
                "preview line"
            )
            helpers.assert_ok(
                helpers.wait_for_window_line_contains(
                    picker.select.preview_window, "two", 1500
                ),
                "preview line"
            )
            helpers.assert_ok(
                helpers.wait_for_window_line_contains(
                    picker.select.preview_window, "three", 1500
                ),
                "preview line"
            )
            picker:close()
        end)
    end)

    helpers.run_test_case("registers_filter", function()
        vim.fn.setreg("a", "alpha")
        vim.fn.setreg("b", "bravo")
        local registers_picker = require("fuzzy.pickers.registers")
        local picker = registers_picker.open_registers_picker({
            prompt_debounce = 0,
            preview = false,
            filter = "^a$",
        })
        helpers.wait_for_stream(picker)
        helpers.wait_for_list(picker)
        helpers.wait_for_line_contains(picker, "[a]")
        helpers.assert_line_missing(helpers.get_list_lines(picker), "[b]", "filter")
        picker:close()
    end)
end

return M
