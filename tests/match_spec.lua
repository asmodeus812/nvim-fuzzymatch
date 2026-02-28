---@diagnostic disable: invisible
local Match = require("fuzzy.match")
local helpers = require("tests.helpers")

local M = { name = "match" }

local function new_match(opts)
  return Match.new(opts or {})
end

local function run_basic_case()
  local match = new_match({ step = 1, timer = 2 })
  local list = { "alpha", "beta", "gamma", "delta" }
  match:match(list, "a", function() end)

  local results = match:wait(2000)
  helpers.assert_ok(results ~= nil, "match nil")
  local entries = results and results[1] or {}
  helpers.assert_ok(type(entries) == "table", "results")
  if #entries > 0 then
    helpers.assert_list_contains(entries, "alpha", "missing")
  end
end

local function run_transform_key()
  local match = new_match({ step = 1, timer = 2 })
  local list = {
    { text = "alpha" },
    { text = "beta" },
  }

  match:match(list, "alp", function() end, {
    key = "text",
  })
  local results = match:wait(2000)
  helpers.assert_ok(results ~= nil, "transform nil")

  helpers.assert_ok(results ~= nil, "entry")
end

local function run_text_cb()
  local match = new_match({ step = 1, timer = 2 })
  local list = {
    { text = "foo" },
    { text = "bar" },
    { text = "baz" },
  }

  local expected = vim.fn.matchfuzzypos(list, "foo", {
    text_cb = function(entry)
      return entry.text
    end,
  })

  match:match(list, "foo", function() end, {
    text_cb = function(entry)
      return entry.text
    end,
  })
  local results = match:wait(2000)
  helpers.assert_ok(results ~= nil, "text_cb nil")
  local got = results[1] or {}
  local exp = expected and expected[1] or {}
  helpers.eq(got, exp, "text_cb results")
end

local function run_stop_case()
  local match = new_match({ step = 1, timer = 50 })
  local list = {}
  for i = 1, 200 do
    list[i] = "item-" .. i
  end

  match:match(list, "item", function() end)
  helpers.wait_for(function()
    return match:running()
  end, 500)
  match:stop()
  helpers.assert_ok(match:running() == false, "stopped")
end

local function run_destroy_case()
  local match = new_match({ step = 2, timer = 2 })
  local list = { "alpha", "beta" }

  match:match(list, "a", function() end)
  match:wait(2000)
  match:destroy()
  helpers.assert_ok(match.results == nil, "destroy")
end

local function run_merge_case()
  local source = {
    { "", "", "" },
    { {}, {}, {} },
    { 0, 0, 0 },
  }
  local left = {
    { "a", "b" },
    { { 1 }, { 1 } },
    { 9, 7 },
  }
  local right = {
    { "c" },
    { { 1 } },
    { 8 },
  }

  local merged = Match.merge(source, left, right)
  helpers.eq(merged[3][1], 9, "merge")
  helpers.eq(merged[3][2], 8, "merge")
  helpers.eq(merged[3][3], 7, "merge")
end

function M.run()
  run_basic_case()
  run_transform_key()
  run_text_cb()
  run_stop_case()
  run_destroy_case()
  run_merge_case()
end

return M
