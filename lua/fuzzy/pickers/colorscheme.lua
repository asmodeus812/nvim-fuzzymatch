local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class ColorschemePickerOptions
--- @field preview? boolean Enable preview window

local M = {}

local function apply_colorscheme_name(colorscheme_name)
    local ok = pcall(vim.cmd.colorscheme, colorscheme_name)
    assert(ok)
    return true
end

--- Open Colorscheme picker.
--- @param opts ColorschemePickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_colorscheme_picker(opts)
    opts = util.merge_picker_options({
        preview = true,
    }, opts)

    local current_colorscheme_name = vim.g.colors_name or ""
    local preview_state_table = { last = current_colorscheme_name }
    if opts.preview ~= false then
        opts.preview = Select.CustomPreview.new(function(entry)
            if entry ~= preview_state_table.last then
                apply_colorscheme_name(entry)
                preview_state_table.last = entry
            end
            return { string.format("Colorscheme: %s", entry) }
        end)
    else
        opts.preview = false
    end

    local function restore_colorscheme()
        if current_colorscheme_name ~= "" and preview_state_table.last ~= current_colorscheme_name then
            apply_colorscheme_name(current_colorscheme_name)
        end
    end

    local picker = nil
    local actions = {
        ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry_value)
            apply_colorscheme_name(entry_value)
            return false
        end)),
        ["<esc>"] = Select.action(Select.close_view, function()
            restore_colorscheme()
            assert(picker):_cancel_prompt()
        end),
        ["<m-esc>"] = Select.action(Select.close_view, function()
            restore_colorscheme()
            assert(picker):_hide_prompt()
        end),
    }

    picker = Picker.new(vim.tbl_extend("force", {
        content = function(stream_callback, args)
            local colorscheme_name_list = args.items
            for _, colorscheme_name in ipairs(colorscheme_name_list) do
                stream_callback(colorscheme_name)
            end
            stream_callback(nil)
        end,
        headers = util.build_picker_headers("Colorschemes", opts),
        context = {
            args = function(_)
                return {
                    items = vim.fn.getcompletion("", "color") or {},
                }
            end,
        },
        preview = opts.preview,
        actions = actions,
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
