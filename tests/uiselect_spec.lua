---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "uiselect" }

function M.run()
    helpers.run_test_case("uiselect", function()
        local picked = nil
        local items = { "one", "two" }
        local picker = require("fuzzy.pickers.select").open_select_picker(
            items,
            { prompt = "Pick", format_item = function(i) return i end },
            function(item)
                picked = item
            end
        )
        helpers.wait_for_list(picker)
        helpers.wait_for_entries(picker)
        local action = picker.select._options.mappings["<cr>"]
        --- @cast action fun(self: any)
        action(picker.select)
        helpers.eq(picked, "one", "picked")
        helpers.close_picker(picker)
    end)
end

return M
