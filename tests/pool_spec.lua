---@diagnostic disable: invisible
local helpers = require("script.test_utils")

local M = { name = "pool" }

local function reset_pool()
    local loaded = package.loaded["fuzzy.pool"]
    if loaded then
        pcall(function()
            if loaded.prune_timer and not vim.uv.is_closing(loaded.prune_timer) then
                loaded.prune_timer:stop()
                loaded.prune_timer:close()
            end
        end)
    end
    package.loaded["fuzzy.pool"] = nil
end

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
                            prime_min = 16,
                            prime_max = 256,
                            prime_chunk = 8,
                        },
                        registry = {},
                    })
                end)
            end)
        end)

        helpers.eq(captured.pool.max_idle, 10, "pool")
        helpers.eq(captured.pool.prune_interval, 20, "pool")
        helpers.eq(captured.pool.max_tables, 3, "pool")
        helpers.eq(called.pool, 1, "pool called")
        helpers.eq(captured.pool.prime_min, 16, "pool prime min")
        helpers.eq(captured.pool.prime_max, 256, "pool prime max")
        helpers.eq(captured.pool.prime_chunk, 8, "pool prime chunk")
    end)

    helpers.run_test_case("pool_obtain_allocates_normalized_size", function()
        reset_pool()
        local Pool = require("fuzzy.pool")
        Pool.new({
            max_tables = 10,
            prime_min = 16384,
            prime_max = 524288,
            now = function() return 1 end,
        })

        local tbl = Pool.obtain(120000)
        helpers.eq(#tbl, 131072, "normalized alloc")
        Pool._return(tbl)
    end)

    helpers.run_test_case("pool_obtain_closest_fit", function()
        reset_pool()
        local Pool = require("fuzzy.pool")
        Pool.new({ now = function() return 1 end })

        local t1 = Pool.attach({})
        Pool.resize(t1, 8, false)
        Pool._return(t1)

        local t2 = Pool.attach({})
        Pool.resize(t2, 16, false)
        Pool._return(t2)

        local t3 = Pool.attach({})
        Pool.resize(t3, 32, false)
        Pool._return(t3)

        local pick = Pool.obtain(10)
        helpers.eq(#pick, 16, "closest fit")
        Pool._return(pick)

        local largest = Pool.obtain()
        helpers.eq(#largest, 32, "largest when no size")
        Pool._return(largest)
    end)

    helpers.run_test_case("pool_reuses_existing_bucket", function()
        reset_pool()
        local Pool = require("fuzzy.pool")
        Pool.new({
            prime_min = 64,
            prime_max = 2048,
            now = function() return 1 end,
        })

        local t1 = Pool.obtain(1000)
        helpers.eq(#t1, 1024, "bucket alloc")
        Pool._return(t1)

        local t2 = Pool.obtain(1000)
        helpers.eq(t2, t1, "reused same table")
        helpers.eq(#t2, 1024, "reused same bucket")
        Pool._return(t2)
    end)

    helpers.run_test_case("pool_return_normalizes_bucket", function()
        reset_pool()
        local Pool = require("fuzzy.pool")
        Pool.new({
            prime_min = 64,
            prime_max = 1024,
            now = function() return 1 end,
        })

        local tbl = Pool.attach({})
        Pool.resize(tbl, 600, false)
        Pool._return(tbl)

        helpers.eq(#Pool.tables, 1, "normalized insert")
        helpers.eq(#Pool.tables[1], 1024, "normalized to bucket")
    end)

    helpers.run_test_case("pool_obtain_prefers_smallest_fit", function()
        reset_pool()
        local Pool = require("fuzzy.pool")
        Pool.new({
            prime_min = 64,
            prime_max = 2048,
            now = function() return 1 end,
        })

        local small = Pool.attach({})
        Pool.resize(small, 1024, false)
        Pool._return(small)
        local large = Pool.attach({})
        Pool.resize(large, 2048, false)
        Pool._return(large)

        local pick = Pool.obtain(900)
        helpers.eq(pick, small, "smallest fit reused")
        Pool._return(pick)
    end)

    helpers.run_test_case("pool_prime_steps_are_noops", function()
        reset_pool()
        local Pool = require("fuzzy.pool")
        Pool.new({
            now = function() return 1 end,
        })
        Pool._prime_step()
    end)

    helpers.run_test_case("pool_trim_respects_max_tables", function()
        reset_pool()
        local Pool = require("fuzzy.pool")
        Pool.new({
            max_tables = 0,
            prime_max = 8,
            now = function() return 1 end,
        })

        local tbl = Pool.attach({})
        Pool.resize(tbl, 12, false)
        Pool._return(tbl)

        helpers.eq(#Pool.tables, 0, "trim discarded when max_tables reached")
        helpers.eq(Pool.meta[tbl], nil, "trim meta cleared")
    end)

    helpers.run_test_case("pool_trim_step_stops_timer_when_empty", function()
        reset_pool()
        local Pool = require("fuzzy.pool")
        Pool.new({
            now = function() return 1 end,
        })
        Pool._trim_step()
    end)

    helpers.run_test_case("pool_prune_idle", function()
        reset_pool()
        local Pool = require("fuzzy.pool")
        Pool.new({
            max_idle = 10,
            now = function() return 1 end,
        })

        local t1 = Pool.obtain()
        Pool.resize(t1, 4, false)
        Pool._return(t1)
        local t2 = Pool.obtain()
        Pool.resize(t2, 6, false)
        Pool._return(t2)

        Pool.meta[t1].last_used = 0
        Pool.meta[t2].last_used = 95
        Pool.prune(100)

        helpers.eq(#Pool.tables, 1, "prune idle")
        helpers.eq(Pool.tables[1], t2, "keeps recent")
    end)

    helpers.run_test_case("pool_prune_max_tables", function()
        reset_pool()
        local Pool = require("fuzzy.pool")
        Pool.new({
            max_tables = 1,
            now = function() return 1 end,
        })

        local t1 = Pool.obtain()
        Pool.resize(t1, 4, false)
        Pool._return(t1)
        local t2 = Pool.obtain()
        Pool.resize(t2, 6, false)
        Pool._return(t2)

        Pool.meta[t1].last_used = 0
        Pool.meta[t2].last_used = 10
        Pool.prune(10)

        helpers.eq(#Pool.tables, 1, "prune max_tables")
        helpers.eq(Pool.tables[1], t2, "keeps newest")
    end)

    helpers.run_test_case("pool_helpers", function()
        reset_pool()
        local Pool = require("fuzzy.pool")
        Pool.new({ now = function() return 1 end })

        local tbl = Pool.obtain()
        Pool.resize(tbl, 3, false)
        Pool.fill(tbl, true)
        helpers.eq(tbl[1], true, "fill start")
        helpers.eq(tbl[3], true, "fill end")
        Pool.resize(tbl, 1, false)
        helpers.eq(#tbl, 1, "resize shrink")
        Pool.resize(tbl, 0, false)
        helpers.eq(#tbl, 0, "resize zero")

        local list = { 1, 2, 1 }
        helpers.assert_ok(Pool.remove(list, 1), "remove value")
        helpers.eq(#list, 1, "remove count")
        helpers.eq(list[1], 2, "remove left")

        local attached = { "a" }
        Pool.attach(attached)
        Pool.detach(attached)
    end)
end

return M
