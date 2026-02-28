local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class ColorschemePickerOptions
--- @field preview? boolean Enable preview window
--- @field match_step? integer Match batch size

local M = {}

local function apply_colorscheme_name(colorscheme_name)
    assert(type(colorscheme_name) == "string" and #colorscheme_name > 0)
    local ok = pcall(vim.cmd.colorscheme, colorscheme_name)
    assert(ok)
    return true
end

--- Open Colorscheme picker.
--- @param opts ColorschemePickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_colorscheme_picker(opts)
    opts = util.merge_picker_options({        live_preview = false,
        preview = true,
        prompt_query = "",
        match_step = 50000,
    }, opts)

    local current_colorscheme_name = vim.g.colors_name or ""
    local preview_state_table = { last = current_colorscheme_name }
    local colorscheme_name_list = vim.fn.getcompletion("", "color") or {}

    --- @type table|false
    local preview_instance_object = false
    if opts.preview ~= false then
        preview_instance_object = Select.CustomPreview.new(function(entry_value, buffer_id, _)
            assert(type(entry_value) == "string" and #entry_value > 0)
            if opts.live_preview
                and entry_value ~= preview_state_table.last then
                apply_colorscheme_name(entry_value)
                preview_state_table.last = entry_value
            end
            vim.api.nvim_buf_set_lines(buffer_id, 0, -1, false, {
                "Colorscheme:",
                entry_value,
                "",
                "Preview is global.",
            })
        end)
    end

    local function restore_colorscheme()
        if current_colorscheme_name ~= ""
            and preview_state_table.last ~= current_colorscheme_name then
            apply_colorscheme_name(current_colorscheme_name)
        end
    end

    local action_map_table = {
        ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry_value)
            apply_colorscheme_name(entry_value)
            return false
        end)),
        ["<esc>"] = Select.action(Select.close_view, function()
            restore_colorscheme()
        end),
        ["<m-esc>"] = Select.action(Select.close_view, function()
            restore_colorscheme()
        end),
    }

    if opts.actions then
        action_map_table = vim.tbl_deep_extend(
            "force",
            action_map_table,
            opts.actions
        )
    end

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = colorscheme_name_list,
        headers = util.build_picker_headers("Colorschemes", opts),
        preview = preview_instance_object,
        actions = action_map_table,
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
