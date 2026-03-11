local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class SearchHistoryPickerOptions

local M = {}

--- Open Search history picker.
--- @param opts SearchHistoryPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_search_history(opts)
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
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry)
                vim.fn.setreg("/", entry)
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
