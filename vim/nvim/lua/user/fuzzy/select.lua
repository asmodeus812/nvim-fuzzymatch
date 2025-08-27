local LIST_HIGHLIGHT_NAMESPACE = vim.api.nvim_create_namespace("list_highlight_namespace")
local LIST_DECORATED_NAMESPACE = vim.api.nvim_create_namespace("list_decorated_namespace")
local highlight_extmark_opts = { limit = 1, type = "highlight", details = false, hl_name = false }
local detailed_extmark_opts = { limit = 4, type = "highlight", details = true, hl_name = true }
local utils = require("user.fuzzy.utils")

--- @class Select
--- @field source_window integer window where the selection was opened from
--- @field prompt_window integer window showing the prompt
--- @field list_window integer window showing the list of entries
--- @field preview_window integer preview window showing the current entry
--- @field prompt_buffer integer buffer showing the prompt
--- @field list_buffer integer buffer showing the entries
--- @field preview_buffer integer entry preview buffer
--- @field _options table configuration options
--- @field _content table content holder
--- @field _content.entries table[]|string[]|nil list of entries to display, one per line
--- @field _content.positions integer[][]|nil list of highlight positions for each entry
--- @field _content.display string|function when entries consists of array of tables populate the list with the value a property from the table which value is equal to display, or if display is a function populate the list with result of the display function, which receives the entry as its only argument
--- @field _content.streaming boolean marks if the content is still streaming or receiving data
local Select = {}
Select.__index = Select
local render_step = 50000

local function icon_set()
    local ok, module = pcall(require, 'nvim-web-devicons')
    return ok and module or nil
end

local function buffer_getline(buf, lnum)
    local row = lnum ~= nil and (lnum - 1) or 0
    local text = vim.api.nvim_buf_get_text(
        buf, row, 0, row, -1, {}
    )
    return text and #text == 1 and text[1]
end

local function extract_match(entry, display)
    local match = entry
    local typ = display and type(entry)
    assert(not typ or typ == "table")
    if type(display) == "function" then
        match = display(assert(entry))
    elseif type(display) == "string" then
        assert(entry and next(entry))
        match = entry[display]
    end
    return match
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
    local file_icons = icon_set()

    if type(decoration.status_provider) == "function" then
        local status, status_highlight = decoration.status_provider(str)
        if type(status) == "string" and #status > 0 then
            table.insert(content, status)
            table.insert(highlights, status_highlight or "Normal")
        end
    elseif decoration.status_provider == true and file_icons then
        local result = vim.system({
            'git',
            'status',
            '--porcelain',
            '-z',
            '--',
            str,
        }):wait(50)
        local modified = result.code == 0 and #result.stdout > 0
        local status, status_highlight = modified and "~", "SpecialChar"
        if type(status) == "string" and #status > 0 then
            table.insert(content, status)
            table.insert(highlights, status_highlight or "Normal")
        end
    end

    if type(decoration.icon_provider) == "function" then
        local icon, icon_highlight = decoration.icon_provider(str)
        if type(icon) == "string" and #icon > 0 then
            table.insert(content, icon)
            table.insert(highlights, icon_highlight or "Normal")
        end
    elseif decoration.icon_provider == true and file_icons then
        local icon, icon_highlight = file_icons.get_icon(str,
            vim.fn.fnamemodify(str, ':e'), { default = true })
        if type(icon) == "string" and #icon > 0 then
            table.insert(content, icon)
            table.insert(highlights, icon_highlight or "Normal")
        end
    end

    return content, highlights
end

local function initialize_window(window)
    vim.wo[window][0].rnu = false
    vim.wo[window][0].number = false
    vim.wo[window][0].list = false
    vim.wo[window][0].showbreak = ''
    vim.wo[window][0].foldexpr = '0'
    vim.wo[window][0].foldmethod = 'manual'
    vim.wo[window][0].breakindent = false
    vim.wo[window][0].fillchars = "eob: "
    vim.wo[window][0].cursorline = false
    vim.wo[window][0].wrap = false
    vim.wo[window][0].winfixbuf = true
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

local function populate_buffer(buffer, list, display)
    local oldma = vim.bo[buffer].modifiable
    vim.bo[buffer].modifiable = true
    if display ~= nil then
        local start = 1
        local _end = math.min(#list, render_step)
        local lines = utils.obtain_table(render_step)

        while start < _end do
            for i = start, _end, 1 do
                lines[i] = extract_match(list[i], display)
            end
            vim.api.nvim_buf_set_lines(buffer, start - 1, _end - 1, false, lines)
            start = math.min(#list, _end + 1)
            _end = math.min(#list, _end + render_step)
        end
        vim.api.nvim_buf_set_lines(buffer, _end, -1, false, {})
        utils.return_table(utils.fill_table(lines, utils.EMPTY_STRING))
    else
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, list)
        vim.bo[buffer].modifiable = oldma
    end
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
                        extract_match(entry, display), matches[i + 0], matches[i + 1]
                    )
                    vim.api.nvim_buf_set_extmark(
                        buffer,
                        LIST_HIGHLIGHT_NAMESPACE,
                        target - 1,
                        offset + byte_start,
                        {
                            strict = true,
                            hl_eol = false,
                            invalidate = true,
                            ephemeral = false,
                            undo_restore = false,
                            right_gravity = true,
                            end_right_gravity = true,
                            hl_group = "IncSearch",
                            end_line = target - 1,
                            end_col = offset + byte_end,
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
                extract_match(entry, display), decoration
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

-- TODO: make this work beter with cursorline and shit
function Select:_normalize_view()
    if self.list_window and vim.api.nvim_win_is_valid(self.list_window) then
        vim.wo[self.list_window][0].cursorline = true
    end
    if self.prompt_window and vim.api.nvim_win_is_valid(self.prompt_window) then
        vim.wo[self.prompt_window][0].cursorline = false
    end
    if self.preview_window and vim.api.nvim_win_is_valid(self.preview_window) then
        vim.wo[self.preview_window][0].cursorline = false
    end
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
            assert(s.lnum <= #self._content.entries)
            return self._content.entries[s.lnum]
        end, placed[1].signs)
    else
        assert(lnum <= #self._content.entries)
        return { self._content.entries[lnum] }
    end
end

function Select:_prompt_getquery(lnum)
    if not self.prompt_buffer or not vim.api.nvim_buf_is_valid(self.prompt_buffer) then
        return nil
    end
    return buffer_getline(self.prompt_buffer, lnum)
end

function Select:_make_callback(callback)
    return function()
        return utils.safe_call(
            callback,
            self
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
    local entries = self._content.entries
    local positions = self._content.positions
    if entries and #entries > 0 and positions and #positions > 0 then
        local cursor = vim.api.nvim_win_get_cursor(self.list_window)
        local height = vim.api.nvim_win_get_height(self.list_window)
        assert(#entries == #positions)
        highlight_range(
            self.list_buffer,
            math.max(1, cursor[1] - height),
            math.min(#entries, cursor[1] + height),
            entries, positions,
            self._content.display,
            self._content.streaming)
    end
end

function Select:_decorate_list()
    local entries = self._content.entries
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
            self._content.display,
            self._content.streaming)
    end
end

function Select:_render_list()
    if self.list_buffer and vim.api.nvim_buf_is_valid(self.list_buffer) then
        populate_buffer(
            self.list_buffer,
            self._content.entries,
            self._content.display
        )
    end

    if self.list_window and vim.api.nvim_win_is_valid(self.list_window) then
        self:_decorate_list()
        self:_highlight_list()
        vim.api.nvim_win_call(
            self.list_window,
            vim.cmd.redraw
        )
    end
end

function Select:_destroy_view()
    self:close_view()

    self._content.streaming = false
    self._content.positions = nil
    self._content.entries = nil

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
end

function Select:move_cursor(dir, callback)
    local list_window = self.list_window
    local cursor = vim.api.nvim_win_get_cursor(list_window)
    local line_count = vim.fn.line("$", list_window)

    if cursor[1] == 1 and dir < 0 then cursor[1] = 0 end
    cursor[1] = (cursor[1] + dir) % (line_count + 1)
    if cursor[1] == 0 and dir > 0 then cursor[1] = 1 end
    vim.api.nvim_win_set_cursor(list_window, cursor)
    utils.safe_call(callback, callback and self:_list_selection(cursor[1]))
end

function Select:edit_entry(command, mods, callback)
    local list_window = self.list_window
    local cursor = vim.api.nvim_win_get_cursor(list_window)
    local selection = self:_list_selection(cursor[1])
    local items = vim.tbl_map(function(entry)
        local ok, result = utils.safe_call(callback, entry)
        if ok and result == false then
            return nil
        elseif not ok or not type(result) == "string" then
            result = extract_match(entry, self._content.display)
        end
        return {
            col = 1,
            lnum = 1,
            filename = result,
        }
    end, selection)

    self:close_view()
    for _, value in ipairs(items) do
        vim.cmd[command]({
            args = { value },
            mods = mods,
            bang = true,
        })
    end
end

function Select:toggle_entry(callback)
    local list_window = self.list_window
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
    utils.safe_call(callback, callback and self:_list_selection(cursor[1]))
    self:move_cursor(1)
end

function Select:send_fixlist(type, callback)
    local selection = self:_list_selection()
    local items = vim.tbl_map(function(entry)
        local ok, result = utils.safe_call(callback, entry)
        if ok and result == false then
            return nil
        elseif not ok or not type(result) == "string" then
            result = extract_match(entry, self._content.display)
        end
        return {
            col = 1,
            lnum = 1,
            filename = result,
        }
    end, selection)

    local args = {
        nr = "$",
        items = vim.tbl_filter(function(item)
            return item ~= nil
        end, items),
        title = "[Selection]",
    }

    if type == "qf" then
        vim.fn.setqflist({}, " ", args)
        self._options.quickfix_open()
    else
        local target
        if self.source_window and vim.api.nvim_win_is_valid(self.source_window) then
            target = self.source_window
        else
            target = vim.fn.winnr("#")
        end
        vim.fn.setloclist(target, {}, " ", args)
        self._options.loclist_open()
    end
    self:close_view()
end

function Select:close_view(callback)
    if self.source_window and vim.api.nvim_win_is_valid(self.source_window) then
        vim.api.nvim_set_current_win(self.source_window)
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
        vim.api.nvim_win_close(self.list_window, true)
        self.preview_window = nil
    end

    utils.safe_call(callback, nil)
end

function Select:select_next(callback)
    return self:move_cursor(1, callback)
end

function Select:select_prev(callback)
    return self:move_cursor(-1, callback)
end

function Select:select_entry(callback)
    self:edit_entry("edit", {}, callback)
end

function Select:select_horizontal(callback)
    self:edit_entry("split", { horizontal = true }, callback)
end

function Select:select_vertical(callback)
    self:edit_entry("split", { vertical = true }, callback)
end

function Select:select_tab(callback)
    self:edit_entry("tabedit", {}, callback)
end

function Select:send_quickfix(callback)
    self:send_fixlist("qf", callback)
end

function Select:send_locliset(callback)
    self:send_fixlist("loclist", callback)
end

function Select:query()
    return self:_prompt_getquery()
end

function Select:close()
    return self:close_view()
end

function Select:isopen()
    local prompt = self.prompt_window and vim.api.nvim_win_is_valid(self.prompt_window)
    local list = self.list_window and vim.api.nvim_win_is_valid(self.list_window)
    return prompt and list
end

function Select:render(entries, positions, display)
    if entries ~= nil then
        self._content.positions = positions
        self._content.entries = entries
        self._content.display = display
        self._content.streaming = true
        self:_render_list()
    elseif positions == nil then
        self._content.streaming = false
    end
end

function Select:open(opts)
    if type(opts) == "table" then
        self:_destroy_view()
        self._options = opts
    elseif not self:isopen() then
        opts = assert(self._options)
    else
        return
    end

    self.source_window = vim.api.nvim_get_current_win()
    local size = vim.g.win_viewport_height * opts.window_ratio
    if opts.prompt_input then
        local prompt_buffer = self.prompt_buffer
        if not prompt_buffer or not vim.api.nvim_buf_is_valid(prompt_buffer) then
            prompt_buffer = vim.api.nvim_create_buf(false, true)
            prompt_buffer = initialize_buffer(prompt_buffer, "prompt", "fuzzy")
            self:_create_mappings(prompt_buffer, "i", opts.mappings)
            self:_create_mappings(prompt_buffer, "i", {
                ["<esc>"] = opts.prompt_cancel,
            })
            vim.bo[prompt_buffer].bufhidden = opts.ephemeral and "wipe" or "hide"
            vim.bo[prompt_buffer].modifiable = true

            local prompt_trigger = vim.api.nvim_create_autocmd({ "TextChangedP", "TextChangedI" }, {
                buffer = prompt_buffer,
                callback = function(args)
                    if not args.buf or not vim.api.nvim_buf_is_valid(args.buf) then
                        local ok, re = utils.safe_call(opts.prompt_input, nil)
                        if not ok and re then vim.notify(re, vim.log.levels.ERROR) end
                        self:close_view()
                    else
                        local line = self:_prompt_getquery()
                        if line and type(opts.prompt_input) == "function" then
                            local ok, status, entries, positions = pcall(opts.prompt_input, line)
                            if not ok or ok == false then
                                vim.notify(status, vim.log.levels.ERROR)
                            elseif entries ~= nil then
                                self:render(entries, positions)
                                self:render(nil, nil)
                            end
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
                callback = function()
                    vim.cmd.startinsert()
                end
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

            vim.fn.prompt_setprompt(prompt_buffer, opts.prompt_query or "")
            vim.fn.prompt_setcallback(prompt_buffer, self:_make_callback(opts.prompt_confirm))
            vim.fn.prompt_setinterrupt(prompt_buffer, self:_make_callback(opts.prompt_cancel))
        elseif opts.resume_view == false then
            populate_buffer(prompt_buffer, {})
        end

        local prompt_window = self.prompt_window
        if not prompt_window or not vim.api.nvim_win_is_valid(prompt_window) then
            prompt_window = vim.api.nvim_open_win(prompt_buffer, true, {
                split = "below", win = -1, height = 1, noautocmd = false
            });
            vim.api.nvim_win_set_height(prompt_window, 1)
            prompt_window = initialize_window(prompt_window)

            vim.api.nvim_create_autocmd("WinClosed", {
                pattern = tostring(prompt_window),
                callback = function()
                    -- pcall(vim.fn.sign_und())
                    self:close_view()
                    return true
                end,
                once = true,
            })
        end

        local sign_name = string.format(
            "prompt_line_query_sign_%d",
            prompt_buffer
        )
        assert(vim.fn.sign_place(
            1,
            "prompt_line_query_group",
            sign_name,
            prompt_buffer,
            {
                lnum = 1,
                priority = 10,
            }
        ) == 1, "failed to place sign")

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
            list_buffer = initialize_buffer(list_buffer, "nofile", "list")
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
            if not entries then
                self._content.positions = positions
                self._content.entries = entries
                self._content.streaming = false
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
                    self._content.streaming = false
                    self._content.positions = nil
                    self._content.entries = nil
                    self.list_buffer = nil
                    self.list_window = nil
                    return true
                end,
                once = true,
            })

            assert(vim.fn.sign_define(sign_name, {
                text = "*", priority = 10
            }) == 0)
        elseif opts.resume_view == false then
            self._content.streaming = false
            self._content.positions = nil
            self._content.entries = nil
            populate_buffer(list_buffer, {})
        end

        local list_window = self.list_window
        if not list_window or not vim.api.nvim_win_is_valid(list_window) then
            local list_height = math.floor(math.ceil(size))
            list_window = vim.api.nvim_open_win(list_buffer, true, {
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

            local highlight_matches = vim.api.nvim_create_autocmd("WinScrolled", {
                pattern = tostring(list_window),
                callback = function()
                    self:_decorate_list()
                    self:_highlight_list()
                end
            })

            vim.api.nvim_create_autocmd("WinClosed", {
                pattern = tostring(list_window),
                callback = function()
                    pcall(vim.api.nvim_del_autocmd, highlight_matches)
                    self:close_view()
                    return true
                end,
                once = true,
            })
        end

        self.list_buffer = list_buffer
        self.list_window = list_window
    end

    if opts.prompt_list and opts.prompt_preview then
        local preview_buffer = self.preview_buffer
        if not preview_buffer or not vim.api.nvim_buf_is_valid(preview_buffer) then
            preview_buffer = vim.api.nvim_create_buf(false, true)
            preview_buffer = initialize_buffer(preview_buffer, "nofile", "preview")
            vim.bo[preview_buffer].bufhidden = opts.ephemeral and "wipe" or "hide"
            vim.bo[preview_buffer].modifiable = false
        elseif opts.resume_view == false then
            populate_buffer(preview_buffer, {})
        end

        local preview_window = self.preview_window
        if not preview_window or not vim.api.nvim_win_is_valid(preview_window) then
            local preview_height = math.floor(math.ceil(size))
            preview_window = vim.api.nvim_open_win(preview_buffer, true, {
                split = self.list_window and "above" or "below",
                height = preview_height,
                noautocmd = false,
                win = self.list_window or -1,
            });
            vim.api.nvim_win_set_height(preview_window, preview_height)
            preview_window = initialize_window(preview_window)
        end

        self.preview_buffer = preview_buffer
        self.preview_window = preview_window
    end

    if self.prompt_window then
        vim.api.nvim_set_current_win(self.prompt_window)
        vim.api.nvim_win_call(self.prompt_window, vim.cmd.startinsert)
        self:_normalize_view()
    elseif self.list_window then
        vim.api.nvim_set_current_win(self.list_window)
        vim.api.nvim_win_call(self.list_window, vim.cmd.stopinsert)
        self:_normalize_view()
    else
        vim.api.nvim_set_current_win(self.source_window)
    end

    return self
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

--- @class SelectOptions
--- @field prompt_input fun(query: string): (string[], integer[])? Function that is called when the user inputs text in the prompt.
--- @field prompt_confirm fun(selection: string[]): (string[]|false)? Function that is called when the user confirms the selection.
--- @field prompt_cancel fun(): nil Function that is called when the user cancels the selection.
--- @field prompt_list (boolean|string[]|(fun(): (string[], integer[])?))? List of entries to show in the list when opened, or a function that returns such a list.
--- @field prompt_query string? The query prompt prefix.
--- @field prompt_prefix string? The sign text to show in the prompt line.
--- @field prompt_input boolean? Whether to show the prompt window.
--- @field ephemeral boolean? Whether to wipe the buffers when closed.
--- @field window_ratio number? The ratio of the screen height to use for the list window.
--- @field step integer? The number of entries to load per batch when streaming.
--- @field mappings table<string, fun(self: Select)>? A table of key mappings to set in the prompt and/or list buffer.
--- @field providers table<string, boolean|fun(target: string): (string, string)?> A table of decoration providers to use for each entry in the list.
--- @param opts SelectOptions
--- @return Select
function Select.new(opts)
    opts = vim.tbl_deep_extend("force", {
        --
        quickfix_open = vim.cmd.copen,
        loclist_open = vim.cmd.lopen,
        --
        prompt_confirm = Select.select_entry,
        prompt_cancel = Select.close_view,
        prompt_preview = false,
        prompt_input = false,
        prompt_list = true,
        prompt_prefix = "> ",
        --
        window_ratio = 0.15,
        resume_view = false,
        ephemeral = true,
        -- providers
        providers = {
            status_provider = false,
            icon_provider = false,
        },
        mappings = {
            ["<c-q>"] = Select.send_quickfix,
            ["<tab>"] = Select.toggle_entry,
            ["<c-p>"] = Select.select_prev,
            ["<c-n>"] = Select.select_next,
            ["<c-k>"] = Select.select_prev,
            ["<c-j>"] = Select.select_next,
            ["<c-s>"] = Select.select_horizontal,
            ["<c-v>"] = Select.select_vertical,
            ["<c-t>"] = Select.select_tab,
        },
    }, opts or {})

    local self = setmetatable({
        preview_buffer = nil,
        preview_window = nil,
        prompt_buffer = nil,
        prompt_window = nil,
        list_buffer = nil,
        list_window = nil,
        _options = opts,
        _content = {
            entries = nil,
            positions = nil,
            streaming = false
        }
    }, Select)

    return self
end

return Select
