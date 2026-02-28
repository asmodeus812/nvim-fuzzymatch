---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "spell_suggest" }

local function set_cursor(row, col)
    vim.api.nvim_win_set_cursor(0, { row, col })
end

function M.run()
    helpers.run_test_case("spell_suggest", function()
        local buf = helpers.create_named_buffer("spell.txt", {
            "helo world",
        })
        vim.api.nvim_set_current_buf(buf)
        set_cursor(1, 1)

        helpers.with_mock_map(vim.fn, {
            expand = function()
                return "helo"
            end,
            spellsuggest = function(word, _)
                if word ~= "helo" then
                    error("unexpected word")
                end
                return { "hello", "help" }
            end,
        }, function()
            local picker = require("fuzzy.pickers.spell_suggest").open_spell_suggest({
                preview = false,
                prompt_debounce = 0,
            })
            helpers.wait_for_list(picker)
            helpers.wait_for_line_contains(picker, "hello")

            local action = picker.select._options.mappings["<cr>"]
            helpers.wait_for_entries(picker)
            action(picker.select)

            local line = helpers.get_buffer_lines(buf, 0, 1)[1] or ""
            helpers.eq(line, "hello world", "replace")
            helpers.close_picker(picker)
        end)

        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    helpers.run_test_case("spell_suggest_target", function()
        helpers.with_mock_map(vim.fn, {
            expand = function()
                error("expand called")
            end,
            spellsuggest = function(word, _)
                helpers.eq(word, "wrng", "target")
                return { "wrong" }
            end,
        }, function()
            local picker = require("fuzzy.pickers.spell_suggest").open_spell_suggest({
                target_word_text = "wrng",
                preview = false,
                prompt_debounce = 0,
            })
            helpers.wait_for_list(picker)
            helpers.wait_for_line_contains(picker, "wrong")
            picker:close()
        end)
    end)
end

return M
