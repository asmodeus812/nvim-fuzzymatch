local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class FilesPickerOptions
--- @field cwd? boolean|string|fun(): string Working directory for the scan; `true` resolves to `vim.loop.cwd`
--- @field hidden? boolean Include hidden files
--- @field follow? boolean Follow symlinks
--- @field no_ignore? boolean Disable ignore files
--- @field no_ignore_vcs? boolean Disable VCS ignore files
--- @field preview? boolean|Select.Preview Enable preview window or provide a custom previewer
--- @field icons? boolean Enable file icons
--- @field watch? boolean Refresh on reopen when the directory changes

local M = {}

local function build_files_command(opts)
    local cmd = util.pick_first_command({ "rg", "fd", "find" })
    if not cmd then
        return nil, nil
    end

    if cmd == "rg" then
        local args = {
            "--files",
            "--color=never",
        }
        if opts.hidden then
            table.insert(args, "--hidden")
        end
        if opts.follow then
            table.insert(args, "--follow")
        end
        if opts.no_ignore then
            table.insert(args, "--no-ignore")
        end
        if opts.no_ignore_vcs then
            table.insert(args, "--no-ignore-vcs")
        end
        return cmd, args
    elseif cmd == "fd" then
        local args = {
            "--type", "f",
            "--color", "never",
        }
        if opts.hidden then
            table.insert(args, "--hidden")
        end
        if opts.follow then
            table.insert(args, "--follow")
        end
        if opts.no_ignore then
            table.insert(args, "--no-ignore")
        end
        if opts.no_ignore_vcs then
            table.insert(args, "--no-ignore-vcs")
        end
        return cmd, args
    else
        local args = { ".", "-type", "f" }
        if opts.hidden == false then
            table.insert(args, "-not")
            table.insert(args, "-path")
            table.insert(args, "*/.*")
        end
        return cmd, args
    end
end

--- Open Files picker.
--- @param opts FilesPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_files_picker(opts)
    opts = util.merge_picker_options({
        cwd = vim.loop.cwd,
        hidden = true,
        follow = false,
        no_ignore = false,
        no_ignore_vcs = false,
        preview = true,
        icons = true,
        watch = false,
    }, opts)

    if opts.cwd == true then
        opts.cwd = vim.loop.cwd
    end

    local converter = Picker.Converter.new(
        Picker.default_converter,
        Picker.cwd_visitor
    )
    local conv = converter:get()

    if opts.preview == true then
        opts.preview = Select.BufferPreview.new(nil, conv)
    elseif opts.preview == false or opts.preview == nil then
        opts.preview = false
    end

    local decorators = {}
    if opts.icons ~= false then
        decorators = { Select.IconDecorator.new(conv) }
    end

    local tick_counter = 0
    local cmd, args = build_files_command(opts)
    local picker = Picker.new(vim.tbl_extend("force", {
        content = assert(cmd),
        headers = util.build_picker_headers("Files", opts),
        context = {
            args = args,
            cwd = opts.cwd,
            tick = function()
                if opts.watch == true then
                    return util.dir_watch_state(opts.cwd).tick
                end
                tick_counter = tick_counter + 1
                return tick_counter
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
    }, opts, {
        match_timer = 30,
        match_step = 75000,
        stream_step = 250000,
        stream_debounce = 0,
        prompt_debounce = 125,
    }))

    converter:bind(picker)
    picker:open()
    return picker
end

return M
