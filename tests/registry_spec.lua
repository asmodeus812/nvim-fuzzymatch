---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "registry" }

function M.run()
    helpers.run_test_case("registry", function()
        local registry = require("fuzzy.pickers.registry")
        registry.clear_picker_registry()

        local opened = false
        local picker = {
            open = function()
                opened = true
            end,
        }

        registry.register_picker_instance("alpha", picker)
        helpers.eq(registry.get_picker_instance("alpha"), picker, "get")

        local opened_picker = registry.open_picker_instance("alpha")
        helpers.eq(opened_picker, picker, "open")
        helpers.assert_ok(opened, "opened")

        local removed = registry.remove_picker_instance("alpha")
        helpers.eq(removed, picker, "remove")
        helpers.eq(registry.get_picker_instance("alpha"), nil, "missing")

        registry.register_picker_instance("beta", picker)
        registry.clear_picker_registry()
        helpers.eq(registry.get_picker_instance("beta"), nil, "cleared")
    end)

    helpers.run_test_case("registry_prune", function()
        local Registry = require("fuzzy.registry")
        local original_timer = vim.uv.new_timer
        Registry.items = nil
        if Registry.prune_timer and Registry.prune_timer.stop then
            pcall(Registry.prune_timer.stop, Registry.prune_timer)
        end
        Registry.prune_timer = nil
        helpers.with_mock(vim.uv, "new_timer", function()
            return {
                start = function() end,
            }
        end, function()
            Registry.new({
                max_idle = 100,
                prune_interval = 10,
                now = function()
                    return 0
                end,
            })
        end)
        vim.uv.new_timer = original_timer

        local idle_picker = {}
        idle_picker.isopen = function() return false end
        idle_picker.isvalid = function() return false end
        idle_picker.close = function() idle_picker.closed = true end

        local used_picker = {}
        used_picker.isopen = function() return false end
        used_picker.isvalid = function() return false end
        used_picker.close = function() used_picker.closed = true end
        used_picker.match = { running = function() return true end }

        Registry.register(idle_picker)
        Registry.register(used_picker)

        Registry.prune(200)

        helpers.assert_ok(idle_picker.closed == true, "idle closed")
        helpers.assert_ok(used_picker.closed ~= true, "used kept")
    end)
end

return M
