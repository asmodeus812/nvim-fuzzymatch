local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")

--- Open ui.select picker.
--- @param items table
--- @param opts table|nil
--- @param confirm fun(item: any): nil
--- @return Picker
local function open_select_picker(items, opts, confirm)
    local picker = Picker.new({
        content = items,
        context = {
            cwd = vim.loop.cwd()
        },
        preview = false,
        display = opts and opts.format_item and function(i)
            local item, _ = opts.format_item(i)
            return assert(item)
        end,
        headers = { opts and opts.prompt and { opts.prompt } },
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry)
                confirm(entry)
                return false
            end)),
            ["<tab>"] = Select.noop_select
        }
    })
    picker:open()
    return picker
end

return {
    open_select_picker = open_select_picker,
}
