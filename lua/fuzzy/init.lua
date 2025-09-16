Scheduler = require("fuzzy.scheduler")

local M = {}


function M.setup(opts)
    opts = vim.tbl_deep_extend("keep", opts or {}, {
    })

    Scheduler.new({})

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
