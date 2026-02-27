local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

local M = {}

function M.open_btags_picker(opts)
    opts = util.merge_picker_options({
        reuse = true,
        preview = false,
        match_step = 50000,
    }, opts)

    local current_buffer_name = vim.api.nvim_buf_get_name(0)
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
                if entry_value and entry_value.name then
                    vim.cmd({ cmd = "tag", args = { entry_value.name } })
                end
                return false
            end)),
        },
        display = function(entry_value)
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
