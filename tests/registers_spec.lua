---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "registers" }

function M.run()
  helpers.run_test_case("registers", function()
    vim.fn.setreg("a", string.rep("x", 100))
    local registers_picker = require("fuzzy.pickers.registers")
    local picker = registers_picker.open_registers_picker({
      prompt_debounce = 0,
    })
    helpers.wait_for_list(picker)
    helpers.wait_for_line_contains(picker, "[a]")
    helpers.wait_for_line_contains(picker, "...")
    picker:close()
  end)
end

return M
