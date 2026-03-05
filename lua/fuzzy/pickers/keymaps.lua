local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class KeymapsPickerOptions
--- @field show_desc? boolean Include descriptions in display
--- @field show_details? boolean Include verbose details in display
--- @field preview? boolean Enable preview window

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
                local right_hand_side_text = entry.rhs or ""
                if #right_hand_side_text > 0 then
                    vim.fn.setreg('\"', right_hand_side_text)
                end
                return false
            end)),
        },
        display = function(entry)
            local prefix_text = (entry.buffer == 1) and "[b]" or "[g]"
            local mode_text = entry.mode or "?"
            local right_hand_side_text = entry.rhs or ""
            if opts.max_text
                and #right_hand_side_text > opts.max_text then
                right_hand_side_text = right_hand_side_text:sub(
                    1,
                    opts.max_text
                )
            end
            local description_text = entry.desc or ""
            if #description_text > 0 then
                description_text = table.concat({ " - ", description_text })
            end
            local left_hand_side_text = entry.lhs or ""
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
