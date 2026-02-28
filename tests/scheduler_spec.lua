---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "scheduler" }

function M.run()
    helpers.run_test_case("scheduler_setup", function()
        local captured = {}
        local called = {}
        local scheduler_module = require("fuzzy.scheduler")
        local pool_module = require("fuzzy.pool")
        local registry_module = require("fuzzy.registry")

        helpers.with_mock_map(scheduler_module, {
            new = function(opts)
                captured.scheduler = opts
                called.scheduler = (called.scheduler or 0) + 1
            end,
        }, function()
            helpers.with_mock_map(pool_module, {
                new = function() end,
                prime = function() end,
            }, function()
                helpers.with_mock_map(registry_module, {
                    new = function() end,
                }, function()
                    require("fuzzy").setup({
                        override_select = false,
                        scheduler = { async_budget = 123 },
                        pool = { prime_sizes = {} },
                        registry = {},
                    })
                end)
            end)
        end)

        helpers.eq(captured.scheduler.async_budget, 123, "scheduler")
        helpers.eq(called.scheduler, 1, "scheduler called")
    end)
end

return M
