---@diagnostic disable: invisible
local helpers = require("script.test_utils")

local M = { name = "scheduler" }

local function reset_scheduler()
    local loaded = package.loaded["fuzzy.scheduler"]
    if loaded then
        pcall(function()
            if loaded.close then
                loaded.close()
            elseif loaded._executor and loaded._executor.stop then
                loaded._executor:stop()
                if loaded._executor.close then
                    loaded._executor:close()
                end
            end
        end)
    end
    package.loaded["fuzzy.scheduler"] = nil
    package.loaded["fuzzy"] = nil
end

function M.run()
    helpers.run_test_case("scheduler_setup", function()
        reset_scheduler()
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
                        registry = {},
                        pool = {},
                    })
                end)
            end)
        end)

        helpers.eq(captured.scheduler.async_budget, 123, "scheduler")
        helpers.eq(called.scheduler, 1, "scheduler called")
    end)

    helpers.run_test_case("scheduler_trace", function()
        reset_scheduler()
        local Scheduler = require("fuzzy.scheduler")
        local events = {}
        local active = false

        helpers.with_mock_map(vim.uv, {
            new_check = function()
                return {
                    start = function() active = true end,
                    stop = function() active = false end,
                    is_active = function() return active end,
                }
            end,
            hrtime = vim.uv.hrtime,
        }, function()
            Scheduler.new({
                async_budget = 1,
                trace = function(event)
                    events[#events + 1] = event
                end,
            })

            local async = {
                _step = function() end,
                is_running = function() return false end,
            }
            Scheduler.add(async)
            Scheduler.step()
        end)

        helpers.assert_ok(vim.tbl_contains(events, "scheduler_new"), "trace new")
        helpers.assert_ok(vim.tbl_contains(events, "scheduler_start"), "trace start")
        helpers.assert_ok(vim.tbl_contains(events, "scheduler_idle"), "trace idle")
    end)
end

return M
