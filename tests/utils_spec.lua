---@diagnostic disable: invisible
local helpers = require("script.test_utils")
local utils = require("fuzzy.utils")

local M = { name = "utils" }

function M.run()
    helpers.run_test_case("utils_fill_resize_table", function()
        local tbl = { 1, 2, 3 }
        utils.fill_table(tbl, 9)
        helpers.eq(tbl[1], 9, "fill_table")
        helpers.eq(tbl[3], 9, "fill_table")

        utils.resize_table(tbl, 5, 7)
        helpers.eq(#tbl, 5, "resize expand")
        helpers.eq(tbl[5], 7, "resize expand default")

        utils.resize_table(tbl, 2)
        helpers.eq(#tbl, 2, "resize shrink")

        utils.resize_table(tbl, 0)
        helpers.eq(#tbl, 0, "resize zero")
    end)

    helpers.run_test_case("utils_compare_tables", function()
        local a = { x = 1, y = { 2 } }
        local b = { x = 1, y = { 2 } }
        local c = { x = 1, y = { 3 } }
        helpers.assert_ok(utils.compare_tables(a, b), "compare equal")
        helpers.assert_ok(not utils.compare_tables(a, c), "compare not equal")

        local ta = {}
        local tb = {}
        ta.self = ta
        tb.self = tb
        helpers.assert_ok(utils.compare_tables(ta, tb), "compare cyclic")
    end)

    helpers.run_test_case("utils_table_remove", function()
        local tbl = { "a", "b", "a" }
        helpers.assert_ok(utils.table_remove(tbl, "a"), "table_remove")
        helpers.eq(#tbl, 1, "table_remove count")
        helpers.eq(tbl[1], "b", "table_remove value")

        helpers.assert_ok(not utils.table_remove(tbl, "x"), "table_remove missing")
    end)

    helpers.run_test_case("utils_pack_unpack", function()
        local packed = utils.table_pack(1, nil, "a")
        helpers.eq(packed.n, 3, "pack count")
        local a, b, c = utils.table_unpack(packed)
        helpers.eq(a, 1, "unpack a")
        helpers.eq(b, nil, "unpack b")
        helpers.eq(c, "a", "unpack c")
    end)

    helpers.run_test_case("utils_safe_call", function()
        local original_notify = vim.notify
        vim.notify = function() end
        local ok, res = utils.safe_call(function(x) return x + 1 end, 2)
        helpers.assert_ok(ok, "safe_call ok")
        helpers.eq(res, 3, "safe_call res")

        local ok2, res2 = utils.safe_call(function() error("boom") end)
        helpers.assert_ok(ok2 == false, "safe_call error")
        helpers.assert_ok(type(res2) == "string", "safe_call error msg")
        vim.notify = original_notify
    end)

    helpers.run_test_case("utils_generate_uuid", function()
        local id = utils.generate_uuid()
        helpers.assert_ok(type(id) == "string" and #id > 0, "uuid string")
        helpers.assert_ok(id:find("^[0-9a-f%-]+$") ~= nil, "uuid format")
        helpers.eq(#id, 36, "uuid length")
    end)

    helpers.run_test_case("utils_debounce_callback", function()
        local count = 0
        local last = nil
        local cb = utils.debounce_callback(20, function(value)
            count = count + 1
            last = value
        end)
        cb("a")
        cb("b")
        vim.wait(60, function() return count == 1 end, 10)
        helpers.eq(count, 1, "debounce count")
        helpers.eq(last, "b", "debounce last")
    end)

    helpers.run_test_case("utils_time_execution", function()
        local result, duration = utils.timed_call(function() return 7 end)
        helpers.eq(result, 7, "time_execution result")
        helpers.assert_ok(type(duration) == "number" and duration >= 0, "time_execution duration")
    end)

    helpers.run_test_case("utils_qf_helpers", function()
        helpers.assert_ok(utils.win_is_qf(0) == false, "win_is_qf invalid")
        local buf = vim.api.nvim_create_buf(false, true)
        helpers.assert_ok(utils.is_quickfix(buf) == false, "is_quickfix invalid")
        local info = utils.get_bufinfo(buf)
        helpers.assert_ok(type(info) == "table" and info.bufnr == buf, "get_bufinfo")
    end)

    helpers.run_test_case("utils_get_bufname", function()
        local buf = vim.api.nvim_create_buf(false, true)
        helpers.assert_ok(vim.api.nvim_buf_is_valid(buf), "buf valid")
        local name = utils.get_bufname(buf)
        helpers.assert_ok(type(name) == "string" and #name > 0, "buf name")
    end)
end

return M
