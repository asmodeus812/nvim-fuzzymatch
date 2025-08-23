local PROMPT_HIGHLIGHT_NAMESPACE = vim.api.nvim_create_namespace("prompt_matches_highlight")
local highlight_extmark_opts = { limit = 1, type = "highlight", details = false, hl_name = false }
local utils = require("user.fuzzy.utils")

local Select = {}
Select.__index = Select

local function buffer_getline(buf, lnum)
    local row = lnum ~= nil and (lnum - 1) or 0
    local text = vim.api.nvim_buf_get_text(
        buf, row, 0, row, -1, {}
    )
    return text and #text == 1 and text[1]
end

local function compute_offsets(str, start_char, char_len)
    local start_byte = vim.str_byteindex(str, start_char)
    local end_char = start_char + char_len
    local end_byte = vim.str_byteindex(str, end_char)
    return start_byte, end_byte
end

local function initialize_window(window)
    vim.api.nvim_win_set_cursor(window, { 1, 0 })
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

local function populate_buffer(buffer, lines)
    local oldma = vim.bo[buffer].modifiable
    vim.bo[buffer].modifiable = true
    pcall(vim.api.nvim_buf_set_lines, buffer, 0, -1, false, lines or {})
    vim.bo[buffer].modifiable = oldma
    vim.bo[buffer].modified = false
end

local function highlight_range(buffer, start, _end, entries, positions, override)
    assert(start <= _end and start > 0)
    for target = start, _end, 1 do
        if positions and #positions > 0 and target <= #positions then
            assert(target <= #entries)
            local marks = (override == false) and vim.api.nvim_buf_get_extmarks(
                buffer, PROMPT_HIGHLIGHT_NAMESPACE,
                { target - 1, 0 }, { target - 1, -1 },
                highlight_extmark_opts
            )
            if not marks or #marks < 1 then
                local entry = entries[target]
                local matches = positions[target]
                assert(#matches % 2 == 0 and entry ~= nil)
                for i = 1, #matches, 2 do
                    local byte_start, byte_end = compute_offsets(
                        entry,
                        matches[i + 0],
                        matches[i + 1]
                    )
                    vim.api.nvim_buf_set_extmark(
                        buffer,
                        PROMPT_HIGHLIGHT_NAMESPACE,
                        target - 1,
                        byte_start,
                        {
                            strict = true,
                            hl_eol = false,
                            invalidate = true,
                            ephemeral = false,
                            undo_restore = false,
                            end_col = byte_end,
                            end_line = target - 1,
                            hl_group = "IncSearch",
                        }
                    )
                end
            end
        end
    end
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
    local placed = lnum == nil and vim.fn.sign_getplaced(self.list_buffer, {
        group = "list_toggle_entry_group",
    })
    if placed and #placed > 0 and placed[1].signs then
        local marked = vim.tbl_map(function(s)
            return s.lnum
        end, placed[1].signs)
        table.sort(marked)

        return vim.api.nvim_buf_get_text(
            self.list_buffer,
            marked[1] - 1,
            0,
            marked[#marked - 1],
            -1,
            {}
        )
    end
    return { buffer_getline(self.list_buffer, lnum) }
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
            entries, positions, self._content.streaming)
    end
end

function Select:_decorate_list()
end

function Select:_render_list()
    if self.list_buffer and vim.api.nvim_buf_is_valid(self.list_buffer) then
        populate_buffer(
            self.list_buffer,
            self._content.entries
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
    local selection = self:_list_selection()
    local ok, items = utils.safe_call(callback, callback and selection)
    if not ok or not type(items) == "table" or #items == 0 then
        items = selection
    end
    self:close_view()
    for _, value in ipairs(items or {}) do
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
    local items = vim.tbl_map(function(line)
        return {
            col = 1,
            lnum = 1,
            filename = line,
        }
    end, selection)

    local args = {
        nr = "$",
        items = items,
        title = "[Selection]",
    }

    if type == "qf" then
        vim.fn.setqflist({}, " ", args)
        self._options.quickfix_open()
    else
        vim.fn.setloclist(0, {}, " ", args)
        self._options.loclist_open()
    end
    utils.safe_call(callback, callback and selection)
    self:close_view()
end

function Select:close_view(callback)
    if self.source_window and vim.api.nvim_win_is_valid(self.source_window) then
        vim.api.nvim_set_current_win(self.source_window)
    end
    if self.prompt_window and vim.api.nvim_win_is_valid(self.prompt_window) then
        vim.api.nvim_win_close(self.prompt_window, true)
    end
    self.prompt_window = nil
    if self.list_window and vim.api.nvim_win_is_valid(self.list_window) then
        vim.api.nvim_win_close(self.list_window, true)
    end
    self.list_window = nil
    if self.preview_window and vim.api.nvim_win_is_valid(self.preview_window) then
        vim.api.nvim_win_close(self.list_window, true)
    end
    utils.safe_call(callback, nil)
    self.preview_window = nil
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
    self:edit_entry("edit", { horizontal = true }, callback)
end

function Select:select_vertical(callback)
    self:edit_entry("edit", { vertical = true }, callback)
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

function Select:destroy()
    self:close_view()

    if self.list_buffer and vim.api.nvim_buf_is_valid(self.list_buffer) then
        vim.api.nvim_buf_delete(self.list_buffer, { force = true })
    end
    self.list_buffer = nil
    if self.prompt_buffer and vim.api.nvim_buf_is_valid(self.prompt_buffer) then
        vim.api.nvim_buf_delete(self.prompt_buffer, { force = true })
    end
    self.prompt_buffer = nil
    if self.preview_buffer and vim.api.nvim_buf_is_valid(self.preview_buffer) then
        vim.api.nvim_buf_delete(self.preview_buffer, { force = true })
    end
    self.preview_buffer = nil
end

function Select:query()
    return self:_prompt_getquery()
end

function Select:isopen()
    local prompt = self.prompt_window and vim.api.nvim_win_is_valid(self.prompt_window)
    local list = self.list_window and vim.api.nvim_win_is_valid(self.list_window)
    return prompt and list
end

function Select:render(entries, positions)
    if entries ~= nil then
        self._content.positions = positions
        self._content.entries = entries
        self._content.streaming = true
        self:_render_list()
    elseif positions == nil then
        -- new entries will no longer be sent here
        -- _content holds the latest and all entries
        self._content.streaming = false
    end
end

function Select:open(opts)
    if type(opts) == "table" then
        self:destroy()
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
                callback = utils.debounce_callback(opts.prompt_debounce, function(args)
                    if not args.buf or not vim.api.nvim_buf_is_valid(args.buf) then
                        local ok, re = utils.safe_call(opts.prompt_input, nil)
                        if not ok and re then vim.notify(re, vim.log.levels.ERROR) end
                        self:close_view()
                    else
                        local line = self:_prompt_getquery()
                        if line and #line > 0 and type(opts.prompt_input) == "function" then
                            vim.api.nvim_win_set_cursor(self.list_window, { 1, 0 })
                            local ok, status, entries, positions = pcall(opts.prompt_input, line)
                            if not ok or ok == false then
                                vim.notify(status, vim.log.levels.ERROR)
                            elseif entries ~= nil and #entries > 0 then
                                self:render(entries, positions)
                                self:render(nil, nil)
                            end
                        end
                    end
                end)
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

            if type(opts.prompt_list) == "table" then
                local entries, positions
                if type(opts.prompt_list[1]) == "table" then
                    entries = opts.prompt_list[1]
                    positions = opts.prompt_list[2]
                elseif type(opts.prompt_list) == "function" then
                    entries, positions = opts.prompt_list(self)
                else
                    entries = opts.prompt_list
                end
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

    return self;
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

function Select.new(opts)
    opts = vim.tbl_deep_extend("force", {
        --
        quickfix_open = vim.cmd.copen,
        loclist_open = vim.cmd.lopen,
        --
        prompt_confirm = Select.select_entry,
        prompt_cancel = Select.close_view,
        prompt_debounce = 200,
        prompt_preview = false,
        prompt_input = false,
        prompt_list = true,
        prompt_prefix = "> ",
        --
        window_ratio = 0.15,
        resume_view = false,
        open_view = true,
        ephemeral = true,
        mappings = {
            ["<tab>"] = Select.toggle_entry,
            ["<c-p>"] = Select.select_prev,
            ["<c-n>"] = Select.select_next,
            ["<c-k>"] = Select.select_prev,
            ["<c-j>"] = Select.select_next,
            ["<c-q>"] = Select.send_quickfix,
            ["<c-s>"] = Select.split_horizontal,
            ["<c-v>"] = Select.split_vertical,
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

    if opts.open_view == true then
        self:open()
    end
    return self
end

return Select
