local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")
local utils = require("fuzzy.utils")

local M = {}

function M.open_tabs_picker(opts)
    opts = util.merge_picker_options({
        reuse = true,
        filename_only = false,
        path_shorten = nil,
        home_to_tilde = true,
        preview = false,
        match_step = 50000,
    }, opts)

    local tabpage_list = vim.api.nvim_list_tabpages() or {}

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = tabpage_list,
        headers = util.build_picker_headers("Tabs", opts),
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry_value)
                assert(vim.api.nvim_tabpage_is_valid(entry_value))
                vim.api.nvim_set_current_tabpage(entry_value)
                return false
            end)),
        },
        display = function(entry_value)
            assert(vim.api.nvim_tabpage_is_valid(entry_value))
            local tabpage_index = vim.api.nvim_tabpage_get_number(entry_value)
            local window_list = vim.api.nvim_tabpage_list_wins(entry_value)
            local active_window_id = window_list[1]
            local buf = active_window_id and vim.api.nvim_win_get_buf(active_window_id) or nil
            local file_path = buf
                and utils.get_bufname(buf, utils.get_bufinfo(buf))
                or "[No Name]"
            file_path = util.format_display_path(file_path, opts)
            return table.concat({ "[", tabpage_index, "] ", file_path })
        end,
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
