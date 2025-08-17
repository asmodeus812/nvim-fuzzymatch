local PROMPT_HIGHLIGHT_NAMESPACE = vim.api.nvim_create_namespace("prompt_matches_highlight")
local highlight_extmark_opts = { limit = 1, type = "highlight", details = false, hl_name = false }

local M = {
    state = {},
    actions = {}
}

local function debounce_callback(wait, callback)
    local debounce_timer = nil
    return function(args)
        if debounce_timer and not debounce_timer:is_closing() then
            debounce_timer:close()
            debounce_timer = nil
        end
        debounce_timer = vim.defer_fn(function()
            callback(args)
        end, wait)
    end
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

local function invoke_action(callback, payload)
    return function()
        if callback ~= nil and type(callback) == "function" then
            local ok, res = pcall(callback, payload)
            if not ok and res and #res > 0 then
                vim.notify(res, vim.log.levels.ERROR)
            end
        end
    end
end

local function create_mappings(buffer, mode, mappings, payload)
    for key, action in pairs(mappings) do
        vim.api.nvim_buf_set_keymap(buffer, mode, key, "", {
            expr = false,
            silent = false,
            noremap = true,
            replace_keycodes = false,
            callback = invoke_action(action, payload)
        })
    end
end

local function populate_buffer(buffer, lines)
    local oldma = vim.bo[buffer].modifiable
    vim.bo[buffer].modifiable = true
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines or {})
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
local function normalize_view(state)
    if state.list_window and vim.api.nvim_win_is_valid(state.list_window) then
        vim.wo[state.list_window][0].cursorline = true
    end
    if state.prompt_window and vim.api.nvim_win_is_valid(state.prompt_window) then
        vim.wo[state.prompt_window][0].cursorline = false
    end
    if state.preview_window and vim.api.nvim_win_is_valid(state.preview_window) then
        vim.wo[state.preview_window][0].cursorline = false
    end
end

local function highlight_list(state)
    local entries = state._content.entries
    local positions = state._content.positions
    if entries and #entries > 0 and positions and #positions > 0 then
        local cursor = vim.api.nvim_win_get_cursor(state.list_window)
        local height = vim.api.nvim_win_get_height(state.list_window)
        assert(#entries == #positions)
        highlight_range(
            state.list_buffer,
            math.max(1, cursor[1] - height),
            math.min(#entries, cursor[1] + height),
            entries, positions, state._content.streaming)
    end
end

local function decorate_list(state)
end

local function render_list(state)
    if state.list_buffer and vim.api.nvim_buf_is_valid(state.list_buffer) then
        populate_buffer(
            state.list_buffer,
            state._content.entries
        )
    end

    if state.list_window and vim.api.nvim_win_is_valid(state.list_window) then
        decorate_list(state)
        highlight_list(state)
        vim.api.nvim_win_call(
            state.list_window,
            vim.cmd.redraw
        )
    end
end

M.actions.move_cursor = function(context, dir)
    local list_window = context.list_window
    local cursor = vim.api.nvim_win_get_cursor(list_window)
    local line_count = vim.fn.line("$", list_window)

    if cursor[1] == 1 and dir < 0 then cursor[1] = 0 end
    cursor[1] = (cursor[1] + dir) % (line_count + 1)
    if cursor[1] == 0 and dir > 0 then cursor[1] = 1 end
    vim.api.nvim_win_set_cursor(list_window, cursor)
end

M.actions.select_next = function(context)
    return M.actions.move_cursor(context, 1)
end

M.actions.select_prev = function(context)
    return M.actions.move_cursor(context, -1)
end

M.actions.select_entry = function(context)
    local cursor = vim.api.nvim_win_get_cursor(context.list_window)
    local text = vim.api.nvim_buf_get_text(
        context.list_buffer,
        cursor[1] - 1,
        cursor[2],
        cursor[1] - 1,
        -1,
        {}
    )
    if text and #text > 0 and text[1] ~= nil then
    end
    M.actions.close_prompt(context)
end

M.actions.toggle_entry = function(context)
    local list_window = context.list_window
    local cursor = vim.api.nvim_win_get_cursor(list_window)
    local placed = vim.fn.sign_getplaced(context.list_buffer, {
        group = "list_toggle_entry_group", lnum = cursor[1],
    })
    if placed and #placed > 0 and placed[1].signs and #placed[1].signs > 0 and placed[1].signs[1] then
        vim.fn.sign_unplace(
            "list_toggle_entry_group",
            {
                buffer = context.list_buffer,
                id = placed[1].signs[1].id,
            }
        )
    else
        local sign_name = string.format(
            "list_toggle_entry_sign_%d",
            context.list_buffer
        )
        vim.fn.sign_place(
            cursor[1],
            "list_toggle_entry_group",
            sign_name,
            context.list_buffer,
            {
                lnum = cursor[1],
                priority = 10,
            }
        )
    end
    M.actions.move_cursor(context, 1)
end

M.actions.send_quickfix = function(context)
    local placed = vim.fn.sign_getplaced(context.list_buffer, {
        group = "list_toggle_entry_group",
    })
    if placed and #placed > 0 and placed[1].signs then
        local items = {}
        for _, sign in ipairs(placed[1].signs or {}) do
            local line = vim.fn.getbufline(
                context.list_buffer,
                sign.lnum
            )
            if line and #line > 0 then
                table.insert(items, {
                    filename = line[1],
                    col = 1,
                    lnum = 1,
                })
            end
        end
        vim.fn.setqflist({}, " ", {
            nr = "$",
            items = items,
            title = "[Selection]",
        })
        vim.cmd.copen()
        M.actions.close_prompt(context)
    end
end

M.actions.close_prompt = function(context)
    if context.prompt_window and vim.api.nvim_win_is_valid(context.prompt_window) then
        vim.api.nvim_win_close(context.prompt_window, true)
    end
    if context.list_window and vim.api.nvim_win_is_valid(context.list_window) then
        vim.api.nvim_win_close(context.list_window, true)
    end
    if context.preview_window and vim.api.nvim_win_is_valid(context.preview_window) then
        vim.api.nvim_win_close(context.list_window, true)
    end
    return context
end

function M.context(identifier, context)
    if type(identifier) == "function" then
        identifier = identifier(context)
    end
    if not identifier or identifier == false then
        return context
    end
    M.state[identifier] = context
    return context
end

function M.select(opts)
    opts = vim.tbl_deep_extend("force", {
        prompt_confirm = M.actions.select_entry,
        prompt_interrupt = M.actions.close_prompt,
        prompt_debounce = 200,
        prompt_preview = false,
        prompt_input = false,
        prompt_list = true,
        prompt_prefix = "> ",
        window_ratio = 0.15,
        resume_view = false,
        identifier = nil,
        mappings = {
            ["<tab>"] = M.actions.toggle_entry,
            -- ["<esc>"] = M.actions.close_prompt,
            ["<c-p>"] = M.actions.select_prev,
            ["<c-n>"] = M.actions.select_next,
            ["<c-k>"] = M.actions.select_prev,
            ["<c-j>"] = M.actions.select_next,
            ["<c-q>"] = M.actions.send_quickfix,
            ["<c-s>"] = M.actions.split_horizontal,
            ["<c-v>"] = M.actions.split_vertical,
        },
    }, opts or {})

    local size = vim.g.win_viewport_height * opts.window_ratio
    local context = {
        source_window = vim.api.nvim_get_current_win(),
        list_buffer = nil,
        list_window = nil,
        preview_buffer = nil,
        preview_window = nil,
        prompt_buffer = nil,
        prompt_window = nil,
        _content = {
            entries = nil,
            positions = nil,
            streaming = false
        }
    }

    if opts.prompt_input then
        local prompt_buffer = context.prompt_buffer
        if not prompt_buffer or not vim.api.nvim_buf_is_valid(prompt_buffer) then
            prompt_buffer = vim.api.nvim_create_buf(false, true)
            prompt_buffer = initialize_buffer(prompt_buffer, "prompt", "fuzzy")
            create_mappings(prompt_buffer, "i", opts.mappings, context)
            vim.bo[prompt_buffer].bufhidden = opts.identifier and "hide" or "wipe"
            vim.bo[prompt_buffer].modifiable = true

            local onlist = vim.schedule_wrap(function(entries, positions)
                if entries ~= nil and positions ~= nil then
                    context._content.positions = positions
                    context._content.entries = entries
                    context._content.streaming = true
                    render_list(context)
                elseif entries == nil and positions == nil then
                    -- new entries will no longer be sent here
                    -- _content holds the latest and all entries
                    context._content.streaming = false
                end
            end)

            local prompt_trigger = vim.api.nvim_create_autocmd({ "TextChangedP", "TextChangedI" }, {
                buffer = prompt_buffer,
                callback = debounce_callback(opts.prompt_debounce, function(args)
                    if not args.buf or not vim.api.nvim_buf_is_valid(args.buf) then
                        return
                    end
                    local text = vim.api.nvim_buf_get_text(args.buf, 0, 0, 0, -1, {})
                    if text and #text > 0 and text[1] ~= nil and type(opts.prompt_input) == "function" then
                        vim.api.nvim_win_set_cursor(context.list_window, { 1, 0 })
                        local ok, status, entries, positions = pcall(opts.prompt_input, text[1], context, onlist)
                        if not ok or ok == false then
                            vim.notify(status, vim.log.levels.ERROR)
                        elseif entries ~= nil and #entries > 0 then
                            onlist(entries, positions)
                            onlist(nil, nil)
                        end
                    end
                end),
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
                    M.context(opts.identifier, nil)
                    context.prompt_buffer = nil
                    context.prompt_window = nil
                    prompt_buffer = nil
                    return true
                end,
                once = true,
            })

            vim.fn.prompt_setprompt(prompt_buffer, opts.prompt_query or "")
            vim.fn.prompt_setcallback(prompt_buffer, invoke_action(opts.prompt_confirm, context))
            vim.fn.prompt_setinterrupt(prompt_buffer, invoke_action(opts.prompt_interrupt, context))

            assert(vim.fn.sign_define(sign_name, {
                text = opts.prompt_prefix, priority = 10
            }) == 0, "failed to define sign")
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
        elseif opts.resume_view == false then
            populate_buffer(prompt_buffer, {})
        end

        local prompt_window = context.prompt_window
        if not prompt_window or not vim.api.nvim_win_is_valid(prompt_window) then
            prompt_window = vim.api.nvim_open_win(prompt_buffer, true, {
                split = "below", win = -1, height = 1, noautocmd = false
            });
            vim.api.nvim_win_set_height(prompt_window, 1)
            prompt_window = initialize_window(prompt_window)
        end

        context.prompt_buffer = prompt_buffer
        context.prompt_window = prompt_window
    end

    if opts.prompt_list then
        local list_buffer = context.list_buffer
        if not list_buffer or not vim.api.nvim_buf_is_valid(list_buffer) then
            list_buffer = vim.api.nvim_create_buf(false, true)
            list_buffer = initialize_buffer(list_buffer, "nofile", "list")
            vim.bo[list_buffer].bufhidden = opts.identifier and "hide" or "wipe"
            vim.bo[list_buffer].modifiable = false

            if not opts.prompt_input then
                create_mappings(list_buffer, "n", opts.mappings, context)
                create_mappings(list_buffer, "n", {
                    ["<cr>"] = opts.prompt_confirm,
                    ["<esc>"] = opts.prompt_interrupt,
                    ["<c-c>"] = opts.prompt_interrupt,
                }, context)
            end

            if type(opts.prompt_list) == "table" then
                local entries, positions
                if type(opts.prompt_list[1]) == "table" then
                    entries = opts.prompt_list[1]
                    positions = opts.prompt_list[2]
                elseif type(opts.prompt_list) == "function" then
                    entries, positions = opts.prompt_list(context)
                else
                    entries = opts.prompt_list
                end
                context._content.positions = positions
                context._content.entries = entries
                context._content.streaming = false
                render_list(context)
            end

            local sign_name = string.format(
                "list_toggle_entry_sign_%d",
                list_buffer
            )

            vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
                buffer = list_buffer,
                callback = function()
                    assert(vim.fn.sign_undefine(sign_name) == 0)
                    M.context(opts.identifier, nil)
                    context.list_buffer = nil
                    context.list_window = nil
                    list_buffer = nil
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

        local list_window = context.list_window
        if not list_window or not vim.api.nvim_win_is_valid(list_window) then
            local list_height = math.floor(math.ceil(size))
            list_window = vim.api.nvim_open_win(list_buffer, true, {
                split = context.prompt_window and "above" or "below",
                height = list_height,
                noautocmd = false,
                win = context.prompt_window or -1,
            });
            vim.api.nvim_win_set_height(list_window, list_height)
            list_window = initialize_window(list_window)
            vim.wo[list_window][0].signcolumn = 'number'

            local highlight_matches = vim.api.nvim_create_autocmd("WinScrolled", {
                pattern = tostring(list_window),
                callback = function()
                    decorate_list(context)
                    highlight_list(context)
                end
            })

            vim.api.nvim_create_autocmd("WinClosed", {
                pattern = tostring(list_window),
                callback = function()
                    pcall(vim.api.nvim_del_autocmd, highlight_matches)
                    return true
                end,
                once = true,
            })
        end

        context.list_buffer = list_buffer
        context.list_window = list_window
    end

    if opts.prompt_list and opts.prompt_preview then
        local preview_buffer = context.preview_buffer
        if not preview_buffer or not vim.api.nvim_buf_is_valid(preview_buffer) then
            preview_buffer = vim.api.nvim_create_buf(false, true)
            preview_buffer = initialize_buffer(preview_buffer, "nofile", "preview")
            vim.bo[preview_buffer].bufhidden = opts.identifier and "hide" or "wipe"
            vim.bo[preview_buffer].modifiable = false
        elseif opts.resume_view == false then
            populate_buffer(preview_buffer, {})
        end

        local preview_window = context.preview_window
        if not preview_window or not vim.api.nvim_win_is_valid(preview_window) then
            local preview_height = math.floor(math.ceil(size))
            preview_window = vim.api.nvim_open_win(preview_buffer, true, {
                split = context.list_window and "above" or "below",
                height = preview_height,
                noautocmd = false,
                win = context.list_window or -1,
            });
            vim.api.nvim_win_set_height(preview_window, preview_height)
            preview_window = initialize_window(preview_window)
        end

        context.preview_buffer = preview_buffer
        context.preview_window = preview_window
    end

    if context.prompt_window then
        vim.api.nvim_set_current_win(context.prompt_window)
        vim.api.nvim_win_call(context.prompt_window, vim.cmd.startinsert)
        normalize_view(context)
    elseif context.list_window then
        vim.api.nvim_set_current_win(context.list_window)
        vim.api.nvim_win_call(context.list_window, vim.cmd.stopinsert)
        normalize_view(context)
    else
        vim.api.nvim_set_current_win(context.source_window)
    end

    return M.context(opts.identifier, context)
end

return M
