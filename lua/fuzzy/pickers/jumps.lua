local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

local M = {}

local function format_jump_entry(jump_entry, opts)
    local buf = jump_entry.bufnr
    local file_path = buf and vim.api.nvim_buf_get_name(buf) or jump_entry.filename
    file_path = util.format_display_path(file_path, opts)
    return util.format_location_entry(
        file_path,
        jump_entry.lnum or 1,
        jump_entry.col or 1,
        nil,
        table.concat({ "[", (jump_entry.nr or "?"), "]" })
    )
end

function M.open_jumps_picker(opts)
    opts = util.merge_picker_options({
        reuse = true,
        filename_only = false,
        path_shorten = nil,
        home_to_tilde = true,
        preview = true,
        icons = true,
        match_step = 50000,
    }, opts)

    local jump_list_data = vim.fn.getjumplist()
    local jump_entry_list = jump_list_data[1] or {}

    local conv = function(entry_value)
        local buf = entry_value.bufnr
        local file_path = buf and vim.api.nvim_buf_get_name(buf) or entry_value.filename
        return {
            filename = file_path,
            lnum = entry_value.lnum or 1,
            col = entry_value.col or 1,
            bufnr = buf,
        }
    end

    local decorators = {}
    if opts.icons ~= false then
        decorators = { Select.IconDecorator.new(conv) }
    end

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = jump_entry_list,
        headers = util.build_picker_headers("Jumps", opts),
        preview = opts.preview ~= false
            and Select.BufferPreview.new(nil, conv) or false,
        actions = util.build_default_actions(conv, opts),
        decorators = decorators,
        display = function(entry_value)
            return format_jump_entry(entry_value, opts)
        end,
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
