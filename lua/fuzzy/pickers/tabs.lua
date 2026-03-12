local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")
local utils = require("fuzzy.utils")

--- @class TabsPickerOptions
--- @field filename_only? boolean Display only the filename
--- @field path_shorten? number|nil Path shorten value for display
--- @field home_to_tilde? boolean Replace home prefix with ~ in display

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
            for _, tabpage in ipairs(args.items) do
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
                assert(vim.api.nvim_tabpage_is_valid(entry.tabpage))
                vim.api.nvim_set_current_tabpage(entry.tabpage)
                return false
            end)),
        },
        highlighters = {
            Select.RegexHighlighter.new({
                { "^%[[%d]+%]", "Number" },
                { "^%[[%d]+%]%s(.*/)", "Directory", 1 },
                { "([^/]+)$", "Function", 1 },
            }),
        },
        display = function(entry)
            assert(vim.api.nvim_tabpage_is_valid(entry.tabpage))
            local index = vim.api.nvim_tabpage_get_number(entry.tabpage)
            local filename = util.format_display_path(entry.filename, opts)
            return table.concat({ "[", index, "] ", filename })
        end,
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
