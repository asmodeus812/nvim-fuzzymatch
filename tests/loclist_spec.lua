---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "loclist" }

function M.run()
    helpers.run_test_case("loclist", function()
        local buf = helpers.create_named_buffer("loclist.txt", { "alpha", "beta" })
        local item_list = {
            { bufnr = buf, lnum = 1, col = 1, text = "alpha" },
        }
        vim.fn.setloclist(0, {}, "r", { title = "Loclist", items = item_list })
        local loc_info = vim.fn.getloclist(0, { items = 1 })
        if not loc_info or not loc_info.items or #loc_info.items == 0 then
            vim.api.nvim_buf_delete(buf, { force = true })
            return
        end
        local loc_picker = require("fuzzy.pickers.loclist")
        local picker = loc_picker.open_loclist_picker({
            preview = false,
            icons = false,
            prompt_debounce = 0,
        })
        helpers.wait_for_list(picker)
        helpers.wait_for_line_contains(picker, "loclist.txt")
        helpers.wait_for_line_contains(picker, "alpha")
        picker:close()
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    helpers.run_test_case("loclist_cwd_visual", function()
        local dir_path = helpers.create_temp_dir()
        local other_dir = helpers.create_temp_dir()
        local file_one = vim.fs.joinpath(dir_path, "one.txt")
        local file_two = vim.fs.joinpath(other_dir, "two.txt")
        local buf_one = helpers.create_named_buffer(file_one, { "one" })
        local buf_two = helpers.create_named_buffer(file_two, { "two" })

        helpers.with_mock(vim.fn, "getloclist", function()
            return {
                title = "Loclist",
                items = {
                    { bufnr = buf_one, lnum = 1, col = 1, text = "one", filename = file_one },
                    { bufnr = buf_two, lnum = 1, col = 1, text = "two", filename = file_two },
                },
            }
        end, function()
            helpers.with_mock(require("fuzzy.utils"), "get_visual_text", function()
                return "one"
            end, function()
                local loc_picker = require("fuzzy.pickers.loclist")
                local picker = loc_picker.open_loclist_visual({
                    preview = false,
                    icons = false,
                    cwd = dir_path,
                    prompt_debounce = 0,
                })
                helpers.wait_for_list(picker)
                helpers.wait_for_entries(picker)
                helpers.wait_for(function()
                    return helpers.get_query(picker) == "one"
                end, 1500)
                helpers.wait_for_prompt_cursor(picker)
                local entries = helpers.get_entries(picker)
                helpers.eq(#entries, 1, "cwd filtered")
                local entry_name = entries[1].filename or ""
                local expected = vim.fs.normalize(file_one)
                helpers.eq(vim.fs.normalize(entry_name), expected, "cwd include")
                picker:close()
            end)
        end)

        vim.api.nvim_buf_delete(buf_one, { force = true })
        vim.api.nvim_buf_delete(buf_two, { force = true })
    end)
end

return M
