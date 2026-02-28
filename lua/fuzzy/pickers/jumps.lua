local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")
local utils = require("fuzzy.utils")

--- @class JumpsPickerOptions
--- @field reuse? boolean Reuse the picker instance between opens
--- @field filename_only? boolean Display only the filename
--- @field path_shorten? number|nil Path shorten value for display
--- @field home_to_tilde? boolean Replace home prefix with ~ in display
--- @field preview? boolean Enable preview window
--- @field icons? boolean Enable file icons
--- @field match_step? integer Match batch size

local M = {}

--- Open Jumps picker.
--- @param opts JumpsPickerOptions|nil Picker options for this picker
--- @return Picker
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
        local file_name = entry_value.filename
        local buf = entry_value.bufnr
        if buf and buf > 0 then
            file_name = utils.get_bufname(
                buf,
                utils.get_bufinfo(buf)
            )
        end
        return {
            filename = file_name,
            lnum = entry_value.lnum or 1,
            col = entry_value.col or 1,
            bufnr = entry_value.bufnr,
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
            local file_name = entry_value.filename
            local buf = entry_value.bufnr
            if buf and buf > 0 then
                file_name = utils.get_bufname(
                    buf,
                    utils.get_bufinfo(buf)
                )
            end
            return util.format_location_entry(
                util.format_display_path(
                    file_name,
                    opts
                ),
                entry_value.lnum or 1,
                entry_value.col or 1,
                nil,
                table.concat({ "[", (entry_value.nr or "?"), "]" })
            )
        end,
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
