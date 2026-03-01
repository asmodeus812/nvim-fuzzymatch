local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class HelptagsPickerOptions
--- @field preview? boolean Enable preview window

local M = {}

--- Open Helptags picker.
--- @param opts HelptagsPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_helptags_picker(opts)
    opts = util.merge_picker_options({
        preview = false,
    }, opts)

    local picker = Picker.new(vim.tbl_extend("force", {
        content = function(stream_callback, args)
            local helptag_list = args.items
            for _, helptag in ipairs(helptag_list) do
                stream_callback(helptag)
            end
            stream_callback(nil)
        end,
        headers = util.build_picker_headers("Helptags", opts),
        context = {
            args = function(_)
                return {
                    items = vim.fn.getcompletion("", "help") or {},
                }
            end,
        },
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry_value)
                vim.cmd({ cmd = "help", args = { entry_value } })
                return false
            end)),
        },
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
