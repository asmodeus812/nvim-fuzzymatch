---@diagnostic disable: invisible
local helpers = require("script.test_utils")

local M = { name = "btags" }

function M.run()
    helpers.run_test_case("btags", function()
        local buf = helpers.create_named_buffer("btags.txt", { "alpha", "beta" })
        vim.api.nvim_set_current_buf(buf)
        local tag_list = {
            { name = "tag-b", filename = vim.api.nvim_buf_get_name(buf), kind = "f" },
        }
        helpers.with_mock(vim.fn, "taglist", function(_)
            return tag_list
        end, function()
            local btags_picker = require("fuzzy.pickers.btags")
            local picker = btags_picker.open_btags_picker({
                preview = false,
                prompt_debounce = 0,
            })
            helpers.wait_for_stream(picker)
            helpers.type_query(picker, "tag-b")
            helpers.wait_for_stream(picker)
            helpers.wait_for_match(picker)
            helpers.wait_for_line_contains(picker, "tag-b")
            helpers.wait_for_list_extmarks(picker)
            local extmarks = helpers.get_list_extmarks(picker)
            helpers.assert_has_hl(extmarks, "Identifier", "btags name hl")
            helpers.assert_has_hl(extmarks, "Type", "btags kind hl")
            picker:close()
        end)
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    helpers.run_test_case("btags_action", function()
        local buf = helpers.create_named_buffer("btags-action.txt", { "alpha" })
        vim.api.nvim_set_current_buf(buf)
        local tag_list = {
            { name = "tag-b", filename = vim.api.nvim_buf_get_name(buf) },
        }
        helpers.with_mock(vim.fn, "taglist", function()
            return tag_list
        end, function()
            helpers.with_cmd_capture(function(calls)
                local btags_picker = require("fuzzy.pickers.btags")
                local picker = btags_picker.open_btags_picker({
                    preview = false,
                    prompt_debounce = 0,
                })
                helpers.wait_for_stream(picker)
                helpers.wait_for_list(picker)
                helpers.wait_for_entries(picker)
                local action = picker.select._options.mappings["<cr>"]
                action(picker.select)
                helpers.assert_ok(#calls > 0, "tag cmd")
                helpers.close_picker(picker)
            end)
        end)
        vim.api.nvim_buf_delete(buf, { force = true })
    end)
end

return M
