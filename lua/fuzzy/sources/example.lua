local Select = require("fuzzy.select")
local Picker = require("fuzzy.picker")

local M = {}

function M.stream(opts)
    opts = opts or {
        count = 1000000,
        cwd = vim.loop.cwd,
    }
    local picker = Picker.new({
        content = function(cb, args)
            for i = 1, opts.count, 1 do
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
    })
    picker:open()
    return picker
end

return M
