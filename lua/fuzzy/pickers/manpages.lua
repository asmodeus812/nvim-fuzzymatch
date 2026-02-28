local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class ManpagesPickerOptions
--- @field reuse? boolean Reuse the picker instance between opens
--- @field preview? boolean Enable preview window
--- @field match_step? integer Match batch size

local M = {}

--- Open Manpages picker.
--- @param opts ManpagesPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_manpages_picker(opts)
    opts = util.merge_picker_options({
        reuse = true,
        preview = false,
        match_step = 50000,
    }, opts)

    local manpage_list = vim.fn.getcompletion("", "man") or {}

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = manpage_list,
        headers = util.build_picker_headers("Manpages", opts),
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry_value)
                assert(type(entry_value) == "string" and #entry_value > 0)
                vim.cmd({ cmd = "Man", args = { entry_value } })
                return false
            end)),
        },
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
