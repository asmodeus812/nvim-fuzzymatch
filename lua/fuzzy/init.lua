Picker = require("fuzzy.picker")
Pool = require("fuzzy.pool")
Registry = require("fuzzy.registry")
Scheduler = require("fuzzy.scheduler")
Select = require("fuzzy.select")

local M = {
    config = {},
}

function M.setup(opts)
    M.config = vim.tbl_deep_extend("keep", opts or {}, {
        general = {
            override_select = true
        },
        scheduler = {
            async_budget = 1 * 1e6,
        },
        pool = {
            max_idle = 5 * 60 * 1000,
            prune_interval = 30 * 1000,
            max_tables = nil,
            prime_sizes = { 1024, 2048, 4096, 8192, 16384 },
        },
        registry = {
            max_idle = 5 * 60 * 1000,
            prune_interval = 30 * 1000,
        },
    })

    local pool_config = M.config.pool
    local registry_config = M.config.registry
    local scheduler_config = M.config.scheduler

    Pool.new(pool_config)
    Registry.new(registry_config)
    Scheduler.new(scheduler_config)

    if M.config.general.override_select then
        local select_picker = require("fuzzy.pickers.select")
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.ui.select = select_picker.open_select_picker
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

    Pool.prime(pool_config.prime_sizes or {})
end

return M
