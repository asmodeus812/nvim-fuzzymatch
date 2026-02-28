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
end

return M
