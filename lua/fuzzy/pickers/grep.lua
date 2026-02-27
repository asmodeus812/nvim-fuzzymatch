local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")
local utils = require("fuzzy.utils")

local M = {}

local function split_argument_list(arg_text)
    if type(arg_text) == "table" then
        return vim.list_extend({}, arg_text)
    end
    if type(arg_text) ~= "string" or #arg_text == 0 then
        return {}
    end
    return vim.split(arg_text, "%s+")
end

local function build_grep_command(opts)
    local cmd = util.pick_first_command({ "grep", "rg" })
    if not cmd then
        return nil, nil
    end

    if cmd == "rg" then
        local args = split_argument_list(opts.rg_opts)
        if #args == 0 then
            args = {
                "--column",
                "--line-number",
                "--no-heading",
                "--color=never",
                "--smart-case",
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
        end
        return cmd, args
    else
        local args = split_argument_list(opts.grep_opts)
        if #args == 0 then
            args = {
                "-n",
                "-H",
                "-r",
                "--line-buffered",
            }
        end
        return cmd, args
    end
end

function M.open_grep_picker(opts)
    opts = util.merge_picker_options({
        reuse = true,
        cwd = vim.loop.cwd,
        hidden = false,
        follow = false,
        no_ignore = false,
        no_ignore_vcs = false,
        rg_glob = false,
        rg_glob_fn = nil,
        glob_flag = "--iglob",
        glob_separator = "%s%-%-",
        rg_opts = nil,
        grep_opts = nil,
        RIPGREP_CONFIG_PATH = nil,
        preview = true,
        icons = true,
        stream_step = 25000,
        match_step = 25000,
        prompt_debounce = 200,
    }, opts)

    local cmd, args = build_grep_command(opts)
    assert(cmd, "No grep command available (grep/rg).")

    local converter = Picker.Converter.new(
        Picker.grep_converter,
        Picker.cwd_visitor
    )
    local converter_cb = converter:get()

    local decorators = {}
    if opts.icons ~= false then
        decorators = { Select.IconDecorator.new(converter_cb) }
    end

    local function parse_query_value(query)
        if not opts.rg_glob then
            return query, nil
        end
        if type(opts.rg_glob_fn) == "function" then
            return opts.rg_glob_fn(query, opts)
        end
        local separator = opts.glob_separator or "%s%-%-"
        local glob_match = table.concat({ "^(.-)", separator, "(.*)$" })
        local regex_text, glob_flags = query:match(glob_match)
        if not glob_flags or #glob_flags == 0 then
            return query, nil
        end
        local extra_args = {}
        for _, glob_value in ipairs(split_argument_list(glob_flags)) do
            if #glob_value > 0 then
                table.insert(extra_args, table.concat({
                    opts.glob_flag or "--iglob",
                    "=",
                    glob_value,
                }))
            end
        end
        return regex_text or query, extra_args
    end

    local function build_interactive_arguments(query, ctx)
        local args_list = vim.list_extend({}, ctx.args or {})
        local pattern, extra = parse_query_value(query)

        if cmd == "rg" then
            table.insert(args_list, pattern)
            if type(extra) == "string" and #extra > 0 then
                table.insert(args_list, "--")
                vim.list_extend(args_list, split_argument_list(extra))
            elseif type(extra) == "table" and #extra > 0 then
                table.insert(args_list, "--")
                vim.list_extend(args_list, extra)
            end
        else
            table.insert(args_list, pattern)
            table.insert(args_list, ".")
        end
        return args_list
    end

    local env = nil
    if opts.RIPGREP_CONFIG_PATH then
        env = {
            table.concat({
                "RIPGREP_CONFIG_PATH=",
                opts.RIPGREP_CONFIG_PATH,
            })
        }
    end

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = cmd,
        headers = util.build_picker_headers("Grep", opts),
        context = {
            args = args,
            cwd = opts.cwd,
            env = env,
            interactive = build_interactive_arguments,
        },
        preview = opts.preview ~= false
            and Select.BufferPreview.new(nil, converter_cb) or false,
        actions = util.build_default_actions(converter_cb, opts),
        decorators = decorators,
    }, util.build_picker_options(opts)))

    converter:bind(picker)
    picker:open()
    return picker
end

function M.open_grep_word(opts)
    local word = vim.fn.expand("<cword>")
    local query = util.normalize_query_text(word)
    opts = opts or {}
    if query then
        opts.prompt_query = query
    end
    return M.open_grep_picker(opts)
end

function M.open_grep_visual(opts)
    local visual = utils.get_visual_text()
    local query = util.normalize_query_text(visual)
    opts = opts or {}
    if query then
        opts.prompt_query = query
    end
    return M.open_grep_picker(opts)
end

return M
