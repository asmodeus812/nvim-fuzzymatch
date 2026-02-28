---@diagnostic disable: invisible
local helpers = require("tests.helpers")
local util = require("fuzzy.pickers.util")

local M = { name = "search_history" }

function M.run()
  helpers.run_test_case("search_history", function()
    helpers.with_mock_map(vim.fn, {
      histnr = function()
        return 2
      end,
      histget = function(_, index)
        if index == 2 then
          return "needle-two"
        end
        return "needle"
      end,
    }, function()
      local history_picker = require("fuzzy.pickers.search_history")
      local picker = history_picker.open_search_history({
        preview = false,
        prompt_debounce = 0,
      })
      helpers.wait_for_list(picker)
      helpers.wait_for_line_contains(picker, "needle")
      helpers.wait_for_line_contains(picker, "needle-two")
      picker:close()
    end)
  end)
end

return M
