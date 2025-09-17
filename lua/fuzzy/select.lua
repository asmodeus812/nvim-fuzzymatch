local LIST_HIGHLIGHT_NAMESPACE = vim.api.nvim_create_namespace("list_highlight_namespace")
local LIST_DECORATED_NAMESPACE = vim.api.nvim_create_namespace("list_decorated_namespace")
local LIST_STATUS_NAMESPACE = vim.api.nvim_create_namespace("list_status_namespace")
local LIST_HEADER_NAMESPACE = vim.api.nvim_create_namespace("list_header_namespace")

local highlight_extmark_opts = { limit = 1, type = "highlight", details = false, hl_name = false }
local detailed_extmark_opts = { limit = 4, type = "highlight", details = true, hl_name = true }
local padding = { " ", "SelectHeaderPadding" }
local spacing = { ",", "SelectHeaderDelimiter" }

local utils = require("fuzzy.utils")
local Async = require("fuzzy.async")
local Scheduler = require("fuzzy.scheduler")

--- @class Select
--- @field private source_window integer|nil The window ID of the source window where the selection interface was opened from.
--- @field private prompt_window integer|nil The window ID of the prompt input window.
--- @field private prompt_buffer integer|nil The buffer ID of the prompt input buffer.
--- @field private list_window integer|nil The window ID of the list display window.
--- @field private list_buffer integer|nil The buffer ID of the list display buffer.
--- @field private preview_buffer integer|nil The buffer ID of the preview display buffer.
--- @field private preview_window integer|nil The window ID of the preview display window.
--- @field private _options SelectOptions The configuration options for the selection interface.
--- @field private _state table The internal state of the selection interface.
local Select = {}
Select.__index = Select

--- @class Select.Decorator
Select.Decorator = {}
Select.Decorator.__index = Select.Decorator

--- This is a decorator that resolves file or directory icons for entries. This implementation uses the nvim-web-devicons to find the correct icon based on the file extension
--- @class Select.IconDecorator
--- @field converter function|nil A function that takes the entry and returns a table with bufnr, filename, lnum and col fields.
Select.IconDecorator = {}
Select.IconDecorator.__index = Select.IconDecorator
setmetatable(Select.IconDecorator, { __index = Select.Decorator })

--- This is a decorator that runs and combines the result of multiple decorators, combination is done by using a user defined separator or delimiter and a single highlight group for the entire combined result
--- @class Select.CombineDecorator
--- @field decorators Select.Decorator[] A list of decorators to run, the result of which non-nil decorator will be added to the combined result
--- @field delimiter? string|nil A delimiter to use to combine or join the results of the configured decorators, space by default
--- @field highlight? string|nil A single highlight group to use for the entire combined result of the decorators
Select.CombineDecorator = {}
Select.CombineDecorator.__index = Select.CombineDecorator
setmetatable(Select.CombineDecorator, { __index = Select.Decorator })

--- This is a decorator that returns the first decorator with a valid non-nil result from a list of pre-defined decorators.
--- @class Select.ChainDecorator
--- @field decorators Select.Decorator[] A list of decorators to run, the first non-nil decorator result will be used as a result for the decorate function
Select.ChainDecorator = {}
Select.ChainDecorator.__index = Select.ChainDecorator
setmetatable(Select.CombineDecorator, { __index = Select.Decorator })

--- @class Select.Preview
Select.Preview = {}
Select.Preview.__index = Select.Preview

function Select.Preview.new()
    local obj = {}
    setmetatable(obj, Select.Preview)
    return obj
end

function Select.Preview:clean()
    -- default empty implementation
end

function Select.Preview:preview(_)
    error("must be implemented by sub-classing")
end

function Select.Decorator.new()
    local obj = {}
    setmetatable(obj, Select.Decorator)
    return obj
end

function Select.Decorator:clean()
    -- default empty implementation
end

function Select.Decorator:decorate(_, _)
    error("must be implemented by sub-classing")
end

--- This is a previewer that shows the content of a buffer. This implementation uses the native neovim buffer handling to read and display
--- the buffer contents.
--- @class Select.BufferPreview
--- @field converter function|nil A function that takes the entry and returns a table with bufnr, filename, lnum and col fields.
--- @field default number A default dummy buffer used to be displayed in windows when a preview is not possible for the entry
--- @field buffers table A table of buffers that are held for clean up for the preview window
Select.BufferPreview = {}
Select.BufferPreview.__index = Select.BufferPreview
setmetatable(Select.BufferPreview, { __index = Select.Preview })

--- This is a previewer that runs a command to generate the preview content. The command can be any executable that produces output on
--- stdout or/and stderr. The command is run in a terminal job, and the output is streamed to the preview buffer.
--- @class Select.CommandPreview
--- @field converter function|nil A function that takes the entry and returns a table with bufnr, filename, lnum and col fields.
--- @field command string|table The command to run, can be a string or a table where the first element is the executable the rest are the arguments, the last argument is always the filename/resource from the entry.
--- @field jobs number[] table A table of job IDs that are held for clean up for the preview.
Select.CommandPreview = {}
Select.CommandPreview.__index = Select.CommandPreview
setmetatable(Select.CommandPreview, { __index = Select.Preview })

--- This is a previewer that uses a user-defined callback to generate the preview content. The callback can return the lines, filetype,
--- buftype and cursor but it also accepts the buffer and window so the user has full control over the preview generation.
--- @class Select.CustomPreview
--- @field callback function A function that takes the entry, buffer and window as arguments and returns optionally the lines, filetype, buftype and cursor position.
--- @field buffers table A table of buffers that are held for clean up for the preview window
Select.CustomPreview = {}
Select.CustomPreview.__index = Select.CustomPreview
setmetatable(Select.CustomPreview, { __index = Select.Preview })

local function icon_set()
    local ok, module = pcall(require, 'nvim-web-devicons')
    return ok and module or {}
end

local function buffer_delete(buffers)
    if #buffers > 0 then
        buffers = vim.tbl_filter(
            vim.api.nvim_buf_is_valid,
            buffers
        )
        for _, buf in ipairs(buffers or {}) do
            vim.api.nvim_buf_delete(
                buf, { force = vim.bo[buf].buftype ~= "" }
            )
        end
        return {}
    end
    return buffers
end

local function buffer_getline(buf, lnum)
    local row = lnum ~= nil and (lnum - 1) or 0
    local text = vim.api.nvim_buf_get_text(
        buf, row, 0, row, -1, {}
    )
    return (text and #text == 1) and text[1] or nil
end

local function line_mapper(entry, display)
    if type(display) == "function" then
        return display(assert(entry))
    elseif type(display) == "string" then
        assert(entry and next(entry))
        return entry[display]
    else
        return entry
    end
end

local function entry_mapper(entry)
    local col = 1
    local lnum = 1
    local fname = nil
    local bufnr = nil

    if type(entry) == "table" then
        col = entry.col or 1
        lnum = entry.lnum or 1
        bufnr = entry.bufnr or nil
        fname = entry.filename or nil
        if bufnr and not fname and assert(vim.api.nvim_buf_is_valid(bufnr)) then
            fname = vim.api.nvim_buf_get_name(bufnr)
        end
    elseif type(entry) == "number" then
        assert(entry > 0 and vim.api.nvim_buf_is_valid(entry))
        bufnr = entry
        fname = vim.api.nvim_buf_get_name(bufnr)
    elseif type(entry) == "string" then
        assert(#entry > 0 and vim.loop.fs_stat(entry) ~= nil)
        fname = entry
        bufnr = vim.fn.bufnr(fname, false)
        bufnr = bufnr > 0 and bufnr or nil
    end
    -- TODO: normalize the fname to be absolute, vim.fn.expand ?
    -- buf_get_name and expand can differ based on the cwd, this
    -- needs to be taken care of when taking the full buffer name
    assert(fname ~= nil or bufnr ~= nil)
    assert(#fname > 0 or bufnr > 0)

    return {
        col = col,
        lnum = lnum,
        bufnr = bufnr,
        filename = fname,
    }
end

local function compute_offsets(str, start_char, char_len)
    local start_byte = vim.str_byteindex(str, start_char)
    local end_char = start_char + char_len
    local end_byte = vim.str_byteindex(str, end_char)
    return start_byte, end_byte
end

local function compute_decoration(entry, str, decorators)
    local text, highlights = {}, {}
    for _, decor in ipairs(decorators) do
        local txt, hl = decor:decorate(entry, str)
        if type(txt) == "table" then
            vim.list_extend(text, txt)
        elseif type(txt) == "string" then
            table.insert(text, txt)
        end
        if type(hl) == "table" then
            vim.liset_extend(highlights, hl)
        elseif type(hl) == "string" then
            table.insert(highlights, hl)
        end
    end
    assert(#text == #highlights)
    return text, highlights
end

local function initialize_window(window)
    vim.wo[window][0].relativenumber = false
    vim.wo[window][0].number = false
    vim.wo[window][0].list = false
    vim.wo[window][0].showbreak = ""
    vim.wo[window][0].foldexpr = "0"
    vim.wo[window][0].foldmethod = "manual"
    vim.wo[window][0].breakindent = false
    vim.wo[window][0].fillchars = "eob: "
    vim.wo[window][0].cursorline = false
    vim.wo[window][0].winfixheight = true
    vim.wo[window][0].winfixwidth = true
    vim.wo[window][0].wrap = false
    return window
end

local function initialize_buffer(buffer, ft, bt)
    vim.bo[buffer].buftype = bt or "nofile"
    vim.bo[buffer].filetype = ft or ""
    vim.bo[buffer].bufhidden = "hide"
    vim.bo[buffer].buflisted = false
    vim.bo[buffer].swapfile = false
    vim.bo[buffer].modified = false
    vim.bo[buffer].autoread = false
    vim.bo[buffer].undofile = false
    vim.bo[buffer].undolevels = 0
    return buffer
end

local function populate_buffer(buffer, entries, display, step)
    local oldma = vim.bo[buffer].modifiable
    vim.bo[buffer].modifiable = true
    if step ~= nil and step > 0 then
        local start = 1
        local _end = math.min(#entries, step)
        local lines = utils.obtain_table(step)
        utils.resize_table(lines, step, utils.EMPTY_STRING)

        repeat
            for target = start, _end, 1 do
                lines[(target - start) + 1] = line_mapper(entries[target], display)
            end
            assert(#lines == step)
            Async.yield()

            vim.api.nvim_buf_set_lines(buffer, start - 1, _end, false, lines)
            start = math.min(#entries, _end + 1)
            _end = math.min(#entries, _end + step)
        until start == #entries or start > _end
        vim.api.nvim_buf_set_lines(buffer, _end, -1, false, {})
        utils.return_table(utils.fill_table(lines, utils.EMPTY_STRING))
    else
        if display ~= nil then
            local mapper = function(entry)
                return line_mapper(entry, display)
            end
            entries = vim.tbl_map(mapper, entries)
        end
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, entries)
    end
    vim.bo[buffer].modifiable = oldma
    vim.bo[buffer].modified = false
end

local function populate_range(buffer, start, _end, entries, display)
    assert(start <= _end and start > 0)
    local diff = math.abs(_end - start) + 1
    local lines = utils.obtain_table(diff)
    utils.resize_table(lines, diff, utils.EMPTY_STRING)

    for target = start, _end, 1 do
        lines[(target - start) + 1] = line_mapper(entries[target], display)
    end
    assert(#lines == diff)
    Async.yield()

    local oldma = vim.bo[buffer].modifiable
    vim.bo[buffer].modifiable = true
    vim.api.nvim_buf_set_lines(buffer, start - 1, _end, false, lines)
    utils.return_table(utils.fill_table(lines, utils.EMPTY_STRING))
    vim.bo[buffer].modifiable = oldma
    vim.bo[buffer].modified = false
end

local function highlight_range(buffer, start, _end, entries, positions, display, override)
    assert(start <= _end and start > 0)
    for target = start, _end, 1 do
        if positions and #positions > 0 and target <= #positions then
            assert(target <= #entries)
            local marks = (override == false) and vim.api.nvim_buf_get_extmarks(
                buffer, LIST_HIGHLIGHT_NAMESPACE,
                { target - 1, 0 }, { target - 1, -1 },
                highlight_extmark_opts
            )
            if not marks or #marks < 1 then
                local entry = entries[target]
                local matches = positions[target]
                assert(#matches % 2 == 0 and entry ~= nil)

                local decors = vim.api.nvim_buf_get_extmarks(
                    buffer, LIST_DECORATED_NAMESPACE,
                    { target - 1, 0 }, { target - 1, -1 },
                    detailed_extmark_opts
                )

                -- if the line has been decorated, we need to offset the highlights by the
                -- length of the last decoration, as it is the one that will be at the end
                local decor = decors ~= nil and #decors > 0 and decors[#decors]
                local offset = (decor and #decor >= 4 and decor[4].end_col + 1 or 0)

                for i = 1, #matches, 2 do
                    local byte_start, byte_end = compute_offsets(
                        line_mapper(entry, display), matches[i + 0], matches[i + 1]
                    )
                    vim.api.nvim_buf_set_extmark(
                        buffer,
                        LIST_HIGHLIGHT_NAMESPACE,
                        target - 1,
                        offset + byte_start,
                        {
                            strict = false,
                            hl_eol = false,
                            invalidate = true,
                            ephemeral = false,
                            undo_restore = false,
                            right_gravity = true,
                            end_right_gravity = true,
                            hl_group = "IncSearch",
                            end_line = target - 1,
                            end_col = offset + byte_end
                        }
                    )
                end
            end
        end
    end
    Async.yield()
end

local function decorate_range(buffer, start, _end, entries, decorators, display, override)
    assert(start <= _end and start > 0)
    local oldma = vim.bo[buffer].modifiable
    vim.bo[buffer].modifiable = true
    for target = start, _end, 1 do
        local marks = (override == false) and vim.api.nvim_buf_get_extmarks(
            buffer, LIST_DECORATED_NAMESPACE,
            { target - 1, 0 }, { target - 1, -1 },
            highlight_extmark_opts
        )
        if not marks or #marks < 1 then
            local entry = entries[target]
            local content, highlights = compute_decoration(entry,
                line_mapper(entry, display), decorators
            )
            if #content > 0 then
                assert(#content == #highlights)

                -- prefix the line with the decorations, they are concatenated in order from the content table,
                -- afterwards the matching highlights are inserted as extmarks, this will make sure that this append
                -- is going to shift the extmarks forward
                table.insert(content, "") -- extra padding
                local decor = table.concat(content, " ")
                vim.api.nvim_buf_set_text(buffer,
                    target - 1, 0, target - 1, 0, { decor }
                )

                local offset = 0
                for index, highlight in ipairs(highlights) do
                    local decor_item = content[index]
                    local end_col = offset + #decor_item
                    vim.api.nvim_buf_set_extmark(
                        buffer,
                        LIST_DECORATED_NAMESPACE,
                        target - 1,
                        offset,
                        {
                            strict = true,
                            hl_eol = false,
                            invalidate = true,
                            ephemeral = false,
                            undo_restore = false,
                            end_col = end_col,
                            end_line = target - 1,
                            right_gravity = true,
                            end_right_gravity = true,
                            hl_group = highlight,
                        }
                    )
                    offset = end_col + 1
                end
            end
        end
    end
    vim.bo[buffer].modifiable = oldma
    vim.bo[buffer].modified = false
    Async.yield()
end

local function display_entry(strategy, entry, window)
    vim.schedule(function()
        local old_ignore = vim.o.eventignore
        vim.o.eventignore = "all"
        local ok, res = pcall(strategy.preview, strategy, entry, window)
        if not ok and res then vim.notify(res, vim.log.levels.ERROR) end
        vim.o.eventignore = old_ignore
    end)
end

--- Create a new buffer previewer instance, the converter is used to map the entry to a table with bufnr, filename, lnum and col fields. By
--- default the converter is `entry_mapper`, which tries its best to extract those fields from the entry.
--- @param converter function|nil A function that takes the entry and returns a table with bufnr, filename, lnum and col fields.
function Select.BufferPreview.new(converter)
    local obj = Select.Preview.new()
    setmetatable(obj, Select.BufferPreview)
    obj.converter = converter or entry_mapper
    obj.default = assert(vim.api.nvim_create_buf(false, true))
    obj.default = initialize_buffer(obj.default, "fuzzy-preview")
    obj.buffers = { obj.default }
    return obj
end

function Select.BufferPreview:clean()
    self.buffers = buffer_delete(self.buffers)
end

function Select.BufferPreview:preview(entry, window)
    entry = self.converter(entry)
    if entry == false then
        return
    end
    assert(entry ~= nil)

    local buffer
    if entry.bufnr and vim.api.nvim_buf_is_valid(entry.bufnr) then
        buffer = entry.bufnr
    elseif entry.filename and vim.fn.bufexists(entry.filename) ~= 0 then
        buffer = vim.fn.bufnr(entry.filename, false)
    elseif entry.filename and vim.loop.fs_stat(entry.filename) then
        buffer = assert(vim.fn.bufadd(entry.filename))
        assert(not vim.tbl_contains(self.buffers, buffer))
        initialize_buffer(buffer, "", "")
        table.insert(self.buffers, buffer)
    else
        vim.api.nvim_win_set_buf(window, self.default)
        vim.api.nvim_win_set_cursor(window, { 1, 0 })
        return
    end

    local cursor = { entry.lnum or 1, entry.col and (entry.col - 1) or 0 }
    assert(buffer ~= nil and vim.api.nvim_buf_is_valid(buffer))

    local done = vim.wait(1000, function()
        local ok, err = pcall(vim.fn.bufload, buffer)
        if not ok and err ~= nil then error(ok) end
        return ok
    end, 250, false)

    if done then
        vim.api.nvim_win_set_buf(window, buffer)
        local ok, err = pcall(vim.api.nvim_win_set_cursor, window, cursor)
        if not ok and err ~= nil then error(err) end

        if not vim.b[buffer].ts_highlight then
            vim.api.nvim_win_call(window, function()
                local ft = vim.filetype.match({ buf = buffer, filename = entry.filename })
                local lang = vim.treesitter.language.get_lang(ft or '')
                local loaded = lang and vim.treesitter.language.add(lang)
                if loaded and lang then
                    ok, err = pcall(vim.treesitter.start, buffer, lang)
                    if not ok and err ~= nil then error(err) end
                end
            end)
        end
    else
        vim.api.nvim_win_set_buf(window, self.default)
        vim.api.nvim_win_set_cursor(window, { 1, 0 })
    end
end

--- Create a new custom previewer instance, the callback is invoked on each entry that has to be previewed
--- @param callback function A function that takes the entry, buffer and window as arguments and returns optionally the lines, filetype, buftype and cursor position.
function Select.CustomPreview.new(callback)
    local obj = Select.Preview.new()
    setmetatable(obj, Select.CustomPreview)
    obj.callback = assert(callback)
    obj.buffers = {}
    return obj
end

function Select.CustomPreview:clean()
    self.buffers = buffer_delete(self.buffers)
end

function Select.CustomPreview:preview(entry, window)
    if entry == false then
        return
    end
    assert(type(entry) == "string" or type(entry) == "table")

    local id = tostring(entry):gsub("table: ", "")
    local name = string.format("%s#fuzzy-custom-preview-entry", id)

    if vim.fn.bufexists(name) == 0 then
        local buffer = vim.api.nvim_create_buf(false, true)
        buffer = initialize_buffer(buffer, "fuzzy-preview")
        vim.api.nvim_win_set_buf(window, buffer)
        vim.api.nvim_buf_set_name(buffer, name)
        local ok, lines, ft, bt, cursor = utils.safe_call(
            self.callback, entry, buffer, window
        )
        if ok then
            if lines and type(lines) == "table" then
                populate_buffer(buffer, lines)
            end
            if bt and type(bt) == "string" then
                vim.bo[buffer].buftype = bt
            end
            if ft and type(ft) == "string" then
                vim.bo[buffer].filetype = ft
            end
            if cursor and type(cursor) == "table" then
                local ok, err = pcall(vim.api.nvim_win_set_cursor, window, cursor)
                if not ok and err ~= nil then error(err) end
            end
        else
            populate_buffer(buffer, {
                "Unable to display or preview entry",
            })
        end
        assert(not vim.tbl_contains(self.buffers, buffer))
        table.insert(self.buffers, buffer)
    else
        local buffer = assert(vim.fn.bufnr(name, false))
        vim.api.nvim_win_set_buf(window, buffer)
    end
end

--- Create a new command previewer instance, the command is run in a terminal job and the output is streamed to the preview buffer, the
--- converter is used to map the entry to a table with bufnr, filename, lnum and col fields. By default the converter is `entry_mapper`,
--- which tries its best to extract those fields from the entry.
--- @param command string|table The command to run, can be a string or a table where the first element is the command and the rest are arguments.
--- @param converter function|nil A function that takes the entry and returns a table with bufnr, filename, lnum and col fields.
function Select.CommandPreview.new(command, converter)
    local obj = Select.Preview.new()
    setmetatable(obj, Select.CommandPreview)
    obj.converter = converter or entry_mapper
    obj.command = assert(command)
    obj.buffers = {}
    obj.jobs = {}
    return obj
end

function Select.CommandPreview:clean()
    buffer_delete(self.buffers)
    vim.tbl_map(vim.fn.jobstop, self.jobs)
    self.buffers, self.jobs = {}, {}
end

function Select.CommandPreview:preview(entry, window)
    entry = self.converter(entry)
    if entry == false then
        return
    end
    assert(entry ~= nil)

    local name = string.format(
        "%s#fuzzy-command-preview-entry",
        tostring(entry.bufnr or entry.filename)
    )

    local cursor = { entry.lnum or 1, 0 }
    if vim.fn.bufexists(name) == 1 then
        local buffer = assert(vim.fn.bufnr(name, false))
        vim.api.nvim_win_set_buf(window, buffer)
        local streaming = vim.b[buffer].streaming
        if not streaming or streaming == false then
            pcall(vim.api.nvim_win_set_cursor, window, cursor)
        else
            vim.api.nvim_buf_attach(buffer, false, {
                on_lines = function(_, buf)
                    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_line_count(buf) >= cursor[1]
                        and vim.api.nvim_win_is_valid(window) and vim.api.nvim_win_get_buf(window) == buf
                    then
                        pcall(vim.api.nvim_win_set_cursor, window, cursor)
                        return true
                    end
                    return false
                end
            })
        end
    else
        local buffer
        if entry.bufnr and vim.api.nvim_buf_is_valid(entry.bufnr) then
            vim.bo[buffer].modifiable = true
            vim.bo[buffer].modified = false
            buffer = entry.bufnr
        else
            buffer = vim.api.nvim_create_buf(false, true)
            buffer = initialize_buffer(buffer, "fuzzy-preview")
            vim.api.nvim_buf_set_name(buffer, name)
            assert(not vim.tbl_contains(self.buffers, buffer))
            table.insert(self.buffers, buffer)
        end

        vim.api.nvim_win_set_buf(window, buffer)
        vim.api.nvim_buf_set_var(buffer, "streaming", true)
        local chan = vim.api.nvim_open_term(buffer, {
            force_crlf = true, on_input = nil,
        })

        local cmd
        if type(self.command) == "table" then
            cmd = assert(vim.fn.copy(self.command))
            ---@diagnostic disable-next-line: param-type-mismatch
            table.insert(cmd, entry.filename)
        elseif type(self.command) == "string" then
            ---@diagnostic disable-next-line: param-type-mismatch
            cmd = { self.command, entry.filename }
        end
        assert(vim.fn.executable(cmd[1]) == 1)

        local on_stdata = function(_, data)
            for _, value in ipairs(data or {}) do
                if value and #value > 0 then
                    vim.api.nvim_chan_send(chan, value)
                    vim.api.nvim_chan_send(chan, "\r\n")
                end
            end
        end

        vim.api.nvim_buf_attach(buffer, false, {
            on_lines = function(_, buf)
                if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_line_count(buf) >= cursor[1]
                    and vim.api.nvim_win_is_valid(window) and vim.api.nvim_win_get_buf(window) == buf
                then
                    pcall(vim.api.nvim_win_set_cursor, window, cursor)
                    return true
                end
                return false
            end
        })

        table.insert(self.jobs, vim.fn.jobstart(cmd, {
            pty = true,
            detach = false,
            clear_env = true,
            on_stdout = on_stdata,
            on_stderr = on_stdata,
            on_exit = function()
                if buffer and vim.api.nvim_buf_is_valid(buffer) then
                    vim.api.nvim_buf_set_var(buffer, "streaming", false)
                    if vim.api.nvim_win_is_valid(window) and vim.api.nvim_win_get_buf(window) == buffer then
                        pcall(vim.api.nvim_win_set_cursor, window, cursor)
                    end
                    vim.bo[buffer].modifiable = false
                    vim.bo[buffer].modified = false
                end
            end,
            stdout_buffered = false,
            stderr_buffered = false,
        }))
    end
end

--- Create a new icon decorator instance, the converter is used to map the entry to a table with bufnr, filename, lnum and col fields. By
--- default the converter is `entry_mapper`, which tries its best to extract those fields from the entry.
--- @param converter function|nil A function that takes the entry and returns a table with bufnr, filename, lnum and col fields.
function Select.IconDecorator.new(converter)
    local obj = Select.Decorator.new()
    setmetatable(obj, Select.IconDecorator)
    obj.converter = converter or entry_mapper
    return obj
end

function Select.IconDecorator:decorate(entry, line)
    entry = self.converter(entry)
    if not line or entry == false or #line == 0 then
        return
    end
    assert(entry ~= nil and entry.filename)

    local icon, icon_highlight = icon_set().get_icon(
        entry.filename, vim.fn.fnamemodify(entry.filename, ':e'),
        { default = true }
    )
    return assert(icon), icon_highlight or "SelectDecoratorDefault"
end

--- Create a new combine decorator instance, the decorators are run in order and their results are combined using the delimiter
--- and a single highlight group is used for the entire combined result.
--- @param decorators Select.Decorator[] A list of decorators to run, the result of which non-nil decorator will be added to the combined result
--- @param highlight? string|nil A single highlight group to use for the entire combined result of the decorators
--- @param delimiter? string|nil A delimiter to use to combine or join the results of the configured decorators, space by default
function Select.CombineDecorator.new(decorators, highlight, delimiter)
    local obj = Select.Decorator.new()
    setmetatable(obj, Select.CombineDecorator)
    obj.decorators = assert(decorators)
    obj.highlight = highlight or "SelectDecoratorDefault"
    obj.delimiter = delimiter or " "
    return obj
end

function Select.CombineDecorator:decorate(entry)
    local text = {}
    for _, decor in ipairs(self.decorators) do
        local str, _ = decor:decorate(entry)

        if str and type(str) == "string" and #str > 0 then
            table.insert(text, str)
        end
    end

    return table.concat(text, self.delimiter), self.highlight
end

--- Create a new chain decorator instance, the decorators are run in order and the first non-nil result is returned.
--- @param decorators Select.Decorator[] A list of decorators to run, the first non-nil decorator result will be used as a result for the decorate function
function Select.ChainDecorator.new(decorators)
    local obj = Select.Decorator.new()
    setmetatable(obj, Select.ChainDecorator)
    obj.decorators = assert(decorators)
    return obj
end

function Select.ChainDecorator:decorate(entry)
    for _, decor in ipairs(self.decorators) do
        local str, hl = decor:decorate(entry)
        if str and type(str) == "string" and #str > 0 then
            return str, hl or "SelectDecoratorDefault"
        end
    end
    return nil, nil
end

function Select:_prompt_input(input, callback)
    if type(callback) == "function" then
        local ok, status, entries, positions = pcall(callback, input)
        if not ok or ok == false then
            vim.notify(status, vim.log.levels.ERROR)
        elseif entries ~= nil then
            self:list(entries, positions)
            self:list(nil, nil)
        end
    end
end

function Select:_prompt_getquery(lnum)
    if not self.prompt_buffer or not vim.api.nvim_buf_is_valid(self.prompt_buffer) then
        return nil
    end
    return buffer_getline(self.prompt_buffer, lnum)
end

function Select:_list_selection(lnum)
    if not self.list_buffer or not vim.api.nvim_buf_is_valid(self.list_buffer) then
        return {}
    end
    local placed = vim.fn.sign_getplaced(self.list_buffer, {
        group = "list_toggle_entry_group",
    })
    if placed and #placed > 0 and placed[1].signs and #placed[1].signs > 0 then
        return vim.tbl_map(function(s)
            assert(s.lnum <= #self._state.entries)
            return self._state.entries[s.lnum]
        end, placed[1].signs)
    else
        local entries = self._state.entries
        assert(#entries == 0 or lnum <= #entries)
        return #entries > 0 and { entries[lnum] } or {}
    end
end

function Select:_make_callback(callback)
    return function()
        return utils.safe_call(
            callback, self
        )
    end
end

function Select:_create_mappings(buffer, mode, mappings)
    for key, action in pairs(mappings or {}) do
        vim.api.nvim_buf_set_keymap(buffer, mode, key, "", {
            expr = false,
            silent = false,
            noremap = true,
            replace_keycodes = false,
            callback = self:_make_callback(action)
        })
    end
end

function Select:_populate_list(full)
    local entries = self._state.entries
    local streaming = self._state.streaming
    if streaming == true and entries and #entries >= 0 then
        if #entries == 0 then
            populate_buffer(
                self.list_buffer,
                utils.EMPTY_TABLE
            )
        elseif full == true then
            populate_buffer(
                self.list_buffer, entries,
                self._options.display,
                self._options.list_step
            )
        elseif full == false then
            local cursor = vim.api.nvim_win_get_cursor(self.list_window)
            local height = vim.api.nvim_win_get_height(self.list_window)
            assert(#entries >= cursor[1] and cursor[1] > 0)
            populate_range(
                self.list_buffer,
                math.max(1, cursor[1] - height),
                math.min(#entries, cursor[1] + height),
                entries, self._options.display)
        end
    end
end

function Select:_highlight_list()
    local entries = self._state.entries
    local positions = self._state.positions
    if entries and #entries > 0 and positions and #positions > 0 then
        local cursor = vim.api.nvim_win_get_cursor(self.list_window)
        local height = vim.api.nvim_win_get_height(self.list_window)
        assert(#entries == #positions)
        highlight_range(
            self.list_buffer,
            math.max(1, cursor[1] - height),
            math.min(#entries, cursor[1] + height),
            entries, positions,
            self._options.display,
            self._state.streaming)
    end
end

function Select:_decorate_list()
    local entries = self._state.entries
    local decorators = self._options.decorators
    if entries and #entries > 0 and decorators and #decorators > 0 then
        local cursor = vim.api.nvim_win_get_cursor(self.list_window)
        local height = vim.api.nvim_win_get_height(self.list_window)
        assert(#entries >= cursor[1] and cursor[1] > 0)
        decorate_range(
            self.list_buffer,
            math.max(1, cursor[1] - height),
            math.min(#entries, cursor[1] + height),
            entries, decorators,
            self._options.display,
            self._state.streaming)
    end
end

function Select:_display_preview()
    local entries = self._state.entries
    local previewer = self._options.preview
    if entries and previewer ~= nil and previewer ~= false then
        if #entries == 0 then
            local window = assert(self.preview_window)
            local buffer = assert(self.preview_buffer)
            assert(vim.api.nvim_win_is_valid(window))
            vim.api.nvim_win_set_buf(window, buffer)
        else
            local cursor = vim.api.nvim_win_get_cursor(self.list_window)
            assert(#entries >= cursor[1] and cursor[1] > 0)
            local entry = assert(entries[cursor[1]])
            display_entry(
                previewer, entry,
                self.preview_window
            )
        end
    end
end

function Select:_render_list(full)
    if self:_is_rendering() then
        self:_stop_rendering()
    end
    local executor = Async.wrap(function()
        if self.list_buffer and vim.api.nvim_buf_is_valid(self.list_buffer) then
            self:_populate_list(full)
        end

        if self.list_window and vim.api.nvim_win_is_valid(self.list_window) then
            self:_decorate_list()
            self:_highlight_list()
            self:_display_preview()
            vim.api.nvim_win_call(
                self.list_window,
                vim.cmd.redraw
            )
        end
    end)
    self._state.renderer = executor()
    Scheduler.add(self._state.renderer)
end

function Select:_destroy_view()
    if self.list_buffer and vim.api.nvim_buf_is_valid(self.list_buffer) then
        vim.api.nvim_buf_delete(self.list_buffer, { force = true })
        self.list_buffer = nil
    end

    if self.prompt_buffer and vim.api.nvim_buf_is_valid(self.prompt_buffer) then
        vim.api.nvim_buf_delete(self.prompt_buffer, { force = true })
        self.prompt_buffer = nil
    end

    if self.preview_buffer and vim.api.nvim_buf_is_valid(self.preview_buffer) then
        vim.api.nvim_buf_delete(self.preview_buffer, { force = true })
        self.preview_buffer = nil
    end

    self._state.streaming = false
    self._state.positions = nil
    self._state.entries = nil
    self._state.query = ""
end

function Select:_clean_preview()
    local preview = self._options.preview or nil
    if type(preview) == "table" and preview.clean then
        preview:clean()
    end
end

function Select:_clear_view()
    if self:_is_rendering() then
        self:_stop_rendering()
    end

    if self.prompt_buffer and vim.api.nvim_buf_is_valid(self.prompt_buffer) then
        populate_buffer(self.prompt_buffer, { "" })
        local sign_name = string.format(
            "prompt_line_query_sign_%d",
            self.prompt_buffer
        )
        vim.fn.sign_place(
            0, "prompt_line_query_group",
            sign_name, self.prompt_buffer,
            { lnum = 1, priority = 10 }
        )
    end
    if self.list_buffer and vim.api.nvim_buf_is_valid(self.list_buffer) then
        vim.api.nvim_buf_clear_namespace(self.list_buffer, LIST_DECORATED_NAMESPACE, 0, -1)
        vim.api.nvim_buf_clear_namespace(self.list_buffer, LIST_HIGHLIGHT_NAMESPACE, 0, -1)
        populate_buffer(self.list_buffer, {})
    end
    if self.preview_buffer and vim.api.nvim_buf_is_valid(self.preview_buffer) then
        populate_buffer(self.preview_buffer, {})
    end

    if self.prompt_window and vim.api.nvim_win_is_valid(self.prompt_window) then
        vim.api.nvim_win_set_cursor(self.prompt_window, { 1, 0 })
    end
    if self.list_window and vim.api.nvim_win_is_valid(self.list_window) then
        vim.api.nvim_win_set_cursor(self.list_window, { 1, 0 })
    end
    if self.preview_window and vim.api.nvim_win_is_valid(self.preview_window) then
        vim.api.nvim_win_set_buf(self.preview_window, self.preview_buffer)
        vim.api.nvim_win_set_cursor(self.preview_window, { 1, 0 })
    end

    self._state.streaming = false
    self._state.positions = nil
    self._state.entries = nil
    self._state.query = ""
end

function Select:_close_view()
    if self:_is_rendering() then
        self:_stop_rendering()
    end

    if self.source_window and vim.api.nvim_win_is_valid(self.source_window) then
        vim.api.nvim_set_current_win(self.source_window)
        self.source_window = nil
    end
    if self.prompt_window and vim.api.nvim_win_is_valid(self.prompt_window) then
        vim.api.nvim_win_close(self.prompt_window, true)
        self.prompt_window = nil
    end
    if self.list_window and vim.api.nvim_win_is_valid(self.list_window) then
        vim.api.nvim_win_close(self.list_window, true)
        self.list_window = nil
    end
    if self.preview_window and vim.api.nvim_win_is_valid(self.preview_window) then
        vim.api.nvim_win_close(self.preview_window, true)
        self.preview_window = nil
    end
end

function Select:_is_rendering()
    return self._state.renderer and self._state.renderer:is_running()
end

function Select:_stop_rendering()
    return self._state.renderer and self._state.renderer:cancel()
end

--- Executes user callback with the current selection passed in, the action performs a no operation and is entirely reliant on the user
--- callback to perform any action, this is a generic function used to invoke the user callback with current selection
function Select:default_select(callback)
    local cursor = vim.api.nvim_win_get_cursor(self.list_window)
    local selection = callback and self:_list_selection(cursor[1])

    self:_close_view()

    local ok, result = utils.safe_call(callback, selection, cursor)
    if ok and result == false then
        return
    end
end

--- Scrolls the preview window by sending normal mode commands to it, this is a generic function used by other selection methods.
function Select:scroll_preview(input, callback)
    local preview_window = assert(self.preview_window)
    local term_codes = vim.api.nvim_replace_termcodes(
        assert(input), false, false, true
    )
    vim.api.nvim_win_call(preview_window, function()
        vim.cmd.normal({ args = { term_codes }, bang = true })
        local cursor = vim.api.nvim_win_get_cursor(preview_window)
        utils.safe_call(callback, {}, cursor)
    end)
end

--- Moves the cursor in the list by a specified direction, this is a generic function used by other selection methods.
function Select:move_cursor(dir, callback)
    local list_window = assert(self.list_window)

    local list_entries = assert(self._state.entries)
    local line_count = vim.fn.line("$", list_window)

    local cursor = vim.api.nvim_win_get_cursor(list_window)
    -- ensure that if not all entries are rendered, we don't move the cursor past the end of the entries,
    -- meaning we do not allow looping from the first entry to the last one until all entries are rendered
    dir = (cursor[1] == 1 and dir < 0 and line_count < #list_entries) and 0 or dir

    if dir and dir ~= 0 then
        if cursor[1] == 1 and dir < 0 then cursor[1] = 0 end
        cursor[1] = (cursor[1] + dir) % (line_count + 1)
        if cursor[1] == 0 and dir > 0 then cursor[1] = 1 end
        vim.api.nvim_win_set_cursor(list_window, cursor)
    end

    self:_display_preview()

    local selection = self:_list_selection(cursor[1])
    utils.safe_call(callback, selection, cursor)
end

--- Executes command against the selected entry as an argument passed to that command, this is a generic function used by other
--- selection methods.
function Select:exec_command(command, mods, callback)
    local list_window = assert(self.list_window)
    local cursor = vim.api.nvim_win_get_cursor(list_window)
    local selection = self:_list_selection(cursor[1])
    local ok, result = utils.safe_call(callback, selection, cursor)
    if ok and result == false then
        return
    else
        result = vim.tbl_map(
            entry_mapper,
            result or selection
        )
    end

    self:_close_view()

    for _, entry in ipairs(result) do
        local cmd
        local arg = entry.filename
        if entry.bufnr ~= nil then
            if command == "edit" then
                command = "buffer"
            elseif command == "split" then
                command = "sbuffer"
            elseif command == "tabedit" then
                command = "tab"
                cmd = "sbuffer"
            end
            arg = entry.bufnr
        end

        vim.cmd[command]({
            args = { arg },
            mods = mods,
            bang = true,
            cmd = cmd,
        })

        local col = entry.col or 1
        local lnum = entry.lnum or 1
        local position = { lnum, col - 1 }
        pcall(vim.api.nvim_win_set_cursor, 0, position)
    end
end

--- Sends the selected entries to the quickfix or location list, using the provided callback to extract filenames from entries, the type
--- argument value must be either "quickfix" or "loclist".
function Select:send_fixlist(type, callback)
    local list_window = assert(self.list_window)
    local cursor = vim.api.nvim_win_get_cursor(list_window)
    local selection = self:_list_selection(cursor[1])
    local ok, result = utils.safe_call(callback, selection, cursor)
    if ok and result == false then
        return
    else
        result = vim.tbl_map(
            entry_mapper,
            result or selection
        )
    end

    self:_close_view()

    local args = {
        nr = "$",
        items = vim.tbl_filter(function(item)
            return item ~= nil and (item.filename or item.bufnr)
        end, result),
        title = "[Fuzzymatch]",
    }

    if type == "quickfix" then
        vim.fn.setqflist({}, " ", args)
        self._options.quickfix_open()
    elseif type == "loclist" then
        local target
        if self.source_window and vim.api.nvim_win_is_valid(self.source_window) then
            target = self.source_window
        else
            target = vim.fn.winnr("#")
        end
        vim.fn.setloclist(assert(
            target
        ), {}, " ", args)
        self._options.loclist_open()
    end
end

--- Toggles the selection state of the current entry in the list, using signs to indicate selection, and moves the cursor down by one
--- entry by default.
function Select:toggle_entry(callback)
    local list_window = assert(self.list_window)
    local cursor = vim.api.nvim_win_get_cursor(list_window)
    local placed = vim.fn.sign_getplaced(self.list_buffer, {
        group = "list_toggle_entry_group", lnum = cursor[1],
    })
    if placed and #placed > 0 and placed[1].signs and #placed[1].signs > 0 and placed[1].signs[1] then
        vim.fn.sign_unplace(
            "list_toggle_entry_group",
            {
                buffer = self.list_buffer,
                id = placed[1].signs[1].id,
            }
        )
    else
        local sign_name = string.format(
            "list_toggle_entry_sign_%d",
            self.list_buffer
        )
        vim.fn.sign_place(
            cursor[1],
            "list_toggle_entry_group",
            sign_name,
            self.list_buffer,
            {
                lnum = cursor[1],
                priority = 10,
            }
        )
    end

    self:move_cursor(1)

    local selection = callback and self:_list_selection(cursor[1])
    utils.safe_call(callback, selection, cursor)
end

--- Closes all open windows associated with the selection interface and returns focus to the source window.
function Select:close_view(callback)
    self:_close_view()
    utils.safe_call(callback)
end

--- Scrolls the preview window up by one page.
function Select:page_down(callback)
    self:scroll_preview("<c-f>", callback)
end

--- Scrolls the preview window down by one page.
function Select:page_up(callback)
    self:scroll_preview("<c-b>", callback)
end

--- Scrolls the preview window up by half a page.
function Select:half_up(callback)
    self:scroll_preview("<c-u>", callback)
end

--- Scrolls the preview window down by half a page.
function Select:half_down(callback)
    self:scroll_preview("<c-d>", callback)
end

--- Scrolls the preview window up by one line.
function Select:line_up(callback)
    self:scroll_preview("<c-y>", callback)
end

--- Scrolls the preview window down by one line.
function Select:line_down(callback)
    self:scroll_preview("<c-e>", callback)
end

--- Moves the cursor to the next entry in the list.
function Select:select_next(callback)
    return self:move_cursor(1, callback)
end

--- Moves the cursor to the previous entry in the list.
function Select:select_prev(callback)
    return self:move_cursor(-1, callback)
end

--- Opens the selected entry in the source window. See `:edit` and Select.source_window.
function Select:select_entry(callback)
    self:exec_command("edit", {}, callback)
end

--- Opens the selected entry in a horizontal split.
function Select:select_horizontal(callback)
    self:exec_command("split", { horizontal = true }, callback)
end

--- Opens the selected entry in a vertical split.
function Select:select_vertical(callback)
    self:exec_command("split", { vertical = true }, callback)
end

--- Opens the selected entry in a new tab.
function Select:select_tab(callback)
    self:exec_command("tabedit", {}, callback)
end

--- Sends the selected entries to the quickfix list and opens it.
function Select:send_quickfix(callback)
    self:send_fixlist("quickfix", callback)
end

--- Sends the selected entries to the location list and opens it.
function Select:send_locliset(callback)
    self:send_fixlist("loclist", callback)
end

--- Gets the current query from the prompt input. The query is updated on each input change in the prompt. It is not extracted directly from
--- the prompt buffer on-demand but is captured with each input change using TextChangedI and TextChanged autocmd events.
--- @return string The current query string, the query will never be nil, otherwise that represents invalid state of the selection interface.
function Select:query()
    return assert(self._state.query)
end

--- Closes the selection interface, the buffers and any state associated with the interface will be destroyed as well, to retain the selection state consider using `hide`
function Select:close()
    self:_close_view()
    self:_clean_preview()
    self:_destroy_view()
end

-- Hides the select interface, does not enforce any resource de-allocation taken up by the select interface, to enforce this use `close` method instead
function Select:hide()
    self:_close_view()
end

-- Clears the select interface, from any content and state, that includes the query, list and preview interfaces, but does not close the interface itself, or destroy any internal state or resources associated with it.
function Select:clear()
    self:_clear_view()
end

--- Checks if the selection interface is currently open, this is determined by checking if both the prompt and list windows are valid.
--- @return boolean True if the selection interface is open, false otherwise.
function Select:isopen()
    local prompt = self.prompt_window and vim.api.nvim_win_is_valid(self.prompt_window)
    local list = self.list_window and vim.api.nvim_win_is_valid(self.list_window)
    return list ~= nil and prompt ~= nil and list and prompt
end

--- Checks if the selection interface is showing any entries, the entries can be rendered or set using the `list` method, which renders the specified entries into the list.
--- @return boolean True if the list is empty, false otherwise.
function Select:isempty()
    return not self._state.entries or #self._state.entries == 0
end

--- Checks if the selection interface is valid, meaning that it has been initialized/opened at least once and has not been destroyed by
--- calling any of the `destroy` or `close` methods which would invalidate its state
--- @return boolean True if the select interface is still valid, false otherwise.
function Select:isvalid()
    local prompt = self.prompt_buffer and vim.api.nvim_buf_is_valid(self.prompt_buffer)
    local list = self.list_buffer and vim.api.nvim_buf_is_valid(self.list_buffer)
    return list ~= nil and prompt ~= nil and list and prompt
end

-- Render a list of entries in the list window, with optional highlighting positions and display formatting function or property.
-- @param entries? any[]|string[]|nil The list of entries to display.
-- @param positions? integer[][]|nil The list of positions for highlighting
-- @param display? string|fun(entry: any): string|nil The field or function to use for displaying entries.
function Select:list(entries, positions)
    vim.validate {
        entries = { entries, { "table", "nil" }, true },
        positions = { positions, { "table", "nil" }, true },
    }
    if entries ~= nil then
        self._state.positions = positions
        self._state.entries = entries
        self._state.streaming = true
        utils.time_execution(Select._render_list, self, false)
    elseif positions == nil then
        utils.time_execution(Select._render_list, self, true)
        if self._state.renderer then
            self._state.renderer:await(function(_, reason)
                assert(not reason or #reason == 0)
                self._state.streaming = false
            end)
        else
            self._state.streaming = false
        end
    end
end

--- Render the current status of the select, providing information about the selection list, preview or prompt, as virtual text in the select interface
--- @param status string the status data to render in the window
function Select:status(status, hl)
    vim.validate {
        status = { status, "string" },
        hl = { hl, { "string", "nil" }, true },
    }

    local decor = self._options.prompt_decor or nil
    local suffix = type(decor) == "table" and assert(decor.suffix)

    vim.api.nvim_buf_clear_namespace(self.prompt_buffer, LIST_STATUS_NAMESPACE, 0, 1)
    vim.api.nvim_buf_set_extmark(self.prompt_buffer, LIST_STATUS_NAMESPACE, 0, 0, {
        priority = 1000,
        hl_mode = "combine",
        right_gravity = false,
        virt_text_pos = "eol",
        virt_text_win_col = nil,
        virt_text = {
            suffix and { suffix, "SelectPrefixText" },
            { assert(status), hl or "SelectStatusText" },
        },
    })
end

--- Render a header at the top of the selection interface, the header can be a string or a table of strings or string/highlight pairs, where each
--- inner table represents a block of header entries.
--- @param header string|table The header to render, can be a string or a table of strings or string/highlight pairs.
function Select:header(header)
    vim.validate {
        header = { header, { "table", "string" } },
    }

    local header_entries
    if type(header) == "table" then
        header_entries = {}
        for idx, block in ipairs(header) do
            assert(type(block) == "table")

            for _, element in ipairs(block) do
                local entry = {}
                if type(element) == "table" then
                    assert(#element == 2 and #element[1] > 0 and #element[2] > 0)
                    table.insert(entry, element[1])
                    table.insert(entry, element[2])
                elseif type(element) == "string" then
                    assert(#element > 0)
                    table.insert(entry, element)
                    table.insert(entry, "SelectHeaderDefault")
                end
                assert(#entry[1] and #entry[2])
                table.insert(header_entries, padding)
                table.insert(header_entries, entry)
            end

            if idx >= 1 and idx < #header then
                table.insert(header_entries, spacing)
                table.insert(header_entries, padding)
            end
        end
    elseif type(header) == "string" then
        header_entries = { { header, "SelectHeaderDefault" } }
    end

    if not header_entries or #header_entries == 0 then
        return
    end

    if vim.api.nvim_win_get_height(self.prompt_window) == 1 then
        vim.api.nvim_win_set_height(self.prompt_window, 2)
    end

    vim.api.nvim_buf_clear_namespace(self.prompt_buffer, LIST_HEADER_NAMESPACE, 0, 1)
    vim.api.nvim_buf_set_extmark(self.prompt_buffer, LIST_HEADER_NAMESPACE, 0, 0, {
        priority = 2000,
        hl_mode = "combine",
        virt_lines_above = true,
        virt_lines_leftcol = true,
        virt_lines_overflow = "trunc",
        virt_lines = { header_entries }
    })

    -- TODO: https://github.com/neovim/neovim/issues/27967
    vim.api.nvim_win_call(self.prompt_window, function()
        local scroll_up = vim.api.nvim_replace_termcodes(
            assert("<c-b>"), false, false, true
        )
        vim.cmd.normal({ args = { scroll_up }, bang = true })
    end)
end

--- Opens the selection interface, creating necessary buffers and windows as needed, and sets up autocommands and mappings, if no set. If
--- the interface is already open, this method is a no-op and does nothing.
function Select:open()
    if self:isopen() then
        return
    end
    local opts = assert(self._options)

    self.source_window = vim.api.nvim_get_current_win()
    local factor = opts.preview and 2.0 or 1.0
    local ratio = math.abs(opts.window_ratio / factor)
    local size = math.ceil(vim.o.lines * ratio)

    if opts.prompt_input then
        local prompt_buffer = self.prompt_buffer
        if not prompt_buffer or not vim.api.nvim_buf_is_valid(prompt_buffer) then
            prompt_buffer = vim.api.nvim_create_buf(false, true)
            prompt_buffer = initialize_buffer(prompt_buffer, "fuzzy-prompt")
            self:_create_mappings(prompt_buffer, "i", opts.mappings)
            vim.bo[prompt_buffer].modifiable = true

            local prompt_trigger = vim.api.nvim_create_autocmd({ "TextChangedP", "TextChangedI" }, {
                buffer = prompt_buffer,
                callback = function(args)
                    if not args.buf or not vim.api.nvim_buf_is_valid(args.buf) then
                        self:_prompt_input(nil, opts.prompt_input)
                        self:close()
                    elseif self:isopen() then
                        local query = self:_prompt_getquery()
                        if query == nil then
                            self:_prompt_input(nil, opts.prompt_input)
                            self:close()
                        elseif self._state.query ~= query then
                            self:_prompt_input(query, opts.prompt_input)
                            self._state.query = assert(query)
                        end
                    end
                end
            })

            local sign_name = string.format(
                "prompt_line_query_sign_%d",
                prompt_buffer
            )

            local mode_changed = vim.api.nvim_create_autocmd("ModeChanged", {
                buffer = prompt_buffer,
                callback = vim.schedule_wrap(function()
                    vim.cmd.startinsert()
                end)
            })

            vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
                buffer = prompt_buffer,
                callback = function()
                    pcall(vim.api.nvim_del_autocmd, prompt_trigger)
                    pcall(vim.api.nvim_del_autocmd, mode_changed)
                    assert(vim.fn.sign_undefine(sign_name) == 0)
                    self.prompt_buffer = nil
                    self.prompt_window = nil
                    return true
                end,
                once = true,
            })

            local decor = opts.prompt_decor or "> "
            assert(vim.fn.sign_define(sign_name, {
                text = type(decor) == "table"
                    and assert(decor.prefix)
                    or assert(decor),
                texthl = "SelectPrefixText",
            }) == 0, "failed to define sign")

            assert(vim.fn.sign_place(
                0,
                "prompt_line_query_group",
                sign_name,
                prompt_buffer,
                {
                    lnum = 1,
                    priority = 10,
                }
            ) == 1, "failed to place sign")

            if type(opts.prompt_query) == "string" and #opts.prompt_query > 0 then
                self._state.query = opts.prompt_query -- initialize query, and set the line
                -- will trigger the prompt input callback, due to the TextChanged autocommand
                -- being set, so we don't need to call it manually here, just set the line
                vim.api.nvim_buf_set_lines(prompt_buffer, 0, 1, false, { opts.prompt_query })
            end
        end

        local prompt_window = self.prompt_window
        if not prompt_window or not vim.api.nvim_win_is_valid(prompt_window) then
            prompt_window = vim.api.nvim_open_win(prompt_buffer, false, {
                split = "below", win = -1, height = 1, noautocmd = false
            });
            vim.api.nvim_win_set_height(prompt_window, 1)
            prompt_window = initialize_window(prompt_window)
            vim.wo[prompt_window][0].signcolumn = 'number'
            vim.wo[prompt_window][0].cursorline = false
            vim.wo[prompt_window][0].winfixbuf = true

            vim.api.nvim_create_autocmd("WinClosed", {
                pattern = tostring(prompt_window),
                callback = function()
                    self:_close_view()
                    return true
                end,
                once = true,
            })
        end

        local query = self:query()
        if query and #query > 0 then
            vim.schedule(function()
                vim.api.nvim_win_set_cursor(prompt_window, {
                    1, -- set cursor on the first line
                    vim.str_byteindex(query, #query),
                })
            end)
        end

        self.prompt_buffer = prompt_buffer
        self.prompt_window = prompt_window
        if opts.prompt_headers ~= nil then
            self:header(opts.prompt_headers)
        end
    end

    if opts.prompt_list then
        local list_buffer = self.list_buffer
        if not list_buffer or not vim.api.nvim_buf_is_valid(list_buffer) then
            list_buffer = vim.api.nvim_create_buf(false, true)
            list_buffer = initialize_buffer(list_buffer, "fuzzy-list")
            if not opts.prompt_input then
                self:_create_mappings(list_buffer, "n", opts.mappings)
            end
            vim.bo[list_buffer].modifiable = false

            local entries, positions
            if type(opts.prompt_list) == "function" then
                entries, positions = opts.prompt_list()
            elseif type(opts.prompt_list) == "table" then
                if type(opts.prompt_list[1]) == "table" then
                    entries = opts.prompt_list[1]
                    positions = opts.prompt_list[2]
                else
                    entries = opts.prompt_list
                end
            end
            if entries ~= nil then
                self:list(entries, positions)
                self:list(nil, nil)
            end

            local sign_name = string.format(
                "list_toggle_entry_sign_%d",
                list_buffer
            )

            vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
                buffer = list_buffer,
                callback = function()
                    assert(vim.fn.sign_undefine(sign_name) == 0)
                    self._state.streaming = false
                    self._state.positions = nil
                    self._state.entries = nil
                    self.list_buffer = nil
                    self.list_window = nil
                    return true
                end,
                once = true,
            })

            assert(vim.fn.sign_define(sign_name, {
                text = self._options.toggle_prefix,
                texthl = "SelectToggleSign",
            }) == 0)
        end

        local list_window = self.list_window
        if not list_window or not vim.api.nvim_win_is_valid(list_window) then
            local list_height = math.floor(math.ceil(size))
            list_window = vim.api.nvim_open_win(list_buffer, false, {
                noautocmd = false,
                height = list_height,
                win = self.prompt_window or -1,
                split = self.prompt_window and "above" or "below",
            });
            vim.api.nvim_win_set_height(list_window, list_height)
            list_window = initialize_window(list_window)
            vim.wo[list_window][0].signcolumn = 'number'
            vim.wo[list_window][0].cursorline = true
            vim.wo[list_window][0].winfixbuf = true

            local highlight_matches = vim.api.nvim_create_autocmd("WinScrolled", {
                pattern = tostring(list_window),
                callback = function()
                    if not self:_is_rendering() and vim.api.nvim_buf_line_count(list_buffer) >= 1 then
                        utils.time_execution(Select._render_list, self, false)
                    end
                end
            })

            vim.api.nvim_create_autocmd("WinClosed", {
                pattern = tostring(list_window),
                callback = function()
                    pcall(vim.api.nvim_del_autocmd, highlight_matches)
                    self:_close_view()
                    return true
                end,
                once = true,
            })
        end

        self.list_buffer = list_buffer
        self.list_window = list_window
    end

    if opts.prompt_list and opts.preview then
        local preview_buffer = self.preview_buffer
        if not preview_buffer or not vim.api.nvim_buf_is_valid(preview_buffer) then
            preview_buffer = vim.api.nvim_create_buf(false, true)
            preview_buffer = initialize_buffer(preview_buffer, "fuzzy-preview")
            vim.bo[preview_buffer].modifiable = false
        end

        local preview_window = self.preview_window
        if not preview_window or not vim.api.nvim_win_is_valid(preview_window) then
            local preview_height = math.floor(math.ceil(size))
            preview_window = vim.api.nvim_open_win(preview_buffer, false, {
                split = self.list_window and "above" or "below",
                height = preview_height,
                noautocmd = false,
                win = self.list_window or -1,
            });
            vim.api.nvim_win_set_height(preview_window, preview_height)
            preview_window = initialize_window(preview_window)
            vim.wo[preview_window].relativenumber = false
            vim.wo[preview_window].number = true
        end

        self.preview_window = preview_window
        self.preview_buffer = preview_buffer
        self:_display_preview()
    end

    if self.prompt_window then
        vim.api.nvim_set_current_win(self.prompt_window)
        vim.api.nvim_win_call(
            self.prompt_window,
            vim.cmd.startinsert
        )
    elseif self.list_window then
        vim.api.nvim_set_current_win(self.list_window)
        vim.api.nvim_win_call(
            self.list_window,
            vim.cmd.stopinsert
        )
    else
        vim.api.nvim_set_current_win(self.source_window)
    end
end

--- Creates an action function that safely calls the provided action with the Select instance as the first argument, and the callback as the
--- second argument. If the action or callback raises an error, it is caught and handled gracefully.
--- @param action fun(self: Select, callback: fun(selection: any, cursor: integer[]|nil): any) The action function to be executed.
function Select.action(action, callback)
    return function(_self)
        utils.safe_call(
            action,
            _self,
            callback
        )
    end
end

--- Creates a converter function that applies the provided converter function to all entries in the list and returns a table of results. If
--- the converter function is nil, it returns false. If the converter function returns nil or false for all entries, it also returns false.
--- @param converter fun(entry: any): any|nil The converter function to apply to each entry.
function Select.all(converter)
    return function(e)
        if not converter then return false end
        assert(e and #e > 0 and e[1] ~= nil)
        local results = vim.tbl_map(converter, e)
        results = vim.tbl_filter(function(o)
            return o and o ~= false
        end, results)
        if not results or #results == 0 then
            return false
        end
        return results
    end
end

--- Creates a converter function that applies the provided converter function to the first entry in the list and returns the result. If the
--- converter function is nil, it returns false. If the first entry is nil or the converter function returns nil or false, it raises an
--- assertion error.
--- @param converter fun(entry: any): any|nil The converter function to apply to the first entry.
function Select.first(converter)
    return function(e)
        assert(e and #e > 0 and e[1] ~= nil)
        return converter and converter(e[1])
    end
end

--- Creates a converter function that applies the provided converter function to the last entry in the list and returns the result. If the
--- converter function is nil, it returns false. If the last entry is nil or the converter function returns nil or false, it raises an
--- assertion error.
--- @param converter fun(entry: any): any|nil The converter function to apply to the last entry.
function Select.last(converter)
    return function(e)
        assert(e and #e > 0 and e[#e] ~= nil)
        return converter and converter(e[#e])
    end
end

--- Creates a new Select instance, which provides an interactive selection interface.
--- @class SelectOptions
--- @inlinedoc
--- @field prompt_list? boolean|fun()|any[] Whether to show the list window or a function to provide initial entries.
--- @field prompt_input? boolean|fun() Whether to show the input prompt, when function is provided it is used as the input callback.
--- @field prompt_headers? table|string|nil Headers to display above the prompt input, can be a string or a table of strings or string/highlight pairs, where each inner table represents a block of header entries.
--- @field prompt_query? string|nil Initial query to populate the prompt input with. If provided, the prompt input must also be enabled. The query will be set in the prompt input and the input callback will be invoked with this initial query.
--- @field prompt_decor? table|string Symbol decoration to display in the query prompt window. A table of two items can be provided show around the prompt query, or a single string which by default is interpreted as the prompt prefix. If a table is provided key value pairs are expected of prefix and suffix i.e { prefix = "> ", suffix = "< " }.
--- @field toggle_prefix? string Prefix to display for toggled entries in the list, when multi select is enabled
--- @field window_ratio? number Ratio of the window height to the total editor height.
--- @field list_step? integer|nil Number of entries to render at a time when populating the list.
--- @field quickfix_open? fun() Function to open the quickfix list.
--- @field loclist_open? fun() Function to open the location list.
--- @field mappings? table<string, fun(self: Select, callback: fun(selection: any, cursor: integer[]|nil): any)> Key mappings for the selection interface. The keys are the key sequences and the values are functions that take the Select instance and an optional callback as arguments.
--- @field preview? Select.Preview|boolean|nil Preview instance or boolean indicating whether to show the preview window. If an instance is provided, it will be used to render the preview. The preview instance must be a subclass of Select.Preview. Preview instances must implement the `preview` method.
--- @field display? string|fun(entry: any): string|string|nil Function or string to format the display of entries in the list. If a function is provided, it will be called with each entry and should return a string to display. If a string is provided, it will be used as the property name to extract from each entry for display.
--- @field decorators? Select.Decorator[]|nil List of decorators to apply to entries in the list. Each decorator should be a table with a `decorate` function that takes an entry and returns a decorated string along with optional highlight group information.

--- Creates a new Select instance with the given options.
--- @param opts? SelectOptions|nil The options to configure the selection interface.
--- @return Select The new Select instance.
function Select.new(opts)
    opts = opts or {}
    vim.validate({
        prompt_list = { opts.prompt_list, { "boolean", "function", "table" }, true },
        prompt_input = { opts.prompt_input, { "boolean", "function" }, true },
        prompt_headers = { opts.prompt_headers, { "table", "string", "nil" }, true },
        prompt_query = { opts.prompt_query, { "string", "nil" }, true },
        prompt_decor = { opts.prompt_decor, { "table", "string" }, true },
        toggle_prefix = { opts.toggle_prefix, "string", true },
        window_ratio = { opts.window_ratio, "number", true },
        list_step = { opts.list_step, { "number", "nil" }, true },
        quickfix_open = { opts.quickfix_open, "function", true },
        loclist_open = { opts.loclist_open, "function", true },
        display = { opts.display, { "function", "string", "nil" }, true },
        preview = { opts.preview, { "table", "boolean" }, true },
        decorators = { opts.decorators, "table", true },
        mappings = { opts.mappings, "table", true },
    })
    opts = vim.tbl_deep_extend("force", {
        prompt_list = true,
        prompt_input = true,
        prompt_headers = nil,
        prompt_query = nil,
        prompt_decor = "› ",
        toggle_prefix = "✓",
        preview_timeout = 500,
        window_ratio = 0.20,
        list_step = nil,
        decorators = {},
        preview = nil,
        display = nil,
        mappings = {
            ["<cr>"]    = Select.default_select,
            ["<tab>"]   = Select.toggle_entry,
            ["<esc>"]   = Select.close,
            ["<c-p>"]   = Select.select_prev,
            ["<c-n>"]   = Select.select_next,
            ["<c-k>"]   = Select.select_prev,
            ["<c-j>"]   = Select.select_next,
            ["<c-f>"]   = Select.page_down,
            ["<c-b>"]   = Select.page_up,
            ["<c-d>"]   = Select.half_down,
            ["<c-u>"]   = Select.half_up,
            ["<c-e>"]   = Select.line_down,
            ["<c-y>"]   = Select.line_up,
        },
        quickfix_open = vim.cmd.copen,
        loclist_open = vim.cmd.lopen,
    }, opts)

    local self = setmetatable({
        preview_buffer = nil,
        preview_window = nil,
        prompt_buffer = nil,
        prompt_window = nil,
        list_buffer = nil,
        list_window = nil,
        _options = opts,
        _state = {
            query = "",
            buffers = {},
            entries = nil,
            positions = nil,
            streaming = false
        },
    }, Select)

    return self
end

return Select
