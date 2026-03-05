local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class TagsPickerOptions
--- @field preview? boolean Enable preview window

local M = {}

--- Open Tags picker.
--- @param opts TagsPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_tags_picker(opts)
    opts = util.merge_picker_options({
        preview = false,
    }, opts)

    local picker = Picker.new(vim.tbl_extend("force", {
        content = function(stream, args)
            local items = args.items
            for _, tag_name in ipairs(items) do
                stream(tag_name)
            end
            stream(nil)
        end,
        headers = util.build_picker_headers("Tags", opts),
        context = {
            args = function(_)
                return {
                    items = vim.fn.getcompletion("", "tag") or {},
                }
            end,
        },
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry)
                vim.cmd({ cmd = "tag", args = { entry } })
                return false
            end)),
        },
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
