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
    assert(type(entry) == "string" and #entry > 0)
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
    opts = opts or {}

    local picker = Picker.new({
        content = "rg",
        headers = {
            {
                { "Files", "Special" }
            }
        },
        context = {
            args = {
                "--files",
                "--hidden",
            },
            cwd = opts.cwd,
        },
        prompt_confirm = Select.select_entry,
        prompt_preview = Select.BufferPreview.new(),
        actions = {
            ["<c-q>"] = Select.send_quickfix,
            ["<c-t>"] = Select.select_tab,
            ["<c-v>"] = Select.select_vertical,
            ["<c-s>"] = Select.select_horizontal,
        }
    })
    picker:open()
    return picker
end

function M.dirs(opts)
    opts = opts or {}

    local picker = Picker.new({
        content = "find",
        headers = {
            {
                { "Directories", "Special" }
            }
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
        -- find`s a bit slow
        stream_step = 50000,
        prompt_confirm = Select.select_entry,
        prompt_preview = Select.CommandPreview.new({
            "ls", "-lah"
        }),
        actions = {
            ["<c-q>"] = Select.send_quickfix,
            ["<c-t>"] = Select.select_tab,
            ["<c-v>"] = Select.select_vertical,
            ["<c-s>"] = Select.select_horizontal,
        }
    })
    picker:open()
    return picker
end

function M.ls(opts)
    opts = opts or {}

    local picker = Picker.new({
        content = "ls",
        headers = {
            {
                { "Ls", "Special" }
            }
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
        prompt_confirm = Select.action(Select.select_entry, Picker.many(ls_converter)),
        actions = {
            ["<c-q>"] = Select.action(Select.send_quickfix, Picker.many(ls_converter)),
            ["<c-t>"] = Select.action(Select.select_tab, Picker.many(ls_converter)),
            ["<c-v>"] = Select.action(Select.select_vertical, Picker.many(ls_converter)),
            ["<c-s>"] = Select.action(Select.select_horizontal, Picker.many(ls_converter)),
        }
    })
    picker:open()
    return picker
end

function M.grep(opts)
    opts = opts or {}

    local picker = Picker.new({
        content = "rg",
        headers = {
            {
                { "Grep", "Special" }
            }
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
        prompt_confirm = Select.action(Select.select_entry, Picker.many(grep_converter)),
        prompt_preview = Select.CommandPreview.new("cat", grep_converter),
        actions = {
            ["<c-q>"] = { Select.action(Select.send_quickfix, Picker.many(grep_converter)), "qflist" },
            ["<c-t>"] = { Select.action(Select.send_quickfix, Picker.many(grep_converter)), "tabe" },
            ["<c-v>"] = { Select.action(Select.send_quickfix, Picker.many(grep_converter)), "vert" },
            ["<c-s>"] = { Select.action(Select.send_quickfix, Picker.many(grep_converter)), "split" },
        }
    })
    picker:open()
    return picker
end

return M
