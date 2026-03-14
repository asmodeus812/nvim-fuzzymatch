local Pool = require("fuzzy.pool")
local Registry = require("fuzzy.registry")
local Scheduler = require("fuzzy.scheduler")
local group = vim.api.nvim_create_augroup("FUZZYMATCH", { clear = true })

local M = {
    config = {},
}

function M.teardown()
    if Scheduler and Scheduler.close then
        Scheduler.close()
    end
    if Registry and Registry.close then
        Registry.close()
    end
    if Pool and Pool.close then
        Pool.close()
    end
end

function M.setup(opts)
    M.config = vim.tbl_deep_extend("keep", opts or {}, {
        general = {
            override_select = true,
            user_command = {
                enabled = true,
                name = "Fzm",
            },
        },
        scheduler = {
            async_budget = 1 * 1e6,
        },
        pool = {
            prime_min = 16384,
            prime_max = 524288,
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

    local user_command = M.config.general.user_command or {}
    if user_command.enabled then
        local excmd = require("fuzzy.pickers.excmd")
        excmd.register_user_commands(user_command.name)
    end

    vim.api.nvim_set_hl(0, "SelectToggleSign", { link = "Special", default = false })
    vim.api.nvim_set_hl(0, "SelectPrefixText", { link = "Normal", default = false })
    vim.api.nvim_set_hl(0, "SelectStatusText", { link = "NonText", default = false })
    vim.api.nvim_set_hl(0, "SelectToggleCount", { link = "NonText", default = false })

    vim.api.nvim_set_hl(0, "SelectHeaderDefault", { link = "Normal", default = false })
    vim.api.nvim_set_hl(0, "SelectHeaderPadding", { link = "NonText", default = false })
    vim.api.nvim_set_hl(0, "SelectHeaderDelimiter", { link = "Ignore", default = false })

    vim.api.nvim_set_hl(0, "PickerHeaderActionKey", { link = "ErrorMsg", default = false })
    vim.api.nvim_set_hl(0, "PickerHeaderActionLabel", { link = "MoreMsg", default = false })
    vim.api.nvim_set_hl(0, "PickerHeaderActionSeparator", { link = "ModeMsg", default = false })

    vim.api.nvim_set_hl(0, "SelectLineHighlight", { link = "Normal", default = false })
    vim.api.nvim_set_hl(0, "SelectDecoratorDefault", { link = "Normal", default = false })

    vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.teardown })
end

return M
