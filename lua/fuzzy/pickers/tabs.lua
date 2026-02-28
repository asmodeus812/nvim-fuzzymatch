local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")
local utils = require("fuzzy.utils")

--- @class TabsPickerOptions
--- @field tab_marker? string Marker for current tab display
--- @field preview? boolean Enable preview window
--- @field match_step? integer Batch size for matching

local M = {}

--- Open Tabs picker.
--- @param opts TabsPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_tabs_picker(opts)
    opts = util.merge_picker_options({
        filename_only = false,
        path_shorten = nil,
        home_to_tilde = true,
        preview = false,
        match_step = 50000,
    }, opts)

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = function(stream_callback)
            local tabpage_list = vim.api.nvim_list_tabpages() or {}
            for _, tabpage in ipairs(tabpage_list) do
                if not vim.api.nvim_tabpage_is_valid(tabpage) then
                    goto continue
                end
                local file_path = nil
                local window_list = vim.api.nvim_tabpage_list_wins(tabpage)
                local active_window_id = window_list[1]
                local buf = active_window_id
                    and vim.api.nvim_win_get_buf(active_window_id)
                    or nil
                if buf and buf ~= 0 then
                    file_path = utils.get_bufname(
                        buf,
                        nil
                    )
                end
                stream_callback({
                    tabpage = tabpage,
                    file_path = file_path,
                })
                ::continue::
            end
            stream_callback(nil)
        end,
        headers = util.build_picker_headers("Tabs", opts),
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry_value)
                local tabpage = type(entry_value) == "table"
                    and entry_value.tabpage or entry_value
                assert(vim.api.nvim_tabpage_is_valid(tabpage))
                vim.api.nvim_set_current_tabpage(tabpage)
                return false
            end)),
        },
        display = function(entry_value)
            local tabpage = type(entry_value) == "table"
                and entry_value.tabpage or entry_value
            assert(vim.api.nvim_tabpage_is_valid(tabpage))
            local tabpage_index = vim.api.nvim_tabpage_get_number(tabpage)
            local file_path = type(entry_value) == "table"
                and entry_value.file_path or nil
            if not file_path or #file_path == 0 then
                local window_list = vim.api.nvim_tabpage_list_wins(tabpage)
                local active_window_id = window_list[1]
                local buf = active_window_id
                    and vim.api.nvim_win_get_buf(active_window_id)
                    or nil
                file_path = buf
                    and utils.get_bufname(
                        buf,
                        utils.get_bufinfo(buf)
                    )
                    or utils.NO_NAME
            end
            file_path = util.format_display_path(file_path, opts)
            return table.concat({ "[", tabpage_index, "] ", file_path })
        end,
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
