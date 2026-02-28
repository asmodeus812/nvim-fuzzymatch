---@diagnostic disable: invisible
local Select = require("fuzzy.select")
local helpers = require("tests.helpers")

local M = { name = "select" }

local function new_select(opts)
  return Select.new(opts or {})
end

local function run_action_case()
  local select = new_select({
    prompt_list = true,
    prompt_input = true,
    preview = false,
    list_offset = 1,
  })

  select:open()
  local height = helpers.is_window_valid(select.list_window)
    and vim.api.nvim_win_get_height(select.list_window) or 10
  local entries = {}
  local total = height + 8
  for i = 1, total do
    entries[i] = "item-" .. i
  end
  select:list(entries)
  helpers.wait_for(function()
    return select._state.entries and #select._state.entries == total
  end, 2000)
  helpers.wait_for(function()
    local lines = helpers.get_buffer_lines(select.list_buffer)
    return lines and #lines > 0
  end, 2000)
  helpers.wait_for(function()
    return helpers.get_buffer_line_count(select.list_buffer) >= height
  end, 2000)

  select:move_down()
  helpers.eq(select._state.cursor[1], 2, "move down")
  select:move_up()
  helpers.eq(select._state.cursor[1], 1, "move up")

  select:move_bot()
  helpers.assert_ok(
    select._state.cursor[1] >= 1 and select._state.cursor[1] <= total,
    "move bot"
  )
  select:move_top()
  helpers.assert_ok(
    select._state.cursor[1] >= 1 and select._state.cursor[1] <= total,
    "move top"
  )

  select:toggle_entry()
  helpers.assert_ok(select._state.toggled.entries["1"] ~= nil, "toggle entry")
  select:toggle_down()
  helpers.eq(select._state.cursor[1], 2, "toggle down")
  select:toggle_up()
  helpers.assert_ok(select._state.toggled.entries["2"] ~= nil, "toggle up")
  helpers.eq(select._state.cursor[1], 1, "toggle up")

  select:toggle_all()
  helpers.assert_ok(select._state.toggled.all, "toggle all")
  select:toggle_clear()
  helpers.eq(helpers.count_table_entries(select._state.toggled.entries), 0, "toggle clear")
  helpers.assert_ok(select._state.toggled.all == false, "toggle clear")

  helpers.assert_ok(select.prompt_buffer ~= nil, "prompt buffer")
  select:toggle_list()
  helpers.assert_ok(select._state.toggled.all, "toggle list")
  select:toggle_list()
  helpers.assert_ok(select._state.toggled.all == false, "toggle list")

  select:close()
end


local function run_select_action_case()
  local select = new_select({
    prompt_list = true,
    prompt_input = false,
    preview = false,
  })

  local selected = nil
  select:open()
  select:list({ "one", "two", "three" })
  helpers.wait_for(function()
    return select._state.entries and #select._state.entries == 3
  end, 2000)

  select:select_entry(function(list)
    selected = list
    return false
  end)
  helpers.assert_ok(selected and #selected == 1, "select entry")
  helpers.assert_ok(select:isopen() == false, "closed")

  select = new_select({
    prompt_list = true,
    prompt_input = false,
    preview = false,
  })
  selected = nil
  select:open()
  select:list({ "one", "two", "three" })
  helpers.wait_for(function()
    return select._state.entries and #select._state.entries == 3
  end, 2000)

  select:select_next(function(list)
    selected = list
    return false
  end)
  helpers.assert_ok(selected and #selected == 1, "select next")
  helpers.assert_ok(select:isopen() == false, "closed")

  select = new_select({
    prompt_list = true,
    prompt_input = false,
    preview = false,
  })
  selected = nil
  select:open()
  select:list({ "one", "two", "three" })
  helpers.wait_for(function()
    return select._state.entries and #select._state.entries == 3
  end, 2000)

  select:select_prev(function(list)
    selected = list
    return false
  end)
  helpers.assert_ok(selected and #selected == 1, "select prev")
  helpers.assert_ok(select:isopen() == false, "closed")

  select = new_select({
    prompt_list = true,
    prompt_input = false,
    preview = false,
  })
  select:open()
  select:list({ "one", "two" })
  helpers.wait_for(function()
    return select._state.entries and #select._state.entries == 2
  end, 2000)

  select:select_horizontal(function() return false end)
  helpers.assert_ok(select:isopen() == false, "closed")

  select = new_select({
    prompt_list = true,
    prompt_input = false,
    preview = false,
  })
  select:open()
  select:list({ "one", "two" })
  helpers.wait_for(function()
    return select._state.entries and #select._state.entries == 2
  end, 2000)

  select:select_vertical(function() return false end)
  helpers.assert_ok(select:isopen() == false, "closed")

  select = new_select({
    prompt_list = true,
    prompt_input = false,
    preview = false,
  })
  select:open()
  select:list({ "one", "two" })
  helpers.wait_for(function()
    return select._state.entries and #select._state.entries == 2
  end, 2000)

  select:select_tab(function() return false end)
  helpers.assert_ok(select:isopen() == false, "closed")

  select = new_select({
    prompt_list = true,
    prompt_input = false,
    preview = false,
  })
  select:open()
  select:list({ "one", "two" })
  helpers.wait_for(function()
    return select._state.entries and #select._state.entries == 2
  end, 2000)

  select:send_quickfix(function() return false end)
  helpers.assert_ok(select:isopen() == false, "closed")

  select = new_select({
    prompt_list = true,
    prompt_input = false,
    preview = false,
  })
  select:open()
  select:list({ "one", "two" })
  helpers.wait_for(function()
    return select._state.entries and #select._state.entries == 2
  end, 2000)

  select:send_locliset(function() return false end)
  helpers.assert_ok(select:isopen() == false, "closed")
end

local function run_basic_case()
  local select = new_select({
    prompt_list = true,
    prompt_input = true,
    preview = false,
    display = "text",
  })

  select:open()
  select:list({
    { text = "one" },
    { text = "two" },
    { text = "three" },
  })

  helpers.wait_for(function()
    return select._state.entries
      and #select._state.entries == 3
  end, 2000)

  helpers.eq(#select._state.entries, 3, "entries")
  helpers.wait_for(function()
    local lines = helpers.get_buffer_lines(select.list_buffer)
    for _, line in ipairs(lines or {}) do
      if line:find("one", 1, true) then
        return true
      end
    end
    return false
  end, 2000)

  helpers.eq(select:query(), "", "query")



  select:close()
end

local function run_toggle_case()
  local select = new_select({
    prompt_list = true,
    prompt_input = true,
    preview = false,
  })

  select:open()
  select:list({ "one", "two", "three" })
  helpers.wait_for(function()
    return select._state.entries
      and #select._state.entries == 3
  end, 2000)

  select:toggle_entry()
  helpers.assert_ok(
    select._state.toggled.entries["1"] ~= nil,
    "toggle"
  )

  select:toggle_all()
  helpers.assert_ok(select._state.toggled.all, "toggle all")

  select:toggle_clear()
  helpers.assert_ok(select._state.toggled.all == false, "toggle clear")
  helpers.eq(
    helpers.count_table_entries(select._state.toggled.entries),
    0,
    "toggle clear"
  )

  select:close()
end

local function run_prompt_case()
  local select = new_select({
    prompt_list = false,
    prompt_input = true,
    preview = false,
  })

  select:open()
  local prompt_ready = helpers.wait_for(function()
    return helpers.is_window_valid(select.prompt_window)
  end, 2000)
  helpers.assert_ok(prompt_ready, "prompt window")
  vim.api.nvim_buf_set_lines(select.prompt_buffer, 0, 1, false, { "hello" })
  local query = select:_prompt_getquery()
  select:_prompt_input(query, select._options.prompt_input)
  select._state.query = query
  helpers.wait_for(function()
    return select:query() == "hello"
  end, 2000)
  helpers.eq(select:query(), "hello", "prompt query")
  vim.api.nvim_buf_set_lines(select.prompt_buffer, 0, 1, false, { "" })
  query = select:_prompt_getquery()
  select:_prompt_input(query, select._options.prompt_input)
  select._state.query = query
  helpers.eq(select:query(), "", "prompt delete")
  select:close()
end

local function run_preview_case()
  local preview = Select.CustomPreview.new(function(entry)
    return {
      "preview: " .. tostring(entry),
      "line two",
    }, "lua", ""
  end)

  local select = new_select({
    prompt_list = true,
    prompt_input = false,
    preview = preview,
  })

  select:open()
  select:list({ "alpha", "beta" })
  helpers.wait_for(function()
    return select.preview_window
      and helpers.is_window_valid(select.preview_window)
  end, 2000)

  helpers.wait_for(function()
    local preview_buffer = select.preview_window
      and vim.api.nvim_win_get_buf(select.preview_window)
    local preview_lines = helpers.get_buffer_lines(preview_buffer)
    for _, line in ipairs(preview_lines or {}) do
      if line:find("preview: alpha", 1, true) then
        return true
      end
    end
    return false
  end, 2000)
  local preview_buffer = select.preview_window
    and vim.api.nvim_win_get_buf(select.preview_window)
  local preview_lines = helpers.get_buffer_lines(preview_buffer)
  helpers.assert_line_contains(preview_lines, "preview: alpha", "preview")

  local preview_window = select.preview_window
  select:toggle_preview()
  helpers.assert_ok(helpers.is_window_valid(preview_window) == false, "preview")
  select:toggle_preview()
  helpers.assert_ok(
    helpers.is_window_valid(select.preview_window),
    "preview"
  )

  if helpers.is_window_valid(select.preview_window) then
    select:line_down()
    select:line_up()
    select:page_down()
    select:page_up()
    select:half_down()
    select:half_up()
  end

  vim.wait(50, function() return true end, 10)
  select:close()
  preview:clean()
end

local function run_converter_case()
  local first_conv = Select.first(function(entry)
    return entry.value
  end)
  local last_conv = Select.last(function(entry)
    return entry.value
  end)
  local all_conv = Select.all(function(entry)
    return entry.value
  end)

  local entries = {
    { value = "one" },
    { value = "two" },
  }

  helpers.eq(first_conv(entries), "one", "first")
  helpers.eq(last_conv(entries), "two", "last")
  helpers.eq(all_conv(entries)[1], "one", "all")
end

function M.run()
  run_action_case()
  run_select_action_case()
  run_basic_case()
  run_toggle_case()
  run_prompt_case()
  run_preview_case()
  run_converter_case()
end

return M
