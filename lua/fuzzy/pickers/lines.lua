local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")
local utils = require("fuzzy.utils")

--- @class LinesPickerOptions
--- @field reuse? boolean Reuse the picker instance between opens
--- @field line_chunk_size? integer Number of line entries per chunk
--- @field show_unlisted? boolean Include unlisted buffers
--- @field show_unloaded? boolean Include unloaded buffers
--- @field ignore_current_buffer? boolean Exclude current buffer
--- @field preview? boolean Enable preview window
--- @field match_step? integer Batch size for matching
--- @field prompt_query? string|nil Initial prompt query

local M = {}

--- Open Lines picker.
--- @param opts LinesPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_lines_picker(opts)
    opts = util.merge_picker_options({
        reuse = true,
        line_chunk_size = 1000,
        show_unlisted = false,
        show_unloaded = false,
        ignore_current_buffer = false,
        preview = false,
        match_step = 50000,
    }, opts)

    local buffers = vim.api.nvim_list_bufs() or {}
    local current_buf = vim.api.nvim_get_current_buf()

    local converter_cb = function(entry)
        return {
            bufnr = entry.bufnr,
            filename = utils.get_bufname(
                entry.bufnr,
                utils.get_bufinfo(entry.bufnr)
            ) or "[No Name]",
            lnum = entry.lnum or 1,
            col = 1,
        }
    end
    local decorator = Select.Decorator.new()
    function decorator:decorate(entry)
        local file_path = utils.get_bufname(
            entry.bufnr,
            utils.get_bufinfo(entry.bufnr)
        )
        if not file_path or #file_path == 0 then
            file_path = "[No Name]"
        end
        local display_path = util.format_display_path(file_path, opts)
        return table.concat({ display_path, ":", entry.lnum, ": " })
    end

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = function(stream_callback)
            for _, buf in ipairs(buffers) do
                if vim.api.nvim_buf_is_valid(buf)
                    and (opts.show_unlisted
                        or vim.fn.buflisted(buf) == 1
                        or buf == current_buf)
                    and (opts.show_unloaded
                        or vim.api.nvim_buf_is_loaded(buf))
                    and (not opts.ignore_current_buffer
                        or buf ~= current_buf) then
                    util.stream_line_numbers(
                        buf,
                        opts.line_chunk_size or 1000,
                        stream_callback
                    )
                end
            end
            stream_callback(nil)
        end,
        headers = util.build_picker_headers("Lines", opts),
        preview = opts.preview ~= false
            and Select.BufferPreview.new(nil, converter_cb) or false,
        actions = util.build_default_actions(converter_cb, opts),
        decorators = { decorator },
        display = function(entry)
            local line_text = vim.api.nvim_buf_get_lines(
                entry.bufnr,
                entry.lnum - 1,
                entry.lnum,
                false
            )[1]
            return line_text or ""
        end,
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

--- Open Lines word picker.
--- Prefills the prompt with the word under cursor.
--- @param opts LinesPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_lines_word(opts)
    local word = vim.fn.expand("<cword>")
    local query = util.normalize_query_text(word)
    opts = opts or {}
    if query then
        opts.prompt_query = query
    end
    return M.open_lines_picker(opts)
end

--- Open Lines visual picker.
--- Prefills the prompt with the visual selection.
--- @param opts LinesPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_lines_visual(opts)
    local visual = utils.get_visual_text()
    local query = util.normalize_query_text(visual)
    opts = opts or {}
    if query then
        opts.prompt_query = query
    end
    return M.open_lines_picker(opts)
end

return M
