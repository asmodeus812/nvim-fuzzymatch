local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local utils = require("fuzzy.utils")
local util = require("fuzzy.pickers.util")

--- @class OldfilesPickerOptions
--- @field max? integer|nil Maximum number of entries to emit
--- @field preview? boolean|Select.Preview Enable preview window or provide a custom previewer
--- @field icons? boolean Enable file icons
--- @field cwd? boolean|string|fun(): string Working directory for path display; `true` resolves to `vim.loop.cwd`
--- @field filename_only? boolean Display only the filename
--- @field path_shorten? number|nil Path shorten value for display
--- @field home_to_tilde? boolean Replace home prefix with ~ in display

local M = {}

--- Open Oldfiles picker.
--- @param opts OldfilesPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_oldfiles_picker(opts)
    local conv = Select.default_converter
    opts = util.merge_picker_options({
        cwd = nil,
        max = 256,
        stat_file = true,
        filename_only = false,
        path_shorten = nil,
        home_to_tilde = true,
        preview = true,
        icons = true,
    }, opts)

    if opts.cwd == true then
        opts.cwd = vim.loop.cwd
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
        content = function(stream, args, cwd)
            local oldfiles = args.items
            local seen_file_map = {}
            local seen_file_count = 0
            for _, filename in ipairs(oldfiles) do
                if filename and #filename > 0 then
                    if not seen_file_map[filename] and (not cwd or util.is_under_directory(cwd, filename))
                    then
                        local stat = vim.loop.fs_stat(filename)
                        if stat and stat.type == "file" then
                            seen_file_map[filename] = true
                            seen_file_count = seen_file_count + 1
                            stream({
                                size = stat.size,
                                mtime = stat.mtime,
                                filename = filename,
                            })
                            if opts.max and seen_file_count >= opts.max then
                                stream(nil)
                                return
                            end
                        end
                    end
                end
            end
            stream(nil)
        end,
        headers = util.build_picker_headers("Oldfiles", opts),
        context = {
            cwd = opts.cwd,
            args = function(_)
                return { items = vim.v.oldfiles or {} }
            end,
        },
        preview = opts.preview,
        actions = util.build_default_actions(conv, opts),
        decorators = decorators,
        highlighters = {
            Select.RegexHighlighter.new({
                { "^.+/", "Directory" },
                { "[^/]+$", "Identifier" },
            }),
        },
        display = function(entry)
            local filename = assert(entry.filename)
            return util.format_display_path(filename, opts)
        end,
    }, opts, {
        match_timer = 10,
        match_step = 4096,
        stream_step = 8192,
        stream_debounce = 0,
        prompt_debounce = 30,
    }))

    picker:open()
    return picker
end

return M
