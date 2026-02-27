local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

local M = {}

local function collect_command_names(opts)
    local command_name_list = {}
    local command_name_map = {}

    if opts.include_builtin then
        local builtin_command_map = vim.api.nvim_get_commands({ builtin = true }) or {}
        for command_name in pairs(builtin_command_map) do
            if not command_name_map[command_name] then
                command_name_map[command_name] = true
                command_name_list[#command_name_list + 1] = command_name
            end
        end
    end

    if opts.include_user then
        local user_command_map = vim.api.nvim_get_commands({}) or {}
        for command_name in pairs(user_command_map) do
            if not command_name_map[command_name] then
                command_name_map[command_name] = true
                command_name_list[#command_name_list + 1] = command_name
            end
        end
    end

    table.sort(command_name_list)
    return command_name_list
end

function M.open_commands_picker(opts)
    opts = util.merge_picker_options({
        reuse = true,
        include_builtin = true,
        include_user = true,
        preview = false,
        match_step = 50000,
    }, opts)

    local command_name_list = collect_command_names(opts)

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = command_name_list,
        headers = util.build_picker_headers("Commands", opts),
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry_value)
                if entry_value and #entry_value > 0 then
                    vim.cmd(entry_value)
                end
                return false
            end)),
        },
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
