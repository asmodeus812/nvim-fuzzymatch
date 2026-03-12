---@diagnostic disable: invisible
local helpers = require("script.test_utils")
local excmd = require("fuzzy.pickers.excmd")

local M = { name = "excmd" }

function M.run()
    helpers.run_test_case("excmd_requires_picker_name", function()
        local captured = {}
        helpers.with_mock(vim.api, "nvim_create_user_command", function(name, fn, opts)
            captured.name = name
            captured.fn = fn
            captured.opts = opts
        end, function()
            excmd.register_user_commands("FzmTest")
        end)

        helpers.eq(captured.name, "FzmTest", "command name")
        local warning = nil
        helpers.with_mock(vim, "notify", function(msg)
            warning = msg
        end, function()
            captured.fn({ fargs = {} })
        end)
        helpers.assert_ok(
            warning and warning:find("Usage:", 1, true) ~= nil,
            "missing usage warning"
        )
    end)

    helpers.run_test_case("excmd_parses_values", function()
        local captured = {}
        local cmd_fn = nil
        helpers.with_mock(vim.api, "nvim_create_user_command", function(_, fn)
            cmd_fn = fn
        end, function()
            excmd.register_user_commands("FzmTest")
        end)
        helpers.with_mock(excmd, "open_picker", function(name, opts)
            captured.name = name
            captured.opts = opts
        end, function()
            helpers.with_mock(vim, "notify", function() end, function()
                cmd_fn({
                    fargs = {
                        "grep",
                        "preview=true",
                        "match_step=2000",
                        "args=--hidden,'--iglob=*.lua',foo\\,bar",
                        "env='A=1,B=2'",
                        "prompt_query=\"hello world\"",
                    },
                })
            end)
        end)
        helpers.eq(captured.name, "grep", "picker name")
        helpers.eq(captured.opts.preview, true, "preview bool")
        helpers.eq(captured.opts.match_step, 2000, "match step")
        helpers.eq(captured.opts.args[1], "--hidden", "args[1]")
        helpers.eq(captured.opts.args[2], "--iglob=*.lua", "args[2]")
        helpers.eq(captured.opts.args[3], "foo,bar", "args[3]")
        helpers.eq(captured.opts.env[1], "A=1", "env[1]")
        helpers.eq(captured.opts.env[2], "B=2", "env[2]")
        helpers.eq(captured.opts.prompt_query, "hello world", "prompt query")
    end)

    helpers.run_test_case("excmd_invalid_values_warn", function()
        local captured = {}
        local warnings = {}
        local cmd_fn = nil
        helpers.with_mock(vim.api, "nvim_create_user_command", function(_, fn)
            cmd_fn = fn
        end, function()
            excmd.register_user_commands("FzmTest")
        end)
        helpers.with_mock(excmd, "open_picker", function(name, opts)
            captured.name = name
            captured.opts = opts
        end, function()
            helpers.with_mock(vim, "notify", function(msg)
                warnings[#warnings + 1] = msg
            end, function()
                cmd_fn({ fargs = { "files", "preview=maybe", "unknown=1" } })
            end)
        end)
        helpers.eq(captured.name, "files", "picker name")
        helpers.assert_ok(captured.opts.preview == nil, "invalid preview ignored")
        helpers.assert_ok(#warnings >= 2, "warnings emitted")
    end)

    helpers.run_test_case("excmd_completion", function()
        local cmd_opts = nil
        helpers.with_mock(vim.api, "nvim_create_user_command", function(_, _, opts)
            cmd_opts = opts
        end, function()
            excmd.register_user_commands("FzmTest")
        end)

        local matches = cmd_opts.complete("", "FzmTest files x")
        helpers.assert_ok(vim.tbl_contains(matches, "cwd="), "cwd completion")
        helpers.assert_ok(vim.tbl_contains(matches, "args="), "args completion")

        local preview_matches = cmd_opts.complete("preview=", "FzmTest files preview=")
        helpers.assert_ok(
            vim.tbl_contains(preview_matches, "preview=true"),
            "preview true completion"
        )
        helpers.assert_ok(
            vim.tbl_contains(preview_matches, "preview=false"),
            "preview false completion"
        )

        helpers.with_mock(vim.fn, "getcompletion", function()
            return { "/tmp", "/tmp/foo" }
        end, function()
            local cwd_matches = cmd_opts.complete("cwd=/t", "FzmTest files cwd=/t")
            helpers.assert_ok(
                vim.tbl_contains(cwd_matches, "cwd=/tmp"),
                "cwd path completion"
            )
        end)
    end)
end

return M
