local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

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

function M.open_files_picker(opts)
    opts = util.merge_picker_options({
        reuse = true,
        cwd = vim.loop.cwd,
        cwd_prompt = false,
        cwd_prompt_shorten_val = 1,
        cwd_prompt_shorten_len = 32,
        hidden = true,
        follow = false,
        no_ignore = false,
        no_ignore_vcs = false,
        ignore_current_file = false,
        preview = true,
        icons = true,
        stream_step = 100000,
        match_step = 75000,
    }, opts)

    local cmd, args = build_files_command(opts)
    assert(cmd, "No file search command available (rg/fd/find).")

    local converter = Picker.Converter.new(
        Picker.default_converter,
        Picker.cwd_visitor
    )
    local conv = converter:get()

    local decorators = {}
    if opts.icons ~= false then
        decorators = { Select.IconDecorator.new(conv) }
    end

    local map_callback_func = nil
    if opts.ignore_current_file then
        local current_file_path = vim.api.nvim_buf_get_name(0)
        local current_working_directory = type(opts.cwd) == "function"
            and opts.cwd() or opts.cwd
        local current_relative_path = nil
        if current_file_path and #current_file_path > 0
            and current_working_directory
            and #current_working_directory > 0 then
            local normalized_cwd = vim.fs.normalize(current_working_directory)
            local normalized_current = vim.fs.normalize(current_file_path)
            if normalized_current:sub(1, #normalized_cwd + 1) == normalized_cwd .. "/" then
                current_relative_path = normalized_current:sub(#normalized_cwd + 2)
            end
        end
        map_callback_func = function(entry_value)
            if current_file_path and #current_file_path > 0
                and (entry_value == current_file_path
                    or entry_value == current_relative_path) then
                return nil
            end
            return entry_value
        end
    end

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = cmd,
        headers = util.build_picker_headers("Files", opts),
        context = {
            args = args,
            cwd = opts.cwd,
            map = map_callback_func,
        },
        preview = opts.preview ~= false
            and Select.BufferPreview.new(nil, conv) or false,
        actions = util.build_default_actions(conv, opts),
        decorators = decorators,
    }, util.build_picker_options(opts)))

    converter:bind(picker)
    picker:open()
    return picker
end

return M
