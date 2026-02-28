---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "marks" }

function M.run()
    helpers.run_test_case("marks", function()
        local buf = helpers.create_named_buffer("marks.txt", {
            "mark one",
            "mark two",
        })
        vim.api.nvim_set_current_buf(buf)
        vim.api.nvim_buf_set_mark(buf, "a", 1, 0, {})
        local buffer_mark_list = {
            { mark = "a", pos = { buf, 1, 0, 0 }, file = "" },
        }
        helpers.with_mock(vim.fn, "getmarklist", function(bufnr)
            if bufnr == 0 then
                return buffer_mark_list
            end
            return {}
        end, function()
            local marks_picker = require("fuzzy.pickers.marks")
            local picker = marks_picker.open_marks_picker({
                preview = false,
                icons = false,
                prompt_debounce = 0,
            })
            helpers.wait_for_list(picker)
            helpers.wait_for_line_contains(picker, "[a]")
            helpers.wait_for_line_contains(picker, "marks.txt")
            picker:close()
        end)

        vim.api.nvim_buf_delete(buf, { force = true })
    end)
end

return M
