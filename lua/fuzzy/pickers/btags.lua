local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")
local utils = require("fuzzy.utils")

--- @class BufferTagsPickerOptions
--- @field preview? boolean Enable preview window
--- @field match_step? integer Match batch size

local M = {}

--- Open Btags picker.
--- @param opts BufferTagsPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_btags_picker(opts)
    opts = util.merge_picker_options({        preview = false,
        match_step = 50000,
    }, opts)

    local buf = vim.api.nvim_get_current_buf()
    local current_buffer_name = utils.get_bufname(
        buf,
        utils.get_bufinfo(buf)
    )
    local tag_entry_list = vim.fn.taglist(".*") or {}
    local filtered_entry_list = {}
    for _, tag_entry in ipairs(tag_entry_list) do
        if tag_entry and tag_entry.filename == current_buffer_name then
            filtered_entry_list[#filtered_entry_list + 1] = tag_entry
        end
    end

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = filtered_entry_list,
        headers = util.build_picker_headers("Buffer Tags", opts),
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry_value)
                assert(entry_value and entry_value.name)
                vim.cmd({ cmd = "tag", args = { entry_value.name } })
                return false
            end)),
        },
        display = function(entry_value)
            assert(entry_value)
            local name_text = entry_value.name or ""
            local kind_text = entry_value.kind or ""
            if #kind_text > 0 then
                kind_text = table.concat({ " [", kind_text, "]" })
            end
            return table.concat({ name_text, kind_text })
        end,
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
