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
--- @field cwd? string|fun(): string Working directory for path display
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

local function should_include_buffer(
    opts,
    buf,
    current_buf,
    included_buffer_map
)
    if included_buffer_map
        and included_buffer_map[buf] ~= true then
        return false
    end
    if not vim.api.nvim_buf_is_valid(buf) then
        return false
    end
    if opts.no_term_buffers
        and vim.bo[buf].buftype == "terminal" then
        return false
    end
    if not opts.show_unlisted
        and buf ~= current_buf
        and vim.fn.buflisted(buf) ~= 1 then
        return false
    end
    if not opts.show_unloaded
        and not vim.api.nvim_buf_is_loaded(buf) then
        return false
    end
    if opts.ignore_current_buffer
        and buf == current_buf then
        return false
    end
    return true
end

local function filter_buffer_numbers(
    opts,
    buf_list,
    included_buffer_map
)
    local filtered_buffer_list = {}
    for _, buf in ipairs(buf_list) do
        if should_include_buffer(
                opts, buf,
                vim.api.nvim_get_current_buf(),
                included_buffer_map
            ) then
            filtered_buffer_list[#filtered_buffer_list + 1] = buf
        end
    end
    return filtered_buffer_list
end

--- Open Buffers picker.
--- @param opts BuffersPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_buffers_picker(opts)
    opts = util.merge_picker_options({
        current_tab = false,
        show_unlisted = false,
        show_unloaded = false,
        no_term_buffers = false,
        ignore_current_buffer = false,
        sort_lastused = true,
        cwd = nil,
        filename_only = false,
        path_shorten = nil,
        home_to_tilde = true,
        preview = true,
        icons = true,
    }, opts)

    local decorators = {}
    if opts.icons ~= false then
        decorators = { Select.IconDecorator.new() }
    end
    local prefix_decorator = Select.Decorator.new()
    function prefix_decorator:decorate(entry_value)
        local buf = type(entry_value) == "table"
            and entry_value.bufnr or entry_value
        local buffer_info = type(entry_value) == "table"
            and entry_value.buffer_info or nil
        local buf_info = buffer_info or utils.get_bufinfo(buf)
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
        content = function(stream_callback)
            local included_buffer_map
            local buf_list = vim.api.nvim_list_bufs() or {}
            local current_tab = vim.api.nvim_get_current_tabpage()
            local current_working_directory = util.resolve_working_directory(opts.cwd)

            if opts.current_tab == true then
                included_buffer_map = {}
                for _, win in ipairs(
                    vim.api.nvim_tabpage_list_wins(current_tab)
                ) do
                    local win_buf = vim.api.nvim_win_get_buf(win)
                    included_buffer_map[win_buf] = true
                end
            end

            buf_list = filter_buffer_numbers(
                opts,
                buf_list,
                included_buffer_map
            )
            if opts.sort_lastused then
                buf_list = sort_buffers_used(
                    opts,
                    buf_list
                )
            end
            for _, buf in ipairs(buf_list) do
                local buffer_info = utils.get_bufinfo(buf)
                local buffer_name_value = utils.get_bufname(
                    buf,
                    buffer_info
                )
                if buffer_name_value
                    and #buffer_name_value > 0
                    and not util.is_under_directory(
                        current_working_directory,
                        buffer_name_value
                    ) then
                    goto continue
                end
                stream_callback({
                    bufnr = buf,
                    filename = buffer_name_value,
                    buffer_info = buffer_info,
                })
                ::continue::
            end
            stream_callback(nil)
        end,
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
            local buffer_name = type(entry_value) == "table"
                and entry_value.filename or nil
            if not buffer_name or #buffer_name == 0 then
                buffer_name = utils.get_bufname(
                    buf,
                    utils.get_bufinfo(buf)
                )
            end
            if not buffer_name or #buffer_name == 0 then
                buffer_name = utils.NO_NAME
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
