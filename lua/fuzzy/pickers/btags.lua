local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")
local utils = require("fuzzy.utils")

--- @class BufferTagsPickerOptions
--- @field preview? boolean Enable preview window

local M = {}

--- Open Btags picker.
--- @param opts BufferTagsPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_btags_picker(opts)
    opts = util.merge_picker_options({
        preview = false,
    }, opts)

    local picker = Picker.new(vim.tbl_extend("force", {
        content = function(stream, args)
            local current_buffer_name = args.bufname
            for _, tag_entry in ipairs(args.items) do
                if tag_entry and tag_entry.filename == current_buffer_name then
                    stream(tag_entry)
                end
            end
            stream(nil)
        end,
        headers = util.build_picker_headers("Buffer Tags", opts),
        context = {
            args = function(_)
                local buf = vim.api.nvim_get_current_buf()
                return {
                    buf = buf,
                    bufname = utils.get_bufname(buf),
                    items = vim.fn.taglist(".*") or {},
                }
            end,
        },
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry)
                assert(entry and entry.name)
                vim.cmd({ cmd = "tag", args = { entry.name } })
                return false
            end)),
        },
        display = function(entry)
            local name = entry.name or ""
            local kind = entry.kind or ""
            if #kind > 0 then
                kind = " [" .. kind .. "]"
            end
            return name .. kind
        end,
    }, opts, {
        match_timer = 5,
        match_step = 2000,
        stream_step = 4000,
        stream_debounce = 0,
        prompt_debounce = 25,
    }))

    picker:open()
    return picker
end

return M
