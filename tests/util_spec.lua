---@diagnostic disable: invisible
local helpers = require("script.test_utils")
local util = require("fuzzy.pickers.util")

local M = { name = "util" }

function M.run()
    helpers.run_test_case("util_resolve_working_directory", function()
        helpers.eq(util.resolve_working_directory("/tmp"), "/tmp", "cwd direct")
        helpers.eq(util.resolve_working_directory(function() return "/tmp" end), "/tmp", "cwd fn")
    end)

    helpers.run_test_case("util_command_pick", function()
        helpers.assert_ok(util.command_is_available("sh"), "command available")
        helpers.assert_ok(not util.command_is_available("definitely-not-a-cmd"), "command missing")
        helpers.eq(util.pick_first_command({ "definitely-not-a-cmd", "sh" }), "sh", "pick_first")
    end)

    helpers.run_test_case("util_build_picker_headers", function()
        local headers = assert(util.build_picker_headers("Title", { cwd = "/tmp" }))
        helpers.assert_ok(type(headers) == "table" and #headers >= 1, "headers table")
        local cwd_block = headers[2]
        helpers.assert_ok(type(cwd_block) == "table", "cwd block")
        local cwd_entry = cwd_block[1]
        helpers.assert_ok(type(cwd_entry) == "function", "cwd header fn")
        helpers.eq(cwd_entry(), "/tmp", "cwd header text")
    end)

    helpers.run_test_case("util_sanitize_display_text", function()
        helpers.eq(util.sanitize_display_text("a\tb\nc"), "a b c", "sanitize")
        helpers.eq(util.sanitize_display_text("   "), " ", "sanitize spaces")
        helpers.eq(util.sanitize_display_text(nil), nil, "sanitize nil")
    end)

    helpers.run_test_case("util_is_under_directory", function()
        helpers.assert_ok(util.is_under_directory(nil, "/a/b"), "no root ok")
        helpers.assert_ok(util.is_under_directory("", "/a/b"), "empty root ok")
        helpers.assert_ok(util.is_under_directory("/a", "/a"), "equal ok")
        helpers.assert_ok(util.is_under_directory("/a", "/a/b"), "prefix ok")
        helpers.assert_ok(not util.is_under_directory("/a", "/ab"), "prefix boundary")
        helpers.assert_ok(util.is_under_directory("/a/", "/a/b"), "prefix slash ok")
    end)

    helpers.run_test_case("util_format_location_entry", function()
        local value = util.format_location_entry("file.txt", 2, 3, "msg", "[x]")
        helpers.assert_ok(value:find("file.txt", 1, true) ~= nil, "location filename")
        helpers.assert_ok(value:find("2:3", 1, true) ~= nil, "location line/col")
        helpers.assert_ok(value:find("msg", 1, true) ~= nil, "location text")
    end)

    helpers.run_test_case("util_format_display_path_basic", function()
        local opts = {
            cwd = vim.uv.cwd(),
            home_to_tilde = true,
            path_shorten = 1,
        }
        local cases = {
            "term://foo",
            "oil:///tmp",
            "fugitive://./.git//HEAD",
            "scp://user@host/path/file",
            "zipfile://some.zip::path",
        }
        for _, value in ipairs(cases) do
            local ok, result = pcall(util.format_display_path, value, opts)
            helpers.assert_ok(ok, "format_display_path threw")
            helpers.assert_ok(type(result) == "string" and #result > 0, "format_display_path empty")
        end
    end)

    helpers.run_test_case("util_format_display_path_strip_cwd", function()
        local cwd = "/tmp/fuzzymatch-root"
        local value = "/tmp/fuzzymatch-root/dir/file.txt"
        local result = util.format_display_path(value, {
            cwd = cwd,
            absolute_path = false,
        })
        helpers.eq(result, "dir/file.txt", "format_display_path strip cwd")
    end)

    helpers.run_test_case("util_format_display_path_non_string_cwd", function()
        local ok, result = pcall(util.format_display_path, "/tmp/file.txt", {
            cwd = true,
            home_to_tilde = true,
        })
        helpers.assert_ok(not ok, "format_display_path should reject non-string cwd")
        helpers.assert_ok(type(result) == "string" and #result > 0, "format_display_path error")
    end)

    helpers.run_test_case("util_format_display_path_home_to_tilde", function()
        local original = vim.uv.os_homedir
        vim.uv.os_homedir = function()
            return "/tmp/home"
        end
        local ok, result = pcall(util.format_display_path, "/tmp/home/file.txt", {
            home_to_tilde = true,
        })
        vim.uv.os_homedir = original
        helpers.assert_ok(ok, "format_display_path threw on home_to_tilde")
        helpers.eq(result, "~/file.txt", "format_display_path home_to_tilde")
    end)

    helpers.run_test_case("util_format_display_path_home_prefix_no_next", function()
        local original = vim.uv.os_homedir
        vim.uv.os_homedir = function()
            return "/tmp/home"
        end
        local ok, result = pcall(util.format_display_path, "/tmp/home", {
            home_to_tilde = true,
        })
        vim.uv.os_homedir = original
        helpers.assert_ok(ok, "format_display_path threw on home exact")
        helpers.eq(result, "/tmp/home", "format_display_path home exact")
    end)

    helpers.run_test_case("util_format_display_path_filename_only", function()
        local ok, result = pcall(util.format_display_path, "/tmp/home/file.txt", {
            filename_only = true,
        })
        helpers.assert_ok(ok, "format_display_path threw on filename_only")
        helpers.eq(result, "file.txt", "format_display_path filename_only")
    end)

    helpers.run_test_case("util_format_display_path_absolute", function()
        local ok, result = pcall(util.format_display_path, "/tmp/home/file.txt", {
            absolute_path = true,
            home_to_tilde = true,
        })
        helpers.assert_ok(ok, "format_display_path threw on absolute")
        helpers.eq(result, "/tmp/home/file.txt", "format_display_path absolute")
    end)

    helpers.run_test_case("util_build_default_actions", function()
        local actions = util.build_default_actions(function(entry) return entry end, {})
        helpers.assert_ok(actions["<cr>"] ~= nil, "default actions")
        helpers.assert_ok(actions["<c-q>"] ~= nil, "default actions qf")
    end)

    helpers.run_test_case("util_merge_picker_options", function()
        local defaults = { a = 1, nested = { x = 1 } }
        local merged = util.merge_picker_options(defaults, { b = 2, nested = { y = 2 } })
        helpers.eq(merged.a, 1, "merge defaults")
        helpers.eq(merged.b, 2, "merge user")
        helpers.eq(merged.nested.x, 1, "merge nested default")
        helpers.eq(merged.nested.y, 2, "merge nested user")
    end)
end

return M
