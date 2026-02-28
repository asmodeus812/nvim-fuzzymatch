---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "tags" }

function M.run()
    helpers.run_test_case("tags", function()
        helpers.with_mock(vim.fn, "getcompletion", function(_, _)
            return { "tag-one" }
        end, function()
            local tags_picker = require("fuzzy.pickers.tags")
            local picker = tags_picker.open_tags_picker({
                preview = false,
                prompt_debounce = 0,
            })
            helpers.wait_for(function()
                return helpers.get_entries(picker) ~= nil
            end, 2000)
            local prompt_input = picker.select._options.prompt_input
            prompt_input("tag-one")
            helpers.wait_for_line_contains(picker, "tag-one")
            picker:close()
        end)
    end)
end

return M
