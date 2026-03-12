---@diagnostic disable: invisible
local helpers = require("script.test_utils")

local M = { name = "async" }

function M.run()
    helpers.run_test_case("async_trace", function()
        local Async = require("fuzzy.async")
        local events = {}
        Async.trace = function(event)
            events[#events + 1] = event
        end

        local async = Async.new(function() end)
        async:_step()

        helpers.assert_ok(vim.tbl_contains(events, "async_new"), "trace new")
        helpers.assert_ok(vim.tbl_contains(events, "async_done"), "trace done")
    end)
end

return M
