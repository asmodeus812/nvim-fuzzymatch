local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")
local utils = require("fuzzy.utils")

--- @class ChangesPickerOptions
--- @field reuse? boolean Reuse the picker instance between opens
--- @field filename_only? boolean Display only the filename
--- @field path_shorten? number|nil Path shorten value for display
--- @field home_to_tilde? boolean Replace home prefix with ~ in display
--- @field preview? boolean Enable preview window
--- @field icons? boolean Enable file icons
--- @field match_step? integer Match batch size

local M = {}

--- Open Changes picker.
--- @param opts ChangesPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_changes_picker(opts)
    opts = util.merge_picker_options({
        reuse = true,
        filename_only = false,
        path_shorten = nil,
        home_to_tilde = true,
        preview = true,
        icons = true,
        match_step = 50000,
    }, opts)

    local change_list_data = vim.fn.getchangelist(0)
    local change_entry_list = change_list_data[1] or {}
    local current_buf = vim.api.nvim_get_current_buf()
    local conv = function(entry_value)
        return {
            bufnr = current_buf,
            filename = utils.get_bufname(
                current_buf,
                utils.get_bufinfo(current_buf)
            ),
            lnum = entry_value.lnum or 1,
            col = entry_value.col or 1,
        }
    end

    local decorators = {}
    if opts.icons ~= false then
        decorators = { Select.IconDecorator.new(conv) }
    end

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = change_entry_list,
        headers = util.build_picker_headers("Changes", opts),
        preview = opts.preview ~= false
            and Select.BufferPreview.new(nil, conv) or false,
        actions = util.build_default_actions(conv, opts),
        decorators = decorators,
        display = function(entry_value)
            local buffer_name = utils.get_bufname(
                current_buf,
                utils.get_bufinfo(current_buf)
            ) or "[No Name]"
            local display_path = util.format_display_path(
                buffer_name,
                opts
            )
            return util.format_location_entry(
                display_path,
                entry_value.lnum or 1,
                entry_value.col or 1,
                nil,
                nil
            )
        end,
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
