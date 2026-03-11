---@diagnostic disable: invisible
local Match = require("fuzzy.match")
local helpers = require("script.test_utils")

local M = { name = "match" }

local function new_match(opts)
    return Match.new(opts or {})
end

local function run_basic_case()
    local match = new_match({ step = 1, timer = 2 })
    helpers.assert_ok(match:options() ~= nil, "match options")
    helpers.eq(match:options().step, 1, "match options reference")
    local list = {}
    for i = 1, 500 do
        list[i] = string.format("item-%03d", i)
    end
    list[1] = "alpha"
    match:match(list, "a", function() end)

    local results = match:wait(1500)
    helpers.assert_ok(results ~= nil, "match nil")
    local entries = results and results[1] or {}
    helpers.assert_ok(type(entries) == "table", "results")
    helpers.assert_ok(#entries > 0, "results empty")
    helpers.assert_list_contains(entries, "alpha", "missing")
end

local function run_transform_key()
    local match = new_match({ step = 1, timer = 2 })
    local list = {
        { text = "alpha" },
        { text = "beta" },
    }
    for i = 3, 300 do
        list[i] = { text = string.format("item-%03d", i) }
    end

    match:match(list, "alp", function() end, "text")
    local results = match:wait(1500)
    helpers.assert_ok(results ~= nil, "transform nil")
    local entries = results and results[1] or {}
    helpers.assert_ok(#entries == 1, "transform count")
    helpers.eq(entries[1].text, "alpha", "transform entry")
end

local function run_text_cb()
    local match = new_match({ step = 1, timer = 2 })
    local list = {}
    for i = 1, 400 do
        list[i] = { text = string.format("item-%03d", i) }
    end
    list[10] = { text = "foo" }
    list[20] = { text = "bar" }
    list[30] = { text = "baz" }

    local expected = vim.fn.matchfuzzypos(list, "foo", {
        text_cb = function(entry)
            return entry.text
        end,
    })

    match:match(list, "foo", function() end, function(entry)
        return entry.text
    end)
    local results = match:wait(1500)
    helpers.assert_ok(results ~= nil, "text_cb nil")
    assert(results)
    local got = results[1] or {}
    local exp = expected and expected[1] or {}
    helpers.eq(got, exp, "text_cb results")
end

local function run_stop_case()
    local match = new_match({ step = 1, timer = 50 })
    local list = {}
    for i = 1, 2000 do
        list[i] = "item-" .. i
    end

    match:match(list, "item", function() end)
    helpers.assert_ok(helpers.wait_for(function()
        return match:running()
    end, 500), "running")
    match:stop()
    helpers.assert_ok(match:running() == false, "stopped")
end

local function run_destroy_case()
    local match = new_match({ step = 2, timer = 2 })
    local list = {}
    for i = 1, 1000 do
        list[i] = string.format("item-%03d", i)
    end

    match:match(list, "a", function() end)
    match:wait(1500)
    match:destroy()
    helpers.assert_ok(match.results == nil, "destroy")
end

local function run_merge_case()
    local source = {
        { "", "", "" },
        { {}, {}, {} },
        { 0,  0,  0 },
    }
    local left = {
        { "a",   "b" },
        { { 1 }, { 1 } },
        { 9,     7 },
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

local function run_no_results_case()
    local match = new_match({ step = 2, timer = 2 })
    local list = {}
    for i = 1, 1000 do
        list[i] = string.format("item-%03d", i)
    end
    local calls = 0
    local saw_nil = false

    match:match(list, "zzz", function(results)
        if results == nil then
            saw_nil = true
        else
            calls = calls + 1
        end
    end)

    local results = match:wait(1500)
    helpers.assert_ok(results ~= nil, "no results nil")
    helpers.eq(#(results or {}), 0, "no results empty")
    helpers.eq(calls, 0, "no results callback")
    helpers.assert_ok(saw_nil, "no results nil callback")
end

local function run_callback_nil_case()
    local match = new_match({ step = 50, timer = 1 })
    local list = {}
    for i = 1, 800 do
        list[i] = string.format("item-%03d", i)
    end
    list[1] = "alpha"
    local saw_nil = false
    local saw_non_nil = false

    match:match(list, "item", function(results)
        if results == nil then
            saw_nil = true
        else
            saw_non_nil = true
        end
    end)

    match:wait(4000)
    helpers.wait_for(function()
        return saw_nil
    end, 4000)
    helpers.assert_ok(saw_non_nil, "callback non-nil")
    helpers.assert_ok(saw_nil, "callback nil")
end

local function run_multi_chunk_case()
    local match = new_match({ step = 1, timer = 2 })
    local list = {}
    for i = 1, 200 do
        list[i] = string.format("item-%03d", i)
    end
    local calls = 0
    local saw_sizes = {}

    match:match(list, "item", function(results)
        if results ~= nil then
            calls = calls + 1
            saw_sizes[#saw_sizes + 1] = #results[1]
        end
    end)
    local results = match:wait(1500)
    helpers.assert_ok(results ~= nil, "multi chunk nil")
    helpers.assert_ok(calls >= 2, "multi chunk calls")
    helpers.eq(#results[1], 200, "multi chunk results")
    helpers.assert_ok(saw_sizes[1] ~= nil, "multi chunk size track")
    helpers.assert_ok(saw_sizes[#saw_sizes] == 200, "multi chunk final size")
end

local function run_transform_function_case()
    local match = new_match({ step = 2, timer = 2 })
    local list = {}
    for i = 1, 600 do
        list[i] = { name = string.format("item-%03d", i), id = i }
    end
    list[1] = { name = "alpha", id = 1 }
    match:match(list, "alp", function() end, function(entry)
        return entry.name
    end)
    local results = match:wait(1500)
    helpers.assert_ok(results ~= nil, "transform fn nil")
    helpers.eq(results[1][1].id, 1, "transform fn entry")
end

local function run_wait_timeout_case()
    local match = new_match({ step = 1, timer = 1000, timeout = 1 })
    local list = {}
    for i = 1, 5000 do
        list[i] = "item-" .. i
    end
    local saw_results = false
    match:match(list, "item", function() end)
    local results = match:wait(1)
    helpers.assert_ok(results ~= nil, "wait timeout results")
    helpers.assert_ok(match:running() == false, "wait timeout stopped")
    helpers.assert_ok(results and results[1] and #results[1] > 0, "wait timeout entries")
    saw_results = results ~= nil
    helpers.assert_ok(saw_results, "wait timeout saw results")
end

local function run_restart_ephemeral_true_case()
    local match = new_match({ step = 1, timer = 2, ephemeral = true })
    local first = {}
    local second = {}
    for i = 1, 500 do
        first[i] = string.format("alpha-%03d", i)
        second[i] = string.format("gamma-%03d", i)
    end

    match:match(first, "a", function() end)
    match:match(second, "g", function() end)
    local results = match:wait(1500)
    helpers.assert_ok(results ~= nil, "restart ephemeral nil")
    local found_gamma = false
    local found_alpha = false
    for _, entry in ipairs(results[1] or {}) do
        if entry:find("gamma-", 1, true) then
            found_gamma = true
        end
        if entry:find("alpha-", 1, true) then
            found_alpha = true
        end
    end
    helpers.assert_ok(found_gamma, "restart ephemeral results")
    helpers.assert_ok(not found_alpha, "restart ephemeral old")
end

local function run_restart_ephemeral_false_case()
    local match = new_match({ step = 1, timer = 2, ephemeral = false })
    local first = {}
    local second = {}
    for i = 1, 500 do
        first[i] = string.format("alpha-%03d", i)
        second[i] = string.format("gamma-%03d", i)
    end

    match:match(first, "a", function() end)
    match:wait(1500)
    match:match(second, "g", function() end)
    local results = match:wait(1500)
    helpers.assert_ok(results ~= nil, "restart non-ephemeral nil")
    local found_gamma = false
    local found_alpha = false
    for _, entry in ipairs(results[1] or {}) do
        if entry:find("gamma-", 1, true) then
            found_gamma = true
        end
        if entry:find("alpha-", 1, true) then
            found_alpha = true
        end
    end
    helpers.assert_ok(found_gamma, "restart non-ephemeral results")
    helpers.assert_ok(not found_alpha, "restart non-ephemeral old")
end

local function run_tail_chunk_case()
    local match = new_match({ step = 2, timer = 2 })
    local list = {}
    for i = 1, 503 do
        list[i] = string.format("item-%03d", i)
    end
    match:match(list, "item", function() end)
    local results = match:wait(1500)
    helpers.assert_ok(results ~= nil, "tail chunk nil")
    helpers.eq(#results[1], 503, "tail chunk results")
end

local function run_positions_shape_case()
    local match = new_match({ step = 2, timer = 2 })
    local list = {}
    for i = 1, 700 do
        list[i] = string.format("item-%03d", i)
    end
    list[1] = "alpha"
    list[2] = "beta"
    list[3] = "gamma"
    match:match(list, "a", function() end)
    local results = match:wait(1500)
    helpers.assert_ok(results ~= nil, "positions nil")
    local positions = results[2] or {}
    for _, pos in ipairs(positions) do
        helpers.assert_ok(#pos % 2 == 0, "positions even pairs")
    end
end

local function run_merge_equal_score_case()
    local source = {
        { "", "" },
        { {}, {} },
        { 0, 0 },
    }
    local left = {
        { "a" },
        { { 1 } },
        { 5 },
    }
    local right = {
        { "b" },
        { { 2 } },
        { 5 },
    }
    local merged = Match.merge(source, left, right)
    helpers.eq(merged[1][1], "b", "merge equal score prefers right")
    helpers.eq(merged[1][2], "a", "merge equal score order")
end

function M.run()
    helpers.run_test_case("match_basic", run_basic_case)
    helpers.run_test_case("match_transform_key", run_transform_key)
    helpers.run_test_case("match_text_cb", run_text_cb)
    helpers.run_test_case("match_stop", run_stop_case)
    helpers.run_test_case("match_destroy", run_destroy_case)
    helpers.run_test_case("match_merge", run_merge_case)
    helpers.run_test_case("match_no_results", run_no_results_case)
    helpers.run_test_case("match_callback_nil", run_callback_nil_case)
    helpers.run_test_case("match_multi_chunk", run_multi_chunk_case)
    helpers.run_test_case("match_transform_function", run_transform_function_case)
    helpers.run_test_case("match_wait_timeout", run_wait_timeout_case)
    helpers.run_test_case("match_restart_ephemeral_true", run_restart_ephemeral_true_case)
    helpers.run_test_case("match_restart_ephemeral_false", run_restart_ephemeral_false_case)
    helpers.run_test_case("match_tail_chunk", run_tail_chunk_case)
    helpers.run_test_case("match_positions_shape", run_positions_shape_case)
    helpers.run_test_case("match_merge_equal_score", run_merge_equal_score_case)
end

return M
