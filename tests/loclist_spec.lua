---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "loclist" }

function M.run()
  helpers.run_test_case("loclist", function()
    local buf = helpers.create_named_buffer("loclist.txt", { "alpha", "beta" })
    local item_list = {
      { bufnr = buf, lnum = 1, col = 1, text = "alpha" },
    }
    vim.fn.setloclist(0, {}, "r", { title = "Loclist", items = item_list })
    local loc_info = vim.fn.getloclist(0, { items = 1 })
    if not loc_info or not loc_info.items or #loc_info.items == 0 then
      vim.api.nvim_buf_delete(buf, { force = true })
      return
    end
    local loc_picker = require("fuzzy.pickers.loclist")
    local picker = loc_picker.open_loclist_picker({
      preview = false,
      icons = false,
      prompt_debounce = 0,
    })
    helpers.wait_for_list(picker)
    helpers.wait_for_line_contains(picker, "loclist.txt")
    helpers.wait_for_line_contains(picker, "alpha")
    picker:close()
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end

return M
