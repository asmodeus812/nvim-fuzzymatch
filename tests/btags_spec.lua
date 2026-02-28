---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "btags" }

function M.run()
    helpers.run_test_case("btags", function()
        local buf = helpers.create_named_buffer("btags.txt", { "alpha", "beta" })
        vim.api.nvim_set_current_buf(buf)
        local tag_list = {
            { name = "tag-b", filename = vim.api.nvim_buf_get_name(buf) },
        }
        helpers.with_mock(vim.fn, "taglist", function(_)
            return tag_list
        end, function()
            local btags_picker = require("fuzzy.pickers.btags")
            local picker = btags_picker.open_btags_picker({
                preview = false,
                prompt_debounce = 0,
            })
            helpers.wait_for(function()
                return helpers.get_entries(picker) ~= nil
            end, 2000)
            local prompt_input = picker.select._options.prompt_input
            prompt_input("tag-b")
            helpers.wait_for_line_contains(picker, "tag-b")
            picker:close()
        end)
        vim.api.nvim_buf_delete(buf, { force = true })
    end)
end

return M
