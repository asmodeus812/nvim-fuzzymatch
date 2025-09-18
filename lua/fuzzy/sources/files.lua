local Select = require("fuzzy.select")
local Picker = require("fuzzy.picker")

local M = {}

local function err_converter(entry)
    assert(type(entry) == "string" and #entry > 0)
    local pat = "^([^:]+):(%d+):(%d+):%s*[^:]+:%s*(.+)$"
    local filename, line_num, col_num = entry:match(pat)
    if filename and #filename > 0 then
        return {
            filename = filename,
            col = col_num and tonumber(col_num),
            lnum = line_num and tonumber(line_num),
        }
    end
    return false
end

local function ls_converter(entry)
    assert(type(entry) == "string" and #entry > 0)
    local trimmed = entry:gsub("^%s*(.-)%s*$", "%1")
    local filename = trimmed:match("([^%s]+)$")
    if filename and #filename > 0 then
        return {
            col = 1,
            lnum = 1,
            filename = filename,
        }
    end
    return false
end

local function grep_converter(entry)
    local pat = "^([^:]+):(%d+):(%d+):(.+)$"
    assert(type(entry) == "string" and #entry >= 0)
    local filename, line_num, col_num = entry:match(pat)
    if filename and #filename > 0 then
        return {
            filename = filename,
            col = col_num and tonumber(col_num),
            lnum = line_num and tonumber(line_num),
        }
    end
    return false
end

function M.files(opts)
    opts = opts or {
        cwd = vim.loop.cwd
    }

    local picker = Picker.new({
        content = "rg",
        headers = {
            { "Files" },
            { opts.cwd }
        },
        context = {
            args = {
                "--files",
                "--hidden",
            },
            cwd = opts.cwd
        },
        preview = Select.BufferPreview.new(
        ),
        actions = {
            ["<cr>"] = Select.select_entry,
            ["<c-q>"] = Select.send_quickfix,
            ["<c-t>"] = Select.select_tab,
            ["<c-v>"] = Select.select_vertical,
            ["<c-s>"] = Select.select_horizontal,
        },
        decorators = {
            Select.IconDecorator.new(),
        },
    })
    picker:open()
    return picker
end

function M.grep(opts)
    opts = opts or {
        cwd = vim.loop.cwd
    }

    local picker = Picker.new({
        content = "rg",
        headers = {
            { "Grep" },
            { opts.cwd }
        },
        context = {
            args = {
                "--column",
                "--line-number",
                "--no-heading",
                "{prompt}",
            },
            cwd = opts.cwd,
            interactive = "{prompt}",
        },
        preview = Select.CommandPreview.new(
            {
                "bat",
                "--plain",
                "--paging=never",
            },
            grep_converter
        ),
        actions = {
            ["<cr>"] = Select.action(Select.select_entry, Select.all(grep_converter)),
            ["<c-q>"] = { Select.action(Select.send_quickfix, Select.all(grep_converter)), "qflist" },
            ["<c-t>"] = { Select.action(Select.send_quickfix, Select.all(grep_converter)), "tabe" },
            ["<c-v>"] = { Select.action(Select.send_quickfix, Select.all(grep_converter)), "vert" },
            ["<c-s>"] = { Select.action(Select.send_quickfix, Select.all(grep_converter)), "split" },
        },
        decorators = {
            Select.IconDecorator.new(grep_converter)
        },
    })
    picker:open()
    return picker
end

function M.dirs(opts)
    opts = opts or {
        cwd = vim.loop.cwd
    }

    local picker = Picker.new({
        content = "find",
        headers = {
            { "Directories" },
            { opts.cwd }
        },
        context = {
            args = {
                "-type",
                "d",
            },
            cwd = opts.cwd,
            map = function(e)
                if e:match("%.$") then
                    return nil
                end
                return e
            end
        },
        preview = Select.CommandPreview.new({
            "ls", "-lah"
        }),
        actions = {
            ["<cr>"] = Select.select_entry,
            ["<c-q>"] = Select.send_quickfix,
            ["<c-t>"] = Select.select_tab,
            ["<c-v>"] = Select.select_vertical,
            ["<c-s>"] = Select.select_horizontal,
        },
        -- find`s a bit slow
        stream_step = 50000,
    })
    picker:open()
    return picker
end

function M.ls(opts)
    opts = opts or {
        cwd = vim.loop.cwd
    }

    local picker = Picker.new({
        content = "ls",
        headers = {
            { "Ls" },
            { opts.cwd }
        },
        context = {
            args = {
                "-lah",
                ".",
            },
            cwd = opts.cwd,
            map = function(e)
                if e:match("%.$") or e:match("%.%.$") or e:match("^total") then
                    return nil
                end
                return e
            end
        },
        actions = {
            ["<cr>"] = Select.action(Select.select_entry, Select.all(ls_converter)),
            ["<c-q>"] = Select.action(Select.send_quickfix, Select.all(ls_converter)),
            ["<c-t>"] = Select.action(Select.select_tab, Select.all(ls_converter)),
            ["<c-v>"] = Select.action(Select.select_vertical, Select.all(ls_converter)),
            ["<c-s>"] = Select.action(Select.select_horizontal, Select.all(ls_converter)),
        }
    })
    picker:open()
    return picker
end

return M
