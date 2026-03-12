---@diagnostic disable: invisible
local helpers = require("script.test_utils")
local util = require("fuzzy.pickers.util")
local M = { name = "manpages" }

function M.run()
    helpers.run_test_case("manpages_basic", function()
        local cmd = util.pick_first_command({ "apropos", "man" })
        if not cmd then
            return
        end
        local args = cmd == "apropos" and { "printf" } or { "-k", "printf" }
        local man_picker = require("fuzzy.pickers.manpages")
        local picker = man_picker.open_manpages_picker({
            preview = false,
            prompt_debounce = 0,
            args = args,
        })
        local results = helpers.wait_for_stream(picker, 5000) or {}
        if type(results) == "table" and #results > 0 then
            helpers.wait_for_list(picker)
        end
        picker:close()
    end)

    helpers.run_test_case("manpages_action", function()
        local cmd = util.pick_first_command({ "apropos", "man" })
        if not cmd then
            return
        end
        local args = cmd == "apropos" and { "printf" } or { "-k", "printf" }
        helpers.with_cmd_capture(function(calls)
            local man_picker = require("fuzzy.pickers.manpages")
            local picker = man_picker.open_manpages_picker({
                preview = false,
                prompt_debounce = 0,
                args = args,
            })
            local results = helpers.wait_for_stream(picker, 5000) or {}
            if type(results) == "table" and #results > 0 then
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
            end
            picker:close()
        end)
    end)
end

return M
