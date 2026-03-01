local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")
local utils = require("fuzzy.utils")

--- @class LoclistPickerOptions
--- @field cwd? string|fun(): string Working directory for path display
--- @field filename_only? boolean Display only the filename
--- @field path_shorten? number|nil Path shorten value for display
--- @field home_to_tilde? boolean Replace home prefix with ~ in display
--- @field preview? boolean Enable preview window
--- @field icons? boolean Enable file icons
--- @field prompt_query? string|nil Initial prompt query

local M = {}

--- Open Loclist picker.
--- @param opts LoclistPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_loclist_picker(opts)
    opts = util.merge_picker_options({
        filename_only = false,
        path_shorten = nil,
        home_to_tilde = true,
        cwd = nil,
        preview = true,
        icons = true,
    }, opts)

    local converter_cb = function(entry_value)
        return {
            bufnr = entry_value.bufnr,
            filename = assert(entry_value.filename),
            lnum = entry_value.lnum or 1,
            col = entry_value.col or 1,
        }
    end

    if opts.cwd == true then
        opts.cwd = vim.loop.cwd
    end

    if opts.preview == true then
        opts.preview = Select.BufferPreview.new(nil, converter_cb)
    elseif opts.preview == false or opts.preview == nil then
        opts.preview = false
    end

    local decorators = {}
    if opts.icons ~= false then
        decorators = { Select.IconDecorator.new(converter_cb) }
    end

    local picker = Picker.new(vim.tbl_extend("force", {
        content = function(stream_callback, args, cwd)
            local loc_items = args.items
            for _, entry_value in ipairs(loc_items) do
                local filename = entry_value.filename
                if not filename or #filename == 0 then
                    local buf = entry_value.bufnr
                    filename = utils.get_bufname(buf)
                end
                if cwd and #cwd > 0 and filename and #filename > 0
                    and not util.is_under_directory(cwd, filename)
                then
                    goto continue
                end
                stream_callback(vim.tbl_extend("force", {}, entry_value, {
                    filename = filename or utils.NO_NAME,
                }))
                ::continue::
            end
            stream_callback(nil)
        end,
        headers = util.build_picker_headers("Loclist", opts),
        context = {
            cwd = opts.cwd,
            args = function(_)
                local wid = vim.api.nvim_get_current_win()
                local info = vim.fn.getloclist(wid, { items = 1, title = 1 })
                return { wid = wid, items = info.items or {} }
            end
        },
        preview = opts.preview,
        actions = util.build_default_actions(converter_cb, opts),
        decorators = decorators,
        display = function(entry)
            local filename = assert(entry.filename)
            local display_path = util.format_display_path(filename, opts)
            if not display_path or #display_path == 0 then
                display_path = utils.NO_NAME
            end
            return util.format_location_entry(
                display_path, entry.lnum or 1, entry.col or 1, entry.text,
                table.concat({ "[", (entry.bufnr or "?"), "]" })
            )
        end,
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

--- Open Loclist visual picker.
--- Prefills the prompt with the visual selection.
--- @param opts LoclistPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_loclist_visual(opts)
    local visual = utils.get_visual_text()
    local query = util.normalize_query_text(visual)
    opts = opts or {}
    if query then
        opts.prompt_query = query
    end
    return M.open_loclist_picker(opts)
end

return M
