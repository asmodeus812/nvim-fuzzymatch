local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class HelptagsPickerOptions
--- @field preview? boolean Enable preview window
--- @field match_step? integer Match batch size

local M = {}

--- Open Helptags picker.
--- @param opts HelptagsPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_helptags_picker(opts)
    opts = util.merge_picker_options({        preview = false,
        match_step = 50000,
    }, opts)

    local helptag_list = vim.fn.getcompletion("", "help") or {}

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = helptag_list,
        headers = util.build_picker_headers("Help Tags", opts),
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry_value)
                assert(type(entry_value) == "string" and #entry_value > 0)
                vim.cmd({ cmd = "help", args = { entry_value } })
                return false
            end)),
        },
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
