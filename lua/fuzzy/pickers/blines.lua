local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")
local utils = require("fuzzy.utils")

--- @class BufferLinesPickerOptions
--- @field preview? boolean|Select.Preview Enable preview window or provide a custom previewer
--- @field prompt_query? string|nil Initial prompt query

local M = {}
--- Open Blines picker.
--- @param opts BufferLinesPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_blines_picker(opts)
    opts = util.merge_picker_options({
        preview = false,
    }, opts)

    local convert = function(entry)
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
        opts.preview = Select.BufferPreview.new(nil, convert)
    elseif opts.preview == false or opts.preview == nil then
        opts.preview = false
    end

    local picker = Picker.new(vim.tbl_extend("force", {
        content = function(stream, args)
            local buf = args.buf
            local line_count = args.line_count
            for line_number = 1, line_count do
                stream({
                    bufnr = buf,
                    lnum = line_number,
                })
            end
            stream(nil)
        end,
        headers = util.build_picker_headers("BLines", opts),
        context = {
            args = function(_)
                local buf = vim.api.nvim_get_current_buf()
                return {
                    buf = buf,
                    line_count = vim.api.nvim_buf_line_count(buf),
                }
            end,
        },
        preview = opts.preview,
        actions = util.build_default_actions(convert, opts),
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
    }, opts, {
        match_timer = 10,
        match_step = 8192,
        stream_step = 16384,
        stream_debounce = 0,
        prompt_debounce = 30,
    }))

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
