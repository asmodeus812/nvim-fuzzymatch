local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class LoclistStackPickerOptions
--- @field reuse? boolean Reuse the picker instance between opens
--- @field preview? boolean Enable preview window
--- @field match_step? integer Match batch size

local M = {}

--- Open Loclist stack picker.
--- @param opts LoclistStackPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_loclist_stack(opts)
    opts = util.merge_picker_options({
        reuse = true,
        preview = false,
        match_step = 50000,
    }, opts)

    local history_text = vim.fn.execute("lhistory")
    local history_entry_list = util.parse_stack_entries(history_text)

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = history_entry_list,
        headers = util.build_picker_headers("Loclist Stack", opts),
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry_value)
                assert(entry_value and entry_value.number)
                vim.cmd({ cmd = "lhistory", args = { tostring(entry_value.number) } })
                vim.cmd("lopen")
                return false
            end)),
        },
        display = function(entry_value)
            assert(entry_value and entry_value.text)
            return entry_value.text
        end,
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
