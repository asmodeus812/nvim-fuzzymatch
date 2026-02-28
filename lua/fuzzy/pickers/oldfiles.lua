local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class OldfilesPickerOptions
--- @field stat_file? boolean Stat entries to filter missing files
--- @field preview? boolean Enable preview window
--- @field icons? boolean Enable file icons
--- @field match_step? integer Match batch size
--- @field cwd? string|fun(): string Working directory for path display
--- @field filename_only? boolean Display only the filename
--- @field path_shorten? number|nil Path shorten value for display
--- @field home_to_tilde? boolean Replace home prefix with ~ in display

local M = {}

--- Open Oldfiles picker.
--- @param opts OldfilesPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_oldfiles_picker(opts)
    opts = util.merge_picker_options({
        cwd = nil,
        stat_file = false,
        max = nil,
        filename_only = false,
        path_shorten = nil,
        home_to_tilde = true,
        preview = true,
        icons = true,
        match_step = 50000,
    }, opts)

    local decorators = {}
    local conv = Select.default_converter
    if opts.icons ~= false then
        decorators = { Select.IconDecorator.new(conv) }
    end

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = function(stream_callback)
            local current_working_directory = util.resolve_working_directory(opts.cwd)
            local seen_file_map = {}
            local seen_file_count = 0
            for _, file_path in ipairs(vim.v.oldfiles or {}) do
                if type(file_path) == "string" and #file_path > 0 then
                    if not seen_file_map[file_path]
                        and (not current_working_directory
                            or util.is_under_directory(
                                current_working_directory,
                                file_path
                            )) then
                        if not opts.stat_file
                            or vim.loop.fs_stat(file_path) then
                            seen_file_map[file_path] = true
                            seen_file_count = seen_file_count + 1
                            stream_callback(file_path)
                            if opts.max
                                and seen_file_count >= opts.max then
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
        preview = opts.preview ~= false
            and Select.BufferPreview.new(nil, conv) or false,
        actions = util.build_default_actions(conv, opts),
        decorators = decorators,
        display = function(entry_value)
            return util.format_display_path(entry_value, opts)
        end,
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
