local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class SpellSuggestPickerOptions
--- @field target_word_text? string|nil Override the word under cursor
--- @field suggest_limit_count? integer Maximum number of suggestions

local M = {}

local function find_word_bounds(line_text, cursor_col)
    local start = 0
    while true do
        local match_result_list = vim.fn.matchstrpos(
            line_text,
            "\\k\\+",
            start
        )
        assert(
            match_result_list
            and match_result_list[2] ~= nil
            and match_result_list[2] >= 0
        )
        local match_start = match_result_list[2]
        local match_end = match_result_list[3]
        if cursor_col >= match_start
            and cursor_col < match_end then
            return match_start, match_end
        end
        start = match_end
    end
end

local function replace_cursor_word(word)
    if type(word) ~= "string" or #word == 0 then
        return
    end
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1]
    local col = cursor[2]
    local line = vim.api.nvim_buf_get_lines(
        0,
        row - 1,
        row,
        false
    )[1] or ""
    local start_col, end_col = find_word_bounds(
        line,
        col
    )
    assert(start_col ~= nil and end_col ~= nil)
    vim.api.nvim_buf_set_text(
        0,
        row - 1,
        start_col,
        row - 1,
        end_col,
        { word }
    )
end

local function resolve_target_word(opts)
    local target = opts.target_word_text
    if type(target) ~= "string" or #target == 0 then
        target = vim.fn.expand("<cword>")
    end
    return target
end

--- Open Spell suggest picker.
--- @param opts SpellSuggestPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_spell_suggest(opts)
    opts = util.merge_picker_options({
        target_word_text = nil,
        suggest_limit_count = 25,
        preview = false,
    }, opts)

    local limit = tonumber(opts.suggest_limit_count) or 25
    local headers = util.build_picker_headers("Spell", opts)
    headers = headers or {}
    table.insert(headers, {
        function()
            return resolve_target_word(opts)
        end
    })

    local picker = Picker.new(vim.tbl_extend("force", {
        content = function(stream, args)
            local target = args and args[1] or ""
            local items = {}
            if target and #target > 0 then
                items = vim.fn.spellsuggest(
                    target,
                    limit
                )
            end
            if not items or #items == 0 then
                stream(nil)
                return
            end
            for _, item in ipairs(items) do
                stream(item)
            end
            stream(nil)
        end,
        context = {
            args = function()
                return { resolve_target_word(opts) }
            end,
        },
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
        highlighters = {
            Select.RegexHighlighter.new({
                { "^%S+", "Keyword" },
            }),
        },
    }, opts, {
        match_timer = 5,
        match_step = 1000,
        stream_step = 2000,
        stream_debounce = 0,
        prompt_debounce = 20,
    }))

    picker:open()
    return picker
end

return M
