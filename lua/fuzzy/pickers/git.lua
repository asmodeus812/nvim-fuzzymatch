local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")
local utils = require("fuzzy.utils")

--- @class GitPickerOptions
--- @field reuse? boolean Reuse the picker instance between opens
--- @field cwd? string|fun(): string Working directory for git commands
--- @field preview? boolean Enable preview window
--- @field icons? boolean Enable file icons
--- @field stream_step? integer Stream batch size
--- @field match_step? integer Match batch size
--- @field actions? table Custom action map
--- @field untracked? boolean Include untracked files (git files)

local M = {}

local function build_git_commits_format()
    return table.concat({
        "%h ",
        "%cr ",
        "%s ",
        "<%an>",
    })
end

local function build_git_command_entry(command_args, opts, title)
    assert(command_args ~= nil)
    local actions = { ["<cr>"] = Select.default_select }
    if opts and opts.actions then
        actions = vim.tbl_deep_extend("force", actions, opts.actions)
    end
    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = "git",
        headers = util.build_picker_headers(title, opts),
        context = {
            args = command_args,
            cwd = opts.cwd,
        },
        preview = false,
        actions = actions,
    }, util.build_picker_options(opts)))
    picker:open()
    return picker
end

local function parse_git_status_entry(entry)
    assert(type(entry) == "string" and #entry > 0)
    local _, _, file_path = entry:find("^..%s+(.+)$")
    assert(file_path ~= nil and #file_path > 0)
    local arrow_position = file_path:find("%s+->%s+")
    if arrow_position then
        file_path = file_path:sub(arrow_position + 4)
    end
    return {
        filename = file_path,
        lnum = 1,
        col = 1,
    }
end

local function resolve_git_root(opts)
    local cwd = type(opts.cwd) == "function" and opts.cwd() or opts.cwd
    local git_root = util.find_git_root(cwd)
    if not git_root then
        return nil
    end
    return git_root
end

--- Open Git files picker.
--- @param opts GitPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_git_files(opts)
    opts = util.merge_picker_options({
        reuse = true,
        cwd = vim.loop.cwd,
        untracked = true,
        preview = true,
        icons = true,
        stream_step = 100000,
        match_step = 75000,
    }, opts)

    assert(util.command_is_available("git"))

    local git_root = assert(resolve_git_root(opts))

    local command_args = { "ls-files" }
    if opts.untracked then
        table.insert(command_args, "--others")
        table.insert(command_args, "--cached")
        table.insert(command_args, "--exclude-standard")
    end

    local converter = Picker.Converter.new(
        Picker.default_converter,
        Picker.cwd_visitor
    )
    local converter_cb = converter:get()

    local decorators = {}
    if opts.icons ~= false then
        decorators = { Select.IconDecorator.new(converter_cb) }
    end

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = "git",
        headers = util.build_picker_headers("Git Files", opts),
        context = {
            args = command_args,
            cwd = git_root,
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

--- Open Git status picker.
--- @param opts GitPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_git_status(opts)
    opts = util.merge_picker_options({
        reuse = true,
        cwd = vim.loop.cwd,
        preview = true,
        icons = true,
        stream_step = 50000,
        match_step = 50000,
    }, opts)

    assert(util.command_is_available("git"))

    local git_root = assert(resolve_git_root(opts))

    local converter = Picker.Converter.new(
        parse_git_status_entry,
        Picker.cwd_visitor
    )
    local converter_cb = converter:get()

    local decorators = {}
    if opts.icons ~= false then
        decorators = { Select.IconDecorator.new(converter_cb) }
    end

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = "git",
        headers = util.build_picker_headers("Git Status", opts),
        context = {
            args = {
                "-c", "color.status=false",
                "status", "--porcelain=v1",
            },
            cwd = git_root,
        },
        preview = opts.preview ~= false
            and Select.BufferPreview.new(nil, converter_cb) or false,
        actions = util.build_default_actions(converter_cb, opts),
        decorators = decorators,
        display = function(entry_value)
            assert(type(entry_value) == "string")
            return entry_value
        end,
    }, util.build_picker_options(opts)))

    converter:bind(picker)
    picker:open()
    return picker
end

--- Open Git branches picker.
--- @param opts GitPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_git_branches(opts)
    opts = util.merge_picker_options({
        reuse = true,
        cwd = vim.loop.cwd,
        preview = false,
        stream_step = 50000,
        match_step = 50000,
    }, opts)

    assert(util.command_is_available("git"))

    local git_root = assert(resolve_git_root(opts))
    opts.cwd = git_root

    local command_args = {
        "branch",
        "--all",
        "--color=never",
        "-vv",
        "--sort=-committerdate",
        "--sort=refname:rstrip=-2",
        "--sort=-HEAD",
    }

    return build_git_command_entry(command_args, opts, "Git Branches")
end

--- Open Git commits picker.
--- @param opts GitPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_git_commits(opts)
    opts = util.merge_picker_options({
        reuse = true,
        cwd = vim.loop.cwd,
        preview = false,
        stream_step = 50000,
        match_step = 50000,
    }, opts)

    assert(util.command_is_available("git"))

    local git_root = assert(resolve_git_root(opts))
    opts.cwd = git_root

    local command_args = {
        "log",
        "--color=never",
        table.concat({
            "--pretty=format:",
            build_git_commits_format(),
        }),
    }

    return build_git_command_entry(command_args, opts, "Git Commits")
end

--- Open Git bcommits picker.
--- @param opts GitPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_git_bcommits(opts)
    opts = util.merge_picker_options({
        reuse = true,
        cwd = nil,
        preview = false,
        stream_step = 50000,
        match_step = 50000,
    }, opts)

    assert(util.command_is_available("git"))

    local buf = vim.api.nvim_get_current_buf()
    local buf_path = utils.get_bufname(buf)
    assert(type(buf_path) == "string" and #buf_path > 0)
    assert(buf_path ~= "[No Name]"
        and buf_path ~= "[Quickfix List]"
        and buf_path ~= "[Location List]")

    local buf_dir = vim.fs.dirname(vim.fs.normalize(buf_path))
    local git_root = assert(util.find_git_root(buf_dir))
    opts.cwd = git_root

    local rel_path = vim.fs.relpath(buf_path, git_root) or buf_path

    local command_args = {
        "log",
        "--color=never",
        table.concat({
            "--pretty=format:",
            build_git_commits_format(),
        }),
        "--",
        rel_path,
    }

    return build_git_command_entry(command_args, opts, "Git Buffer Commits")
end

--- Open Git stash picker.
--- @param opts GitPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_git_stash(opts)
    opts = util.merge_picker_options({
        reuse = true,
        cwd = vim.loop.cwd,
        preview = false,
        stream_step = 50000,
        match_step = 50000,
    }, opts)

    assert(util.command_is_available("git"))

    local git_root = assert(resolve_git_root(opts))
    opts.cwd = git_root

    local command_args = {
        "--no-pager",
        "stash",
        "list",
    }

    return build_git_command_entry(command_args, opts, "Git Stash")
end

return M
