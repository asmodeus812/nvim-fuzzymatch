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
        content = function(stream, args)
            for _, helptag in ipairs(args.items) do
                stream(helptag)
            end
            stream(nil)
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
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry)
                vim.cmd({ cmd = "help", args = { entry } })
                return false
            end)),
        },
    }, opts, {
        match_timer = 10,
        match_step = 5000,
        stream_step = 10000,
        stream_debounce = 0,
        prompt_debounce = 30,
    }))

    picker:open()
    return picker
end

return M
