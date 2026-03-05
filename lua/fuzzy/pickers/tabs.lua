local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")
local utils = require("fuzzy.utils")

--- @class TabsPickerOptions
--- @field tab_marker? string Marker for current tab display
--- @field preview? boolean Enable preview window

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
    }, opts)

    local picker = Picker.new(vim.tbl_extend("force", {
        content = function(stream, args)
            local items = args.items
            for _, tabpage in ipairs(items) do
                if not vim.api.nvim_tabpage_is_valid(tabpage) then
                    goto continue
                end
                local window_list = vim.api.nvim_tabpage_list_wins(tabpage)
                local buf = window_list[1] and vim.api.nvim_win_get_buf(window_list[1])
                local filename = buf and buf > 0 and utils.get_bufname(buf) or utils.NO_NAME
                stream({ tabpage = tabpage, filename = filename })
                ::continue::
            end
            stream(nil)
        end,
        headers = util.build_picker_headers("Tabs", opts),
        context = {
            args = function(_)
                return {
                    items = vim.api.nvim_list_tabpages() or {},
                }
            end,
        },
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry)
                local tabpage = entry.tabpage
                assert(vim.api.nvim_tabpage_is_valid(tabpage))
                vim.api.nvim_set_current_tabpage(tabpage)
                return false
            end)),
        },
        display = function(entry)
            local tabpage = assert(entry.tabpage)
            assert(vim.api.nvim_tabpage_is_valid(tabpage))
            local tabpage_index = vim.api.nvim_tabpage_get_number(tabpage)
            local filename = assert(entry.filename)
            filename = util.format_display_path(filename, opts)
            return table.concat({ "[", tabpage_index, "] ", filename })
        end,
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
