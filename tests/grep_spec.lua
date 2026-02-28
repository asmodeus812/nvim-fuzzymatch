---@diagnostic disable: invisible
local helpers = require("tests.helpers")
local util = require("fuzzy.pickers.util")

local M = { name = "grep" }

function M.run()
    helpers.run_test_case("grep", function()
        local has_rg = util.command_is_available("rg")
        local has_grep = util.command_is_available("grep")
        if not has_rg and not has_grep then
            return
        end

        local dir_path = helpers.create_temp_dir()
        helpers.write_file(vim.fs.joinpath(dir_path, "alpha.txt"), {
            "first line",
            "needle match",
            "last line",
        })

        helpers.with_cwd(dir_path, function()
            local grep_picker = require("fuzzy.pickers.grep")
            local picker = grep_picker.open_grep_picker({
                cwd = dir_path,
                preview = false,
                icons = false,
                prompt_debounce = 0,
                rg_glob = false,
                rg_opts = has_rg and table.concat({
                    "--column",
                    "--line-number",
                    "--no-heading",
                    "--color=never",
                    "--smart-case",
                }, " ") or nil,
                grep_opts = has_grep and "-n -H -r --line-buffered" or nil,
            })

            local prompt_input = picker.select._options.prompt_input
            prompt_input("needle")
            helpers.wait_for_list(picker)
            helpers.wait_for_line_contains(picker, "alpha.txt")
            helpers.wait_for_line_contains(picker, "needle match")

            prompt_input("first")
            helpers.wait_for_line_contains(picker, "first line")
            picker:close()
        end)
    end)
end

return M
