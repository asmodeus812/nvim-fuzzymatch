local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")
local utils = require("fuzzy.utils")

--- @class MarksPickerOptions
--- @field marks? string Pattern of marks to include
--- @field include_local? boolean Include buffer-local marks
--- @field include_global? boolean Include global marks
--- @field filename_only? boolean Display only the filename
--- @field path_shorten? number|nil Path shorten value for display
--- @field home_to_tilde? boolean Replace home prefix with ~ in display
--- @field preview? boolean Enable preview window
--- @field icons? boolean Enable file icons

local M = {}

local function collect_mark_list(opts)
    local mark_entry_list = {}
    if opts.include_local ~= false then
        local buffer_mark_list = vim.fn.getmarklist(0) or {}
        for _, mark_entry in ipairs(buffer_mark_list) do
            table.insert(mark_entry_list, mark_entry)
        end
    end
    if opts.include_global ~= false then
        local global_mark_list = vim.fn.getmarklist() or {}
        for _, mark_entry in ipairs(global_mark_list) do
            table.insert(mark_entry_list, mark_entry)
        end
    end
    return mark_entry_list
end

--- Open Marks picker.
--- @param opts MarksPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_marks_picker(opts)
    opts = util.merge_picker_options({
        include_local = true,
        include_global = true,
        filename_only = false,
        path_shorten = nil,
        home_to_tilde = true,
        preview = true,
        icons = true,
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
        content = function(stream_callback, args)
            local mark_entry_list = args.items
            for _, entry_value in ipairs(mark_entry_list) do
                if opts.marks ~= nil
                    and entry_value.mark
                    and not entry_value.mark:match(opts.marks)
                then
                    goto continue
                end
                local filename = entry_value.file
                if not filename or #filename == 0 then
                    local mark_position = entry_value.pos or {}
                    local buf = mark_position[1]
                    filename = utils.get_bufname(buf)
                end
                stream_callback(vim.tbl_extend("force", {}, entry_value, {
                    file = filename or utils.NO_NAME,
                }))
                ::continue::
            end
            stream_callback(nil)
        end,
        headers = util.build_picker_headers("Marks", opts),
        context = {
            args = function(_)
                return {
                    items = collect_mark_list(opts),
                }
            end,
        },
        preview = opts.preview,
        actions = util.build_default_actions(conv, opts),
        decorators = decorators,
        display = function(entry_value)
            local mark_position = entry_value.pos or {}
            local line_number = mark_position[2]
            local column_number = mark_position[3]
            local filename = assert(entry_value.file)
            local display_path = util.format_display_path(filename, opts)
            if not display_path or #display_path == 0 then
                display_path = utils.NO_NAME
            end
            return util.format_location_entry(
                filename, line_number or 1, column_number or 1, nil,
                table.concat({ "[", entry_value.mark or "?", "]" })
            )
        end,
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
