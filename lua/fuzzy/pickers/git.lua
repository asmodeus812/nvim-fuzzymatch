local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")
local utils = require("fuzzy.utils")
local GIT_ROOT_CACHE = {}

--- @class GitPickerOptions
--- @field cwd? boolean|string|fun(): string Working directory for git commands; `true` resolves to `vim.loop.cwd`
--- @field preview? boolean|Select.Preview Enable preview window or provide a custom previewer
--- @field icons? boolean Enable file icons
--- @field actions? table Custom action map
--- @field untracked? boolean Include untracked files (git files)
--- @field watch? boolean Refresh on reopen when git state changes

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

local function git_execute_args(cwd, args)
    local result = git_system(cwd, args)
    if not result or result.code ~= 0 then
        return false
    end
    return true
end

local function resolve_picker_cwd(source)
    local opts = source or {}
    if type(opts.options) == "function" then
        opts = opts:options() or {}
    end
    return util.resolve_working_directory(opts.cwd)
end

local function resolve_git_root(source)
    local cwd = resolve_picker_cwd(source)
    if type(cwd) ~= "string" or #cwd == 0 then
        return nil
    end
    local normalized_cwd = vim.fs.normalize(cwd)
    if GIT_ROOT_CACHE[normalized_cwd] == nil then
        GIT_ROOT_CACHE[normalized_cwd] = util.find_git_root(normalized_cwd) or false
    end
    return GIT_ROOT_CACHE[normalized_cwd] or nil
end

local function build_git_picker(opts, config)
    local picker = Picker.new(vim.tbl_extend("force", {
        preview = config.preview == nil and false or config.preview,
        headers = util.build_picker_headers(config.title, opts),
        content = config.content or "git",
        context = assert(config.context),
        decorators = config.decorators,
        display = config.display,
        actions = config.actions,
    }, opts))

    picker:open()
    return picker
end

local function build_git_default_action(label, callback)
    return {
        Select.action(Select.default_select, Select.first(callback)),
        label,
    }
end

local function build_git_tick(opts, callback)
    local tick_counter = 0
    return function(picker)
        if opts.watch == true then
            return callback(picker) or ""
        end
        tick_counter = tick_counter + 1
        return tick_counter
    end
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

local function parse_git_branch_entry(entry)
    local branch = vim.trim((entry or ""):gsub("^%*", "", 1))
    return branch:match("^(%S+)")
end

local function parse_git_commit_entry(entry)
    return (entry or ""):match("^(%S+)")
end

local function parse_git_stash_entry(entry)
    return (entry or ""):match("^(stash@{%d+})")
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
            tick = build_git_tick(opts, function(picker)
                local cwd = assert(resolve_git_root(picker))
                return git_version_status(cwd, opts.untracked)
            end),
        },
        preview = opts.preview,
        decorators = decorators,
        actions = util.build_default_actions(convert, opts),
    })
    converter:bind(picker)
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
            tick = build_git_tick(opts, function(picker)
                local cwd = assert(resolve_git_root(picker))
                return git_version_status(cwd, true)
            end),
        },
        preview = opts.preview,
        decorators = decorators,
        actions = util.build_default_actions(convert, opts),
        display = function(entry) return entry end,
    })
    converter:bind(picker)
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
            tick = build_git_tick(opts, function(picker)
                local cwd = assert(resolve_git_root(picker))
                return git_version_refs(cwd)
            end),
        },
        actions = {
            ["<cr>"] = build_git_default_action("checkout", function(entry)
                local branch = parse_git_branch_entry(entry)
                if branch == nil then return false end

                return git_execute_args(
                    assert(resolve_git_root(opts)),
                    { "checkout", branch }
                )
            end),
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
            tick = build_git_tick(opts, function(picker)
                local cwd = assert(resolve_git_root(picker))
                return git_version_refs(cwd)
            end),
        },
        actions = {
            ["<cr>"] = build_git_default_action("checkout", function(entry)
                local commit = parse_git_commit_entry(entry)
                if commit == nil then return false end

                return git_execute_args(
                    assert(resolve_git_root(opts)),
                    { "checkout", commit }
                )
            end),
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
            tick = build_git_tick(opts, function(picker)
                local cwd = assert(resolve_git_root(picker))
                return git_version_stash(cwd)
            end),
        },
        actions = {
            ["<cr>"] = build_git_default_action("unstash", function(entry)
                local stash_ref = parse_git_stash_entry(entry)
                if stash_ref == nil then return false end

                return git_execute_args(
                    assert(resolve_git_root(opts)),
                    { "stash", "pop", stash_ref }
                )
            end),
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

    return build_git_picker(opts, {
        title = "BCommits",
        context = {
            cwd = function(picker)
                return assert(resolve_git_root(picker))
            end,
            args = function(picker)
                local buf = vim.api.nvim_get_current_buf()
                local path = utils.get_bufname(buf)
                path = vim.fs.normalize(assert(path))

                local git_root = assert(resolve_git_root(picker))
                local rel_path = vim.fs.relpath(path, git_root)
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
            tick = build_git_tick(opts, function(picker)
                local cwd = assert(resolve_git_root(picker))
                return git_version_refs(cwd)
            end),
        },
        actions = {
            ["<cr>"] = build_git_default_action("checkout", function(entry)
                local commit = parse_git_commit_entry(entry)
                if commit == nil then return false end

                return git_execute_args(
                    assert(resolve_git_root(opts)),
                    { "checkout", commit }
                )
            end),
        },
    })
end

return M
