---@diagnostic disable: invisible
local helpers = require("script.test_utils")
local Picker = require("fuzzy.picker")
local util = require("fuzzy.pickers.util")

local M = { name = "git" }

local function reload_git_picker_module()
    package.loaded["fuzzy.pickers.git"] = nil
    return require("fuzzy.pickers.git")
end

local function eval(value, picker)
    if type(value) == "function" then
        return value(picker)
    end
    return value
end

local function capture_picker(callback)
    local captured = nil
    helpers.with_mock(Picker, "new", function(opts)
        captured = opts
        local picker = {
            _options = opts,
            open = function() end,
        }
        return picker
    end, function()
        callback(function()
            return captured
        end)
    end)
end

local function git_cmd(repo, args)
    local cmd = { "git", "-C", repo }
    vim.list_extend(cmd, args)
    local result = vim.system(cmd, { text = true }):wait()
    helpers.assert_ok(result and result.code == 0, "git command failed")
    return result
end

local function init_repo()
    local repo = helpers.create_temp_dir()
    local file_path = vim.fs.joinpath(repo, "file.txt")
    git_cmd(repo, { "init" })
    git_cmd(repo, { "config", "user.name", "Fuzzy Test" })
    git_cmd(repo, { "config", "user.email", "fuzzy@test.local" })
    helpers.write_file(file_path, "alpha\n")
    git_cmd(repo, { "add", "file.txt" })
    git_cmd(repo, { "commit", "-m", "init" })
    return repo, file_path
end

local function tick_value(opts)
    local picker_stub = {
        options = function()
            return opts
        end,
    }
    return eval(opts.context.tick, picker_stub)
end

local function trigger_default_action(action, entry)
    action({
        _list_selection = function()
            return { entry }
        end,
        _close_view = function() end,
    })
end

function M.run()
    helpers.run_test_case("git_files", function()
        helpers.with_mock_map(util, {
            command_is_available = function()
                return true
            end,
            find_git_root = function()
                return "/tmp/git-root"
            end,
        }, function()
            capture_picker(function(get)
                reload_git_picker_module().open_git_files({
                    preview = false,
                    icons = false,
                    prompt_debounce = 0,
                    untracked = true,
                    watch = false,
                })
                local opts = get()
                helpers.eq(opts.content, "git", "content")
                helpers.eq(eval(opts.context.cwd, {
                    options = function()
                        return opts
                    end,
                }), "/tmp/git-root", "cwd")
                helpers.assert_list_contains(opts.context.args, "ls-files", "args")
                helpers.assert_list_contains(opts.context.args, "--exclude-standard", "args")
                local picker_stub = {
                    options = function()
                        return opts
                    end,
                }
                helpers.eq(opts.context.tick, true, "tick shorthand")
            end)
        end)
    end)

    helpers.run_test_case("git_status", function()
        helpers.with_mock_map(util, {
            command_is_available = function()
                return true
            end,
            find_git_root = function()
                return "/tmp/git-root"
            end,
        }, function()
            capture_picker(function(get)
                reload_git_picker_module().open_git_status({
                    preview = false,
                    icons = false,
                    prompt_debounce = 0,
                })
                local opts = get()
                helpers.eq(eval(opts.context.cwd, {
                    options = function()
                        return opts
                    end,
                }), "/tmp/git-root", "cwd")
                helpers.assert_list_contains(opts.context.args, "status", "args")
                helpers.assert_list_contains(opts.context.args, "--porcelain=v1", "args")
            end)
        end)
    end)

    helpers.run_test_case("git_branches", function()
        helpers.with_mock_map(util, {
            command_is_available = function()
                return true
            end,
            find_git_root = function()
                return "/tmp/git-root"
            end,
        }, function()
            capture_picker(function(get)
                reload_git_picker_module().open_git_branches({
                    preview = false,
                    prompt_debounce = 0,
                })
                local opts = get()
                helpers.eq(eval(opts.context.cwd, {
                    options = function()
                        return opts
                    end,
                }), "/tmp/git-root", "cwd")
                helpers.assert_list_contains(opts.context.args, "branch", "args")
                helpers.assert_list_contains(opts.context.args, "--all", "args")
            end)
        end)
    end)

    helpers.run_test_case("git_commits", function()
        helpers.with_mock_map(util, {
            command_is_available = function()
                return true
            end,
            find_git_root = function()
                return "/tmp/git-root"
            end,
        }, function()
            capture_picker(function(get)
                reload_git_picker_module().open_git_commits({
                    preview = false,
                    prompt_debounce = 0,
                })
                local opts = get()
                helpers.eq(eval(opts.context.cwd, {
                    options = function()
                        return opts
                    end,
                }), "/tmp/git-root", "cwd")
                helpers.assert_list_contains(opts.context.args, "log", "args")
            end)
        end)
    end)

    helpers.run_test_case("git_bcommits", function()
        local dir = helpers.create_temp_dir()
        local file_path = vim.fs.joinpath(dir, "file.txt")
        helpers.write_file(file_path, "data")
        local buf = helpers.create_named_buffer(file_path, { "line" })
        vim.api.nvim_set_current_buf(buf)

        helpers.with_mock_map(util, {
            command_is_available = function()
                return true
            end,
            find_git_root = function()
                return dir
            end,
        }, function()
            capture_picker(function(get)
                reload_git_picker_module().open_git_bcommits({
                    preview = false,
                    prompt_debounce = 0,
                })
                local opts = get()
                local picker_stub = {
                    options = function()
                        return opts
                    end,
                }
                helpers.eq(eval(opts.context.cwd, picker_stub), dir, "cwd")
                local args_value = eval(opts.context.args, picker_stub)
                helpers.assert_list_contains(args_value, "log", "args")
                helpers.assert_list_contains(args_value, "--", "args")
                local found = false
                for _, value in ipairs(args_value) do
                    if value == "file.txt" or value == file_path then
                        found = true
                        break
                    end
                end
                helpers.assert_ok(found, "path")
            end)
        end)

        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    helpers.run_test_case("git_stash", function()
        helpers.with_mock_map(util, {
            command_is_available = function()
                return true
            end,
            find_git_root = function()
                return "/tmp/git-root"
            end,
        }, function()
            capture_picker(function(get)
                reload_git_picker_module().open_git_stash({
                    preview = false,
                    prompt_debounce = 0,
                })
                local opts = get()
                helpers.eq(eval(opts.context.cwd, {
                    options = function()
                        return opts
                    end,
                }), "/tmp/git-root", "cwd")
                helpers.assert_list_contains(opts.context.args, "stash", "args")
                helpers.assert_list_contains(opts.context.args, "list", "args")
            end)
        end)
    end)

    helpers.run_test_case("git_branches_action_checkout", function()
        local repo, _ = init_repo()
        git_cmd(repo, { "branch", "feature/test" })
        capture_picker(function(get)
            reload_git_picker_module().open_git_branches({
                cwd = repo,
                preview = false,
            })
            local opts = get()
            local action = assert(opts.actions["<cr>"])[1]
            trigger_default_action(action, "feature/test 1234567 init <Fuzzy Test>")
            local head = vim.trim(git_cmd(repo, { "branch", "--show-current" }).stdout or "")
            helpers.eq(head, "feature/test", "branch checkout")
        end)
    end)

    helpers.run_test_case("git_commits_action_checkout", function()
        local repo, _ = init_repo()
        capture_picker(function(get)
            reload_git_picker_module().open_git_commits({
                cwd = repo,
                preview = false,
            })
            local opts = get()
            local action = assert(opts.actions["<cr>"])[1]
            local hash = vim.trim(git_cmd(repo, { "rev-parse", "--short", "HEAD" }).stdout or "")
            trigger_default_action(action, table.concat({ hash, " now init <Fuzzy Test>" }))
            local checked = vim.trim(git_cmd(repo, { "rev-parse", "--short", "HEAD" }).stdout or "")
            helpers.eq(checked, hash, "commit checkout")
        end)
    end)

    helpers.run_test_case("git_bcommits_action_checkout", function()
        local repo, file_path = init_repo()
        local buf = helpers.create_named_buffer(file_path, { "alpha" })
        vim.api.nvim_set_current_buf(buf)
        capture_picker(function(get)
            reload_git_picker_module().open_git_bcommits({
                cwd = repo,
                preview = false,
            })
            local opts = get()
            local action = assert(opts.actions["<cr>"])[1]
            local hash = vim.trim(git_cmd(repo, { "rev-parse", "--short", "HEAD" }).stdout or "")
            trigger_default_action(action, table.concat({ hash, " now init <Fuzzy Test>" }))
            local checked = vim.trim(git_cmd(repo, { "rev-parse", "--short", "HEAD" }).stdout or "")
            helpers.eq(checked, hash, "bcommit checkout")
        end)
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    helpers.run_test_case("git_stash_action_unstash", function()
        local repo, file_path = init_repo()
        helpers.write_file(file_path, "alpha\nbeta\n")
        git_cmd(repo, { "add", "file.txt" })
        git_cmd(repo, { "stash", "push", "-m", "save" })
        capture_picker(function(get)
            reload_git_picker_module().open_git_stash({
                cwd = repo,
                preview = false,
            })
            local opts = get()
            local action = assert(opts.actions["<cr>"])[1]
            trigger_default_action(action, "stash@{0}: On main: save")
            local status = vim.trim(git_cmd(repo, { "status", "--short" }).stdout or "")
            helpers.assert_ok(status:find("file.txt", 1, true) ~= nil, "stash popped")
        end)
    end)

    helpers.run_test_case("git_tick_watch_true", function()
        if not util.command_is_available("git") then
            return
        end

        local repo = helpers.create_temp_dir()
        local file_path = vim.fs.joinpath(repo, "file.txt")

        local function git_cmd(args)
            local cmd = { "git", "-C", repo }
            vim.list_extend(cmd, args)
            local result = vim.system(cmd, { text = true }):wait()
            helpers.assert_ok(result and result.code == 0, "git command failed")
            return result
        end

        git_cmd({ "init" })
        git_cmd({ "config", "user.name", "Fuzzy Test" })
        git_cmd({ "config", "user.email", "fuzzy@test.local" })
        helpers.write_file(file_path, "alpha\n")
        git_cmd({ "add", "file.txt" })
        git_cmd({ "commit", "-m", "init" })

        helpers.with_cwd(repo, function()
            capture_picker(function(get)
                reload_git_picker_module().open_git_status({
                    preview = false,
                    icons = false,
                    prompt_debounce = 0,
                    watch = true,
                })
                local opts = get()
                local picker_stub = {
                    options = function()
                        return opts
                    end,
                }
                local tick1 = eval(opts.context.tick, picker_stub)
                helpers.write_file(file_path, "alpha\nbeta\n")
                local tick2 = eval(opts.context.tick, picker_stub)
                helpers.assert_ok(tick2 ~= tick1, "tick changes after git status update")
            end)
        end)
    end)

    helpers.run_test_case("git_files_watch_true", function()
        if not util.command_is_available("git") then
            return
        end
        local repo, _ = init_repo()
        capture_picker(function(get)
            reload_git_picker_module().open_git_files({
                cwd = repo,
                preview = false,
                icons = false,
                untracked = true,
                watch = true,
            })
            local opts = get()
            local tick1 = tick_value(opts)
            helpers.write_file(vim.fs.joinpath(repo, "new.txt"), "new\n")
            local tick2 = tick_value(opts)
            helpers.assert_ok(tick2 ~= tick1, "git_files tick changes")
        end)
    end)

    helpers.run_test_case("git_status_watch_true", function()
        if not util.command_is_available("git") then
            return
        end
        local repo, file_path = init_repo()
        capture_picker(function(get)
            reload_git_picker_module().open_git_status({
                cwd = repo,
                preview = false,
                icons = false,
                watch = true,
            })
            local opts = get()
            local tick1 = tick_value(opts)
            helpers.write_file(file_path, "alpha\nbeta\n")
            local tick2 = tick_value(opts)
            helpers.assert_ok(tick2 ~= tick1, "git_status tick changes")
        end)
    end)

    helpers.run_test_case("git_branches_watch_true", function()
        if not util.command_is_available("git") then
            return
        end
        local repo, _ = init_repo()
        capture_picker(function(get)
            reload_git_picker_module().open_git_branches({
                cwd = repo,
                watch = true,
            })
            local opts = get()
            local tick1 = tick_value(opts)
            git_cmd(repo, { "checkout", "-b", "feature/test" })
            local tick2 = tick_value(opts)
            helpers.assert_ok(tick2 ~= tick1, "git_branches tick changes")
        end)
    end)

    helpers.run_test_case("git_commits_watch_true", function()
        if not util.command_is_available("git") then
            return
        end
        local repo, file_path = init_repo()
        capture_picker(function(get)
            reload_git_picker_module().open_git_commits({
                cwd = repo,
                watch = true,
            })
            local opts = get()
            local tick1 = tick_value(opts)
            helpers.write_file(file_path, "alpha\nbeta\n")
            git_cmd(repo, { "add", "file.txt" })
            git_cmd(repo, { "commit", "-m", "update" })
            local tick2 = tick_value(opts)
            helpers.assert_ok(tick2 ~= tick1, "git_commits tick changes")
        end)
    end)

    helpers.run_test_case("git_bcommits_watch_true", function()
        if not util.command_is_available("git") then
            return
        end
        local repo, file_path = init_repo()
        local buf = helpers.create_named_buffer(file_path, { "line" })
        vim.api.nvim_set_current_buf(buf)

        capture_picker(function(get)
            reload_git_picker_module().open_git_bcommits({
                cwd = repo,
                watch = true,
            })
            local opts = get()
            local tick1 = tick_value(opts)
            helpers.write_file(file_path, "alpha\nbeta\n")
            git_cmd(repo, { "add", "file.txt" })
            git_cmd(repo, { "commit", "-m", "update" })
            local tick2 = tick_value(opts)
            helpers.assert_ok(tick2 ~= tick1, "git_bcommits tick changes")
        end)

        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    helpers.run_test_case("git_stash_watch_true", function()
        if not util.command_is_available("git") then
            return
        end
        local repo, file_path = init_repo()
        capture_picker(function(get)
            reload_git_picker_module().open_git_stash({
                cwd = repo,
                watch = true,
            })
            local opts = get()
            local tick1 = tick_value(opts)
            helpers.write_file(file_path, "alpha\nbeta\n")
            git_cmd(repo, { "add", "file.txt" })
            git_cmd(repo, { "stash", "push", "-m", "save" })
            local tick2 = tick_value(opts)
            helpers.assert_ok(tick2 ~= tick1, "git_stash tick changes")
        end)
    end)

    helpers.run_test_case("git_status_watch_true_nochange", function()
        if not util.command_is_available("git") then
            return
        end
        local repo, _ = init_repo()
        capture_picker(function(get)
            reload_git_picker_module().open_git_status({
                cwd = repo,
                preview = false,
                icons = false,
                watch = true,
            })
            local opts = get()
            local tick1 = tick_value(opts)
            local tick2 = tick_value(opts)
            helpers.eq(tick2, tick1, "git_status tick stable")
        end)
    end)

    helpers.run_test_case("git_stash_watch_true_nochange", function()
        if not util.command_is_available("git") then
            return
        end
        local repo, _ = init_repo()
        capture_picker(function(get)
            reload_git_picker_module().open_git_stash({
                cwd = repo,
                watch = true,
            })
            local opts = get()
            local tick1 = tick_value(opts)
            local tick2 = tick_value(opts)
            helpers.eq(tick2, tick1, "git_stash tick stable")
        end)
    end)
end

return M
