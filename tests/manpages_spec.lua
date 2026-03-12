---@diagnostic disable: invisible
local helpers = require("script.test_utils")
local M = { name = "manpages" }

function M.run()
    helpers.run_test_case("manpages_basic", function()
        local man_picker = require("fuzzy.pickers.manpages")
        local picker = man_picker.open_manpages_picker({
            preview = false,
            prompt_debounce = 0,
            command = "printf",
            command_args = {
                "printf (3) - formatted output conversion\nls (1) - list directory contents\n",
            },
        })
        helpers.wait_for_stream(picker)
        helpers.type_query(picker, "printf")
        helpers.wait_for_stream(picker)
        helpers.wait_for_match(picker)
        helpers.assert_ok(helpers.wait_for_line_contains(picker, "printf(3)"), "printf entry")
        picker:close()
    end)

    helpers.run_test_case("manpages_action", function()
        helpers.with_cmd_capture(function(calls)
            local man_picker = require("fuzzy.pickers.manpages")
            local picker = man_picker.open_manpages_picker({
                preview = false,
                prompt_debounce = 0,
                command = "printf",
                command_args = { "manpage (1) - test\n" },
            })
            helpers.wait_for_stream(picker)
            helpers.wait_for_list(picker)
            helpers.wait_for_entries(picker)
            local map = picker.select:options().mappings
            map["<cr>"](picker.select)
            local saw_man = false
            for _, call in ipairs(calls) do
                local arg = call.args and call.args[1] or nil
                if type(arg) == "table" and arg.cmd == "Man" then
                    saw_man = true
                end
            end
            helpers.assert_ok(saw_man, "man cmd")
        end)
    end)
end

return M
