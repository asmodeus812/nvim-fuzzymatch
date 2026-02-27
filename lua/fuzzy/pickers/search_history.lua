local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

local M = {}

function M.open_search_history(opts)
    opts = util.merge_picker_options({
        reuse = true,
        preview = false,
        match_step = 50000,
    }, opts)

    local search_history_list = util.collect_history_entries("search")

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = search_history_list,
        headers = util.build_picker_headers("Search History", opts),
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry_value)
                if entry_value and #entry_value > 0 then
                    vim.fn.setreg("/", entry_value)
                end
                return false
            end)),
        },
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
