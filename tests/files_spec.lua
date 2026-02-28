---@diagnostic disable: invisible
local helpers = require("tests.helpers")
local util = require("fuzzy.pickers.util")

local M = { name = "files" }

function M.run()
  helpers.run_test_case("files", function()
    local original_command_is_available = util.command_is_available
    util.command_is_available = function(command_name)
      if command_name == "rg" or command_name == "fd" then
        return false
      end
      return original_command_is_available(command_name)
    end

    local ok, err = pcall(function()
      local cmd = util.pick_first_command({ "rg", "fd", "find" })
      if not cmd or cmd ~= "find" then
        return
      end

      local dir_path = helpers.create_temp_dir()
      local sub_path = vim.fs.joinpath(dir_path, "sub")
      vim.uv.fs_mkdir(sub_path, 448)
      helpers.write_file(vim.fs.joinpath(dir_path, "alpha.txt"), "alpha\n")
      helpers.write_file(vim.fs.joinpath(sub_path, "beta.txt"), "beta\n")

      helpers.with_cwd(dir_path, function()
        local files_picker = require("fuzzy.pickers.files")
        local picker = files_picker.open_files_picker({
          cwd = dir_path,
          preview = false,
          icons = false,
          prompt_debounce = 0,
          stream_step = 1000,
          match_step = 1000,
        })

      helpers.wait_for_list(picker)
      helpers.wait_for(function()
        local entry_list = helpers.get_entries(picker) or {}
        return #entry_list >= 2
      end, 2000)
      helpers.wait_for_line_contains(picker, "alpha.txt")
      helpers.wait_for_line_contains(picker, "beta.txt")

      local prompt_input = picker.select._options.prompt_input
      prompt_input("beta")
        helpers.wait_for(function()
          return picker.select:query():find("beta", 1, true) ~= nil
        end, 2000)
        helpers.wait_for_line_contains(picker, "beta.txt")
        helpers.assert_line_missing(helpers.get_list_lines(picker), "alpha.txt", "filter")
        picker:close()
      end)
    end)

    util.command_is_available = original_command_is_available
    if not ok then
      error(err)
    end
  end)
end

return M
