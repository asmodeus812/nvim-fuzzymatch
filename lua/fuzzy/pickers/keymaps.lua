local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class KeymapsPickerOptions
--- @field include_buffer? boolean Include buffer-local keymaps
--- @field modes? string[] Modes to include
--- @field max_text? integer Maximum displayed rhs width before truncation

local M = {}

--- Open Keymaps picker.
--- @param opts KeymapsPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_keymaps_picker(opts)
    opts = util.merge_picker_options({
        include_buffer = true,
        modes = { "n" },
        max_text = 120,
        preview = false,
    }, opts)

    local picker = Picker.new(vim.tbl_extend("force", {
        content = function(stream, args)
            for _, mode_entry in ipairs(args.items) do
                local mode_name = mode_entry.mode
                local global_keymap_list = vim.api.nvim_get_keymap(mode_name) or {}
                for _, keymap_entry in ipairs(global_keymap_list) do
                    keymap_entry.mode = mode_name
                    keymap_entry.buffer = 0
                    stream(keymap_entry)
                end

                if args.include_buffer then
                    local buffer_keymap_list = vim.api.nvim_buf_get_keymap(args.buf, mode_name) or {}
                    for _, keymap_entry in ipairs(buffer_keymap_list) do
                        keymap_entry.mode = mode_name
                        keymap_entry.buffer = 1
                        stream(keymap_entry)
                    end
                end
            end
            stream(nil)
        end,
        headers = util.build_picker_headers("Keymaps", opts),
        context = {
            args = function(_)
                local items = {}
                local mode_list = opts.modes or { "n" }
                local buf = vim.api.nvim_get_current_buf()
                for _, mode_name in ipairs(mode_list) do
                    items[#items + 1] = {
                        mode = mode_name,
                        global_sig = vim.fn["fuzzymatch#getmapsig"](mode_name, 0),
                        buffer_sig = opts.include_buffer
                            and vim.fn["fuzzymatch#getmapsig"](mode_name, buf)
                            or {},
                    }
                end
                return {
                    include_buffer = opts.include_buffer,
                    items = items,
                    buf = buf,
                }
            end,
        },
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry)
                local rhs = entry.rhs or ""
                if #rhs > 0 then
                    vim.fn.setreg('\"', rhs)
                end
                return false
            end)),
        },
        highlighters = {
            Select.RegexHighlighter.new({
                { "^%[[bg]%]", "Number" },
                { "^%[[bg]%]%s(%S+)", "Keyword", 1 },
                { "%s(%S+)%s%-%>", "Function", 1 },
                { "%-%>%s(%S+)", "String", 1 },
                { "%-%>", "Operator" },
                { "%s%-%s(.+)$", "Comment", 1 },
            }),
        },
        display = function(entry)
            local prefix = entry.buffer == 1 and "[b]" or "[g]"
            local mode = entry.mode or "?"
            local rhs = entry.rhs or ""
            if opts.max_text and #rhs > opts.max_text then
                rhs = rhs:sub(1, opts.max_text)
            end
            local desc = entry.desc or ""
            if #desc > 0 then
                desc = " - " .. desc
            end
            local lhs = entry.lhs or ""
            return table.concat({
                prefix,
                " ",
                mode,
                " ",
                lhs,
                " -> ",
                rhs,
                desc,
            })
        end,
    }, opts, {
        match_timer = 10,
        match_step = 5000,
        stream_step = 10000,
        stream_debounce = 0,
        prompt_debounce = 30,
    }))

    picker:open()
    return picker
end

return M
