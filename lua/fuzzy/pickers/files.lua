local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class FilesPickerOptions
--- @field cwd? string|fun(): string Working directory for the scan
--- @field cwd_prompt? boolean Show cwd in the header
--- @field cwd_prompt_shorten_val? integer Pathshorten value
--- @field cwd_prompt_shorten_len? integer Max cwd header length
--- @field hidden? boolean Include hidden files
--- @field follow? boolean Follow symlinks
--- @field no_ignore? boolean Disable ignore files
--- @field no_ignore_vcs? boolean Disable VCS ignore files
--- @field preview? boolean Enable preview window
--- @field icons? boolean Enable file icons
--- @field stream_step? integer Stream batch size
--- @field match_step? integer Match batch size

local M = {}

local function build_files_command(opts)
    local command_name_text = util.pick_first_command({ "rg", "fd", "find" })
    if not command_name_text then
        return nil, nil
    end

    if command_name_text == "rg" then
        local command_argument_list = {
            "--files",
            "--color=never",
        }
        if opts.hidden then
            table.insert(command_argument_list, "--hidden")
        end
        if opts.follow then
            table.insert(command_argument_list, "--follow")
        end
        if opts.no_ignore then
            table.insert(command_argument_list, "--no-ignore")
        end
        if opts.no_ignore_vcs then
            table.insert(command_argument_list, "--no-ignore-vcs")
        end
        return command_name_text, command_argument_list
    elseif command_name_text == "fd" then
        local command_argument_list = {
            "--type", "f",
            "--color", "never",
        }
        if opts.hidden then
            table.insert(command_argument_list, "--hidden")
        end
        if opts.follow then
            table.insert(command_argument_list, "--follow")
        end
        if opts.no_ignore then
            table.insert(command_argument_list, "--no-ignore")
        end
        if opts.no_ignore_vcs then
            table.insert(command_argument_list, "--no-ignore-vcs")
        end
        return command_name_text, command_argument_list
    else
        local command_argument_list = { ".", "-type", "f" }
        if opts.hidden == false then
            table.insert(command_argument_list, "-not")
            table.insert(command_argument_list, "-path")
            table.insert(command_argument_list, "*/.*")
        end
        return command_name_text, command_argument_list
    end
end

--- Open Files picker.
--- @param opts FilesPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_files_picker(opts)
    opts = util.merge_picker_options({
        cwd = vim.loop.cwd,
        cwd_prompt = true,
        cwd_prompt_shorten_val = 1,
        cwd_prompt_shorten_len = 32,
        hidden = true,
        follow = false,
        no_ignore = false,
        no_ignore_vcs = false,
        preview = true,
        icons = true,
        stream_step = 100000,
        match_step = 75000,
    }, opts)
    if opts.cwd == true then
        opts.cwd = vim.loop.cwd
    end

    local cmd, args = build_files_command(opts)
    assert(cmd)

    local converter = Picker.Converter.new(
        Picker.default_converter,
        Picker.cwd_visitor
    )
    local conv = converter:get()

    local decorators = {}
    if opts.icons ~= false then
        decorators = { Select.IconDecorator.new(conv) }
    end

    if opts.preview == true then
        opts.preview = Select.BufferPreview.new(nil, conv)
    elseif opts.preview == false then
        opts.preview = false
    end

    local picker = Picker.new(vim.tbl_extend("force", {
        content = cmd,
        headers = util.build_picker_headers("Files", opts),
        context = {
            args = args,
            cwd = opts.cwd,
        },
        preview = opts.preview,
        actions = util.build_default_actions(conv, opts),
        decorators = decorators,
    }, util.build_picker_options(opts)))

    converter:bind(picker)
    picker:open()
    return picker
end

return M
