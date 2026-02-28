local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")
local utils = require("fuzzy.utils")

--- @class LinesPickerOptions
--- @field show_unlisted? boolean Include unlisted buffers
--- @field show_unloaded? boolean Include unloaded buffers
--- @field ignore_current_buffer? boolean Exclude current buffer
--- @field cwd? string|fun(): string Working directory to filter buffers
--- @field include_special? boolean|string[]|table<string, boolean> Include special buffers:
---   false: only normal buffers (buftype == "")
---   true: include all special buftypes
---   table: include only listed buftypes, as an array or map
--- @field preview? boolean Enable preview window
--- @field match_step? integer Batch size for matching
--- @field prompt_query? string|nil Initial prompt query

local M = {}

local function should_include_buftype(opts, buftype)
    if buftype == "" then
        return true
    end
    local include_special = opts.include_special
    if include_special == true then
        return true
    end
    if type(include_special) == "table" then
        return include_special[buftype] == true
            or vim.tbl_contains(include_special, buftype)
    end
    return false
end

--- Open Lines picker.
--- @param opts LinesPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_lines_picker(opts)
    opts = util.merge_picker_options({
        show_unlisted = false,
        show_unloaded = false,
        ignore_current_buffer = false,
        cwd = nil,
        include_special = false,
        preview = false,
        match_step = 50000,
    }, opts)
    if opts.cwd == true then
        opts.cwd = vim.loop.cwd
    end

    local converter_cb = function(entry)
        return {
            bufnr = entry.bufnr,
            lnum = entry.lnum or 1,
            col = 1,
        }
    end

    local decorator = Select.Decorator.new()
    function decorator:decorate(entry)
        local file_path = utils.get_bufname(entry.bufnr)
        if not file_path or #file_path == 0 then
            file_path = utils.NO_NAME
        end
        local display_path = util.format_display_path(file_path, opts)
        return {
            display_path,
            tostring(entry.lnum)
        }, {
            "Directory",
            "Number"
        }
    end

    if opts.preview == true then
        opts.preview = Select.BufferPreview.new(nil, converter_cb)
    elseif opts.preview == false or opts.preview == nil then
        opts.preview = false
    end
    local picker = Picker.new(vim.tbl_extend("force", {
        content = function(stream_callback, args, cwd)
            local buffers = vim.api.nvim_list_bufs() or {}
            local current_buf = args and args.buf or vim.api.nvim_get_current_buf()
            for _, buf in ipairs(buffers) do
                if vim.api.nvim_buf_is_valid(buf)
                    and should_include_buftype(opts, vim.bo[buf].buftype)
                    and (opts.show_unlisted
                        or vim.fn.buflisted(buf) == 1
                        or buf == current_buf)
                    and (opts.show_unloaded
                        or vim.api.nvim_buf_is_loaded(buf))
                    and (not opts.ignore_current_buffer
                        or buf ~= current_buf) then
                    local buffer_name = utils.get_bufname(buf)
                    if buffer_name and #buffer_name > 0
                        and not util.is_under_directory(
                            cwd,
                            buffer_name
                        ) then
                        goto continue
                    end
                    util.stream_line_numbers(
                        buf,
                        stream_callback
                    )
                end
                ::continue::
            end
            stream_callback(nil)
        end,
        headers = util.build_picker_headers("Lines", opts),
        context = {
            cwd = opts.cwd,
            args = function()
                return {
                    buf = vim.api.nvim_get_current_buf(),
                }
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
