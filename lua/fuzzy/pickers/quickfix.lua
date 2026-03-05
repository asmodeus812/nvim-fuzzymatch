local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")
local utils = require("fuzzy.utils")

--- @class QuickfixPickerOptions
--- @field cwd? string|fun(): string Working directory for path display
--- @field filename_only? boolean Display only the filename
--- @field path_shorten? number|nil Path shorten value for display
--- @field home_to_tilde? boolean Replace home prefix with ~ in display
--- @field preview? boolean Enable preview window
--- @field icons? boolean Enable file icons
--- @field prompt_query? string|nil Initial prompt query

local M = {}

--- Open Quickfix picker.
--- @param opts QuickfixPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_quickfix_picker(opts)
    opts = util.merge_picker_options({
        filename_only = false,
        path_shorten = nil,
        home_to_tilde = true,
        cwd = nil,
        preview = true,
        icons = true,
    }, opts)

    local convert = function(entry)
        return {
            bufnr = entry.bufnr,
            filename = assert(entry.filename),
            lnum = entry.lnum or 1,
            col = entry.col or 1,
        }
    end

    if opts.cwd == true then
        opts.cwd = vim.loop.cwd
    end

    if opts.preview == true then
        opts.preview = Select.BufferPreview.new(nil, convert)
    elseif opts.preview == false or opts.preview == nil then
        opts.preview = false
    end

    local decorators = {}
    if opts.icons ~= false then
        decorators = { Select.IconDecorator.new(convert) }
    end

    local picker = Picker.new(vim.tbl_extend("force", {
        content = function(stream, args, cwd)
            for _, entry in ipairs(args.items) do
                local filename = entry.filename
                if not filename or #filename == 0 then
                    filename = utils.get_bufname(entry.bufnr)
                end
                if cwd and #cwd > 0 and filename and #filename > 0
                    and not util.is_under_directory(cwd, filename)
                then
                    goto continue
                end
                stream(vim.tbl_extend("force", {}, entry, {
                    filename = filename or utils.NO_NAME,
                }))
                ::continue::
            end
            stream(nil)
        end,
        headers = util.build_picker_headers("Quickfix", opts),
        context = {
            cwd = opts.cwd,
            args = function()
                local info = vim.fn.getqflist({ items = 1, title = 1 })
                return { items = info.items or {} }
            end
        },
        preview = opts.preview,
        actions = util.build_default_actions(convert, opts),
        decorators = decorators,
        display = function(entry)
            local filename = assert(entry.filename)
            local display_path = util.format_display_path(filename, opts)
            return util.format_location_entry(
                display_path, entry.lnum or 1, entry.col or 1, entry.text,
                table.concat({ "[", (entry.bufnr or "?"), "]" })
            )
        end,
    }, opts, {
        match_timer = 10,
        match_step = 10000,
        stream_step = 20000,
        stream_debounce = 0,
        prompt_debounce = 30,
    }))

    picker:open()
    return picker
end

--- Open Quickfix visual picker.
--- Prefills the prompt with the visual selection.
--- @param opts QuickfixPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_quickfix_visual(opts)
    local visual = utils.get_visual_text()
    local query = util.normalize_query_text(visual)
    opts = opts or {}
    if query then
        opts.prompt_query = query
    end
    return M.open_quickfix_picker(opts)
end

return M
