local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class TagsPickerOptions
--- @field preview? boolean Enable preview window
--- @field match_step? integer Match batch size

local M = {}

--- Open Tags picker.
--- @param opts TagsPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_tags_picker(opts)
    opts = util.merge_picker_options({
        preview = false,
        match_step = 50000,
    }, opts)

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = function(stream_callback)
            local tag_name_list = vim.fn.getcompletion("", "tag") or {}
            for _, tag_name in ipairs(tag_name_list) do
                stream_callback(tag_name)
            end
            stream_callback(nil)
        end,
        headers = util.build_picker_headers("Tags", opts),
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry_value)
                assert(type(entry_value) == "string" and #entry_value > 0)
                vim.cmd({ cmd = "tag", args = { entry_value } })
                return false
            end)),
        },
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
