local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")
local utils = require("fuzzy.utils")

--- @class ChangesPickerOptions
--- @field preview? boolean|Select.Preview Enable preview window or provide a custom previewer
--- @field icons? boolean Enable file icons

local M = {}

--- Open Changes picker.
--- @param opts ChangesPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_changes_picker(opts)
    opts = util.merge_picker_options({
        filename_only = false,
        path_shorten = nil,
        home_to_tilde = true,
        preview = true,
        icons = true,
    }, opts)

    local conv = function(entry)
        local current_buf = assert(entry.bufnr)
        local current_buffer_name = assert(entry.filename)
        return {
            bufnr = current_buf,
            filename = current_buffer_name,
            lnum = entry.lnum or 1,
            col = entry.col or 1,
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
            local filename = args.filename
            for _, entry in ipairs(args.items) do
                local change_entry = vim.tbl_extend("force", {}, entry, {
                    bufnr = args.buf,
                    filename = filename,
                    tick = args.tick,
                })
                stream(change_entry)
            end
            stream(nil)
        end,
        headers = util.build_picker_headers("Changes", opts),
        context = {
            args = function(_)
                local buf = vim.api.nvim_get_current_buf()
                return {
                    buf = buf,
                    tick = vim.api.nvim_buf_get_changedtick(buf),
                    filename = utils.get_bufname(buf),
                    items = (vim.fn.getchangelist(buf)[1] or {}),
                }
            end,
        },
        preview = opts.preview,
        actions = util.build_default_actions(conv, opts),
        decorators = decorators,
        highlighters = {
            Select.RegexHighlighter.new({
                { "%d+:%d+", "Number" },
            }),
        },
        display = function(entry)
            return util.format_location_entry(
                nil, entry.lnum or 1, entry.col or 1
            )
        end,
    }, opts, {
        match_timer = 5,
        match_step = 2048,
        stream_step = 4096,
        stream_debounce = 0,
        prompt_debounce = 25,
    }))

    picker:open()
    return picker
end

return M
