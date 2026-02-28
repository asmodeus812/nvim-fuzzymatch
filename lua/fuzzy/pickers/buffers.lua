local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local utils = require("fuzzy.utils")
local util = require("fuzzy.pickers.util")

--- @class BuffersPickerOptions
--- @field current_tab? boolean Restrict to buffers in the current tabpage
--- @field show_unlisted? boolean Include unlisted buffers
--- @field show_unloaded? boolean Include unloaded buffers
--- @field no_term_buffers? boolean Exclude terminal buffers
--- @field ignore_current_buffer? boolean Exclude the current buffer
--- @field sort_lastused? boolean Sort by last used, current/alternate pinned
--- @field filename_only? boolean Display only the filename
--- @field path_shorten? number|nil Path shorten value for display
--- @field home_to_tilde? boolean Replace home prefix with ~ in display
--- @field preview? boolean Enable preview window
--- @field icons? boolean Enable file icons
--- @field match_step? integer Batch size for matching

local M = {}

local FUTURE_TIMESTAMP_VALUE = os.time({
    year = 2038,
    month = 1,
    day = 1,
    hour = 0,
    minute = 0
})

local function get_last_used(buf, info)
    local current_buf = vim.api.nvim_get_current_buf()
    local alternate_buffer_number = vim.fn.bufnr("#")
    if buf == current_buf then
        return FUTURE_TIMESTAMP_VALUE
    elseif buf == alternate_buffer_number then
        return FUTURE_TIMESTAMP_VALUE - 1
    else
        return info.lastused
    end
end

local function sort_buffers_used(opts, buf_list)
    if not opts.sort_lastused then
        return buf_list
    end
    local sorted_buffer_list = {}
    local last_used_score_map = {}
    for _, buf in ipairs(buf_list) do
        local buf_info = utils.get_bufinfo(buf)
        last_used_score_map[buf] = get_last_used(
            buf,
            buf_info.info
        )
        table.insert(sorted_buffer_list, buf)
    end
    table.sort(sorted_buffer_list, function(left_buffer, right_buffer)
        return last_used_score_map[left_buffer] > last_used_score_map[right_buffer]
    end)
    return sorted_buffer_list
end

local function filter_buffer_numbers(
    opts,
    buf_list,
    included_buffer_list
)
    local current_buf = vim.api.nvim_get_current_buf()
    local filtered_buffer_list = vim.tbl_filter(function(buf)
        local should_exclude = false
        if included_buffer_list
            and not vim.tbl_contains(included_buffer_list, buf) then
            should_exclude = true
        elseif not vim.api.nvim_buf_is_valid(buf) then
            should_exclude = true
        elseif opts.no_term_buffers
            and vim.bo[buf].buftype == "terminal" then
            should_exclude = true
        elseif not opts.show_unlisted
            and buf ~= current_buf
            and vim.fn.buflisted(buf) ~= 1 then
            should_exclude = true
        elseif not opts.show_unloaded
            and not vim.api.nvim_buf_is_loaded(buf) then
            should_exclude = true
        elseif opts.ignore_current_buffer
            and buf == current_buf then
            should_exclude = true
        end
        return not should_exclude
    end, buf_list)

    return filtered_buffer_list
end

--- Open Buffers picker.
--- @param opts BuffersPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_buffers_picker(opts)
    opts = util.merge_picker_options({        current_tab = false,
        show_unlisted = false,
        show_unloaded = false,
        no_term_buffers = false,
        ignore_current_buffer = false,
        sort_lastused = true,
        filename_only = false,
        path_shorten = nil,
        home_to_tilde = true,
        preview = true,
        icons = true,
    }, opts)

    local included_buffer_list
    local buf_list = vim.api.nvim_list_bufs() or {}
    local current_tab = vim.api.nvim_get_current_tabpage()

    if opts.current_tab == true then
        included_buffer_list = {}
        for _, win in ipairs(
            vim.api.nvim_tabpage_list_wins(current_tab)
        ) do
            local win_buf = vim.api.nvim_win_get_buf(win)
            table.insert(included_buffer_list, win_buf)
        end
    end

    buf_list = filter_buffer_numbers(
        opts,
        buf_list,
        included_buffer_list
    )
    buf_list = sort_buffers_used(
        opts,
        buf_list
    )

    local decorators = {}
    if opts.icons ~= false then
        decorators = { Select.IconDecorator.new() }
    end
    local prefix_decorator = Select.Decorator.new()
    function prefix_decorator:decorate(entry_value)
        local buf = type(entry_value) == "table"
            and entry_value.bufnr or entry_value
        local buf_info = utils.get_bufinfo(buf)
        local info = buf_info.info

        local hidden_flag = info.hidden == 1 and "h"
            or info.loaded and "a" or " "
        local readonly_flag = vim.bo[buf].readonly and "=" or " "
        local changed_flag = info.changed == 1 and "+" or " "
        local flag_string = table.concat({ hidden_flag, readonly_flag, changed_flag })

        local buffer_prefix = " "
        if buf == vim.api.nvim_get_current_buf() then
            buffer_prefix = "%"
        elseif buf == vim.fn.bufnr("#") then
            buffer_prefix = "#"
        end

        return table.concat({
            "[",
            buf,
            "] ",
            buffer_prefix,
            flag_string,
            " ",
        })
    end

    table.insert(decorators, prefix_decorator)

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = buf_list,
        headers = util.build_picker_headers("Buffers", opts),
        preview = opts.preview ~= false
            and Select.BufferPreview.new() or false,
        actions = util.build_default_actions(
            Picker.default_converter,
            opts
        ),
        decorators = decorators,
        display = function(entry_value)
            local buf = type(entry_value) == "table"
                and entry_value.bufnr or entry_value
            local buffer_name = utils.get_bufname(
                buf,
                utils.get_bufinfo(buf)
            )
            if not buffer_name or #buffer_name == 0 then
                buffer_name = "[No Name]"
            end
            return util.format_display_path(
                buffer_name,
                opts
            )
        end,
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
