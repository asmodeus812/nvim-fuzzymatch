local Select = require("fuzzy.select")
local Picker = require("fuzzy.picker")

local M = {}

function M.stream()
    local picker = Picker.new({
        content = function(cb, args)
            for i = 1, 1000000, 1 do
                cb({ name = string.format("%d-%s-name-entry", i, args[1]) })
            end
            cb(nil)
        end,
        context = {
            args = {
                "{prompt}",
            },
            interactive = "{prompt}",
        },
        display = "name",
        prompt_confirm = Select.default_select,
        actions = {
            -- no default actions for picker
        },
        headers = {
            -- no custom headers for picker
        },
        providers = {
            icon_provider = false,
            status_provider = false
        }
    })
    return picker:open()
end

return M
