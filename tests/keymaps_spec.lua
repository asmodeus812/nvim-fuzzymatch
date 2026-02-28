---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "keymaps" }

function M.run()
  helpers.run_test_case("keymaps", function()
    helpers.with_mock(vim.api, "nvim_get_keymap", function()
      return {
        { lhs = "gx", rhs = "do", desc = "map-test" },
      }
    end, function()
      local keymaps_picker = require("fuzzy.pickers.keymaps")
      local picker = keymaps_picker.open_keymaps_picker({
        modes = { "n" },
        include_buffer = false,
        preview = false,
        prompt_debounce = 0,
      })
      helpers.wait_for_list(picker)
      helpers.wait_for_line_contains(picker, "gx")
      helpers.wait_for_line_contains(picker, "map-test")
      picker:close()
    end)
  end)
end

return M
