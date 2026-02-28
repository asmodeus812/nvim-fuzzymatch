---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "vimdoc" }

function M.run()
    helpers.run_test_case("vimdoc", function()
        helpers.with_mock(vim.fn, "api_info", function()
            return {
                functions = {
                    { name = "nvim_buf_get_lines" },
                    { name = "nvim_win_get_cursor" },
                    { name = "nvim_buf_get_lines" },
                },
            }
        end, function()
            local api_picker = require("fuzzy.pickers.vimdoc")
            local picker = api_picker.open_vimdoc_picker({
                preview = false,
                prompt_debounce = 0,
            })
            helpers.wait_for_entries(picker)
            helpers.wait_for_line_contains(picker, "nvim_buf_get_lines()")
            helpers.type_query(picker, "win_get")
            helpers.wait_for_line_contains(picker, "nvim_win_get_cursor()")
            picker:close()
        end)
    end)

    helpers.run_test_case("vimdoc_action", function()
        helpers.with_mock(vim.fn, "api_info", function()
            return {
                functions = {
                    { name = "nvim_buf_get_lines" },
                },
            }
        end, function()
            helpers.with_cmd_capture(function(calls)
                local api_picker = require("fuzzy.pickers.vimdoc")
                local picker = api_picker.open_vimdoc_picker({
                    preview = false,
                    prompt_debounce = 0,
                })
                helpers.wait_for_list(picker)
                helpers.wait_for_entries(picker)
                local action = picker.select._options.mappings["<cr>"]
                action(picker.select)
                helpers.assert_ok(#calls > 0, "help cmd")
                helpers.close_picker(picker)
            end)
        end)
    end)
end

return M
