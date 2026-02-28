Picker = require("fuzzy.picker")
Select = require("fuzzy.select")
Scheduler = require("fuzzy.scheduler")
Pool = require("fuzzy.pool")

local M = {
    config = {},
}

function M.setup(opts)
    M.config = vim.tbl_deep_extend("keep", opts or {}, {
        override_select = true,
    })
    Scheduler.new({})
    Pool.new({
        max_idle = 5 * 60 * 1000,
        prune_interval = 30 * 1000,
    })
    Pool.prime({ 1024, 2048, 4096, 8192, 16384 })

    if M.config.override_select then
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.ui.select = function(items, o, confirm)
            local picker = Picker.new({
                content = items,
                context = {
                    cwd = vim.loop.cwd()
                },
                preview = false,
                display = o and o.format_item and function(i)
                    local item, _ = o.format_item(i)
                    return assert(item)
                end,
                headers = { o and o.prompt and { o.prompt } },
                actions = {
                    ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry)
                        confirm(entry)
                        return false
                    end)),
                    ["<tab>"] = false
                }
            })
            picker:open()
            return picker
        end
    end

    vim.api.nvim_set_hl(0, "SelectToggleSign", { link = "Special", default = false })
    vim.api.nvim_set_hl(0, "SelectPrefixText", { link = "Normal", default = false })
    vim.api.nvim_set_hl(0, "SelectStatusText", { link = "NonText", default = false })
    vim.api.nvim_set_hl(0, "SelectToggleCount", { link = "NonText", default = false })

    vim.api.nvim_set_hl(0, "SelectHeaderDefault", { link = "Normal", default = false })
    vim.api.nvim_set_hl(0, "SelectHeaderPadding", { link = "NonText", default = false })
    vim.api.nvim_set_hl(0, "SelectHeaderDelimiter", { link = "Ignore", default = false })
    vim.api.nvim_set_hl(0, "SelectDecoratorDefault", { link = "Normal", default = false })

    vim.api.nvim_set_hl(0, "PickerHeaderActionKey", { link = "ErrorMsg", default = false })
    vim.api.nvim_set_hl(0, "PickerHeaderActionLabel", { link = "MoreMsg", default = false })
    vim.api.nvim_set_hl(0, "PickerHeaderActionSeparator", { link = "ModeMsg", default = false })
end

return M
