local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")
local utils = require("fuzzy.utils")

--- @class GitPickerOptions
--- @field cwd? string|fun(): string Working directory for git commands
--- @field preview? boolean Enable preview window
--- @field icons? boolean Enable file icons
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

local function git_system(cwd, args)
    if not cwd or #cwd == 0 then
        return nil
    end
    local cmd = { "git", "-C", cwd }
    vim.list_extend(cmd, args or {})
    return vim.system(cmd, { text = true }):wait()
end

local function git_version_status(cwd, include_untracked)
    local args = {
        "-c", "color.status=false",
        "status", "--porcelain=v1", "-b",
    }
    if not include_untracked then
        table.insert(args, "--untracked-files=no")
    end
    local result = git_system(cwd, args)
    if not result or result.code ~= 0 then
        return nil
    end
    return vim.trim(result.stdout or "")
end

local function git_version_refs(cwd)
    local result = git_system(cwd, { "show-ref", "--heads", "--tags" })
    if not result or result.code ~= 0 then
        return nil
    end
    return vim.trim(result.stdout or "")
end

local function git_version_stash(cwd)
    local result = git_system(cwd, { "rev-parse", "refs/stash" })
    if not result or result.code ~= 0 then
        return nil
    end
    return vim.trim(result.stdout or "")
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
    }, opts))
    if config.bind then
        config.bind(picker)
    end
    picker:open()
    return picker
end

local function parse_git_status_entry(entry)
    local _, _, filename = entry:find("^..%s+(.+)$")
    assert(filename ~= nil and #filename > 0)
    local arrow_position = filename:find("%s+->%s+")
    if arrow_position then
        filename = filename:sub(arrow_position + 4)
    end
    return {
        filename = filename,
        lnum = 1,
        col = 1,
    }
end

--- Open Git files picker.
--- @param opts GitPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_git_files(opts)
    assert(util.command_is_available("git"))
    opts = util.merge_picker_options({
        cwd = vim.loop.cwd,
        untracked = true,
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
    local convert = converter:get()

    if opts.preview == true then
        opts.preview = Select.BufferPreview.new(nil, convert)
    elseif opts.preview == false or opts.preview == nil then
        opts.preview = false
    end

    local decorators = {}
    if opts.icons ~= false then
        decorators = { Select.IconDecorator.new(convert) }
    end

    local tick_counter = 0
    local command_args = { "ls-files" }
    if opts.untracked then
        table.insert(command_args, "--others")
        table.insert(command_args, "--cached")
        table.insert(command_args, "--exclude-standard")
    end
    local picker = build_git_picker(opts, {
        title = "Gitfiles",
        context = {
            args = command_args,
            cwd = function(picker)
                return assert(resolve_git_root(picker))
            end,
            tick = function(picker)
                if opts.watch == true then
                    local cwd = assert(resolve_git_root(picker))
                    return git_version_status(cwd, opts.untracked) or ""
                end
                tick_counter = tick_counter + 1
                return tick_counter
            end,
        },
        preview = opts.preview,
        decorators = decorators,
        actions = util.build_default_actions(convert, opts),
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
    assert(util.command_is_available("git"))
    opts = util.merge_picker_options({
        cwd = vim.loop.cwd,
        preview = true,
        icons = true,
        watch = false,
    }, opts)

    if opts.cwd == true then
        opts.cwd = vim.loop.cwd
    end

    local converter = Picker.Converter.new(
        parse_git_status_entry,
        Picker.cwd_visitor
    )
    local convert = converter:get()

    if opts.preview == true then
        opts.preview = Select.BufferPreview.new(nil, convert)
    elseif opts.preview == false or opts.preview == nil then
        opts.preview = false
    end

    local decorators = {}
    if opts.icons ~= false then
        decorators = { Select.IconDecorator.new(convert) }
    end

    local tick_counter = 0
    local command_args = {
        "-c", "color.status=false",
        "status", "--porcelain=v1",
    }
    local picker = build_git_picker(opts, {
        title = "Status",
        context = {
            args = command_args,
            cwd = function(picker)
                return assert(resolve_git_root(picker))
            end,
            tick = function(picker)
                if opts.watch == true then
                    local cwd = assert(resolve_git_root(picker))
                    return git_version_status(cwd, true) or ""
                end
                tick_counter = tick_counter + 1
                return tick_counter
            end,
        },
        preview = opts.preview,
        decorators = decorators,
        actions = util.build_default_actions(convert, opts),
        display = function(entry)
            return entry
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
    assert(util.command_is_available("git"))
    opts = util.merge_picker_options({
        cwd = vim.loop.cwd,
        preview = false,
        watch = false,
    }, opts)

    if opts.cwd == true then
        opts.cwd = vim.loop.cwd
    end

    local tick_counter = 0
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
            tick = function(picker)
                if opts.watch == true then
                    local cwd = assert(resolve_git_root(picker))
                    return git_version_refs(cwd) or ""
                end
                tick_counter = tick_counter + 1
                return tick_counter
            end,
        },
    })
end

--- Open Git commits picker.
--- @param opts GitPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_git_commits(opts)
    assert(util.command_is_available("git"))
    opts = util.merge_picker_options({
        cwd = vim.loop.cwd,
        preview = false,
        watch = false,
    }, opts)

    if opts.cwd == true then
        opts.cwd = vim.loop.cwd
    end

    local tick_counter = 0
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
            tick = function(picker)
                if opts.watch == true then
                    local cwd = assert(resolve_git_root(picker))
                    return git_version_refs(cwd) or ""
                end
                tick_counter = tick_counter + 1
                return tick_counter
            end,
        },
    })
end

--- Open Git stash picker.
--- @param opts GitPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_git_stash(opts)
    assert(util.command_is_available("git"))
    opts = util.merge_picker_options({
        cwd = vim.loop.cwd,
        preview = false,
        watch = false,
    }, opts)

    if opts.cwd == true then
        opts.cwd = vim.loop.cwd
    end

    local tick_counter = 0
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
            tick = function(picker)
                if opts.watch == true then
                    local cwd = assert(resolve_git_root(picker))
                    return git_version_stash(cwd) or ""
                end
                tick_counter = tick_counter + 1
                return tick_counter
            end,
        },
    })
end

--- Open Git bcommits picker.
--- @param opts GitPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_git_bcommits(opts)
    assert(util.command_is_available("git"))
    opts = util.merge_picker_options({
        cwd = true,
        preview = false,
        watch = false,
    }, opts)

    if opts.cwd == true then
        opts.cwd = vim.loop.cwd
    end

    local tick_counter = 0
    return build_git_picker(opts, {
        title = "BCommits",
        context = {
            cwd = function(picker)
                return resolve_picker_cwd(picker)
            end,
            args = function(picker)
                local buf = vim.api.nvim_get_current_buf()
                local path = utils.get_bufname(buf)
                path = vim.fs.normalize(assert(path))

                local cwd = resolve_picker_cwd(picker) or ""
                local rel_path = vim.fs.relpath(path, cwd)
                rel_path = rel_path or path

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
            tick = function(picker)
                if opts.watch == true then
                    local cwd = resolve_picker_cwd(picker)
                    return git_version_refs(cwd) or ""
                end
                tick_counter = tick_counter + 1
                return tick_counter
            end,
        },
    })
end

return M
