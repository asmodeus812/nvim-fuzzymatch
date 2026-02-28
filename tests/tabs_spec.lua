---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "tabs" }

function M.run()
  helpers.run_test_case("tabs", function()
    helpers.with_mock_map(vim.api, {
      nvim_list_tabpages = function()
        return { "tab-one" }
      end,
      nvim_tabpage_is_valid = function()
        return true
      end,
      nvim_tabpage_get_number = function()
        return 1
      end,
      nvim_tabpage_list_wins = function()
        return { 1 }
      end,
      nvim_win_get_buf = function()
        return 1
      end,
      nvim_buf_get_name = function()
        return "tab-file.txt"
      end,
    }, function()
      local tabs_picker = require("fuzzy.pickers.tabs")
      local picker = tabs_picker.open_tabs_picker({
        preview = false,
        prompt_debounce = 0,
      })
      helpers.wait_for_list(picker)
      helpers.wait_for_line_contains(picker, "[1]")
      helpers.wait_for_line_contains(picker, "tab-file.txt")
      picker:close()
    end)
  end)
end

return M
