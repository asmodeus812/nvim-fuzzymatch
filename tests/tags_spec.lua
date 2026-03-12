---@diagnostic disable: invisible
local helpers = require("script.test_utils")

local M = { name = "tags" }

function M.run()
    helpers.run_test_case("tags_basic", function()
        helpers.with_mock(vim.fn, "getcompletion", function(_, _)
            return { "tag-one" }
        end, function()
            local tags_picker = require("fuzzy.pickers.tags")
            local picker = tags_picker.open_tags_picker({
                preview = false,
                prompt_debounce = 0,
            })
            helpers.wait_for_stream(picker)
            helpers.type_query(picker, "tag-one")
            helpers.wait_for_stream(picker)
            helpers.wait_for_match(picker)
            helpers.wait_for_line_contains(picker, "tag-one")
            picker:close()
        end)
    end)

    helpers.run_test_case("tags_action", function()
        helpers.with_mock(vim.fn, "getcompletion", function()
            return { "tag-one" }
        end, function()
            helpers.with_cmd_capture(function(calls)
                local tags_picker = require("fuzzy.pickers.tags")
                local picker = tags_picker.open_tags_picker({
                    preview = false,
                    prompt_debounce = 0,
                })
                helpers.wait_for_stream(picker)
                helpers.wait_for_list(picker)
                helpers.wait_for_entries(picker)
                local action = picker.select:options().mappings["<cr>"]
                action(picker.select)
                helpers.assert_ok(#calls > 0, "tag cmd")
                helpers.close_picker(picker)
            end)
        end)
    end)
end

return M
