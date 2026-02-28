---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "oldfiles" }

function M.run()
  helpers.run_test_case("oldfiles", function()
    local dir_path = helpers.create_temp_dir()
    local file_path = vim.fs.joinpath(dir_path, "old.txt")
    helpers.write_file(file_path, "old\n")

    local other_dir_path = helpers.create_temp_dir()
    local other_file_path = vim.fs.joinpath(other_dir_path, "other.txt")
    helpers.write_file(other_file_path, "other\n")

    local ok = pcall(function()
      vim.v.oldfiles = { file_path, other_file_path }
    end)
    if not ok then
      return
    end
    if not vim.v.oldfiles or #vim.v.oldfiles == 0 then
      return
    end

    local oldfiles_picker = require("fuzzy.pickers.oldfiles")
    local picker = oldfiles_picker.open_oldfiles_picker({
      cwd = dir_path,
      preview = false,
      icons = false,
      prompt_debounce = 0,
      stat_file = true,
      cwd_only = true,
    })

    helpers.wait_for_list(picker)
    helpers.wait_for_line_contains(picker, "old.txt")
    helpers.assert_line_missing(helpers.get_list_lines(picker), "other.txt", "cwd only")
    picker:close()
  end)
end

return M
