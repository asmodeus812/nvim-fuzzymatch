local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")
local utils = require("fuzzy.utils")

--- @class ChangesPickerOptions
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
        filename_only = false,
        path_shorten = nil,
        home_to_tilde = true,
        preview = true,
        icons = true,
        match_step = 50000,
    }, opts)

    local conv = function(entry_value)
        local current_buf = vim.api.nvim_get_current_buf()
        local current_buffer_name = utils.get_bufname(
            current_buf,
            utils.get_bufinfo(current_buf)
        )
        return {
            bufnr = current_buf,
            filename = current_buffer_name,
            lnum = entry_value.lnum or 1,
            col = entry_value.col or 1,
        }
    end

    local decorators = {}
    if opts.icons ~= false then
        decorators = { Select.IconDecorator.new(conv) }
    end

    if opts.preview == true then
        opts.preview = Select.BufferPreview.new(nil, conv)
    elseif opts.preview == false or opts.preview == nil then
        opts.preview = false
    end
    local picker = Picker.new(vim.tbl_extend("force", {
        content = function(stream_callback, args)
            local buf = args and args.buf or vim.api.nvim_get_current_buf()
            local change_list_data = vim.fn.getchangelist(buf)
            local change_entry_list = change_list_data[1] or {}
            for _, entry_value in ipairs(change_entry_list) do
                stream_callback(entry_value)
            end
            stream_callback(nil)
        end,
        headers = util.build_picker_headers("Changes", opts),
        context = {
            args = function()
                local buf = vim.api.nvim_get_current_buf()
                return {
                    buf = buf,
                    tick = vim.api.nvim_buf_get_changedtick(buf),
                }
            end,
        },
        preview = opts.preview,
        actions = util.build_default_actions(conv, opts),
        decorators = decorators,
        display = function(entry_value)
            local buf = vim.api.nvim_get_current_buf()
            local buffer_name = utils.get_bufname(
                buf,
                utils.get_bufinfo(buf)
            ) or utils.NO_NAME
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
