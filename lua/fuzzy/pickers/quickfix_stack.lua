local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class QuickfixStackPickerOptions

local M = {}

--- Open Quickfix stack picker.
--- @param opts QuickfixStackPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_quickfix_stack(opts)
    opts = util.merge_picker_options({
        preview = false,
    }, opts)

    local picker = Picker.new(vim.tbl_extend("force", {
        content = function(stream, args)
            local history_text = args.history_text
            local entries = util.parse_stack_entries(history_text)
            for _, history_entry in ipairs(entries) do
                stream(history_entry)
            end
            stream(nil)
        end,
        headers = util.build_picker_headers("Quickfix Stack", opts),
        context = {
            args = function(_)
                return {
                    history_text = vim.fn.execute("chistory"),
                }
            end,
        },
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry)
                assert(entry and entry.number)
                vim.cmd({ cmd = "chistory", args = { tostring(entry.number) } })
                vim.cmd("copen")
                return false
            end)),
        },
        display = function(entry)
            assert(entry and entry.text)
            return entry.text
        end,
        highlighters = {
            Select.RegexHighlighter.new({
                { "%d+", "Number" },
                { "%f[%a]list%f[%A]", "Keyword" },
            }),
        },
    }, opts, {
        match_timer = 5,
        match_step = 2048,
        stream_step = 4096,
        stream_debounce = 0,
        prompt_debounce = 20,
    }))

    picker:open()
    return picker
end

return M
