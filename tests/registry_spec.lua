---@diagnostic disable: invisible
local helpers = require("script.test_utils")

local M = { name = "registry" }

local function reset_registry()
    local loaded = package.loaded["fuzzy.registry"]
    if loaded then
        pcall(function()
            if loaded.close then
                loaded.close()
            elseif loaded.prune_timer and not vim.uv.is_closing(loaded.prune_timer) then
                loaded.prune_timer:stop()
                loaded.prune_timer:close()
            end
        end)
    end
    package.loaded["fuzzy.registry"] = nil
    package.loaded["fuzzy"] = nil
end

function M.run()
    helpers.run_test_case("registry_trace", function()
        reset_registry()
        local Registry = require("fuzzy.registry")
        local events = {}

        helpers.with_mock_map(vim.uv, {
            new_timer = function()
                return {
                    start = function() end,
                    stop = function() end,
                    close = function() end,
                }
            end,
            hrtime = vim.uv.hrtime,
        }, function()
            Registry.new({
                max_idle = 0,
                trace = function(event)
                    events[#events + 1] = event
                end,
            })
        end)

        local picker = {}
        Registry.register(picker)
        Registry.touch(picker)
        Registry.remove(picker)

        helpers.assert_ok(vim.tbl_contains(events, "registry_new"), "trace new")
        helpers.assert_ok(vim.tbl_contains(events, "registry_register"), "trace register")
        helpers.assert_ok(vim.tbl_contains(events, "registry_touch"), "trace touch")
        helpers.assert_ok(vim.tbl_contains(events, "registry_remove"), "trace remove")
    end)

    helpers.run_test_case("registry_register_and_touch", function()
        reset_registry()
        local Registry = require("fuzzy.registry")
        local now = 0
        helpers.with_mock_map(vim.uv, {
            new_timer = function()
                return {
                    start = function() end,
                    stop = function() end,
                    close = function() end,
                }
            end,
            hrtime = vim.uv.hrtime,
        }, function()
            Registry.new({
                max_idle = 10,
                now = function()
                    now = now + 1
                    return now
                end,
            })
        end)

        local picker = {}
        Registry.register(picker)
        local first = Registry.items[picker].last_used
        Registry.touch(picker)
        local second = Registry.items[picker].last_used
        helpers.assert_ok(second > first, "touch updates last_used")
    end)

    helpers.run_test_case("registry_remove_clears_entry", function()
        reset_registry()
        local Registry = require("fuzzy.registry")
        helpers.with_mock_map(vim.uv, {
            new_timer = function()
                return {
                    start = function() end,
                    stop = function() end,
                    close = function() end,
                }
            end,
            hrtime = vim.uv.hrtime,
        }, function()
            Registry.new({ max_idle = 10 })
        end)

        local picker = {}
        Registry.register(picker)
        helpers.assert_ok(Registry.items[picker] ~= nil, "registered")
        Registry.remove(picker)
        helpers.eq(Registry.items[picker], nil, "removed")
    end)

    helpers.run_test_case("registry_prune_respects_in_use", function()
        reset_registry()
        local Registry = require("fuzzy.registry")
        local scheduled = {}

        helpers.with_mock_map(vim, {
            schedule = function(fn)
                scheduled[#scheduled + 1] = fn
            end,
        }, function()
            helpers.with_mock_map(vim.uv, {
                new_timer = function()
                    return {
                        start = function() end,
                        stop = function() end,
                        close = function() end,
                    }
                end,
                hrtime = vim.uv.hrtime,
            }, function()
                Registry.new({ max_idle = 1 })
                helpers.eq(Registry.max_idle, 1, "max_idle set")
                local open_picker = {
                    isopen = function() return true end,
                    close = function() error("should not close") end,
                }
                Registry.register(open_picker)
                Registry.items[open_picker].last_used = 0
                Registry.prune(10)
            end)
        end)

        helpers.eq(#scheduled, 1, "scheduled prune")
        scheduled[1]()
        -- picker_in_use should prevent pruning
        local still = Registry.items and next(Registry.items) ~= nil
        helpers.assert_ok(still, "in-use not pruned")
    end)

    helpers.run_test_case("registry_prune_closes_idle", function()
        reset_registry()
        local Registry = require("fuzzy.registry")
        local scheduled = {}
        local closed = 0

        helpers.with_mock_map(vim, {
            schedule = function(fn)
                scheduled[#scheduled + 1] = fn
            end,
        }, function()
            helpers.with_mock_map(vim.uv, {
                new_timer = function()
                    return {
                        start = function() end,
                        stop = function() end,
                        close = function() end,
                    }
                end,
                hrtime = vim.uv.hrtime,
            }, function()
                Registry.new({ max_idle = 1 })
                helpers.eq(Registry.max_idle, 1, "max_idle set")
                local picker = {
                    close = function() closed = closed + 1 end,
                }
                Registry.register(picker)
                Registry.items[picker].last_used = 0
                Registry.prune(10)
            end)
        end)

        helpers.eq(#scheduled, 1, "scheduled prune")
        scheduled[1]()
        helpers.eq(closed, 1, "closed idle picker")
        local empty = Registry.items == nil or next(Registry.items) == nil
        helpers.assert_ok(empty, "pruned entry removed")
    end)
end

return M
