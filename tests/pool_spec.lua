---@diagnostic disable: invisible
local helpers = require("script.test_utils")

local M = { name = "pool" }

local function resize_table(tbl, size, value)
    if size > #tbl then
        for i = #tbl + 1, size do
            tbl[i] = value
        end
    else
        for i = #tbl, size + 1, -1 do
            tbl[i] = nil
        end
    end
    return tbl
end

local function fill_table(tbl, value)
    for i = 1, #tbl do
        tbl[i] = value
    end
    return tbl
end

local function remove_value(tbl, value)
    local removed = false
    for i = #tbl, 1, -1 do
        if tbl[i] == value then
            table.remove(tbl, i)
            removed = true
        end
    end
    return removed
end

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

local function new_pool(opts)
    local Pool = require("fuzzy.pool")
    opts = vim.tbl_extend("force", {
        prime = false,
    }, opts or {})
    Pool.new(opts)
    return Pool
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
    end)

    helpers.run_test_case("pool_obtain_allocates_normalized_size", function()
        reset_pool()
        local Pool = new_pool({
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
        local Pool = new_pool({ now = function() return 1 end })

        local t1 = Pool.attach({})
        resize_table(t1, 8, false)
        Pool._return(t1)

        local t2 = Pool.attach({})
        resize_table(t2, 16, false)
        Pool._return(t2)

        local t3 = Pool.attach({})
        resize_table(t3, 32, false)
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
        local Pool = new_pool({
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
        local Pool = new_pool({
            prime_min = 64,
            prime_max = 1024,
            now = function() return 1 end,
        })

        local tbl = Pool.attach({})
        resize_table(tbl, 600, false)
        Pool._return(tbl)

        helpers.eq(#Pool.tables, 1, "normalized insert")
        helpers.eq(#Pool.tables[1], 1024, "normalized to bucket")
    end)

    helpers.run_test_case("pool_obtain_prefers_smallest_fit", function()
        reset_pool()
        local Pool = new_pool({
            prime_min = 64,
            prime_max = 2048,
            now = function() return 1 end,
        })

        local small = Pool.attach({})
        resize_table(small, 1024, false)
        Pool._return(small)
        local large = Pool.attach({})
        resize_table(large, 2048, false)
        Pool._return(large)

        local pick = Pool.obtain(900)
        helpers.eq(pick, small, "smallest fit reused")
        Pool._return(pick)
    end)

    helpers.run_test_case("pool_trim_respects_max_tables", function()
        reset_pool()
        local Pool = new_pool({
            max_tables = 1,
            prime_max = 8,
            now = function() return 10 end,
        })

        local old = Pool.attach({})
        resize_table(old, 4, false)
        Pool._return(old)
        Pool.meta[old].last_used = 0

        local tbl = Pool.attach({})
        resize_table(tbl, 12, false)
        Pool._return(tbl)

        helpers.eq(#Pool.tables, 1, "trim kept max_tables")
        helpers.eq(Pool.tables[1], tbl, "trim kept newest on return")
        helpers.eq(Pool.meta[old], nil, "trim old meta cleared")
    end)

    helpers.run_test_case("pool_prune_idle", function()
        reset_pool()
        local Pool = new_pool({
            max_idle = 10,
            now = function() return 1 end,
        })

        local t1 = Pool.obtain()
        resize_table(t1, 4, false)
        Pool._return(t1)
        local t2 = Pool.obtain()
        resize_table(t2, 6, false)
        Pool._return(t2)

        Pool.meta[t1].last_used = 0
        Pool.meta[t2].last_used = 95
        Pool.prune(100)

        helpers.eq(#Pool.tables, 1, "prune idle")
        helpers.eq(Pool.tables[1], t2, "keeps recent")
    end)

    helpers.run_test_case("pool_prune_max_tables", function()
        reset_pool()
        local Pool = new_pool({
            max_tables = 1,
            now = function() return 1 end,
        })

        local t1 = Pool.obtain()
        resize_table(t1, 4, false)
        Pool._return(t1)
        local t2 = Pool.obtain()
        resize_table(t2, 6, false)
        Pool._return(t2)

        Pool.meta[t1].last_used = 0
        Pool.meta[t2].last_used = 10
        Pool.prune(10)

        helpers.eq(#Pool.tables, 1, "prune max_tables")
        helpers.eq(Pool.tables[1], t2, "keeps newest")
    end)

    helpers.run_test_case("pool_helpers", function()
        reset_pool()
        local Pool = new_pool({ now = function() return 1 end })

        local tbl = Pool.obtain()
        resize_table(tbl, 3, false)
        fill_table(tbl, true)
        helpers.eq(tbl[1], true, "fill start")
        helpers.eq(tbl[3], true, "fill end")
        resize_table(tbl, 1, false)
        helpers.eq(#tbl, 1, "resize shrink")
        resize_table(tbl, 0, false)
        helpers.eq(#tbl, 0, "resize zero")

        local list = { 1, 2, 1 }
        helpers.assert_ok(remove_value(list, 1), "remove value")
        helpers.eq(#list, 1, "remove count")
        helpers.eq(list[1], 2, "remove left")

        local attached = { "a" }
        Pool.attach(attached)
        Pool.detach(attached)
    end)
end

return M
