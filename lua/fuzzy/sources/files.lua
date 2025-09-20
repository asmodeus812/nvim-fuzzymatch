local Select = require("fuzzy.select")
local Picker = require("fuzzy.picker")

local M = {}

function M.files(opts)
    opts = opts or {
        cwd = vim.loop.cwd
    }

    local converter = Picker.Converter.new(
        Picker.noop_converter,
        Picker.cwd_visitor
    )
    local cb = converter:get()
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
            ["<cr>"] = Select.action(Select.select_entry, cb),
            ["<c-q>"] = Select.action(Select.send_quickfix, cb),
            ["<c-t>"] = Select.action(Select.select_tab, cb),
            ["<c-v>"] = Select.action(Select.select_vertical, cb),
            ["<c-s>"] = Select.action(Select.select_horizontal, cb),
        },
        decorators = {
            Select.IconDecorator.new(cb),
        },
    })
    converter:bind(picker)
    picker:open()
    return picker
end

function M.grep(opts)
    opts = opts or {
        cwd = vim.loop.cwd
    }

    local converter = Picker.Converter.new(
        Picker.grep_converter,
        Picker.cwd_visitor
    )
    local cb = converter:get()
    local picker = Picker.new({
        content = "rg",
        headers = {
            { "Grep" },
            { opts.cwd }
        },
        context = {
            args = {
                "--column",
                -- "--hidden",
                -- "--no-ignore",
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
            cb
        ),
        actions = {
            ["<cr>"] = Select.action(Select.select_entry, Select.all(cb)),
            ["<c-q>"] = { Select.action(Select.send_quickfix, Select.all(cb)), "qflist" },
            ["<c-t>"] = { Select.action(Select.send_quickfix, Select.all(cb)), "tabe" },
            ["<c-v>"] = { Select.action(Select.send_quickfix, Select.all(cb)), "vert" },
            ["<c-s>"] = { Select.action(Select.send_quickfix, Select.all(cb)), "split" },
        },
        decorators = {
            Select.IconDecorator.new(cb)
        },
    })
    converter:bind(picker)
    picker:open()
    return picker
end

function M.dirs(opts)
    opts = opts or {
        cwd = vim.loop.cwd
    }

    local converter = Picker.Converter.new(
        Picker.noop_converter,
        Picker.cwd_visitor
    )
    local cb = converter:get()
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
        }, cb),
        actions = {
            ["<cr>"] = Select.action(Select.select_entry, cb),
            ["<c-q>"] = Select.action(Select.send_quickfix, cb),
            ["<c-t>"] = Select.action(Select.select_tab, cb),
            ["<c-v>"] = Select.action(Select.select_vertical, cb),
            ["<c-s>"] = Select.action(Select.select_horizontal, cb),
        },
        -- find`s a bit slow
        stream_step = 50000,
    })
    converter:bind(picker)
    picker:open()
    return picker
end

function M.ls(opts)
    opts = opts or {
        cwd = vim.loop.cwd
    }

    local converter = Picker.Converter.new(
        Picker.ls_converter,
        Picker.cwd_visitor
    )
    local cb = converter:get()
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
            ["<cr>"] = Select.action(Select.select_entry, Select.all(cb)),
            ["<c-q>"] = Select.action(Select.send_quickfix, Select.all(cb)),
            ["<c-t>"] = Select.action(Select.select_tab, Select.all(cb)),
            ["<c-v>"] = Select.action(Select.select_vertical, Select.all(cb)),
            ["<c-s>"] = Select.action(Select.select_horizontal, Select.all(cb)),
        }
    })
    converter:bind(picker)
    picker:open()
    return picker
end

return M
