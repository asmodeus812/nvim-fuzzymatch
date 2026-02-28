local LIST_HIGHLIGHT_NAMESPACE = vim.api.nvim_create_namespace("list_highlight_namespace")
local LIST_DECORATED_NAMESPACE = vim.api.nvim_create_namespace("list_decorated_namespace")
local LIST_STATUS_NAMESPACE = vim.api.nvim_create_namespace("list_status_namespace")
local LIST_TOGGLE_NAMESPACE = vim.api.nvim_create_namespace("list_toggle_namespace")
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

--- @class Select.Preview
Select.Preview = {}
Select.Preview.__index = Select.Preview

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

function Select.Preview.new()
    local obj = {}
    setmetatable(obj, Select.Preview)
    return obj
end

function Select.Preview:init()
    -- default empty implementation
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

function Select.Decorator:init()
    -- default empty implementation
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
--- @field ignored string[]|nil A list of ignored file type extensions that should not be previewed by the buffer, usually used for executable file formats and the like
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

--- Loads the nvim-web-devicons if available, returns an empty table if not.
--- @return table the nvim-web-devicons module or an empty table
local function icon_set()
    local ok, module = pcall(require, 'nvim-web-devicons')
    return ok and module or {}
end

--- Deletes listed buffers if valid; used for previewer buffer cleanup.
--- @param buffers table List of buffer numbers to delete
--- @return table Empty table or passed table (if empty)
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

--- Gets a specific line as a string from a buffer (0-based).
--- @param buf integer Buffer handle
--- @param lnum integer? 1-based line number
--- @return string|nil The line as a string, or nil if unavailable.
local function buffer_getline(buf, lnum)
    local row = lnum ~= nil and (lnum - 1) or 0
    local text = vim.api.nvim_buf_get_text(
        buf, row, 0, row, -1, {}
    )
    return (text and #text == 1) and text[1] or nil
end

--- Utility for rendering an entry using a display function or field name.
--- @param entry any Entry table
--- @param display function|string|nil Formatter or property
--- @return string|any Rendered string or entry field
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

--- Computes window height based on ratio of Neovim lines.
--- @param multiplier number
--- @param factor number
--- @return integer Window height
local function compute_height(multiplier, factor)
    local ratio = math.abs(multiplier / factor)
    return math.ceil(vim.o.lines * ratio)
end

--- Get byte offsets for character positions in a string.
--- @param str string
--- @param start_char integer Character start index (0-based)
--- @param char_len integer Length in characters
--- @return integer?, integer? Byte offsets (start, end)
local function compute_offsets(str, start_char, char_len)
    local start_byte = vim.str_byteindex(str, start_char)
    local end_char = start_char + char_len
    local end_byte = vim.str_byteindex(str, end_char)
    return start_byte, end_byte
end

--- Aggregates the result of multiple decorators for an entry.
--- @param entry any Entry to decorate
--- @param str string Line for decoration
--- @param decorators table List of decorators
--- @return table, table Table of text pieces and their highlights
local function compute_decoration(entry, str, decorators)
    local text, highlights = {}, {}
    for _, decor in ipairs(decorators) do
        local txt, hl = decor:decorate(entry, str)
        if txt ~= nil and txt == false then
            goto continue
        end
        if type(txt) == "table" then
            vim.list_extend(text, txt)
            if type(hl) == "table" then
                vim.list_extend(highlights, hl)
            elseif type(hl) == "string" then
                for _ = 1, #txt do
                    table.insert(highlights, hl)
                end
            else
                for _ = 1, #txt do
                    table.insert(highlights, "SelectDecoratorDefault")
                end
            end
        elseif type(txt) == "string" then
            table.insert(text, txt)
            if type(hl) == "string" then
                table.insert(highlights, hl)
            else
                table.insert(highlights, "SelectDecoratorDefault")
            end
        end
        ::continue::
    end
    assert(#text == #highlights)
    return text, highlights
end

--- Counts the number of selected/toggled entries.
--- @param entries table List entries
--- @param toggled table Toggled state
--- @return integer Number of toggled entries
local function toggled_count(entries, toggled)
    local count = toggled.all == true and #entries or 0
    for _, value in pairs(toggled.entries or {}) do
        if toggled.all == true and value == false then
            count = count - 1
        elseif value == true then
            count = count + 1
        end
    end
    return count
end

--- Sends keys to the input buffer/window.
--- @param input string The input string (vim keycodes allowed)
--- @param window integer Window ID
--- @param callback function|nil Callback to invoke after
--- @param mode string Insert (i) or normal (n)
local function send_input(input, window, callback, mode)
    assert(window and vim.api.nvim_win_is_valid(window))
    local term_codes = vim.api.nvim_replace_termcodes(
        assert(input), false, false, true
    )

    vim.api.nvim_win_call(window, function()
        local old_ignore = vim.o.eventignore
        vim.o.eventignore = "ModeChanged"
        if mode == "i" then
            vim.api.nvim_feedkeys(term_codes, mode, false)
        else
            vim.cmd.normal({ args = { term_codes }, bang = true })
        end
        local position = vim.api.nvim_win_get_cursor(window)
        vim.o.eventignore = old_ignore
        utils.safe_call(callback, position)
    end)
end

--- Applies default and custom window-local options.
--- @param window integer Window handle
--- @param opts table Option table
--- @return integer Window handle
local function initialize_window(window, opts)
    vim.wo[window].relativenumber = false
    vim.wo[window].number = false
    vim.wo[window].list = false
    vim.wo[window].showbreak = ""
    vim.wo[window].foldexpr = "0"
    vim.wo[window].foldmethod = "manual"
    vim.wo[window].fillchars = "eob: "
    vim.wo[window].cursorline = false
    vim.wo[window].signcolumn = "yes"
    vim.wo[window].winfixheight = true
    vim.wo[window].winfixwidth = true
    vim.wo[window].wrap = false
    for key, value in pairs(opts or {}) do
        vim.wo[window][key] = value
    end
    return window
end

--- Applies buffer-local options for selection interface.
--- @param buffer integer Buffer handle
--- @param ft string|nil Filetype
--- @param bt string|nil Buftype
--- @return integer Buffer handle
local function initialize_buffer(buffer, ft, bt)
    vim.bo[buffer].buftype = bt or "nofile"
    vim.bo[buffer].filetype = ft or ""
    vim.bo[buffer].bufhidden = "hide"
    vim.bo[buffer].buflisted = false
    vim.bo[buffer].swapfile = false
    vim.bo[buffer].modified = false
    vim.bo[buffer].autoread = false
    vim.bo[buffer].undofile = false
    return buffer
end

--- Restores buffer options to global values (after temp changes).
--- @param buffer integer Buffer handle
local function restore_buffer(buffer)
    vim.bo[buffer].bufhidden = vim.o.bufhidden
    vim.bo[buffer].buflisted = vim.o.buflisted
    vim.bo[buffer].swapfile = vim.o.swapfile
    vim.bo[buffer].autoread = vim.o.autoread
    vim.bo[buffer].undofile = vim.o.undofile
end

--- Sets virtual text or lines in buffer using extmarks.
--- @param buffer integer Buffer handle
--- @param ns integer Namespace
--- @param line integer Line (0-based)
--- @param col integer Column (0-based)
--- @param text table|nil Virtual text chunk
--- @param lines table|nil Virtual line chunks
local function virtual_content(buffer, ns, line, col, text, lines)
    vim.api.nvim_buf_clear_namespace(buffer, ns, 0, 1)
    vim.api.nvim_buf_set_extmark(buffer, ns, line, col, {
        priority = 1000,
        hl_mode = "combine",
        right_gravity = false,
        -- virtual text fields
        virt_text = text,
        virt_text_pos = "eol",
        virt_text_win_col = nil,
        -- virtual lines fields
        virt_lines = lines,
        virt_lines_above = true,
        virt_lines_leftcol = true,
        virt_lines_overflow = "trunc",
    })
end

--- Populates a buffer with given lines/items (optional mapping/display).
--- @param buffer integer Buffer handle
--- @param items table List items
--- @param display function|string|nil Display function or property
--- @param step integer|nil Number of lines to populate per step (for large lists)
local function populate_buffer(buffer, items, display, step)
    local oldma = vim.bo[buffer].modifiable
    vim.bo[buffer].modifiable = true
    if step ~= nil and step > 0 then
        local size = math.min(#items, step)
        local lines = utils.obtain_table(size)

        local start, _end = 1, size
        repeat
            for target = start, _end, 1 do
                lines[(target - start) + 1] = line_mapper(items[target], display)
            end
            assert(#lines == size)
            Async.yield()

            vim.api.nvim_buf_set_lines(buffer, start - 1, _end, false, lines)
            start = math.min(#items, _end + 1)
            _end = math.min(#items, _end + step)
        until start == #items or start > _end

        utils.return_table(utils.fill_table(lines, utils.EMPTY_STRING))
        assert(#lines == size)
        Async.yield()

        vim.api.nvim_buf_set_lines(buffer, _end, -1, false, {})
        assert(vim.api.nvim_buf_line_count(buffer) == #items)
    else
        if display ~= nil then
            local mapper = function(entry)
                return line_mapper(entry, display)
            end
            items = vim.tbl_map(mapper, items)
        end
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, items)
    end
    vim.bo[buffer].modifiable = oldma
    vim.bo[buffer].modified = false
end

--- Replaces a range of lines in the buffer with formatted list lines.
--- @param buffer integer Buffer handle
--- @param start integer First (1-based)
--- @param _end integer Last (1-based)
--- @param entries table Data
--- @param display function|string|nil Display/formatter
local function populate_range(buffer, start, _end, entries, display)
    local lines = utils.EMPTY_TABLE
    if _end > 0 then
        assert(start <= _end and start > 0)
        local diff = math.abs(_end - start) + 1
        lines = utils.obtain_table(diff)

        for target = start, _end, 1 do
            lines[(target - start) + 1] = line_mapper(entries[target], display)
        end

        utils.resize_table(lines, diff)
        assert(#lines == diff)
        Async.yield()
    end

    local oldma = vim.bo[buffer].modifiable
    vim.bo[buffer].modifiable = true
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    if lines ~= utils.EMPTY_TABLE then
        utils.fill_table(lines)
        utils.return_table(lines)
    end
    vim.bo[buffer].modifiable = oldma
    vim.bo[buffer].modified = false
end

--- Applies highlights to positions in the lines based on matches array.
--- @param buffer integer Buffer handle
--- @param start integer First (1-based)
--- @param _end integer Last (1-based)
--- @param entries table Entry data
--- @param positions table Positions to highlight (list of [start,len,...])
--- @param display function|string|nil Display/formatter
local function highlight_range(buffer, start, _end, entries, positions, display)
    vim.api.nvim_buf_clear_namespace(buffer,
        LIST_HIGHLIGHT_NAMESPACE, 0, -1
    )

    if _end == 0 then return end
    assert(start <= _end and start > 0)

    for target = start, _end, 1 do
        assert(target <= #entries)
        local entry = entries[target]
        local matches = positions[target]
        local index = (target - start) + 1
        assert(#matches % 2 == 0 and entry ~= nil)

        local decors = vim.api.nvim_buf_get_extmarks(
            buffer, LIST_DECORATED_NAMESPACE,
            { index - 1, 0 }, { index - 1, -1 },
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
                index - 1,
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
                    end_line = index - 1,
                    end_col = offset + byte_end
                }
            )
        end
    end
    Async.yield()
end

--- Applies decorators as extmarks to the visible portion of the buffer.
--- @param buffer integer Buffer handle
--- @param start integer First displayed
--- @param _end integer Last displayed
--- @param entries table The entry data
--- @param decorators table List of decorators
--- @param display function|string|nil Display/formatter
local function decorate_range(buffer, start, _end, entries, decorators, display)
    vim.api.nvim_buf_clear_namespace(buffer,
        LIST_DECORATED_NAMESPACE, 0, -1
    )

    if _end == 0 then return end
    assert(start <= _end and start > 0)

    local oldma = vim.bo[buffer].modifiable
    vim.bo[buffer].modifiable = true

    for target = start, _end, 1 do
        local entry = entries[target]
        local index = (target - start) + 1
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
                index - 1, 0, index - 1, 0, { decor }
            )

            local offset = 0
            for position, highlight in ipairs(highlights) do
                local decor_item = content[position]
                local end_col = offset + #decor_item
                vim.api.nvim_buf_set_extmark(
                    buffer,
                    LIST_DECORATED_NAMESPACE,
                    index - 1,
                    offset,
                    {
                        strict = true,
                        hl_eol = false,
                        invalidate = true,
                        ephemeral = false,
                        undo_restore = false,
                        end_col = end_col,
                        end_line = index - 1,
                        right_gravity = true,
                        end_right_gravity = true,
                        hl_group = highlight,
                    }
                )
                offset = end_col + 1
            end
        end
    end

    vim.bo[buffer].modifiable = oldma
    vim.bo[buffer].modified = false
    Async.yield()
end

--- Sets/unsets signs for toggled (selected) items in the list.
--- @param buffer integer Buffer handle
--- @param start integer First displayed
--- @param _end integer Last displayed
--- @param name string Sign name
--- @param toggled table Toggle state
local function toggle_range(buffer, start, _end, name, toggled)
    vim.fn.sign_unplace(
        "list_toggle_entry_group",
        { buffer = buffer }
    )

    if _end == 0 then return end
    assert(start <= _end and start > 0)

    for target = start, _end, 1 do
        local line = tostring(target)
        local index = (target - start) + 1
        if (toggled.all == true and toggled.entries[line] == nil) or toggled.entries[line] == true then
            vim.fn.sign_place(target,
                "list_toggle_entry_group",
                name, buffer,
                {
                    lnum = index,
                    priority = 10,
                }
            )
        end
    end
end

--- Asynchronously displays the results of the previewer to the preview window.
--- @param previewer boolean|Select.Preview subclass
--- @param entry any Entry to preview
--- @param window integer Preview window
--- @param buffer integer Preview buffer (fallback)
local function display_entry(previewer, entry, window, buffer)
    vim.schedule(function()
        if window == nil or not vim.api.nvim_win_is_valid(window) then
            return
        end
        local old_ignore = vim.o.eventignore
        vim.o.eventignore = "all"
        local ok, res, msg = pcall(previewer.preview, previewer, entry, window)
        if ok and res == false then
            if buffer ~= nil and vim.api.nvim_buf_is_valid(buffer) then
                vim.api.nvim_win_set_buf(window, buffer)
                vim.api.nvim_win_set_cursor(window, { 1, 0 })
                populate_buffer(buffer, {
                    msg or "Unable to preview current entry",
                })
            end
        elseif not ok and res and #res > 0 then
            vim.notify(res, vim.log.levels.ERROR)
        end
        vim.o.eventignore = old_ignore
    end)
end

--- Create a new buffer previewer instance, the converter is used to map the entry to a table with bufnr, filename, lnum and col fields. By
--- default the converter is `entry_mapper`, which tries its best to extract those fields from the entry.
--- @param ignored? string[]|nil A list of ignored file extensions that must not be previewed by vim, this usually includes executable file formats
--- @param converter? function|nil A function that takes the entry and returns a table with bufnr, filename, lnum and col fields.
function Select.BufferPreview.new(ignored, converter)
    local obj = Select.Preview.new()
    setmetatable(obj, Select.BufferPreview)
    obj.converter = converter or Select.default_converter
    obj.ignored = ignored or {
        -- Executable/Binary
        "exe", "dll", "so", "dylib", "bin", "app", "msi",
        -- Archives
        "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "zst", "lzma", "lz4",
        -- Disk Images
        "iso", "img", "dmg", "vhdx", "vhd", "vdi", "vmdk",
        -- Media
        "mp3", "mp4", "avi", "mkv", "mov", "wav", "flac",
        "jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff",
        -- Documents
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt",
        -- Databases
        "db", "sqlite", "sqlite3", "mdb",
        -- Virtual Machines
        "ova", "ovf",
        -- Game Files
        "pak", "dat", "sav",
        -- Other Binary
        "class", "jar", "pyc", "mo",
        -- System
        "sys", "drv",
        -- Fonts
        "ttf", "otf", "woff", "woff2"
    }
    obj.buffers = {}
    return obj
end

--- Clean up any buffers that were created by the buffer previewer, this should be called when the previewer is no longer needed
function Select.BufferPreview:clean()
    self.buffers = buffer_delete(self.buffers)
end

--- Preview the entry by opening it in a buffer, if the entry has a valid bufnr or filename it is used to open the buffer, otherwise
--- an empty buffer is created. If the filename has an ignored extension the entry is not previewed.
--- @param entry any The entry to preview, this is passed to the converter function to extract the bufnr, filename, lnum and col fields.
--- @param window integer The window ID of the preview window where the output should be displayed.
--- @return boolean, any? Returns false if the entry could not be previewed
function Select.BufferPreview:preview(entry, window)
    entry = self.converter(entry)
    if entry == false or not vim.api.nvim_win_is_valid(window) then
        return false
    end
    assert(entry ~= nil)

    local buffer
    if entry.bufnr and vim.api.nvim_buf_is_valid(entry.bufnr) then
        buffer = entry.bufnr
    elseif entry.filename and vim.fn.bufexists(entry.filename) ~= 0 then
        buffer = vim.fn.bufnr(entry.filename, false)
    elseif entry.filename and vim.loop.fs_stat(entry.filename) then
        local ext = vim.fn.fnamemodify(entry.filename, ':e') or ""
        if vim.tbl_contains(self.ignored, string.lower(ext)) then
            return false, "Unable to preview an ignored entry"
        end
        buffer = assert(vim.fn.bufadd(entry.filename))
        initialize_buffer(buffer, "", "")
        vim.api.nvim_create_autocmd("BufWinEnter", {
            buffer = buffer,
            callback = function(args)
                assert(utils.table_remove(
                    self.buffers,
                    args.buf
                ) == true)
                restore_buffer(assert(args.buf))
                vim.schedule(function()
                    vim.cmd.edit({ bang = true })
                end)
                return true
            end
        })
        assert(not vim.tbl_contains(self.buffers, buffer))
        table.insert(self.buffers, buffer)
    else
        return false, "Unable to read or access current entry"
    end

    local cursor = { entry.lnum or 1, entry.col and (entry.col - 1) or 0 }
    assert(buffer ~= nil and vim.api.nvim_buf_is_valid(buffer))

    local ok, err = pcall(vim.fn.bufload, buffer)
    if ok then
        vim.api.nvim_win_set_buf(window, buffer)
        ok, err = pcall(vim.api.nvim_win_set_cursor, window, cursor)
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
    elseif err and #err > 0 then
        return ok, err
    else
        return false, "Unable to load the entry into a buffer"
    end
    return true
end

--- Create a new custom previewer instance, the callback is invoked on each entry that has to be previewed
--- @param callback? function A function that takes the entry, buffer and window as arguments and returns optionally the lines, filetype, buftype and cursor position.
function Select.CustomPreview.new(callback)
    local obj = Select.Preview.new()
    setmetatable(obj, Select.CustomPreview)
    obj.callback = assert(callback)
    obj.buffers = {}
    return obj
end

--- Clean up any buffers that were created by the custom previewer, this should be called when the previewer is no longer needed
function Select.CustomPreview:clean()
    self.buffers = buffer_delete(self.buffers)
end

--- Preview the entry by invoking the user-defined callback, the callback is passed the entry, buffer and window as arguments and can return
--- optionally the lines, filetype, buftype and cursor position.
--- @param entry any The entry to preview, this is passed as-is to the user-defined callback.
--- @param window integer The window ID of the preview window where the output should be displayed.
--- @return boolean Returns false if the entry could not be previewed
function Select.CustomPreview:preview(entry, window)
    if entry == false or not vim.api.nvim_win_is_valid(window) then
        return false
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
            if cursor and type(cursor) == "table" and #cursor == 2 and cursor[2] then
                vim.api.nvim_win_set_cursor(window, cursor)
            end
        else
            populate_buffer(buffer, {
                lines or "Unable to preview current entry"
            })
        end
        assert(not vim.tbl_contains(self.buffers, buffer))
        table.insert(self.buffers, buffer)
    else
        local buffer = assert(vim.fn.bufnr(name, false))
        vim.api.nvim_win_set_buf(window, buffer)
    end
    return true
end

--- Create a new command previewer instance, the command is run in a terminal job and the output is streamed to the preview buffer, the
--- converter is used to map the entry to a table with bufnr, filename, lnum and col fields. By default the converter is `entry_mapper`,
--- which tries its best to extract those fields from the entry.
--- @param command string|table The command to run, can be a string or a table where the first element is the command and the rest are arguments.
--- @param converter? function|nil A function that takes the entry and returns a table with bufnr, filename, lnum and col fields.
function Select.CommandPreview.new(command, converter)
    local obj = Select.Preview.new()
    setmetatable(obj, Select.CommandPreview)
    obj.converter = converter or Select.default_converter
    obj.command = assert(command)
    obj.buffers = {}
    obj.jobs = {}
    return obj
end

--- Clean up any buffers and jobs that were created by the command previewer, this should be called when the previewer is no longer needed
function Select.CommandPreview:clean()
    buffer_delete(self.buffers)
    vim.tbl_map(vim.fn.jobstop, self.jobs)
    self.buffers, self.jobs = {}, {}
end

--- Preview the entry by running the command in a terminal job and streaming the output to the preview window, the command is run with the filename from the entry as the last argument, the entry is converted using the converter function
--- @param entry any The entry to preview, this is converted using the converter function to a table with bufnr, filename, lnum and col fields.
--- @param window integer The window ID of the preview window where the output should be displayed.
--- @return boolean|nil Returns false if the entry could not be previewed, nil otherwise.
function Select.CommandPreview:preview(entry, window)
    entry = self.converter(entry)
    if entry == false or not vim.api.nvim_win_is_valid(window) then
        return false
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
                    pcall(vim.api.nvim_chan_send, chan, value)
                    pcall(vim.api.nvim_chan_send, chan, "\r\n")
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
    obj.converter = converter or Select.default_converter
    return obj
end

--- Decorate the entry with an icon based on the filename and its extension, uses nvim-web-devicons if available
--- @param entry any The entry to decorate, this is converted using the converter function to a table with bufnr, filename, lnum and col fields.
--- @param line? string|nil The line to decorate, if nil the decoration is skipped
--- @return string|nil The icon string if available, nil otherwise
--- @return string|nil The highlight group for the icon, "SelectDecoratorDefault" if no specific highlight is found
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

--- Decorate the entry by combining the results of all configured decorators using the delimiter, the configured highlight or "SelectDecoratorDefault" is used for the entire combined result
--- @param entry any The entry to decorate
--- @return string|nil The combined decoration string if any decorator returned a non-nil result, nil otherwise
--- @return string The highlight group for the combined decoration, the configured highlight or "SelectDecoratorDefault" if none was configured
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

--- Decorate the entry by running the configured decorators in order and returning the first non-nil result, the highlight group returned by the decorator or "SelectDecoratorDefault" if none was returned
--- @param entry any The entry to decorate
--- @return string|nil The decoration string if any decorator returned a non-nil result, nil otherwise
--- @return string|nil The highlight group for the decoration, "SelectDecoratorDefault" if none was returned by the decorator
function Select.ChainDecorator:decorate(entry)
    for _, decor in ipairs(self.decorators) do
        local str, hl = decor:decorate(entry)
        if str and type(str) == "string" and #str > 0 then
            return str, hl or "SelectDecoratorDefault"
        end
    end
    return nil, nil
end

--- Handles prompt input and invokes the selection list update callback.
--- @param input string? The current prompt query or nil
--- @param callback function|boolean? Input callback function (query: string|nil)
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

--- Retrieves the current query string from the prompt buffer.
--- @param lnum integer? The 1-based line number to retrieve (default: 1)
--- @return string|nil Current prompt line value
function Select:_prompt_getquery(lnum)
    if not self.prompt_buffer or not vim.api.nvim_buf_is_valid(self.prompt_buffer) then
        return nil
    end
    return buffer_getline(self.prompt_buffer, lnum)
end

--- Computes and returns the currently selected entries.
--- @return table List of selected entry tables
function Select:_list_selection()
    if not self.list_buffer or not vim.api.nvim_buf_is_valid(self.list_buffer) then
        return {}
    end

    local toggled = assert(self._state.toggled)
    local entries = assert(self._state.entries)
    local size = toggled_count(entries, toggled)
    if size == 0 then
        local cursor = assert(self._state.cursor)
        assert(cursor[1] >= 1 and cursor[1] <= #entries)
        return { entries[cursor[1]] }
    else
        local index, current = 1, 0
        local selection = utils.obtain_table(size)
        for line, status in pairs(toggled.entries) do
            if status == true then
                local position = tonumber(line)
                assert(position <= #entries)
                selection[current + 1] = entries[position]
                current = current + 1
            end
        end
        while index <= #entries and current < size do
            local line = tostring(index)
            local status = toggled.entries[line]
            if toggled.all == true and status == nil then
                selection[current + 1] = entries[index]
                current = current + 1
            end
            index = index + 1
        end
        utils.resize_table(selection, size, nil)
        assert(#selection == size and current == size)
        return selection
    end
end

--- Wraps a callback to run safely with Select as the first argument
--- @param callback function Callback taking select instance as argument
--- @return function
function Select:_make_callback(callback)
    return function()
        return utils.safe_call(
            callback, self
        )
    end
end

--- Sets up buffer-local key mappings for the component buffer.
--- @param buffer integer Buffer handle
--- @param mode string Mode ("i", "n", etc)
--- @param mappings table Key map { lhs = fn }
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

--- Internal: populates the visible portion of the list display buffer.
function Select:_populate_list()
    local entries = self._state.entries
    if entries and #entries >= 0 then
        local position = vim.api.nvim_win_get_cursor(self.list_window)
        local height = vim.api.nvim_win_get_height(self.list_window)
        local cursor = assert(self._state.cursor)
        populate_range(
            self.list_buffer,
            math.max(1, cursor[1] - (position[1] - 1)),
            math.min(#entries, cursor[1] + (height - position[1])),
            entries, self._options.display)
    end
end

--- Internal: displays toggle signs for current toggled state.
function Select:_display_toggle()
    local toggled = self._state.toggled
    local entries = self._state.entries
    if toggled ~= nil and entries and #entries >= 0 then
        local sign_name = string.format(
            "list_toggle_entry_sign_%d",
            self.list_buffer
        )
        local position = vim.api.nvim_win_get_cursor(self.list_window)
        local height = vim.api.nvim_win_get_height(self.list_window)
        local cursor = assert(self._state.cursor)
        toggle_range(
            self.list_buffer,
            math.max(1, cursor[1] - (position[1] - 1)),
            math.min(#entries, cursor[1] + (height - position[1])),
            sign_name, toggled
        )
    end
end

--- Internal: applies search highlights to list entries.
function Select:_highlight_list()
    local entries = self._state.entries
    local positions = self._state.positions
    if entries and #entries >= 0 and positions and #positions > 0 then
        local position = vim.api.nvim_win_get_cursor(self.list_window)
        local height = vim.api.nvim_win_get_height(self.list_window)
        local cursor = assert(self._state.cursor)
        assert(#entries == #positions)
        highlight_range(
            self.list_buffer,
            math.max(1, cursor[1] - (position[1] - 1)),
            math.min(#entries, cursor[1] + (height - position[1])),
            entries, positions,
            self._options.display)
    end
end

--- Internal: applies decorators to visible list display.
function Select:_decorate_list()
    local entries = self._state.entries
    local decorators = self._options.decorators
    if entries and #entries >= 0 and decorators and #decorators > 0 then
        local position = vim.api.nvim_win_get_cursor(self.list_window)
        local height = vim.api.nvim_win_get_height(self.list_window)
        local cursor = assert(self._state.cursor)
        decorate_range(
            self.list_buffer,
            math.max(1, cursor[1] - (position[1] - 1)),
            math.min(#entries, cursor[1] + (height - position[1])),
            entries, decorators,
            self._options.display)
    end
end

--- Internal: renders preview for selected entry or clears if no entries.
function Select:_display_preview()
    local window = self.preview_window
    local entries = self._state.entries
    local previewer = self._options.preview
    if entries and previewer ~= nil and previewer ~= false
        and window and vim.api.nvim_win_is_valid(window)
    then
        if #entries == 0 then
            local buffer = assert(self.preview_buffer)
            vim.api.nvim_win_set_buf(window, buffer)
            vim.api.nvim_win_set_cursor(window, { 1, 0 })
            populate_buffer(buffer, utils.EMPTY_TABLE)
        else
            local cursor = assert(self._state.cursor)
            local entry = assert(entries[cursor[1]])
            display_entry(
                previewer, entry,
                self.preview_window,
                self.preview_buffer
            )
        end
    end
end

--- Internal: schedules a UI render of list+related features.
function Select:_render_list()
    local executor = Async.wrap(function()
        if self.list_buffer and vim.api.nvim_buf_is_valid(self.list_buffer) then
            self:_populate_list()
        end

        if self.list_window and vim.api.nvim_win_is_valid(self.list_window) then
            self:_decorate_list()
            self:_highlight_list()
            self:_display_toggle()
            self:_display_preview()
            vim.api.nvim_win_call(
                self.list_window,
                vim.cmd.redraw
            )
        end
    end)

    local renderer = function()
        self._state.renderer = executor()
        Scheduler.add(self._state.renderer)
    end

    if self:_is_rendering() then
        self._state.renderer:await(renderer)
        self:_stop_rendering()
    else
        renderer()
    end
end

--- Resets the state variables for a Select instance.
function Select:_reset_state()
    self._state.streaming = false
    self._state.positions = nil
    self._state.entries = nil
    self._state.query = ""
    self._state.toggled = {
        all = false,
        entries = {}
    }
end

--- Calls preview:init() if preview instance provided (initialization).
function Select:_init_preview()
    local preview = self._options.preview or nil
    if type(preview) == "table" and preview.init then
        preview:init()
    end
end

--- Calls preview:clean() if preview instance provided (cleanup).
function Select:_clean_preview()
    local preview = self._options.preview or nil
    if type(preview) == "table" and preview.clean then
        preview:clean()
    end
end

--- Calls :init() on all decorator tables (if present).
function Select:_init_decorators()
    for _, decor in ipairs(self._options.decorators or {}) do
        if type(decor) == "table" and decor.init then
            decor:init()
        end
    end
end

--- Calls :clean() on all decorator tables (if present).
function Select:_clean_decorators()
    for _, decor in ipairs(self._options.decorators or {}) do
        if type(decor) == "table" and decor.clean then
            decor:clean()
        end
    end
end

--- Destroys and deletes all buffers and internal state.
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

    self:_reset_state()
end

--- Clears content/state but does not close UI/buffers.
--- @param force boolean Cleanup decorators and preview if true
function Select:_clear_view(force)
    local clearer = function()
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
            populate_buffer(self.list_buffer, utils.EMPTY_TABLE)
        end
        if self.preview_buffer and vim.api.nvim_buf_is_valid(self.preview_buffer) then
            populate_buffer(self.preview_buffer, utils.EMPTY_TABLE)
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

        if force == true then
            self:_clean_decorators()
            self:_clean_preview()
        end
        self:_reset_state()
    end

    if self:_is_rendering() then
        self._state.renderer:await(clearer)
        self:_stop_rendering()
        self._state.renderer = nil
    else
        clearer()
    end
end

--- Fully closes the UI: destroys windows, optionally cleans up state.
--- @param force boolean Cleanup decorators and preview if true
function Select:_close_view(force)
    local closer = function()
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

        if force == true then
            self:_clean_decorators()
            self:_clean_preview()
            self:_destroy_view()
        end
    end

    if self:_is_rendering() then
        self._state.renderer:await(closer)
        self:_stop_rendering()
        self._state.renderer = nil
    else
        closer()
    end
end

--- Returns true if there is a running renderer coroutine.
--- @return boolean
function Select:_is_rendering()
    if self._state.renderer then
        return self._state.renderer:is_running()
    end
    return false
end

--- Cancels and clears the running renderer coroutine.
function Select:_stop_rendering()
    if self._state.renderer then
        self._state.renderer:cancel()
        self._state.renderer = nil
    end
end

--- Closes all open windows associated with the selection interface and returns focus to the source window. This action however does not
--- clear any of the internal state and acts more akin to calling `hide` method on select instance
--- @param callback? function A function that takes no arguments and returns nothing.
function Select:close_view(callback)
    self:_close_view(false)
    utils.safe_call(callback)
end

-- Does simply invoke the callback without any arguments or any context, when the action is invoked through the select interface. Useful to perform stateless operations or simply ignore an existing action binding temporarily.
--- @param callback? function A function that takes no arguments and returns nothing.
function Select:noop_select(callback)
    utils.safe_call(callback)
end

--- Executes user callback with the current selection passed in, the action performs a no operation and is entirely reliant on the user callback to perform any action, this is a generic function used to invoke the user callback with current selection
--- @param callback? function A function that takes the selection and returns nothing, the selection is a table of entries currently selected in the list.
function Select:default_select(callback)
    local selection = callback and self:_list_selection()
    self:_close_view(true)
    utils.safe_call(callback, selection)
end

--- Sends commands to the prompt window by sending normal mode commands to it, this is a generic function used by other selection methods. The mode argument can be "n" for normal mode commands or "i" for insert mode commands.
--- @param input string The input to send to the prompt window, can be any insert mode command.
function Select:position_prompt(input, callback)
    send_input(input, self.prompt_window, callback, "i")
end

--- Sends commands to the preview window by sending normal mode commands to it, this is a generic function used by other selection methods.
--- @param input string The input to send to the preview window, can be any normal mode command.
function Select:scroll_preview(input, callback)
    send_input(input, self.preview_window, callback, "n")
end

--- Moves the cursor in the list by in a specified direction, this is a generic function used by other selection methods. The dir argument can be a positive or negative integer, where positive values move the cursor down, negative values move the cursor up, values greater than 1 move to the end, and values less than -1 move to the start.
--- @param dir integer The direction to move the cursor, positive values move down, negative values move up, values greater than 1 move to the end, values less than -1 move to the start
function Select:move_cursor(dir, callback)
    local entries = self._state.entries
    local cursor = self._state.cursor
    if not entries or #entries == 0 then
        return
    end

    assert(cursor[1] >= 1 and cursor[1] <= #entries)
    assert(vim.wo[self.list_window].scrolloff == 0)

    local position = vim.api.nvim_win_get_cursor(self.list_window)
    local height = vim.api.nvim_win_get_height(self.list_window)

    local offset = self._options.list_offset
    height = math.min(height, #entries)

    if cursor[1] == 1 and dir < 0 then cursor[1] = 0 end
    cursor[1] = (cursor[1] + dir) % (#entries + 1)
    if cursor[1] == 0 and dir > 0 then cursor[1] = 1 end

    if dir > 1 then
        cursor[1] = #entries
        position[1] = height
        self:_render_list()
    elseif dir < -1 then
        cursor[1] = 1
        position[1] = 1
        self:_render_list()
    else
        if (dir < 0 and position[1] > (offset + 1)) or (dir > 0 and position[1] < (height - offset)) then
            position[1] = math.min(math.max(position[1] + dir, 1), height)
        else
            if cursor[1] <= offset then
                position[1] = cursor[1]
            elseif cursor[1] >= (#entries - offset) then
                position[1] = height - (#entries - cursor[1])
            end
            position[1] = math.max(math.min(position[1], height), 1)
            self:_render_list()
        end
    end
    local max_line = vim.api.nvim_buf_line_count(self.list_buffer)
    if max_line > 0 then
        position[1] = math.max(1, math.min(position[1], max_line))
    else
        position[1] = 1
    end
    vim.api.nvim_win_set_cursor(self.list_window, position)

    self:_display_preview()

    local selection = callback and self:_list_selection()
    utils.safe_call(callback, selection)
end

--- Executes command against the selected entry as an argument passed to that command, this is a generic function used by other
--- selection methods.
--- @param command string The command to execute, can be any vim command that takes a filename or buffer number as an argument, like edit, split, vsplit, tabedit, etc.
--- @param mods? table|nil A table of command modifiers to pass to the command,
--- @param callback? function A function that takes the selection and returns a table of entries to execute the command against, if the callback returns false, the command is not executed.
function Select:exec_command(command, mods, callback)
    local selection = self:_list_selection()
    self:_close_view(true)

    local ok, result = utils.safe_call(callback, selection)
    if ok and result == false then
        return
    else
        result = vim.tbl_map(
            Select.default_converter,
            result or selection
        )
    end

    for _, entry in ipairs(result) do
        if not entry or entry == false then
            goto continue
        end

        local cmd, bang = nil, nil
        local arg = entry.filename
        if entry.bufnr ~= nil then
            if command == "edit" then
                command = "buffer"
                bang = true
            elseif command == "split" then
                command = "sbuffer"
                bang = true
            elseif command == "tabedit" then
                command = "tab"
                cmd = "sbuffer"
            end
            arg = entry.bufnr
        end

        assert(arg ~= nil)
        vim.cmd[command]({
            args = { arg },
            mods = mods,
            bang = bang,
            cmd = cmd,
        })

        local col = entry.col or 1
        local lnum = entry.lnum or 1
        local position = { lnum, col - 1 }
        pcall(vim.api.nvim_win_set_cursor, 0, position)

        ::continue::
    end
end

--- Sends the selected entries to the quickfix or location list, using the provided callback to extract filenames from entries, the type
--- argument value must be either "quickfix" or "loclist".
--- @param type string The type of list to send the entries to, can be either "quickfix" or "loclist".
--- @param callback? function A function that takes the selection and returns a table of entries to send. If the callback returns false, the entries are not sent to the fix list.
function Select:send_fixlist(type, callback)
    local selection = self:_list_selection()
    self:_close_view(true)

    local ok, result = utils.safe_call(callback, selection)
    if ok and result == false then
        return
    else
        result = vim.tbl_map(
            Select.default_converter,
            result or selection
        )
    end

    local args = {
        nr = "$",
        items = vim.tbl_filter(function(item)
            return item ~= nil and item ~= false
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

--- Toggles the preview window, opening it if it is closed and closing it if it is open. The callback is invoked with the current selection after toggling the preview window. If the prompt list or preview options are not enabled, this function does nothing.
--- @param callback? function A function that takes the selection and returns nothing, the selection is a table of entries currently selected in the list.
function Select:toggle_preview(callback)
    if not self._options.prompt_list or not self._options.preview then
        return
    end

    if not self.preview_window or not vim.api.nvim_win_is_valid(self.preview_window) then
        local selection_height = compute_height(self._options.window_ratio, 2.0)
        local position = vim.api.nvim_win_get_cursor(self.list_window)
        self.preview_window = vim.api.nvim_open_win(self.preview_buffer, false, {
            split = self.list_window and "above" or "below",
            height = selection_height,
            noautocmd = false,
            win = self.list_window or -1,
        })
        vim.api.nvim_win_set_height(
            self.preview_window,
            selection_height
        )
        vim.api.nvim_win_set_height(
            self.list_window,
            selection_height
        )
        self.preview_window = initialize_window(
            self.preview_window,
            self._options.window_options.preview
        )
        position[2], position[1] = 0, math.min(position[1], selection_height)
        vim.api.nvim_win_set_cursor(self.list_window, position)
        vim.api.nvim_win_call(self.list_window, function()
            vim.cmd.normal({ args = { "gg" }, bang = true })
        end)
        self:_display_preview()
    else
        local selection_height = compute_height(self._options.window_ratio, 1.0)
        vim.api.nvim_win_set_height(self.list_window, selection_height)
        vim.api.nvim_win_close(self.preview_window, true)
    end

    local selection = callback and self:_list_selection()
    utils.safe_call(callback, selection)
end

--- Toggles the selection state of the current entry in the list, using signs to indicate selection, and moves the cursor down by one entry by default.
--- @param callback? function A function that takes the selection and returns nothing, the selection is a table of entries currently selected in the list. If the callback is nil, no action is performed after toggling the entry.
function Select:toggle_entry(callback)
    local entries = assert(self._state.entries)
    local cursor = assert(self._state.cursor)

    local line = tostring(cursor[1])
    local toggled = self._state.toggled

    local istoggled = toggled.entries[assert(line)]
    if istoggled == nil then istoggled = toggled.all end

    toggled.entries[line] = not istoggled
    self:_display_toggle()

    virtual_content(self.prompt_buffer, LIST_TOGGLE_NAMESPACE, 0, -1, {
        { string.format("(%d)", toggled_count(entries, toggled)), "SelectToggleCount" }
    })

    local selection = callback and self:_list_selection()
    utils.safe_call(callback, selection)
end

--- Sets the selection state of all entries in the list to selected, using signs to indicate selection. The callback is invoked with the current selection after selecting all entries.
--- @param callback? function A function that takes the selection and returns nothing, the selection is a table of entries currently selected in the list, or the entry where the cursor is currently positioned if no entries are selected.
function Select:toggle_all(callback)
    self._state.toggled.all = true
    self._state.toggled.entries = {}
    self:_display_toggle()

    virtual_content(self.prompt_buffer, LIST_TOGGLE_NAMESPACE, 0, -1, {
        { string.format("(%d)", #self._state.entries), "SelectToggleCount" }
    })

    local selection = callback and self:_list_selection()
    utils.safe_call(callback, selection)
end

--- Clears the selection state of all entries in the list, removing any signs used to indicate selection. The callback is invoked with the current selection after clearing the selection.
--- @param callback? function A function that takes the selection and returns nothing, the selection is a table of entries currently selected in the list. Or the entry where the cursor is currently positioned if no entries are selected.
function Select:toggle_clear(callback)
    self._state.toggled.all = false
    self._state.toggled.entries = {}
    self:_display_toggle()

    virtual_content(self.prompt_buffer, LIST_TOGGLE_NAMESPACE, 0, -1, {
        { "(0)", "SelectToggleCount" }
    })

    local selection = callback and self:_list_selection()
    utils.safe_call(callback, selection)
end

--- Toggles the selection state of all entries in the list, if all entries are selected, it clears the selection, otherwise it selects all entries. The callback is invoked with the current selection after toggling.
--- @param callback? function A function that takes the selection and returns nothing, the selection is a table of entries currently selected in the list.
function Select:toggle_list(callback)
    if self._state.toggled.all == true then
        self:toggle_clear(callback)
    else
        self:toggle_all(callback)
    end
end

--- Toggles the selection state of the current entry in the list, using signs to indicate selection, and moves the cursor up by one entry. By default.
--- @param callback? function A function that takes the selection and is not required to return anything
function Select:toggle_up(callback)
    self:toggle_entry(function()
        self:move_cursor(-1, callback)
    end)
end

--- Toggles the selection state of the current entry in the list, using signs to indicate selection, and moves the cursor down by one entry. By default.
--- @param callback? function A function that takes the selection and is not required to return anything
function Select:toggle_down(callback)
    self:toggle_entry(function()
        self:move_cursor(1, callback)
    end)
end

--- Move the prompt cursor to the beginning of the prompt line.
--- @param callback? function A function that takes prompt cursor position and returns nothing, the position is a table with line and column fields.
function Select:prompt_home(callback)
    self:position_prompt("<home>", callback)
end

--- Move the prompt cursor to the end of the prompt line
--- @param callback? function A function that takes prompt cursor position and returns nothing, the position is a table with line and column fields.
function Select:prompt_end(callback)
    self:position_prompt("<end>", callback)
end

--- Move the prompt cursor one position to the left
--- @param callback? function A function that takes prompt cursor position and returns nothing, the position is a table with line and column fields.
function Select:prompt_left(callback)
    self:position_prompt("<left>", callback)
end

--- Move the prompt cursor one position to the right
--- @param callback? function A function that takes prompt cursor position and returns nothing, the position is a table with line and column fields.
function Select:prompt_right(callback)
    self:position_prompt("<right>", callback)
end

-- Move the prompt cursor one word to the left
--- @param callback? function A function that takes prompt cursor position and returns nothing, the position is a table with line and column fields.
function Select:prompt_left_word(callback)
    self:position_prompt("<c-o>b", callback)
end

-- Move the prompt cursor one word to the right
--- @param callback? function A function that takes prompt cursor position and returns nothing, the position is a table with line and column fields.
function Select:prompt_right_word(callback)
    self:position_prompt("<c-o>w", callback)
end

-- Delete a word from the prompt forwards
--- @param callback? function A function that takes prompt cursor position and returns nothing, the position is a table with line and column fields.
function Select:prompt_delete_word_right(callback)
    self:position_prompt("<c-o>:noautocmd lockmarks normal! \"_dw<cr>", callback)
end

-- Delete a word from the prompt backwards
--- @param callback? function A function that takes prompt cursor position and returns nothing, the position is a table with line and column fields.
function Select:prompt_delete_word_left(callback)
    self:position_prompt("<c-o>:noautocmd lockmarks normal! \"_db<cr>", callback)
end

-- Delete the prompt query up until the home position
--- @param callback? function A function that takes prompt cursor position and returns nothing, the position is a table with line and column fields.
function Select:prompt_delete_home(callback)
    self:position_prompt("<c-o>:noautocmd lockmarks normal! \"_d^<cr>", callback)
end

--- Delete the prompt query up until the end position
--- @param callback? function A function that takes prompt cursor position and returns nothing, the position is a table with line and column fields.
function Select:prompt_delete_end(callback)
    self:position_prompt("<c-o>:noautocmd lockmarks normal! \"_d$<cr>", callback)
end

--- Scrolls the preview window down by one page.
--- @param callback? function A function that takes the curosr position in the preview window and returns nothing, the position is a table with line and column fields.
function Select:page_up(callback)
    self:scroll_preview("<c-b>", callback)
end

--- Scrolls the preview window up by one page.
--- @param callback? function A function that takes the curosr position in the preview window and returns nothing, the position is a table with line and column fields.
function Select:page_down(callback)
    self:scroll_preview("<c-f>", callback)
end

--- Scrolls the preview window up by half a page.
--- @param callback? function A function that takes the curosr position in the preview window and returns nothing, the position is a table with line and column fields.
function Select:half_up(callback)
    self:scroll_preview("<c-u>", callback)
end

--- Scrolls the preview window down by half a page.
--- @param callback? function A function that takes the curosr position in the preview window and returns nothing, the position is a table with line and column fields.
function Select:half_down(callback)
    self:scroll_preview("<c-d>", callback)
end

--- Scrolls the preview window up by one line.
--- @param callback? function A function that takes the curosr position in the preview window and returns nothing, the position is a table with line and column fields.
function Select:line_up(callback)
    self:scroll_preview("<c-y>", callback)
end

--- Scrolls the preview window down by one line.
--- @param callback? function A function that takes the curosr position in the preview window and returns nothing, the position is a table with line and column fields.
function Select:line_down(callback)
    self:scroll_preview("<c-e>", callback)
end

--- Moves the cursor to the next entry in the list.
--- @param callback? function A function that takes the selection and returns nothing, the selection is a table of entries currently selected in the list.
function Select:move_down(callback)
    self:move_cursor(1, callback)
end

--- Moves the cursor to the previous entry in the list.
--- @param callback? function A function that takes the selection and returns nothing, the selection is a table of entries currently selected in the list.
function Select:move_up(callback)
    self:move_cursor(-1, callback)
end

--- Moves the cursor to the first valid entry in the list
--- @param callback? function A function that takes the selection and returns nothing, the selection is a table of entries currently selected in the list.
function Select:move_top(callback)
    self:move_cursor(-100, callback)
end

--- Moves the cursor to the last valid entry in the list
--- @param callback? function A function that takes the selection and returns nothing, the selection is a table of entries currently selected in the list.
function Select:move_bot(callback)
    self:move_cursor(100, callback)
end

--- Selects the next entry in the list and acts on it
--- @param callback? function A function that transforms the selection and returns a table of entries to open, if the callback returns false, no action is performed.
function Select:select_next(callback)
    self:move_cursor(1, function(_)
        self:exec_command("edit", utils.EMPTY_TABLE, callback)
    end)
end

--- Selects the prev entry in the liset and acts on it
--- @param callback? function A function that transforms the selection and returns a table of entries to open, if the callback returns false, no action is performed.
function Select:select_prev(callback)
    self:move_cursor(-1, function(_)
        self:exec_command("edit", utils.EMPTY_TABLE, callback)
    end)
end

--- Opens the selected entry in the origin/source window.
--- @param callback? function A function that transforms the selection and returns a table of entries to open, if the callback returns false, no action is performed.
function Select:select_entry(callback)
    self:exec_command("edit", utils.EMPTY_TABLE, callback)
end

--- Opens the selected entry in a horizontal split.
--- @param callback? function A function that transforms the selection and returns a table of entries to open, if the callback returns false, no action is performed.
function Select:select_horizontal(callback)
    self:exec_command("split", { horizontal = true }, callback)
end

--- Opens the selected entry in a vertical split.
--- @param callback? function A function that transforms the selection and returns a table of entries to open, if the callback returns false, no action is performed.
function Select:select_vertical(callback)
    self:exec_command("split", { vertical = true }, callback)
end

--- Opens the selected entry in a new tab.
--- @param callback? function A function that transforms the selection and returns a table of entries to open, if the callback returns false, no action is performed.
function Select:select_tab(callback)
    self:exec_command("tabedit", utils.EMPTY_TABLE, callback)
end

--- Sends the selected entries to the quickfix list and opens it.
--- @param callback? function A function that transforms the selection and returns a table of entries to open, if the callback returns false, no action is performed.
function Select:send_quickfix(callback)
    self:send_fixlist("quickfix", callback)
end

--- Sends the selected entries to the location list and opens it.
--- @param callback? function A function that transforms the selection and returns a table of entries to open, if the callback returns false, no action is performed.
function Select:send_locliset(callback)
    self:send_fixlist("loclist", callback)
end

--- Gets the current query from the prompt input. The query is updated on each input change in the prompt. It is not extracted directly from the prompt buffer on-demand but is captured with each input change using TextChangedI and TextChanged autocmd events.
--- @return string The current query string, the query will never be nil, otherwise that represents invalid state of the selection interface.
function Select:query()
    return assert(self._state.query)
end

--- Closes the selection interface, the buffers and any state associated with the interface will be destroyed as well, to retain the selection state consider using `hide`
function Select:close()
    self:_close_view(true)
end

-- Hides the select interface, does not enforce any resource de-allocation taken up by the select interface, to enforce this use `close` method instead
function Select:hide()
    self:_close_view(false)
end

-- Clears the select interface, from any content and state, that includes the query, list and preview interfaces, but does not close the interface itself, or destroy any internal state or resources associated with it.
function Select:clear()
    self:_clear_view(false)
end

--- Checks if the selection interface is showing any entries, the entries can be rendered or set using the `list` method, which renders the specified entries into the list.
--- @return boolean True if the list is empty, false otherwise.
function Select:isempty()
    return not self._state.entries or #self._state.entries == 0
end

--- Checks if the selection interface is currently open, this is determined by checking if both the prompt and list windows are valid.
--- @return boolean True if the selection interface is open, false otherwise.
function Select:isopen()
    local prompt = self.prompt_window and vim.api.nvim_win_is_valid(self.prompt_window)
    local list = self.list_window and vim.api.nvim_win_is_valid(self.list_window)
    return list ~= nil and prompt ~= nil and list and prompt
end

--- Checks if the selection interface is valid, meaning that it has been initialized/opened at least once and has not been destroyed by calling the `close` method which would invalidate its curent state
--- @return boolean True if the select interface is still valid, false otherwise.
function Select:isvalid()
    local prompt = self.prompt_buffer and vim.api.nvim_buf_is_valid(self.prompt_buffer)
    local list = self.list_buffer and vim.api.nvim_buf_is_valid(self.list_buffer)
    return list ~= nil and prompt ~= nil and list and prompt
end

-- Render a list of entries in the list window, with optional highlighting positions. If entries is nil, it will re-render the current list fully with existing entries and positions. Sending nil for both parameters signals to the interface that the streaming of entries is complete and it should finalize the rendering. This method is optimized to handle large lists of entries efficiently by rendering only the visible portion of the list and updating it as needed around the cursor position. The list is incrementally updated as new entries are provided, allowing for a smooth and responsive user experience even with large datasets.
-- @param entries? any[]|string[]|nil The list of entries to display.
-- @param positions? integer[][]|nil The list of positions for highlighting
function Select:list(entries, positions)
    vim.validate {
        entries = { entries, { "table", "nil" }, true },
        positions = { positions, { "table", "nil" }, true },
    }
    if entries ~= nil then
        self._state.positions = positions
        self._state.entries = entries
        self._state.streaming = true
        self:_render_list()
    elseif positions == nil then
        self._state.streaming = false
    end
end

--- Render the current status of the select, providing information about the selection list, preview or prompt, as virtual text in the select interface. The status is displayed at the end of the prompt line, and can be customized with highlight groups. For example the status value can be "10/100 items" to indicate that 10 out of 100 items are currently displayed in the list. The status can also include information about the current query or any other relevant information.
--- @param status string the status data to render in the window
--- @param hl? string|nil The highlight group to use for the status text, defaults
function Select:status(status, hl)
    vim.validate {
        status = { status, "string" },
        hl = { hl, { "string", "nil" }, true },
    }

    local decor = self._options.prompt_decor or nil
    local suffix = type(decor) == "table" and assert(decor.suffix)

    virtual_content(self.prompt_buffer, LIST_STATUS_NAMESPACE, 0, 0, {
        suffix and { suffix, "SelectPrefixText" },
        { status, hl or "SelectStatusText" },
    })
end

--- Render a header at the top of the selection interface, the header can be a string or a table of strings or string/highlight pairs, where each inner table represents a block of header entries.
--- @param header string|table The header to render, can be a string or a table of strings or string/highlight pairs. For example: { {"Header 1", "HighlightGroup1"}, {"Header 2", "HighlightGroup2"} }, or { "Header 1", "Header 2" }, or { {"Header 1"}, {"Header 2"} }, or { function(select) return "Header 1", "HighlightGroup1" end, function(select) return "Header 2", "HighlightGroup2" end }
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
                elseif type(element) == "function" then
                    local hr, hi = element(self)
                    assert(hr and #hr > 0)
                    table.insert(entry, hr)
                    table.insert(entry, hi or "SelectHeaderDefault")
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

    virtual_content(
        self.prompt_buffer,
        LIST_HEADER_NAMESPACE,
        0, 0, nil, { header_entries }
    )

    -- TODO: https://github.com/neovim/neovim/issues/27967
    vim.api.nvim_win_call(self.prompt_window, function()
        local scroll_up = vim.api.nvim_replace_termcodes(
            assert("<c-b>"), false, false, true
        )
        vim.cmd.normal({ args = { scroll_up }, bang = true })
    end)
end

--- Opens the selection interface, creating necessary buffers and windows as needed, and sets up autocommands and mappings, if no set. This method would ensure that even if the interface was previously closed or hidden, it will be re-initialized and opened properly. If the interface is already open, this method is a no-op and does nothing.
function Select:open()
    if self:isopen() then
        return
    end
    local opts = assert(self._options)
    if not self:isvalid() then
        self:_init_decorators()
        self:_init_preview()
    end

    self.source_window = vim.api.nvim_get_current_win()
    local factor = (opts.prompt_list and opts.preview) and 2.0 or 1.0
    local size = compute_height(opts.window_ratio, factor)
    assert(size >= 2, "selection window size too small")

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
                    self:_close_view(false)
                    self:_clean_decorators()
                    self:_clean_preview()
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
            initialize_window(prompt_window, opts.window_options.prompt)
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
        self:header(opts.prompt_headers or {})
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
                    self:_close_view(false)
                    self:_clean_decorators()
                    self:_clean_preview()
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
            })
            vim.api.nvim_win_set_height(list_window, list_height)
            initialize_window(list_window, opts.window_options.list)

            vim.wo[list_window].scrolloff = 0
            assert(opts.list_offset <= list_height)

            local resize_list = vim.api.nvim_create_autocmd("WinResized", {
                pattern = "*",
                callback = function()
                    if vim.tbl_contains(vim.v.event.windows, self.list_window) and
                        not self:_is_rendering() and vim.api.nvim_buf_line_count(list_buffer) >= 1
                    then
                        utils.time_execution(Select._render_list, self, false)
                    end
                end
            })

            vim.api.nvim_create_autocmd("WinClosed", {
                pattern = tostring(list_window),
                callback = function()
                    pcall(vim.api.nvim_del_autocmd, resize_list)
                    self:_close_view(false)
                    return true
                end,
                once = true,
            })
        end

        self.list_buffer = list_buffer
        self.list_window = list_window
        self:_render_list()
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
            initialize_window(preview_window, opts.window_options.preview)
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

--- Default converter, which converts an entry into a table with col, lnum, bufnr and filename fields. The entry can be a table, number or string. If the entry is a table, it should have col, lnum, bufnr and filename fields. If the entry is a number, it is treated as a buffer number. If the entry is a string, it is treated as a filename. The converter returns a table with col, lnum, bufnr and filename fields. If the entry is invalid, it raises an assertion error.
--- @param entry any The entry to convert, can be a table, number or string.
--- @return table A table with col, lnum, bufnr and filename fields.
function Select.default_converter(entry)
    local col = 1
    local lnum = 1
    local fname = nil
    local bufnr = nil
    assert(entry ~= nil)

    if type(entry) == "table" then
        col = entry.col or 1
        lnum = entry.lnum or 1
        bufnr = entry.bufnr or nil
        fname = entry.filename or nil
        if bufnr and not fname and assert(vim.api.nvim_buf_is_valid(bufnr)) then
            fname = utils.get_bufname(bufnr, utils.get_bufinfo(bufnr))
        end
    elseif type(entry) == "number" then
        assert(entry > 0 and vim.api.nvim_buf_is_valid(entry))
        bufnr = entry
        fname = utils.get_bufname(bufnr, utils.get_bufinfo(bufnr))
    elseif type(entry) == "string" then
        assert(#entry > 0)
        fname = entry
        bufnr = vim.fn.bufnr(fname, false)
        bufnr = bufnr > 0 and bufnr or nil
    end

    assert(fname ~= nil or bufnr ~= nil)
    assert(#fname > 0 or bufnr > 0)

    return {
        col = col,
        lnum = lnum,
        bufnr = bufnr,
        filename = fname,
    }
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
--- @field window_options? table Options to configure the prompt, list and preview windows. The table should have keys `prompt`, `list` and `preview`, each containing a table of window local options
--- @field list_offset? integer|nil Number scroll offset lines to leave at the top and bottom of the list when moving between entries, it works just like see :h 'scrolloffset', but is internally not using the native vim property.
--- @field quickfix_open? fun() Function to open the quickfix list.
--- @field loclist_open? fun() Function to open the location list.
--- @field mappings? table<string, fun(self: Select, callback: fun(selection: any, cursor: integer[]|boolean|nil): any)> Key mappings for the selection interface. The keys are the key sequences and the values are functions that take the Select instance and an optional callback as arguments. If `false` is provided for the value of the key-value pair the mapping for that key is disabled
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
        window_options = { opts.window_options, "table", true },
        list_offset = { opts.list_offset, "number", true },
        quickfix_open = { opts.quickfix_open, "function", true },
        loclist_open = { opts.loclist_open, "function", true },
        display = { opts.display, { "function", "string", "nil" }, true },
        preview = { opts.preview, { "table", "boolean" }, true },
        decorators = { opts.decorators, "table", true },
        mappings = { opts.mappings, "table", true },
    })

    for key, mapping in pairs(opts.mappings or {}) do
        if type(mapping) == "boolean" and mapping == false then
            opts.mappings[key] = Select.noop_select
        end
    end

    opts = vim.tbl_deep_extend("force", {
        prompt_list = true,
        prompt_input = true,
        prompt_headers = nil,
        prompt_query = nil,
        prompt_decor = "› ",
        toggle_prefix = "✓",
        preview_timeout = 500,
        window_ratio = 0.20,
        window_options = {
            preview = {
                cursorline = true,
                winfixbuf = false,
            },
            prompt = {
                cursorline = false,
                winfixbuf = true,
            },
            list = {
                cursorline = true,
                winfixbuf = true,
            },
        },
        list_offset = 2,
        decorators = {},
        preview = nil,
        display = nil,
        mappings = {
            ["<cr>"]    = Select.default_select,
            ["<esc>"]   = Select.close,
            ["<c-l>"]   = opts.preview ~= false and Select.toggle_preview or Select.noop_select,
            ["<c-d>"]   = opts.preview ~= false and Select.half_down or Select.noop_select,
            ["<c-u>"]   = opts.preview ~= false and Select.half_up or Select.noop_select,
            ["<m-p>"]   = opts.prompt_list ~= false and Select.move_down or Select.noop_select,
            ["<m-n>"]   = opts.prompt_list ~= false and Select.move_up or Select.noop_select,
            ["<c-p>"]   = opts.prompt_list ~= false and Select.move_up or Select.noop_select,
            ["<c-n>"]   = opts.prompt_list ~= false and Select.move_down or Select.noop_select,
            ["<c-k>"]   = opts.prompt_list ~= false and Select.move_up or Select.noop_select,
            ["<c-j>"]   = opts.prompt_list ~= false and Select.move_down or Select.noop_select,
            ["<c-z>"]   = opts.prompt_list ~= false and Select.toggle_list or Select.noop_select,
            ["<tab>"]   = opts.prompt_list ~= false and Select.toggle_down or Select.noop_select,
            ["<s-tab>"] = opts.prompt_list ~= false and Select.toggle_up or Select.noop_select,
            ["<c-e>"]   = opts.prompt_input ~= false and Select.prompt_end or Select.noop_select,
            ["<c-a>"]   = opts.prompt_input ~= false and Select.prompt_home or Select.noop_select,
            ["<c-b>"]   = opts.prompt_input ~= false and Select.prompt_left or Select.noop_select,
            ["<c-f>"]   = opts.prompt_input ~= false and Select.prompt_right or Select.noop_select,
            ["<m-b>"]   = opts.prompt_input ~= false and Select.prompt_left_word or Select.noop_select,
            ["<m-f>"]   = opts.prompt_input ~= false and Select.prompt_right_word or Select.noop_select,
            ["<m-bs>"]  = opts.prompt_input ~= false and Select.prompt_delete_word_left or Select.noop_select,
            ["<m-d>"]   = opts.prompt_input ~= false and Select.prompt_delete_word_right or Select.noop_select,
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
            toggled = {
                all = false,
                entries = {}
            },
            cursor = { 1, 0 },
            entries = nil,
            positions = nil,
            streaming = false
        },
    }, Select)

    return self
end

return Select
