local LIST_HIGHLIGHT_NAMESPACE = vim.api.nvim_create_namespace("list_highlight_namespace")
local LIST_DECORATED_NAMESPACE = vim.api.nvim_create_namespace("list_decorated_namespace")
local LIST_STATUS_NAMESPACE = vim.api.nvim_create_namespace("list_status_namespace")
local highlight_extmark_opts = { limit = 1, type = "highlight", details = false, hl_name = false }
local detailed_extmark_opts = { limit = 4, type = "highlight", details = true, hl_name = true }
local async = require("fuzzy.async")
local utils = require("fuzzy.utils")

--- @class Select
--- @field private source_window integer|nil The window ID of the source window where the selection interface was opened from.
--- @field private prompt_window integer|nil The window ID of the prompt input window.
--- @field private prompt_buffer integer|nil The buffer ID of the prompt input buffer.
--- @field private list_window integer|nil The window ID of the list display window.
--- @field private list_buffer integer|nil The buffer ID of the list display buffer.
--- @field private preview_window integer|nil The window ID of the preview display window.
--- @field private preview_buffer integer|nil The buffer ID of the preview display buffer.
--- @field private _options SelectOptions The configuration options for the selection interface.
--- @field private _state table The internal state of the selection interface.
local Select = {}
Select.__index = Select

--- @class Select.Preview
Select.Preview = {}
Select.Preview.__index = Select.Preview

function Select.Preview.new()
    local obj = {}
    setmetatable(obj, Select.Preview)
    return obj
end

function Select.Preview:preview()
    error("must be implemented by sub-classing")
end

Select.BufferPreview = {}
Select.BufferPreview.__index = Select.BufferPreview
setmetatable(Select.BufferPreview, { __index = Select.Preview })

Select.CommandPreview = {}
Select.CommandPreview.__index = Select.CommandPreview
setmetatable(Select.CommandPreview, { __index = Select.Preview })

Select.CustomPreview = {}
Select.CustomPreview.__index = Select.CustomPreview
setmetatable(Select.CustomPreview, { __index = Select.Preview })

local function icon_set()
    local ok, module = pcall(require, 'nvim-web-devicons')
    return ok and module or nil
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

    if type(entry) == "table" and assert(entry.filename) then
        col = entry.col or 1
        lnum = entry.lnum or 1
        entry = entry.filename
    end

    assert(type(entry) == "string" and #entry > 0)
    return { col = col, lnum = lnum, filename = entry }
end

local function compute_offsets(str, start_char, char_len)
    local start_byte = vim.str_byteindex(str, start_char)
    local end_char = start_char + char_len
    local end_byte = vim.str_byteindex(str, end_char)
    return start_byte, end_byte
end

local function compute_decoration(str, decoration)
    local content = {}
    local highlights = {}
    local icons = icon_set()

    local status, status_highlight
    if type(decoration.status_provider) == "function" then
        status, status_highlight = decoration.status_provider(str)
    elseif decoration.status_provider == true and icons then
        local result = #str > 0 and vim.fn.bufnr(str, false) ~= -1
        status, status_highlight = result and "[x]", "SpecialChar"
    end

    local icon, icon_highlight
    if type(decoration.icon_provider) == "function" then
        icon, icon_highlight = decoration.icon_provider(str)
    elseif decoration.icon_provider == true and icons then
        icon, icon_highlight = icons.get_icon(str,
            vim.fn.fnamemodify(str, ':e'), { default = true })
    end

    if type(status) == "string" and #status > 0 then
        table.insert(content, status)
        table.insert(highlights, status_highlight or "Normal")
    end

    if type(icon) == "string" and #icon > 0 then
        table.insert(content, icon)
        table.insert(highlights, icon_highlight or "Normal")
    end

    return content, highlights
end

local function initialize_window(window)
    vim.wo[window][0].relativenumber = false
    vim.wo[window][0].number = false
    vim.wo[window][0].list = false
    vim.wo[window][0].showbreak = ''
    vim.wo[window][0].foldexpr = '0'
    vim.wo[window][0].foldmethod = 'manual'
    vim.wo[window][0].breakindent = false
    vim.wo[window][0].fillchars = "eob: "
    vim.wo[window][0].cursorline = false
    vim.wo[window][0].wrap = false
    vim.wo[window][0].winfixheight = true
    vim.wo[window][0].winfixwidth = true
    return window
end

local function initialize_buffer(buffer, bt, ft)
    vim.bo[buffer].buftype = bt or "nofile"
    vim.bo[buffer].filetype = ft or ""
    vim.bo[buffer].modified = false
    vim.bo[buffer].autoread = false
    vim.bo[buffer].undofile = false
    vim.bo[buffer].undolevels = 0
    return buffer
end

local function populate_buffer(buffer, list, display, step)
    local oldma = vim.bo[buffer].modifiable
    vim.bo[buffer].modifiable = true
    if step ~= nil and step > 0 then
        local start = 1
        local _end = math.min(#list, step)
        local lines = utils.obtain_table(step)

        while start < _end do
            for i = start, _end, 1 do
                lines[i] = line_mapper(list[i], display)
                async.yield()
            end
            vim.api.nvim_buf_set_lines(buffer, start - 1, _end - 1, false, lines)
            start = math.min(#list, _end + 1)
            _end = math.min(#list, _end + step)
        end
        vim.api.nvim_buf_set_lines(buffer, _end, -1, false, {})
        utils.return_table(utils.fill_table(lines, utils.EMPTY_STRING))
    else
        if display ~= nil then
            local mapper = function(entry) return line_mapper(entry, display) end
            vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.tbl_map(mapper, list))
        else
            vim.api.nvim_buf_set_lines(buffer, 0, -1, false, list)
        end
    end
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
end

local function decorate_range(buffer, start, _end, entries, decoration, display, override)
    assert(start <= _end and start > 0)

    local oldma = vim.bo[buffer].modifiable
    vim.bo[buffer].modifiable = true
    for target = start, _end, 1 do
        local marks = vim.api.nvim_buf_get_extmarks(
            buffer, LIST_DECORATED_NAMESPACE,
            { target - 1, 0 }, { target - 1, -1 },
            highlight_extmark_opts
        )
        if not marks or #marks < 1 then
            local entry = entries[target]
            local content, highlights = compute_decoration(
                line_mapper(entry, display), decoration
            )
            if #content > 0 then
                assert(#content == #highlights)

                -- prefix the line with the decorations, they are concatenated in order from the content table,
                -- afterwards the matching highlights are inserted as extmarks, this will make sure that this append
                -- is going to shift the extmarks forward,
                table.insert(content, "")
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
end

local function display_entry(strategy, entry, window, buffers)
    local old_ignore = vim.o.eventignore
    vim.o.eventignore = "all"
    local buf = strategy:preview(entry, window)
    if not vim.tbl_contains(buffers, buf) then
        table.insert(buffers, buf)
    end
    vim.o.eventignore = old_ignore
end

function Select.BufferPreview.new(converter)
    local obj = Select.Preview.new()
    setmetatable(obj, Select.BufferPreview)
    obj.converter = converter or entry_mapper
    return obj
end

function Select.BufferPreview:preview(entry, window)
    local buffer
    entry = self.converter(entry)
    if vim.fn.bufexists(entry.filename) ~= 0 then
        buffer = vim.fn.bufnr(entry.filename, false)
    elseif vim.fn.filereadable(entry.filename) ~= 0 then
        buffer = vim.fn.bufadd(entry.filename)
        vim.bo[buffer].buflisted = false
    end

    local cursor = { entry.lnum or 1, entry.col and (entry.col - 1) or 0 }
    assert(buffer and buffer > 0 and vim.fn.bufload(buffer))

    vim.api.nvim_win_set_buf(window, buffer)
    pcall(vim.api.nvim_win_set_cursor, window, cursor)

    if not vim.b[buffer].ts_highlight then
        vim.api.nvim_win_call(window, function()
            local ft = vim.filetype.match({ buf = buffer, filename = entry.filename })
            local lang = vim.treesitter.language.get_lang(ft or '')
            local loaded = lang and vim.treesitter.language.add(lang)
            if loaded and lang then
                local ok, err = pcall(vim.treesitter.start, buffer, lang)
                if not ok and err then
                    vim.notify(err, vim.log.levels.ERROR)
                end
            end
        end)
    end

    return buffer
end

function Select.CustomPreview.new(callback)
    local obj = Select.Preview.new()
    setmetatable(obj, Select.CustomPreview)
    obj.callback = assert(callback)
    return obj
end

function Select.CustomPreview:preview(entry, window)
    local id = tostring(entry):gsub("table: ", "")
    local name = string.format(
        "%s#fuzzy-custom-preview-entry", id
    )

    local buffer
    if vim.fn.bufexists(name) == 0 then
        buffer = vim.api.nvim_create_buf(false, true)
        buffer = initialize_buffer(buffer, "nofile", "fuzzy-preview")
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
                pcall(vim.api.nvim_win_set_cursor, window, cursor)
            end
        else
            populate_buffer(buffer, {
                "Unable to display or preview entry"
            })
        end
    else
        buffer = assert(vim.fn.bufnr(name, false))
        vim.api.nvim_win_set_buf(window, buffer)
    end

    return buffer
end

function Select.CommandPreview.new(command, converter)
    local obj = Select.Preview.new()
    setmetatable(obj, Select.CommandPreview)
    obj.converter = converter or entry_mapper
    obj.command = assert(command)
    return obj
end

function Select.CommandPreview:preview(entry, window)
    local cursor = { entry.lnum or 1, entry.col and (entry.col - 1) or 0 }
    local name = string.format("%s#fuzzy-command-preview-entry", entry.filename)

    local buffer
    entry = self.converter(entry)
    if vim.fn.bufexists(name) == 0 then
        buffer = vim.api.nvim_create_buf(false, true)
        buffer = initialize_buffer(buffer, "nofile", "fuzzy-preview")
        vim.api.nvim_win_set_buf(window, buffer)
        vim.api.nvim_win_call(window, function()
            local cmd
            if type(self.command) == "table" then
                cmd = assert(vim.fn.copy(self.command))
                table.insert(cmd, entry.filename)
            else
                cmd = { self.command, entry.filename }
            end
            assert(vim.fn.executable(cmd[1]) == 1)
            vim.fn.jobstart(cmd, {
                pty = true,
                term = true,
                detach = false,
                cwd = vim.loop.cwd(),
                on_exit = function()
                    pcall(
                        vim.api.nvim_win_set_cursor,
                        window,
                        cursor
                    )
                end,
                stdout_buffered = true,
                stderr_buffered = true,
            })
            vim.api.nvim_buf_set_name(buffer, name)
            vim.api.nvim_buf_delete(
                vim.fn.bufnr("#"), { force = true }
            )
        end)
    else
        buffer = assert(vim.fn.bufnr(name, false))
        vim.api.nvim_win_set_buf(window, buffer)
        pcall(vim.api.nvim_win_set_cursor, window, cursor)
    end

    return buffer
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
        assert(lnum <= #self._state.entries)
        return { self._state.entries[lnum] }
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
            self._options.list_display,
            self._state.streaming)
    end
end

function Select:_decorate_list()
    local entries = self._state.entries
    local providers = self._options.providers
    if entries and #entries > 0 and providers and next(providers) then
        local cursor = vim.api.nvim_win_get_cursor(self.list_window)
        local height = vim.api.nvim_win_get_height(self.list_window)
        assert(#entries >= cursor[1] and cursor[1] > 0)
        decorate_range(
            self.list_buffer,
            math.max(1, cursor[1] - height),
            math.min(#entries, cursor[1] + height),
            entries, providers,
            self._options.list_display,
            self._state.streaming)
    end
end

function Select:_display_preview()
    local entries = self._state.entries
    local previewer = self._options.prompt_preview
    if entries and #entries > 0 and previewer ~= false then
        local cursor = vim.api.nvim_win_get_cursor(self.list_window)
        assert(#entries >= cursor[1] and cursor[1] > 0)
        local entry = assert(entries[cursor[1]])
        display_entry(
            previewer, entry,
            self.preview_window,
            self._state.buffers
        )
    end
end

function Select:_render_list()
    if self.list_buffer and vim.api.nvim_buf_is_valid(self.list_buffer) then
        populate_buffer(
            self.list_buffer,
            self._state.entries,
            self._options.list_display,
            self._options.list_step
        )
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

    self._state.streaming = false
    self._state.positions = nil
    self._state.entries = nil
end

function Select:_clean_preview()
    if self._state.buffers then
        local valid = vim.tbl_filter(
            vim.api.nvim_buf_is_valid,
            self._state.buffers
        )
        for _, value in ipairs(valid or {}) do
            vim.api.nvim_buf_delete(
                value, { force = false }
            )
        end
        self._state.buffers = {}
    end
end

function Select:_close_view()
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

--- Executes user callback with the current selection passed in, the action performs a no operation and is entirely reliant on the user
--- callback to perform any action, this is a generic function used to invoke the user callback with current selection
function Select:default_select(callback)
    local cursor = vim.api.nvim_win_get_cursor(self.list_window)
    local selection = callback and self:_list_selection(cursor[1])

    self:_close_view()

    utils.safe_call(callback, selection, cursor)
end

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
    local cursor = vim.api.nvim_win_get_cursor(list_window)
    local line_count = vim.fn.line("$", list_window)

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

    for _, value in ipairs(result) do
        if value == nil then
            goto continue
        end

        local col = 1
        local lnum = 1
        local fname = value

        if type(value) == "table" then
            col = assert(value.col)
            lnum = assert(value.lnum)
            fname = assert(value.filename)
        end

        vim.cmd[command]({
            args = { fname },
            mods = mods,
            bang = true,
        })
        vim.api.nvim_win_set_cursor(0, { lnum, col - 1 })

        ::continue::
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
            return item ~= nil and item.filename
        end, result),
        title = "[Selection]",
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
--- entry, by default.
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

--- Closes all open windows associated with the selection interface and returns focus to the source window, if it is still valid.
function Select:close_view(callback)
    self:_close_view()
    utils.safe_call(callback)
end

function Select:page_down(callback)
    self:scroll_preview("<c-f>", callback)
end

function Select:page_up(callback)
    self:scroll_preview("<c-b>", callback)
end

function Select:half_up(callback)
    self:scroll_preview("<c-u>", callback)
end

function Select:half_down(callback)
    self:scroll_preview("<c-d>", callback)
end

function Select:line_up(callback)
    self:scroll_preview("<c-y>", callback)
end

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

--- Gets the current query from the prompt input.
--- @return string The current query string, the query must never be nil, otherwise that represents invalid state
function Select:query()
    return assert(self._state.query)
end

-- Destroy the selection interface, closing all associated windows and buffers.
function Select:destroy()
    self:_destroy_view()
end

--- Closes the selection interface, if the ephemeral option is set to true, the buffers associated with the interface will be destroyed as well.
function Select:close()
    self:_close_view()
    self:_clean_preview()
    if self._options.ephemeral == true then
        self:_destroy_view()
    end
end

--- Checks if the selection interface is currently open, this is determined by checking if both the prompt and list windows are valid.
--- @return boolean True if the selection interface is open, false otherwise.
function Select:isopen()
    local prompt = self.prompt_window and vim.api.nvim_win_is_valid(self.prompt_window)
    local list = self.list_window and vim.api.nvim_win_is_valid(self.list_window)
    return list ~= nil and prompt ~= nil and list and prompt
end

--- Checks if the list has any entries rendered, if the list is not valid or has no lines, it is considered empty, otherwise it is not.
--- @return boolean True if the list is empty, false otherwise.
function Select:isempty()
    if not self.list_buffer or not vim.api.nvim_buf_is_valid(self.list_buffer) then
        return true
    end
    if vim.api.nvim_buf_line_count(self.list_buffer) == 1 then
        -- @Speed: use get_text with minimal col offsets to get a smaller chunk
        local lines = vim.api.nvim_buf_get_lines(self.list_buffer, 0, 1, false)
        return not lines or #lines == 0 or #lines[1] == 0
    end
    return false
end

-- Render a list of entries in the list window, with optional highlighting positions and display formatting function or property.
-- @param entries any[]|string[]|nil The list of entries to display.
-- @param positions integer[][]|nil The list of positions for highlighting
-- @param display string|fun(entry: any): string|nil The field or function to use for displaying entries.
function Select:list(entries, positions)
    if entries ~= nil then
        vim.validate {
            entries = { entries, "table" },
            positions = { positions, { "table", "nil" }, true },
        }
        self._state.positions = positions
        self._state.entries = entries
        self._state.streaming = true
        async.wrap(Select._render_list)(self)
    elseif positions == nil then
        self._state.streaming = false
    end
end

--- Render the current status of the select, providing information about the selection list, preview or prompt, as virtual text in the select interface
--- @param status string the status data to render in the window
function Select:status(status)
    vim.validate {
        status = { status, "string" },
    }
    vim.api.nvim_buf_clear_namespace(self.prompt_buffer, LIST_STATUS_NAMESPACE, 0, 1)
    vim.api.nvim_buf_set_extmark(self.prompt_buffer, LIST_STATUS_NAMESPACE, 0, 0, {
        priority = 1000,
        hl_mode = "combine",
        right_gravity = false,
        virt_text_pos = "eol",
        virt_text_win_col = nil,
        virt_text = {
            -- { self._options.prompt_prefix, "Normal" },
            { assert(status), "NonText" },
        },
    })
end

--- Opens the selection interface, creating necessary buffers and windows as needed, and sets up autocommands and mappings, if not
--- already open.
function Select:open()
    local opts = assert(self._options)
    if self:isopen() then
        self:close()
    end

    self.source_window = vim.api.nvim_get_current_win()
    local factor = opts.prompt_preview and 2.0 or 1.0
    local ratio = math.abs(opts.window_ratio / factor)
    local size = math.ceil(vim.o.lines * ratio)

    if opts.prompt_input then
        local prompt_buffer = self.prompt_buffer
        if not prompt_buffer or not vim.api.nvim_buf_is_valid(prompt_buffer) then
            prompt_buffer = vim.api.nvim_create_buf(false, true)
            prompt_buffer = initialize_buffer(prompt_buffer, "nofile", "fuzzy-prompt")
            self:_create_mappings(prompt_buffer, "i", opts.mappings)
            self:_create_mappings(prompt_buffer, "i", {
                ["<cr>"] = opts.prompt_confirm,
                ["<esc>"] = opts.prompt_cancel,
                ["<c-c>"] = opts.prompt_cancel,
            })
            vim.bo[prompt_buffer].bufhidden = opts.ephemeral and "wipe" or "hide"
            vim.bo[prompt_buffer].modifiable = true

            local prompt_trigger = vim.api.nvim_create_autocmd({ "TextChangedP", "TextChangedI" }, {
                buffer = prompt_buffer,
                callback = function(args)
                    if not args.buf or not vim.api.nvim_buf_is_valid(args.buf) then
                        self:_close_view()
                        self:_prompt_input(nil, opts.prompt_input)
                    elseif self:isopen() then
                        local query = self:_prompt_getquery()
                        if query and self._state.query ~= query then
                            self:_prompt_input(query, opts.prompt_input)
                            self._state.query = query
                        else
                            self._state.query = ""
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

            assert(vim.fn.sign_define(sign_name, {
                text = opts.prompt_prefix, priority = 10
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
        elseif opts.resume_view == false then
            populate_buffer(prompt_buffer, {})
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
            vim.api.nvim_win_set_cursor(prompt_window, {
                1, -- set cursor on the first line
                vim.str_byteindex(query, #query),
            })
        end

        self.prompt_buffer = prompt_buffer
        self.prompt_window = prompt_window
    end

    if opts.prompt_list then
        local list_buffer = self.list_buffer
        if not list_buffer or not vim.api.nvim_buf_is_valid(list_buffer) then
            list_buffer = vim.api.nvim_create_buf(false, true)
            list_buffer = initialize_buffer(list_buffer, "nofile", "fuzzy-list")
            if not opts.prompt_input then
                self:_create_mappings(list_buffer, "n", opts.mappings)
                self:_create_mappings(list_buffer, "n", {
                    ["<cr>"] = opts.prompt_confirm,
                    ["<esc>"] = opts.prompt_cancel,
                    ["<c-c>"] = opts.prompt_cancel,
                })
            end
            vim.bo[list_buffer].bufhidden = opts.ephemeral and "wipe" or "hide"
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
            if entries == nil then
                self._state.positions = positions
                self._state.entries = entries
                self._state.streaming = false
                self:_render_list()
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
                text = self._options.toggle_prefix, priority = 10
            }) == 0)
        elseif opts.resume_view == false then
            self._state.streaming = false
            self._state.positions = nil
            self._state.entries = nil
            populate_buffer(list_buffer, {})
        end

        local list_window = self.list_window
        if not list_window or not vim.api.nvim_win_is_valid(list_window) then
            local list_height = math.floor(math.ceil(size))
            list_window = vim.api.nvim_open_win(list_buffer, false, {
                split = self.prompt_window and "above" or "below",
                height = list_height,
                noautocmd = false,
                win = self.prompt_window or -1,
            });
            vim.api.nvim_win_set_height(list_window, list_height)
            list_window = initialize_window(list_window)
            if not opts.resume_view then
                vim.api.nvim_win_set_cursor(list_window, { 1, 0 })
            end
            vim.wo[list_window][0].signcolumn = 'number'
            vim.wo[list_window][0].cursorline = true
            vim.wo[list_window][0].winfixbuf = true

            local highlight_matches = vim.api.nvim_create_autocmd("WinScrolled", {
                pattern = tostring(list_window),
                callback = function()
                    if not self:isempty() then
                        self:_decorate_list()
                        self:_highlight_list()
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

    if opts.prompt_list and opts.prompt_preview then
        local preview_window = self.preview_window
        if not preview_window or not vim.api.nvim_win_is_valid(preview_window) then
            local preview_height = math.floor(math.ceil(size))
            preview_window = vim.api.nvim_open_win(0, false, {
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

function Select.action(action, callback)
    return function(_self)
        utils.safe_call(
            action,
            _self,
            callback
        )
    end
end

--- Creates a new Select instance, which provides an interactive selection interface.
--- @class SelectOptions
--- @inlinedoc
--- @field prompt_confirm? fun() Function to confirm the selection. Default: Select.select_entry
--- @field prompt_cancel? fun() Function to cancel the selection. Default: Select.close_view
--- @field prompt_preview? Select.Preview|boolean speficies the preview strategy to be used when entries are focused, through different actions which move the cursor in the window showing the list of items
--- @field prompt_list? boolean|fun()|any[] Whether to show the list window or a function to provide initial entries. Default: true
--- @field prompt_input? boolean|fun() Whether to show the input prompt, when function is provided it is used as the input callback. Default: true
--- @field prompt_query? string|nil Initial query to populate the prompt input with. Default: nil
--- @field prompt_prefix? string Prefix to display in the prompt input. Default: "> "
--- @field toggle_prefix? string Prefix to display for toggled entries in the list. Default: "✓"
--- @field preview_timeout? number timeout in milliseconds after which the preview window will unlock the user interface
--- @field window_ratio? number Ratio of the window height to the total editor height. Default: 0.15
--- @field resume_view? boolean Whether to resume the view with existing buffers. Default: false
--- @field list_step? integer|nil Number of entries to render at a time when populating the list. Default: nil
--- @field list_display? function|nil Function governing how the entries in the list are going to be displayed in case they represent complex structures
--- @field ephemeral? boolean Whether to destroy buffers when closing the selection interface. Default: true
--- @field mappings? table Key mappings with keys as the key combination and values as the Select method to invoke, the method will be called with the Select instance as the first argument
--- @field providers? table Providers for additional decorations in the list.
--- @field providers.icon_provider? boolean|fun() Whether to show icons in the list. Default: false
--- @field providers.status_provider? boolean|fun() Whether to show git status in the list. Default: false
--- @field quickfix_open? fun() Function to open the quickfix list. Default: vim.cmd.copen
--- @field loclist_open? fun() Function to open the location list. Default: vim.cmd.lopen

--- Creates a new Select instance with the given options.
--- @param opts? SelectOptions|nil The options to configure the selection interface.
--- @return Select The new Select instance.
function Select.new(opts)
    opts = opts or {}
    vim.validate({
        prompt_confirm = { opts.prompt_confirm, "function", true },
        prompt_cancel = { opts.prompt_cancel, "function", true },
        prompt_preview = { opts.prompt_preview, { "boolean", "table", "function" }, true },
        prompt_list = { opts.prompt_list, { "boolean", "function", "table" }, true },
        prompt_input = { opts.prompt_input, { "boolean", "function" }, true },
        prompt_query = { opts.prompt_query, { "string", "nil" }, true },
        prompt_prefix = { opts.prompt_prefix, "string", true },
        toggle_prefix = { opts.toggle_prefix, "string", true },
        window_ratio = { opts.window_ratio, "number", true },
        resume_view = { opts.resume_view, "boolean", true },
        preview_timeout = { opts.preview_timeout, { "number", "nil" }, true },
        list_display = { opts.list_display, { "function", "string", "nil" }, true },
        list_step = { opts.list_step, { "number", "nil" }, true },
        ephemeral = { opts.ephemeral, "boolean", true },
        providers = { opts.providers, "table", true },
        mappings = { opts.mappings, "table", true },
        quickfix_open = { opts.quickfix_open, "function", true },
        loclist_open = { opts.loclist_open, "function", true },
    })
    opts = vim.tbl_deep_extend("force", {
        prompt_confirm = Select.select_entry,
        prompt_cancel = Select.close_view,
        prompt_preview = false,
        prompt_list = true,
        prompt_input = true,
        prompt_query = nil,
        prompt_prefix = "> ",
        toggle_prefix = "✓",
        preview_timeout = 500,
        window_ratio = 0.15,
        resume_view = false,
        list_display = nil,
        list_step = nil,
        ephemeral = true,
        providers = {
            icon_provider = false,
            status_provider = false,
        },
        mappings = {
            ["<tab>"] = Select.toggle_entry,
            ["<c-p>"] = Select.select_prev,
            ["<c-n>"] = Select.select_next,
            ["<c-k>"] = Select.select_prev,
            ["<c-j>"] = Select.select_next,
            ["<c-f>"] = Select.page_down,
            ["<c-b>"] = Select.page_up,
            ["<c-d>"] = Select.half_down,
            ["<c-u>"] = Select.half_up,
            ["<c-e>"] = Select.line_down,
            ["<c-y>"] = Select.line_up,
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
