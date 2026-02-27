local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")
local utils = require("fuzzy.utils")

local M = {}

function M.open_loclist_picker(opts)
    opts = util.merge_picker_options({
        reuse = true,
        filename_only = false,
        path_shorten = nil,
        home_to_tilde = true,
        preview = true,
        icons = true,
        match_step = 50000,
    }, opts)

    local info = vim.fn.getloclist(0, { items = 1, title = 1 })
    local items = info.items or {}
    local converter_cb = Select.default_converter
    local decorators = {}
    if opts.icons ~= false then
        decorators = { Select.IconDecorator.new(converter_cb) }
    end

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = items,
        headers = util.build_picker_headers(
            info.title or "Location List",
            opts
        ),
        preview = opts.preview ~= false
            and Select.BufferPreview.new(nil, converter_cb) or false,
        actions = util.build_default_actions(converter_cb, opts),
        decorators = decorators,
        display = function(entry)
            local filename = entry.filename
                or (entry.bufnr and vim.api.nvim_buf_get_name(entry.bufnr))
                or "[No Name]"
            return util.format_location_entry(
                filename,
                entry.lnum or 1,
                entry.col or 1,
                entry.text,
                table.concat({ "[", (entry.bufnr or "?"), "]" })
            )
        end,
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

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
