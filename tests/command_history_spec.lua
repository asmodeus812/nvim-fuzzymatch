---@diagnostic disable: invisible
local helpers = require("tests.helpers")
local util = require("fuzzy.pickers.util")

local M = { name = "command_history" }

function M.run()
  helpers.run_test_case("command_history", function()
    helpers.with_mock_map(vim.fn, {
      histnr = function()
        return 2
      end,
      histget = function(_, index)
        if index == 2 then
          return "echo 456"
        end
        return "echo 123"
      end,
    }, function()
      local history_picker = require("fuzzy.pickers.command_history")
      local picker = history_picker.open_command_history({
        preview = false,
        prompt_debounce = 0,
      })
      helpers.wait_for_list(picker)
      helpers.wait_for_line_contains(picker, "echo 123")
      helpers.wait_for_line_contains(picker, "echo 456")
      picker:close()
    end)
  end)
end

return M
