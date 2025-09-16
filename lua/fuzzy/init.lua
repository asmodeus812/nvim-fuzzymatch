Picker = require("fuzzy.picker")
Select = require("fuzzy.select")
Scheduler = require("fuzzy.scheduler")

local M = {}

function M.setup(opts)
    opts = vim.tbl_deep_extend("keep", opts or {}, {
        override_select = true
    })
    Scheduler.new({})

    if opts.override_select then
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.ui.select = function(items, o, confirm)
            local picker = Picker.new({
                content = items,
                headers = {
                    o and o.prompt and { o.prompt }
                },
                display = o and o.format_item,
                prompt_confirm = Select.action(Select.default_select, Picker.first(function(entry)
                    confirm(entry)
                    return entry
                end)),
            })
            picker:open()
            return picker
        end
    end

    vim.api.nvim_set_hl(0, "SelectToggleSign", { link = "Special", default = false })
    vim.api.nvim_set_hl(0, "SelectPrefixText", { link = "Normal", default = false })
    vim.api.nvim_set_hl(0, "SelectStatusText", { link = "NonText", default = false })

    vim.api.nvim_set_hl(0, "SelectProviderStatus", { link = "Special", default = false })
    vim.api.nvim_set_hl(0, "SelectProviderDefault", { link = "Normal", default = false })

    vim.api.nvim_set_hl(0, "SelectHeaderDefault", { link = "Normal", default = false })

    vim.api.nvim_set_hl(0, "PickerHeaderActionKey", { link = "ErrorMsg", default = false })
    vim.api.nvim_set_hl(0, "PickerHeaderActionLabel", { link = "MoreMsg", default = false })
    vim.api.nvim_set_hl(0, "PickerHeaderActionSeparator", { link = "ModeMsg", default = false })
end

return M
