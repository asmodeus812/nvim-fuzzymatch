---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "commands" }

function M.run()
  helpers.run_test_case("commands", function()
    helpers.with_mock(vim.api, "nvim_get_commands", function(opts)
      if opts and opts.builtin then
        return { edit = {}, write = {} }
      end
      return { TestPickerCmd = {} }
    end, function()
      local commands_picker = require("fuzzy.pickers.commands")
      local picker = commands_picker.open_commands_picker({
        include_builtin = false,
        include_user = true,
        preview = false,
        prompt_debounce = 0,
      })
      helpers.wait_for_list(picker)
      helpers.wait_for_line_contains(picker, "TestPickerCmd")
      helpers.assert_line_missing(helpers.get_list_lines(picker), "edit", "builtin exclude")
      picker:close()
    end)
  end)
end

return M
