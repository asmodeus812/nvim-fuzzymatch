local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

local M = {}

local function collect_keymap_entries(opts)
    local keymap_entry_list = {}
    local mode_list = opts.modes or { "n" }

    for _, mode_name in ipairs(mode_list) do
        local global_keymap_list = vim.api.nvim_get_keymap(mode_name) or {}
        for _, keymap_entry in ipairs(global_keymap_list) do
            keymap_entry.mode = mode_name
            keymap_entry.buffer = false
            keymap_entry_list[#keymap_entry_list + 1] = keymap_entry
        end

        if opts.include_buffer then
            local buffer_keymap_list = vim.api.nvim_buf_get_keymap(0, mode_name) or {}
            for _, keymap_entry in ipairs(buffer_keymap_list) do
                keymap_entry.mode = mode_name
                keymap_entry.buffer = true
                keymap_entry_list[#keymap_entry_list + 1] = keymap_entry
            end
        end
    end

    return keymap_entry_list
end

function M.open_keymaps_picker(opts)
    opts = util.merge_picker_options({
        reuse = true,
        include_buffer = true,
        modes = { "n" },
        max_text = 120,
        preview = false,
        match_step = 50000,
    }, opts)

    local keymap_entry_list = collect_keymap_entries(opts)

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = keymap_entry_list,
        headers = util.build_picker_headers("Keymaps", opts),
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry_value)
                local right_hand_side_text = entry_value.rhs or ""
                if #right_hand_side_text > 0 then
                    vim.fn.setreg('\"', right_hand_side_text)
                end
                return false
            end)),
        },
        display = function(entry_value)
            local prefix_text = entry_value.buffer and "[b]" or "[g]"
            local mode_text = entry_value.mode or "?"
            local right_hand_side_text = entry_value.rhs or ""
            if opts.max_text
                and #right_hand_side_text > opts.max_text then
                right_hand_side_text = right_hand_side_text:sub(
                    1,
                    opts.max_text
                )
            end
            local description_text = entry_value.desc or ""
            if #description_text > 0 then
                description_text = table.concat({ " - ", description_text })
            end
            local left_hand_side_text = entry_value.lhs or ""
            return table.concat({
                prefix_text,
                " ",
                mode_text,
                " ",
                left_hand_side_text,
                " -> ",
                right_hand_side_text,
                description_text,
            })
        end,
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
