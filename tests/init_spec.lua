---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "init" }

function M.run()
    helpers.run_test_case("setup_ui_select", function()
        local scheduler_module = require("fuzzy.scheduler")
        local pool_module = require("fuzzy.pool")
        local registry_module = require("fuzzy.registry")
        local original_select = vim.ui.select
        local called = {}

        helpers.with_mock_map(scheduler_module, {
            new = function()
                called.scheduler = (called.scheduler or 0) + 1
            end,
        }, function()
            helpers.with_mock_map(pool_module, {
                new = function()
                    called.pool = (called.pool or 0) + 1
                end,
                prime = function()
                    called.prime = (called.prime or 0) + 1
                end,
            }, function()
                helpers.with_mock_map(registry_module, {
                    new = function()
                        called.registry = (called.registry or 0) + 1
                    end,
                }, function()
                    require("fuzzy").setup({
                        override_select = true,
                        scheduler = { async_budget = 1 },
                        pool = { prime_sizes = {} },
                        registry = {},
                    })
                end)
            end)
        end)

        local picked = nil
        local picker = vim.ui.select({ "one", "two" }, {
            prompt = "Pick",
            format_item = function(i) return i end,
        }, function(item)
            picked = item
        end)

        helpers.wait_for_list(picker)
        helpers.wait_for_entries(picker)
        local action = picker.select._options.mappings["<cr>"]
        action(picker.select)
        helpers.eq(picked, "one", "picked")
        helpers.close_picker(picker)
        vim.ui.select = original_select

        helpers.eq(called.scheduler, 1, "scheduler called")
        helpers.eq(called.pool, 1, "pool called")
        helpers.eq(called.registry, 1, "registry called")
        helpers.eq(called.prime, 1, "prime called")
    end)
end

return M
