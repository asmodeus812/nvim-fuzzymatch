---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "commands" }

function M.run()
    helpers.run_test_case("commands", function()
        helpers.with_mock(vim.api, "nvim_get_commands", function(opts)
            if opts and opts.builtin then
                return { edit = {}, write = {} }
            end
            return { TestPickerCmd = {} }
        end, function()
            local commands_picker = require("fuzzy.pickers.commands")
            local picker = commands_picker.open_commands_picker({
                include_builtin = false,
                include_user = true,
                preview = false,
                prompt_debounce = 0,
            })
            helpers.wait_for_list(picker)
            helpers.wait_for_line_contains(picker, "TestPickerCmd")
            helpers.assert_line_missing(helpers.get_list_lines(picker), "edit", "builtin exclude")
            picker:close()
        end)
    end)

    helpers.run_test_case("commands_builtin_action", function()
        helpers.with_mock_map(vim.api, {
            nvim_get_commands = function(opts)
                if opts and opts.builtin then
                    return { edit = {}, write = {} }
                end
                return {}
            end,
        }, function()
            helpers.with_cmd_capture(function(calls)
                local commands_picker = require("fuzzy.pickers.commands")
                local picker = commands_picker.open_commands_picker({
                    include_builtin = true,
                    include_user = false,
                    preview = false,
                    prompt_debounce = 0,
                })
                helpers.wait_for_list(picker)
                helpers.wait_for_entries(picker)
                helpers.wait_for_line_contains(picker, "edit")
                local action = picker.select._options.mappings["<cr>"]
                action(picker.select)
                local found = false
                for _, call in ipairs(calls) do
                    if call.kind == "cmd" and call.args[1] == "edit" then
                        found = true
                        break
                    end
                end
                helpers.assert_ok(found, "cmd")
                helpers.close_picker(picker)
            end)
        end)
    end)

    helpers.run_test_case("commands_preview_ignored", function()
        helpers.with_mock(vim.api, "nvim_get_commands", function(opts)
            if opts and opts.builtin then
                return { edit = {} }
            end
            return {}
        end, function()
            local commands_picker = require("fuzzy.pickers.commands")
            local picker = commands_picker.open_commands_picker({
                include_builtin = true,
                include_user = false,
                preview = true,
                prompt_debounce = 0,
            })
            helpers.wait_for_list(picker)
            helpers.assert_ok(
                picker.select._options.preview == false or picker.select._options.preview == nil,
                "preview should remain disabled"
            )
            helpers.close_picker(picker)
        end)
    end)
end

return M
