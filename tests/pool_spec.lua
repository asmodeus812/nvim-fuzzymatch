---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "pool" }

function M.run()
    helpers.run_test_case("pool_setup", function()
        local captured = {}
        local called = {}
        local scheduler_module = require("fuzzy.scheduler")
        local pool_module = require("fuzzy.pool")
        local registry_module = require("fuzzy.registry")

        helpers.with_mock_map(scheduler_module, {
            new = function() end,
        }, function()
            helpers.with_mock_map(pool_module, {
                new = function(opts)
                    captured.pool = opts
                    called.pool = (called.pool or 0) + 1
                end,
                prime = function(sizes)
                    captured.prime_sizes = sizes
                    called.prime = (called.prime or 0) + 1
                end,
            }, function()
                helpers.with_mock_map(registry_module, {
                    new = function() end,
                }, function()
                    require("fuzzy").setup({
                        override_select = false,
                        scheduler = {},
                        pool = {
                            max_idle = 10,
                            prune_interval = 20,
                            max_tables = 3,
                            prime_sizes = { 1, 2 },
                        },
                        registry = {},
                    })
                end)
            end)
        end)

        helpers.eq(captured.pool.max_idle, 10, "pool")
        helpers.eq(captured.pool.prune_interval, 20, "pool")
        helpers.eq(captured.pool.max_tables, 3, "pool")
        helpers.eq(captured.prime_sizes[1], 1, "prime")
        helpers.eq(called.pool, 1, "pool called")
        helpers.eq(called.prime, 1, "prime called")
    end)
end

return M
