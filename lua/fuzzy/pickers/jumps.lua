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

    local conv = function(entry)
        local filename = assert(entry.filename)
        return {
            filename = filename,
            lnum = entry.lnum or 1,
            col = entry.col or 1,
            bufnr = entry.bufnr,
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
        content = function(stream, args)
            for _, entry in ipairs(args.items) do
                local filename = entry.filename
                if not filename or #filename == 0 then
                    filename = utils.get_bufname(entry.bufnr)
                end
                stream(vim.tbl_extend("force", {}, entry, {
                    filename = filename or utils.NO_NAME,
                }))
            end
            stream(nil)
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
        display = function(entry)
            local display_path = util.format_display_path(entry.filename, opts)
            if not display_path or #display_path == 0 then
                display_path = utils.NO_NAME
            end
            return util.format_location_entry(
                display_path, entry.lnum or 1, entry.col or 1, nil,
                table.concat({ "[", (entry.nr or "?"), "]" })
            )
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
