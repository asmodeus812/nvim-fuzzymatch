local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class CommandHistoryPickerOptions
--- @field preview? boolean Enable preview window

local M = {}

--- Open Command history picker.
--- @param opts CommandHistoryPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_command_history(opts)
    opts = util.merge_picker_options({
        preview = false,
    }, opts)

    local picker = Picker.new(vim.tbl_extend("force", {
        content = function(stream, args)
            for _, history_entry in ipairs(args.items) do
                stream(history_entry)
            end
            stream(nil)
        end,
        headers = util.build_picker_headers("Command History", opts),
        context = {
            args = function(_)
                return {
                    items = util.collect_history_entries("cmd"),
                }
            end,
        },
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry)
                vim.cmd(entry)
                return false
            end)),
        },
    }, opts, {
        match_timer = 5,
        match_step = 1000,
        stream_step = 2000,
        stream_debounce = 0,
        prompt_debounce = 20,
    }))

    picker:open()
    return picker
end

return M
