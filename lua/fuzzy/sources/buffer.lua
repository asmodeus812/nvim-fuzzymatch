local FUTURE = os.time({ year = 2038, month = 1, day = 1, hour = 0, minute = 00 })

local Select = require("fuzzy.select")
local Picker = require("fuzzy.picker")
local utils = require("fuzzy.utils")

local M = {}

local function get_lastused(buf)
    if buf.flag == "%" then
        return FUTURE
    elseif buf.flag == "#" then
        return FUTURE - 1
    else
        return buf.info.lastused
    end
end

local function enrich_buffers(opts, buffers, winid)
    local result = {}
    for _, bufnr in ipairs(buffers) do
        local buf = utils.get_bufinfo(bufnr)

        if not buf.info.name or #buf.info.name == 0 then
            buf.info.name = utils.get_bufname(buf.bufnr, buf.info)
        end

        if winid then
            buf.info.lnum = vim.api.nvim_win_get_cursor(winid)[1]
        end

        buf.info.display = string.format(
            "[%d] %s:%d",
            bufnr,
            buf.info.name,
            buf.info.lnum
        )

        table.insert(result, buf)
    end

    if opts.sort_lastused then
        table.sort(result, function(a, b)
            return get_lastused(a) > get_lastused(b)
        end)
    end

    return result
end

local function filter_buffers(opts, buffers, included)
    -- TODO: add more user options and customizations
    local bufnr = vim.api.nvim_get_current_buf()
    local bufnrs = vim.tbl_filter(function(b)
        local excluded = false
        if included and not vim.tbl_contains(included, b) then
            excluded = true
        elseif not vim.api.nvim_buf_is_valid(b) then
            excluded = true
        elseif not opts.show_unlisted and b ~= bufnr and vim.fn.buflisted(b) ~= 1 then
            excluded = true
        elseif not opts.show_unloaded and not vim.api.nvim_buf_is_loaded(b) then
            excluded = true
        elseif opts.ignore_current_buffer and b == bufnr then
            excluded = true
        end
        return not excluded
    end, buffers)

    return bufnrs
end

function M.buffers(opts)
    opts = opts or {}
    local included

    local buffers = vim.api.nvim_list_bufs() or {}
    local tabid = vim.api.nvim_get_current_tabpage()
    if opts.current_tab == true then
        included = {}
        for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tabid)) do
            local buf = vim.api.nvim_win_get_buf(w)
            table.insert(included, buf)
        end
    end

    buffers = filter_buffers(opts, buffers, included)
    buffers = enrich_buffers(opts, buffers, nil)

    local picker = Picker.new({
        content = buffers,
        headers = {
            { "Buffers" }
        },
        preview = Select.BufferPreview.new(),
        actions = {
            ["<cr>"] = Select.select_entry,
            ["<c-q>"] = { Select.send_quickfix, "qflist" },
            ["<c-t>"] = { Select.select_tab, "tabe" },
            ["<c-v>"] = { Select.select_vertical, "vert" },
            ["<c-s>"] = { Select.select_horizontal, "split" },
        },
        decorators = {
            Select.IconDecorator.new()
        },
        display = function(e)
            return e.info.display or e.info.name or e.name
        end,
    })
    picker:open()
    return picker
end

return M
