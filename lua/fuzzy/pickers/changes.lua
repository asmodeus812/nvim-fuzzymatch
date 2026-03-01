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
    }, opts)

    local conv = function(entry_value)
        local current_buf = assert(entry_value.bufnr)
        local current_buffer_name = assert(entry_value.filename)
        return {
            bufnr = current_buf,
            filename = current_buffer_name,
            lnum = entry_value.lnum or 1,
            col = entry_value.col or 1,
        }
    end

    if opts.preview == true then
        opts.preview = Select.BufferPreview.new(nil, conv)
    elseif opts.preview == false or opts.preview == nil then
        opts.preview = false
    end

    local decorators = {}
    if opts.icons ~= false then
        decorators = { Select.IconDecorator.new(conv) }
    end

    local picker = Picker.new(vim.tbl_extend("force", {
        content = function(stream_callback, args)
            local change_entry_list = args.items
            local filename = args.filename
            for _, entry_value in ipairs(change_entry_list) do
                local change_entry = vim.tbl_extend("force", {}, entry_value, {
                    bufnr = args.buf,
                    filename = filename,
                    tick = args.tick,
                })
                stream_callback(change_entry)
            end
            stream_callback(nil)
        end,
        headers = util.build_picker_headers("Changes", opts),
        context = {
            args = function(_)
                local buf = vim.api.nvim_get_current_buf()
                return {
                    buf = buf,
                    tick = vim.api.nvim_buf_get_changedtick(buf),
                    filename = utils.get_bufname(buf),
                    items = (vim.fn.getchangelist(buf)[1] or {}),
                }
            end,
        },
        preview = opts.preview,
        actions = util.build_default_actions(conv, opts),
        decorators = decorators,
        display = function(entry_value)
            return util.format_location_entry(
                nil, entry_value.lnum or 1, entry_value.col or 1
            )
        end,
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
