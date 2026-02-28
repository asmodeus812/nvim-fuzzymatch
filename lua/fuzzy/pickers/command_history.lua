local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class CommandHistoryPickerOptions
--- @field preview? boolean Enable preview window
--- @field match_step? integer Match batch size

local M = {}

--- Open Command history picker.
--- @param opts CommandHistoryPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_command_history(opts)
    opts = util.merge_picker_options({        preview = false,
        match_step = 50000,
    }, opts)

    local command_history_list = util.collect_history_entries("cmd")

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = command_history_list,
        headers = util.build_picker_headers("Command History", opts),
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry_value)
                assert(type(entry_value) == "string" and #entry_value > 0)
                vim.cmd(entry_value)
                return false
            end)),
        },
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
