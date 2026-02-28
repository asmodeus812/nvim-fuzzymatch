---@diagnostic disable: invisible
local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local helpers = require("tests.helpers")

local M = { name = "picker" }

function M.run()
  local picker = Picker.new({
    content = { "alpha", "beta", "gamma" },
    headers = { { "Picker" } },
    preview = false,
    prompt_query = "be",
    actions = {
      ["<cr>"] = Select.default_select,
    },
  })

  picker:open()
  helpers.wait_for_list(picker)
  helpers.wait_for_line_contains(picker, "alpha")
  helpers.wait_for(function()
    return picker.select and picker.select._state.entries
        and #picker.select._state.entries == 3
  end, 2000)

  helpers.eq(#picker.select._state.entries, 3, "entries")
  local lines = helpers.get_list_lines(picker)
  helpers.assert_ok(#lines > 0, "list empty")
  helpers.assert_line_contains(lines, "alpha", "missing")

  helpers.type_query(picker, "gam")
  helpers.wait_for(function()
    return picker.select:query():find("gam", 1, true) ~= nil
  end, 2000)

  helpers.type_query(picker, "<c-u>")
  helpers.wait_for(function()
    return picker.select:query() == ""
  end, 2000)

  picker:close()

  local stream_picker = Picker.new({
    content = function(cb)
      cb("one")
      cb("two")
      cb("three")
      cb(nil)
    end,
    display = function(entry)
      return string.upper(entry)
    end,
    preview = false,
    actions = {
      ["<cr>"] = Select.default_select,
    },
  })

  stream_picker:open()
  helpers.wait_for_list(stream_picker)
  helpers.wait_for_line_contains(stream_picker, "ONE")
  helpers.wait_for(function()
    return stream_picker.select
      and stream_picker.select._state.entries
      and #stream_picker.select._state.entries == 3
  end, 2000)

  local stream_lines = helpers.get_list_lines(stream_picker)
  helpers.assert_line_contains(stream_lines, "ONE", "display")
  helpers.assert_line_contains(stream_lines, "TWO", "display")

  stream_picker:close()
end

return M
