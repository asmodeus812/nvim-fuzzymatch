---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "vimdoc" }

function M.run()
    helpers.run_test_case("vimdoc", function()
        helpers.with_mock(vim.fn, "api_info", function()
            return {
                functions = {
                    {
                        name = "nvim_buf_get_lines",
                        since = 1,
                        return_type = "Array",
                        parameters = { { "Buffer", "buffer" }, { "Integer", "start" } },
                    },
                    {
                        name = "nvim_win_get_cursor",
                        since = 2,
                        return_type = "Array",
                        method = true,
                        parameters = { { "Window", "window" } },
                    },
                    {
                        name = "nvim__private_test",
                        since = 3,
                        return_type = "Array",
                        deprecated_since = 7,
                    },
                    {
                        name = "nvim_buf_get_lines",
                        since = 1,
                        return_type = "Array",
                    },
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
            helpers.assert_line_missing(
                helpers.get_list_lines(picker),
                "nvim__private_test()",
                "private entries filtered by default"
            )
            picker:close()
        end)
    end)

    helpers.run_test_case("vimdoc_filters", function()
        helpers.with_mock(vim.fn, "api_info", function()
            return {
                functions = {
                    { name = "nvim_old_fn", since = 1, deprecated_since = 3 },
                    { name = "nvim_new_fn", since = 10 },
                    { name = "vim_old_fn", since = 2, deprecated_since = 5 },
                },
            }
        end, function()
            local api_picker = require("fuzzy.pickers.vimdoc")
            local picker = api_picker.open_vimdoc_picker({
                preview = false,
                prompt_debounce = 0,
                deprecated_only = true,
                prefix = false,
            })
            helpers.wait_for_entries(picker)
            helpers.assert_line_contains(helpers.get_list_lines(picker), "nvim_old_fn()", "deprecated shown")
            helpers.assert_line_contains(helpers.get_list_lines(picker), "vim_old_fn()", "non-prefix shown")
            helpers.assert_line_missing(helpers.get_list_lines(picker), "nvim_new_fn()", "non-deprecated hidden")
            picker:close()
        end)
    end)

    helpers.run_test_case("vimdoc_preview", function()
        helpers.with_mock(vim.fn, "api_info", function()
            return {
                functions = {
                    {
                        name = "nvim_buf_get_lines",
                        since = 9,
                        return_type = "Array",
                        method = false,
                        parameters = { { "Buffer", "buffer" }, { "Integer", "start" } },
                    },
                },
            }
        end, function()
            local api_picker = require("fuzzy.pickers.vimdoc")
            local picker = api_picker.open_vimdoc_picker({
                preview = true,
                prompt_debounce = 0,
            })
            helpers.wait_for_entries(picker)
            helpers.wait_for(function()
                local preview_buf = picker.select.preview_window
                    and vim.api.nvim_win_get_buf(picker.select.preview_window) or nil
                local lines = helpers.get_buffer_lines(preview_buf)
                for _, line in ipairs(lines or {}) do
                    if line:find("Signature:", 1, true) then
                        return true
                    end
                end
                return false
            end, 1500)
            picker:close()
        end)
    end)

    helpers.run_test_case("vimdoc_action", function()
        helpers.with_mock(vim.fn, "api_info", function()
            return {
                functions = {
                    { name = "nvim_buf_get_lines", since = 1 },
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
