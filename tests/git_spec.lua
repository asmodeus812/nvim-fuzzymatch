---@diagnostic disable: invisible
local helpers = require("tests.helpers")
local Picker = require("fuzzy.picker")
local util = require("fuzzy.pickers.util")

local M = { name = "git" }

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
                require("fuzzy.pickers.git").open_git_files({
                    preview = false,
                    icons = false,
                    prompt_debounce = 0,
                    untracked = true,
                })
                local opts = get()
                helpers.eq(opts.content, "git", "content")
                helpers.eq(opts.context.cwd, "/tmp/git-root", "cwd")
                helpers.assert_list_contains(opts.context.args, "ls-files", "args")
                helpers.assert_list_contains(opts.context.args, "--exclude-standard", "args")
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
                require("fuzzy.pickers.git").open_git_status({
                    preview = false,
                    icons = false,
                    prompt_debounce = 0,
                })
                local opts = get()
                helpers.eq(opts.context.cwd, "/tmp/git-root", "cwd")
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
                require("fuzzy.pickers.git").open_git_branches({
                    preview = false,
                    prompt_debounce = 0,
                })
                local opts = get()
                helpers.eq(opts.context.cwd, "/tmp/git-root", "cwd")
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
                require("fuzzy.pickers.git").open_git_commits({
                    preview = false,
                    prompt_debounce = 0,
                })
                local opts = get()
                helpers.eq(opts.context.cwd, "/tmp/git-root", "cwd")
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
                require("fuzzy.pickers.git").open_git_bcommits({
                    preview = false,
                    prompt_debounce = 0,
                })
                local opts = get()
                local cwd_value = opts.context.cwd
                if type(cwd_value) == "function" then
                    cwd_value = cwd_value()
                end
                helpers.eq(cwd_value, dir, "cwd")
                local args_value = opts.context.args
                if type(args_value) == "function" then
                    args_value = args_value()
                end
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
                require("fuzzy.pickers.git").open_git_stash({
                    preview = false,
                    prompt_debounce = 0,
                })
                local opts = get()
                helpers.eq(opts.context.cwd, "/tmp/git-root", "cwd")
                helpers.assert_list_contains(opts.context.args, "stash", "args")
                helpers.assert_list_contains(opts.context.args, "list", "args")
            end)
        end)
    end)
end

return M
