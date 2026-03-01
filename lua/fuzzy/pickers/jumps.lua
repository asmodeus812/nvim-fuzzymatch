local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")
local utils = require("fuzzy.utils")

--- @class JumpsPickerOptions
--- @field filename_only? boolean Display only the filename
--- @field path_shorten? number|nil Path shorten value for display
--- @field home_to_tilde? boolean Replace home prefix with ~ in display
--- @field preview? boolean Enable preview window
--- @field icons? boolean Enable file icons

local M = {}

--- Open Jumps picker.
--- @param opts JumpsPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_jumps_picker(opts)
    opts = util.merge_picker_options({
        filename_only = false,
        path_shorten = nil,
        home_to_tilde = true,
        preview = true,
        icons = true,
    }, opts)

    local conv = function(entry_value)
        local filename = assert(entry_value.filename)
        return {
            filename = filename,
            lnum = entry_value.lnum or 1,
            col = entry_value.col or 1,
            bufnr = entry_value.bufnr,
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
            local jump_entry_list = args.items
            for _, entry_value in ipairs(jump_entry_list) do
                local filename = entry_value.filename
                if not filename or #filename == 0 then
                    local buf = entry_value.bufnr
                    filename = utils.get_bufname(buf)
                end
                stream_callback(vim.tbl_extend("force", {}, entry_value, {
                    filename = filename or utils.NO_NAME,
                }))
            end
            stream_callback(nil)
        end,
        headers = util.build_picker_headers("Jumps", opts),
        context = {
            args = function(_)
                local jump_list_data = vim.fn.getjumplist()
                return {
                    items = jump_list_data[1] or {},
                }
            end,
        },
        preview = opts.preview,
        actions = util.build_default_actions(conv, opts),
        decorators = decorators,
        display = function(entry_value)
            local filename = assert(entry_value.filename)
            local display_path = util.format_display_path(filename, opts)
            if not display_path or #display_path == 0 then
                display_path = utils.NO_NAME
            end
            return util.format_location_entry(
                display_path, entry_value.lnum or 1, entry_value.col or 1, nil,
                table.concat({ "[", (entry_value.nr or "?"), "]" })
            )
        end,
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
