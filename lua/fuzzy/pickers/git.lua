local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")
local utils = require("fuzzy.utils")

--- @class GitPickerOptions
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

local function resolve_picker_cwd(source)
    local opts = source:options() or {}
    return util.resolve_working_directory(opts.cwd)
end

local function resolve_git_root(source)
    local cwd = resolve_picker_cwd(source)
    return util.find_git_root(cwd)
end

local function build_git_picker(opts, config)
    local actions = config.actions or { ["<cr>"] = Select.default_select }
    if opts and opts.actions then
        actions = vim.tbl_deep_extend("force", actions, opts.actions)
    end

    local context = vim.tbl_extend("force", {
        cwd = function(picker)
            return resolve_picker_cwd(picker)
        end,
    }, config.context or {})

    local picker = Picker.new(vim.tbl_extend("force", {
        content = config.content or "git",
        headers = util.build_picker_headers(config.title, opts),
        context = context,
        preview = config.preview == nil and false or config.preview,
        actions = actions,
        decorators = config.decorators,
        display = config.display,
    }, util.build_picker_options(opts)))
    if config.bind then
        config.bind(picker)
    end
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

--- Open Git files picker.
--- @param opts GitPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_git_files(opts)
    opts = util.merge_picker_options({
        cwd = vim.loop.cwd,
        untracked = true,
        preview = true,
        icons = true,
        stream_step = 100000,
        match_step = 75000,
    }, opts)

    if opts.cwd == true then
        opts.cwd = vim.loop.cwd
    end

    assert(util.command_is_available("git"))

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

    if opts.preview == true then
        opts.preview = Select.BufferPreview.new(nil, converter_cb)
    elseif opts.preview == false or opts.preview == nil then
        opts.preview = false
    end

    local decorators = {}
    if opts.icons ~= false then
        decorators = { Select.IconDecorator.new(converter_cb) }
    end
    local picker = build_git_picker(opts, {
        title = "Gitfiles",
        context = {
            args = command_args,
            cwd = function(picker)
                return assert(resolve_git_root(picker))
            end,
        },
        preview = opts.preview,
        decorators = decorators,
        actions = util.build_default_actions(converter_cb, opts),
        bind = function(instance)
            converter:bind(instance)
        end,
    })
    return picker
end

--- Open Git status picker.
--- @param opts GitPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_git_status(opts)
    opts = util.merge_picker_options({
        cwd = vim.loop.cwd,
        preview = true,
        icons = true,
        stream_step = 50000,
        match_step = 50000,
    }, opts)

    if opts.cwd == true then
        opts.cwd = vim.loop.cwd
    end

    assert(util.command_is_available("git"))

    local converter = Picker.Converter.new(
        parse_git_status_entry,
        Picker.cwd_visitor
    )
    local converter_cb = converter:get()

    if opts.preview == true then
        opts.preview = Select.BufferPreview.new(nil, converter_cb)
    elseif opts.preview == false or opts.preview == nil then
        opts.preview = false
    end

    local decorators = {}
    if opts.icons ~= false then
        decorators = { Select.IconDecorator.new(converter_cb) }
    end
    local picker = build_git_picker(opts, {
        title = "Status",
        context = {
            args = {
                "-c", "color.status=false",
                "status", "--porcelain=v1",
            },
            cwd = function(picker)
                return assert(resolve_git_root(picker))
            end,
        },
        preview = opts.preview,
        decorators = decorators,
        actions = util.build_default_actions(converter_cb, opts),
        display = function(entry_value)
            assert(type(entry_value) == "string")
            return entry_value
        end,
        bind = function(instance)
            converter:bind(instance)
        end,
    })
    return picker
end

--- Open Git branches picker.
--- @param opts GitPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_git_branches(opts)
    opts = util.merge_picker_options({
        cwd = vim.loop.cwd,
        preview = false,
        stream_step = 50000,
        match_step = 50000,
    }, opts)

    if opts.cwd == true then
        opts.cwd = vim.loop.cwd
    end

    assert(util.command_is_available("git"))

    local command_args = {
        "branch",
        "--all",
        "--color=never",
        "-vv",
        "--sort=-committerdate",
        "--sort=refname:rstrip=-2",
        "--sort=-HEAD",
    }

    return build_git_picker(opts, {
        title = "Branches",
        context = {
            args = command_args,
            cwd = function(picker)
                return assert(resolve_git_root(picker))
            end,
        },
    })
end

--- Open Git commits picker.
--- @param opts GitPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_git_commits(opts)
    opts = util.merge_picker_options({
        cwd = vim.loop.cwd,
        preview = false,
        stream_step = 50000,
        match_step = 50000,
    }, opts)

    if opts.cwd == true then
        opts.cwd = vim.loop.cwd
    end

    assert(util.command_is_available("git"))

    local command_args = {
        "log",
        "--color=never",
        table.concat({
            "--pretty=format:",
            build_git_commits_format(),
        }),
    }

    return build_git_picker(opts, {
        title = "Commits",
        context = {
            args = command_args,
            cwd = function(picker)
                return assert(resolve_git_root(picker))
            end,
        },
    })
end

--- Open Git stash picker.
--- @param opts GitPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_git_stash(opts)
    opts = util.merge_picker_options({
        cwd = vim.loop.cwd,
        preview = false,
        stream_step = 50000,
        match_step = 50000,
    }, opts)

    if opts.cwd == true then
        opts.cwd = vim.loop.cwd
    end

    assert(util.command_is_available("git"))

    local command_args = {
        "--no-pager",
        "stash",
        "list",
    }

    return build_git_picker(opts, {
        title = "Stash",
        context = {
            args = command_args,
            cwd = function(picker)
                return assert(resolve_git_root(picker))
            end,
        },
    })
end

--- Open Git bcommits picker.
--- @param opts GitPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_git_bcommits(opts)
    opts = util.merge_picker_options({
        cwd = true,
        preview = false,
        stream_step = 50000,
        match_step = 50000,
    }, opts)

    if opts.cwd == true then
        opts.cwd = vim.loop.cwd
    end

    assert(util.command_is_available("git"))

    return build_git_picker(opts, {
        title = "BCommits",
        context = {
            cwd = function(picker)
                return resolve_picker_cwd(picker)
            end,
            args = function(picker)
                local buf = vim.api.nvim_get_current_buf()
                local buf_path = utils.get_bufname(buf) or utils.NO_NAME
                buf_path = vim.fs.normalize(assert(buf_path))

                local cwd = resolve_picker_cwd(picker) or ""
                local rel_path = vim.fs.relpath(buf_path, cwd)
                rel_path = rel_path or buf_path

                return {
                    "log",
                    "--color=never",
                    table.concat({
                        "--pretty=format:",
                        build_git_commits_format(),
                    }),
                    "--",
                    rel_path,
                }
            end,
        },
    })
end

return M
