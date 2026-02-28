local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")
local utils = require("fuzzy.utils")

--- @class MarksPickerOptions
--- @field marks? string Pattern of marks to include
--- @field filename_only? boolean Display only the filename
--- @field path_shorten? number|nil Path shorten value for display
--- @field home_to_tilde? boolean Replace home prefix with ~ in display
--- @field preview? boolean Enable preview window
--- @field icons? boolean Enable file icons
--- @field match_step? integer Match batch size

local M = {}

local function collect_mark_list()
    local mark_entry_list = {}
    local buffer_mark_list = vim.fn.getmarklist(0) or {}
    local global_mark_list = vim.fn.getmarklist() or {}
    for _, mark_entry in ipairs(buffer_mark_list) do
        table.insert(mark_entry_list, mark_entry)
    end
    for _, mark_entry in ipairs(global_mark_list) do
        table.insert(mark_entry_list, mark_entry)
    end
    return mark_entry_list
end

--- Open Marks picker.
--- @param opts MarksPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_marks_picker(opts)
    opts = util.merge_picker_options({
        filename_only = false,
        path_shorten = nil,
        home_to_tilde = true,
        preview = true,
        icons = true,
        match_step = 50000,
    }, opts)

    local conv = function(entry_value)
        local mark_position = entry_value.pos or {}
        local buf = mark_position[1]
        local line_number = mark_position[2]
        local column_number = mark_position[3]
        local filename = assert(entry_value.file)
        return {
            bufnr = buf,
            filename = filename,
            lnum = line_number or 1,
            col = column_number or 1,
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
        content = function(stream_callback)
            local mark_entry_list = collect_mark_list()
            for _, entry_value in ipairs(mark_entry_list) do
                local filename = entry_value.file
                if not filename or #filename == 0 then
                    local mark_position = entry_value.pos or {}
                    local buf = mark_position[1]
                    if buf and buf > 0 then
                        filename = utils.get_bufname(buf)
                    end
                end
                stream_callback(vim.tbl_extend("force", {}, entry_value, {
                    file = filename or utils.NO_NAME,
                }))
            end
            stream_callback(nil)
        end,
        headers = util.build_picker_headers("Marks", opts),
        preview = opts.preview,
        actions = util.build_default_actions(conv, opts),
        decorators = decorators,
        display = function(entry_value)
            local mark_position = entry_value.pos or {}
            local buf = mark_position[1]
            local line_number = mark_position[2]
            local column_number = mark_position[3]
            local filename = assert(entry_value.file)
            local display_path = util.format_display_path(filename, opts)
            if not display_path or #display_path == 0 then
                display_path = utils.NO_NAME
            end
            return util.format_location_entry(
                filename,
                line_number or 1,
                column_number or 1,
                nil,
                table.concat({ "[", entry_value.mark or "?", "]" })
            )
        end,
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
