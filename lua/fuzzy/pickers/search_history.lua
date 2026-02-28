local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class SearchHistoryPickerOptions
--- @field preview? boolean Enable preview window
--- @field match_step? integer Match batch size

local M = {}

--- Open Search history picker.
--- @param opts SearchHistoryPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_search_history(opts)
    opts = util.merge_picker_options({        preview = false,
        match_step = 50000,
    }, opts)

    local search_history_list = util.collect_history_entries("search")

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = search_history_list,
        headers = util.build_picker_headers("Search History", opts),
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry_value)
                assert(type(entry_value) == "string" and #entry_value > 0)
                vim.fn.setreg("/", entry_value)
                return false
            end)),
        },
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
