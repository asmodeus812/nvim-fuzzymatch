---@diagnostic disable: invisible
local helpers = require("script.test_utils")

local M = { name = "registers" }

function M.run()
    helpers.run_test_case("registers", function()
        vim.fn.setreg("a", string.rep("x", 100))
        local registers_picker = require("fuzzy.pickers.registers")
        local picker = registers_picker.open_registers_picker({
            prompt_debounce = 0,
            preview = false,
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

    helpers.run_test_case("registers_preview_multiline", function()
        vim.fn.setreg("a", { "one", "two", "three" })
        local registers_picker = require("fuzzy.pickers.registers")
        local picker = registers_picker.open_registers_picker({
            prompt_debounce = 0,
            preview = true,
            filter = "^a$",
        })
        helpers.wait_for_list(picker)
        helpers.wait_for_entries(picker)
        helpers.wait_for(function()
            return picker.select.preview_window
                and helpers.is_window_valid(picker.select.preview_window)
        end, 1500)
        local preview_buf = vim.api.nvim_win_get_buf(picker.select.preview_window)
        helpers.wait_for(function()
            local lines = helpers.get_buffer_lines(preview_buf)
            return vim.tbl_contains(lines, "one")
                and vim.tbl_contains(lines, "two")
                and vim.tbl_contains(lines, "three")
        end, 1500)
        local lines = helpers.get_buffer_lines(preview_buf)
        helpers.assert_line_contains(lines, "one", "preview line")
        helpers.assert_line_contains(lines, "two", "preview line")
        helpers.assert_line_contains(lines, "three", "preview line")
        picker:close()
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
        helpers.wait_for_list(picker)
        helpers.wait_for_line_contains(picker, "[a]")
        helpers.assert_line_missing(helpers.get_list_lines(picker), "[b]", "filter")
        picker:close()
    end)
end

return M
