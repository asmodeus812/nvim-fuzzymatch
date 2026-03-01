local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class SearchHistoryPickerOptions
--- @field preview? boolean Enable preview window

local M = {}

--- Open Search history picker.
--- @param opts SearchHistoryPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_search_history(opts)
    opts = util.merge_picker_options({
        preview = false,
    }, opts)

    local picker = Picker.new(vim.tbl_extend("force", {
        content = function(stream_callback, args)
            local search_history_list = args.items
            for _, history_entry in ipairs(search_history_list) do
                stream_callback(history_entry)
            end
            stream_callback(nil)
        end,
        headers = util.build_picker_headers("Search History", opts),
        context = {
            args = function(_)
                return {
                    items = util.collect_history_entries("search"),
                }
            end,
        },
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry_value)
                vim.fn.setreg("/", entry_value)
                return false
            end)),
        },
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
