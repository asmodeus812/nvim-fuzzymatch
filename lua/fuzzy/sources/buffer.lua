local FUTURE = os.time({ year = 2038, month = 1, day = 1, hour = 0, minute = 00 })

local Select = require("fuzzy.select")
local Picker = require("fuzzy.picker")

local M = {}

function M.buf_is_qf(bufnr, bufinfo)
    bufinfo = bufinfo or (vim.api.nvim_buf_is_valid(bufnr) and M.getbufinfo(bufnr))
    if bufinfo and bufinfo.variables and
        bufinfo.variables.current_syntax == "qf" and
        not M.tbl_isempty(bufinfo.windows) then
        return M.win_is_qf(bufinfo.windows[1])
    end
    return false
end

local function get_lastused(buf)
    if buf.flag == "%" then
        return FUTURE
    elseif buf.flag == "#" then
        return FUTURE - 1
    else
        return buf.info.lastused
    end
end

local function get_bufinfo(buf)
    return {
        bufnr = buf,
        info = vim.fn["fuzzymatch#getbufinfo"](buf)
    }
end

local function get_bufname(bufnr, bufinfo)
    assert(not vim.in_fast_event())
    if not vim.api.nvim_buf_is_valid(bufnr) then return end
    if bufinfo and bufinfo.name and #bufinfo.name > 0 then
        return bufinfo.name
    end
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    if #bufname == 0 then
        local is_qf = M.buf_is_qf(bufnr, bufinfo)
        if is_qf then
            bufname = is_qf == 1 and "[Quickfix List]" or "[Location List]"
        else
            bufname = "[No Name]"
        end
    end
    assert(#bufname > 0)
    return bufname
end

local function enrich_buffers(opts, buffers, winid)
    local result = {}
    for _, bufnr in ipairs(buffers) do
        local buf = get_bufinfo(bufnr)

        if not buf.info.name or #buf.info.name == 0 then
            buf.info.name = get_bufname(buf.bufnr, buf.info)
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
        elseif opts.no_term_buffers and vim.bo[b].buftype == 'terminal' then
            excluded = true
        elseif opts.cwd_only and not path.is_relative_to(vim.api.nvim_buf_get_name(b), vim.loop.cwd()) then
            excluded = true
        elseif opts.cwd and not path.is_relative_to(vim.api.nvim_buf_get_name(b), opts.cwd) then
            excluded = true
        end
        return not excluded
    end, buffers)

    return bufnrs
end

local function buffer_converter(entry)
    if type(entry) == "table" then
        return {
            col = 1,
            lnum = 1,
            bufnr = entry.bufnr or (entry.info and entry.info.bufnr),
            filename = entry.name or (entry.info and entry.info.name),
        }
    elseif type(entry) == "number" then
        return {
            col = 1,
            lnum = 1,
            bufnr = entry,
            filename = get_bufname(entry)
        }
    end
    return false
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
        display = function(e)
            return e.info.display or e.info.name or e.name
        end,
        prompt_confirm = Select.select_entry,
        prompt_preview = Select.BufferPreview.new(buffer_converter),
        actions = {
            ["<c-q>"] = Select.send_quickfix,
            ["<c-t>"] = Select.select_tab,
            ["<c-v>"] = Select.select_vertical,
            ["<c-s>"] = Select.select_horizontal,
        }
    })
    return picker:open()
end

return M
