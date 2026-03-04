local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local utils = require("fuzzy.utils")
local util = require("fuzzy.pickers.util")

--- @class OldfilesPickerOptions
--- @field stat_file? boolean Stat entries to filter missing files
--- @field preview? boolean Enable preview window
--- @field icons? boolean Enable file icons
--- @field cwd? string|fun(): string Working directory for path display
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
        content = function(stream_callback, args, cwd)
            local oldfiles = args.items
            local seen_file_map = {}
            local seen_file_count = 0
            for _, file_path in ipairs(oldfiles) do
                if file_path and #file_path > 0 then
                    if not seen_file_map[file_path] and (not cwd or util.is_under_directory(cwd, file_path))
                    then
                        local stat = vim.loop.fs_stat(file_path)
                        if stat and stat.type == "file" then
                            seen_file_map[file_path] = true
                            seen_file_count = seen_file_count + 1
                            stream_callback({
                                size = stat.size,
                                mtime = stat.mtime,
                                filename = file_path,
                            })
                            if opts.max and seen_file_count >= opts.max then
                                stream_callback(nil)
                                return
                            end
                        end
                    end
                end
            end
            stream_callback(nil)
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
        display = function(entry_value)
            local filename = assert(entry_value.filename)
            return util.format_display_path(filename, opts)
        end,
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
