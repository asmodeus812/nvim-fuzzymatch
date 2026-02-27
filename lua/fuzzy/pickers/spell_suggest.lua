local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

local M = {}

local function find_word_bounds(line_text_value, cursor_col_number)
    local search_start_number = 0
    while true do
        local match_result_list = vim.fn.matchstrpos(
            line_text_value,
            "\\k\\+",
            search_start_number
        )
        if not match_result_list
            or match_result_list[2] == nil
            or match_result_list[2] < 0 then
            return nil, nil
        end
        local match_start_number = match_result_list[2]
        local match_end_number = match_result_list[3]
        if cursor_col_number >= match_start_number
            and cursor_col_number < match_end_number then
            return match_start_number, match_end_number
        end
        search_start_number = match_end_number
    end
end

local function replace_cursor_word(word_text_value)
    if type(word_text_value) ~= "string" or #word_text_value == 0 then
        return
    end
    local cursor_position_list = vim.api.nvim_win_get_cursor(0)
    local cursor_row_number = cursor_position_list[1]
    local cursor_col_number = cursor_position_list[2]
    local line_text_value = vim.api.nvim_buf_get_lines(
        0,
        cursor_row_number - 1,
        cursor_row_number,
        false
    )[1] or ""
    local start_col_number, end_col_number = find_word_bounds(
        line_text_value,
        cursor_col_number
    )
    if not start_col_number then
        return
    end
    vim.api.nvim_buf_set_text(
        0,
        cursor_row_number - 1,
        start_col_number,
        cursor_row_number - 1,
        end_col_number,
        { word_text_value }
    )
end

function M.open_spell_suggest(opts)
    opts = util.merge_picker_options({
        reuse = true,
        target_word_text = nil,
        suggest_limit_count = 25,
        preview = false,
    }, opts)

    local target = opts.target_word_text
    if type(target) ~= "string" or #target == 0 then
        target = vim.fn.expand("<cword>")
    end
    local limit = tonumber(opts.suggest_limit_count) or 25
    local items = {}
    if type(target) == "string" and #target > 0 then
        items = vim.fn.spellsuggest(
            target,
            limit
        )
    end

    if not items or #items == 0 then
        return util.open_empty_picker(
            "No spell suggestions.",
            opts
        )
    end

    local headers = util.build_picker_headers(
        "Spell",
        opts
    )
    if type(target) == "string" and #target > 0 then
        headers = headers or {}
        table.insert(headers, { target })
    end

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = items,
        headers = headers,
        preview = false,
        actions = {
            ["<cr>"] = Select.action(
                Select.default_select,
                function(selection_list)
                    local selected = selection_list and selection_list[1]
                    replace_cursor_word(selected)
                end
            ),
        },
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
