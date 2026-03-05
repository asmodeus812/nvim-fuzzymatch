local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class LoclistStackPickerOptions
--- @field preview? boolean Enable preview window

local M = {}

--- Open Loclist stack picker.
--- @param opts LoclistStackPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_loclist_stack(opts)
    opts = util.merge_picker_options({
        preview = false,
    }, opts)

    local picker = Picker.new(vim.tbl_extend("force", {
        content = function(stream, args)
            local history_text = args.history_text
            local entries = util.parse_stack_entries(history_text)
            for _, history_entry in ipairs(entries) do
                stream(history_entry)
            end
            stream(nil)
        end,
        headers = util.build_picker_headers("Loclist Stack", opts),
        context = {
            args = function(_)
                return {
                    history_text = vim.fn.execute("lhistory"),
                }
            end,
        },
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry)
                assert(entry and entry.number)
                vim.cmd({ cmd = "lhistory", args = { tostring(entry.number) } })
                vim.cmd("lopen")
                return false
            end)),
        },
        display = function(entry)
            assert(entry and entry.text)
            return entry.text
        end,
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
