local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")
local utils = require("fuzzy.utils")

--- @class BufferLinesPickerOptions
--- @field preview? boolean Enable preview window
--- @field match_step? integer Batch size for matching
--- @field prompt_query? string|nil Initial prompt query

local M = {}
--- Open Blines picker.
--- @param opts BufferLinesPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_blines_picker(opts)
    opts = util.merge_picker_options({
        preview = false,
        match_step = 50000,
    }, opts)

    local converter_cb = function(entry)
        return {
            bufnr = entry.bufnr,
            lnum = entry.lnum or 1,
            col = 1,
        }
    end
    local decorator = Select.Decorator.new()
    function decorator:decorate(entry)
        return tostring(entry.lnum), "Number"
    end

    if opts.preview == true then
        opts.preview = Select.BufferPreview.new(nil, converter_cb)
    elseif opts.preview == false or opts.preview == nil then
        opts.preview = false
    end
    local picker = Picker.new(vim.tbl_extend("force", {
        content = function(stream_callback, args)
            local buf = args and args.buf or vim.api.nvim_get_current_buf()
            util.stream_line_numbers(
                buf,
                stream_callback
            )
            stream_callback(nil)
        end,
        headers = util.build_picker_headers("BLines", opts),
        context = {
            args = function()
                return { buf = vim.api.nvim_get_current_buf() }
            end,
        },
        preview = opts.preview,
        actions = util.build_default_actions(converter_cb, opts),
        decorators = { decorator },
        display = function(entry)
            local ok, text = pcall(vim.api.nvim_buf_get_lines,
                entry.bufnr,
                entry.lnum - 1,
                entry.lnum,
                false
            )
            assert(ok ~= false and text ~= nil)
            return ok and #text > 0 and text[1] or ""
        end,
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

--- Open Buffer lines word picker.
--- Prefills the prompt with the word under cursor.
--- @param opts BufferLinesPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_buffer_lines_word(opts)
    local word = vim.fn.expand("<cword>")
    local query = util.normalize_query_text(word)
    opts = opts or {}
    if query then
        opts.prompt_query = query
    end
    return M.open_blines_picker(opts)
end

--- Open Buffer lines visual picker.
--- Prefills the prompt with the visual selection.
--- @param opts BufferLinesPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_buffer_lines_visual(opts)
    local visual = utils.get_visual_text()
    local query = util.normalize_query_text(visual)
    opts = opts or {}
    if query then
        opts.prompt_query = query
    end
    return M.open_blines_picker(opts)
end

return M
