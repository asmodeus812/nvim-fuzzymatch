local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")
local utils = require("fuzzy.utils")

local M = {}

function M.open_quickfix_picker(opts)
    opts = util.merge_picker_options({
        reuse = true,
        filename_only = false,
        path_shorten = nil,
        home_to_tilde = true,
        preview = true,
        icons = true,
        match_step = 50000,
    }, opts)

    local qf_info = vim.fn.getqflist({ items = 1, title = 1 })
    local items = qf_info.items or {}
    local converter_cb = Select.default_converter
    local decorators = {}
    if opts.icons ~= false then
        decorators = { Select.IconDecorator.new(converter_cb) }
    end

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = items,
        headers = util.build_picker_headers(
            qf_info.title or "Quickfix",
            opts
        ),
        preview = opts.preview ~= false
            and Select.BufferPreview.new(nil, converter_cb) or false,
        actions = util.build_default_actions(converter_cb, opts),
        decorators = decorators,
        display = function(entry)
            local filename = entry.filename
            if not filename or #filename == 0 then
                local buf = entry.bufnr
                if not buf or buf <= 0 then
                    filename = "[No Name]"
                else
                    filename = utils.get_bufname(buf) or "[No Name]"
                end
            end
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
