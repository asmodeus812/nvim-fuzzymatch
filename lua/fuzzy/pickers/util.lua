local Select = require("fuzzy.select")
local Picker = require("fuzzy.picker")

local M = {}

local function resolve_working_directory(cwd)
    return type(cwd) == "function" and cwd() or cwd
end

function M.merge_picker_options(default_picker_options, user_picker_options)
    return vim.tbl_deep_extend("force", default_picker_options, user_picker_options or {})
end

function M.command_is_available(command_name)
    return command_name and vim.fn.executable(command_name) == 1
end

function M.pick_first_command(command_candidate_list)
    for _, command_name in ipairs(command_candidate_list or {}) do
        if M.command_is_available(command_name) then
            return command_name
        end
    end
    return nil
end

function M.find_git_root(current_working_directory)
    if not M.command_is_available("git") then
        return nil
    end
    local result = vim.system({
        "git",
        "-C",
        current_working_directory or vim.loop.cwd(),
        "rev-parse",
        "--show-toplevel",
    }, { text = true }):wait()
    if not result or result.code ~= 0 then
        return nil
    end
    local git_root = vim.trim(result.stdout or "")
    if #git_root > 0 then
        return git_root
    end
    return nil
end

function M.build_picker_headers(picker_title, picker_options)
    if picker_options and picker_options.headers ~= nil then
        return picker_options.headers
    end
    if not picker_title then
        return nil
    end
    local header_blocks = { { picker_title } }
    if picker_options and picker_options.cwd and picker_options.cwd_prompt then
        local cwd = resolve_working_directory(picker_options.cwd)
        if type(cwd) == "string" and #cwd > 0 then
            local header_text = cwd
            if picker_options.cwd_prompt_shorten_len then
                header_text = vim.fn.pathshorten(
                    header_text,
                    picker_options.cwd_prompt_shorten_val or 1
                )
                if #header_text > picker_options.cwd_prompt_shorten_len then
                    header_text = header_text:sub(
                        #header_text - picker_options.cwd_prompt_shorten_len + 1
                    )
                end
            end
            table.insert(header_blocks, { header_text })
        end
    elseif picker_options and picker_options.cwd then
        table.insert(header_blocks, {
            resolve_working_directory(picker_options.cwd)
        })
    end
    return header_blocks
end

function M.format_display_path(path_value, picker_options)
    if type(path_value) ~= "string" or #path_value == 0 then
        return path_value
    end
    picker_options = picker_options or {}
    if picker_options.filename_only then
        return vim.fs.basename(path_value)
    end
    local cwd = resolve_working_directory(picker_options.cwd)
    local normalized_path = vim.fs.normalize(path_value)
    if not picker_options.absolute_path and cwd and #cwd > 0 then
        local normalized_cwd = vim.fs.normalize(cwd)
        local cwd_prefix = table.concat({ normalized_cwd, "/" })
        if normalized_path:sub(1, #normalized_cwd + 1) == cwd_prefix then
            normalized_path = normalized_path:sub(#normalized_cwd + 2)
        end
    end
    if picker_options.path_shorten and tonumber(picker_options.path_shorten) then
        normalized_path = vim.fn.pathshorten(
            normalized_path, tonumber(picker_options.path_shorten)
        )
    end
    if picker_options.home_to_tilde and not picker_options.absolute_path then
        local home_directory = vim.loop.os_homedir()
        if home_directory and #home_directory > 0 then
            local home_prefix = table.concat({ home_directory, "/" })
            if normalized_path:sub(1, #home_directory + 1) == home_prefix then
                normalized_path = table.concat({
                    "~",
                    normalized_path:sub(#home_directory + 1)
                })
            end
        end
    end
    return normalized_path
end

function M.format_location_entry(
    filename,
    line_number,
    column_number,
    entry_text,
    entry_prefix
)
    local string_parts = {}
    if entry_prefix and #entry_prefix > 0 then
        string_parts[#string_parts + 1] = entry_prefix
        string_parts[#string_parts + 1] = " "
    end
    string_parts[#string_parts + 1] = filename or "[No Name]"
    string_parts[#string_parts + 1] = ":"
    string_parts[#string_parts + 1] = tostring(line_number or 1)
    string_parts[#string_parts + 1] = ":"
    string_parts[#string_parts + 1] = tostring(column_number or 1)
    if entry_text and #entry_text > 0 then
        string_parts[#string_parts + 1] = ": "
        string_parts[#string_parts + 1] = entry_text
    end
    return table.concat(string_parts)
end

function M.build_default_actions(converter_callback, picker_options)
    local action_map = {
        ["<cr>"] = Select.action(Select.select_entry, Select.all(converter_callback)),
        ["<c-q>"] = {
            Select.action(Select.send_quickfix, Select.all(converter_callback)),
            "qflist"
        },
        ["<c-t>"] = {
            Select.action(Select.select_tab, Select.all(converter_callback)),
            "tabe"
        },
        ["<c-v>"] = {
            Select.action(Select.select_vertical, Select.all(converter_callback)),
            "vert"
        },
        ["<c-s>"] = {
            Select.action(Select.select_horizontal, Select.all(converter_callback)),
            "split"
        },
    }
    if picker_options and picker_options.actions then
        action_map = vim.tbl_deep_extend("force", action_map, picker_options.actions)
    end
    return action_map
end

function M.build_picker_options(picker_options)
    return {
        match_limit = picker_options.match_limit,
        match_step = picker_options.match_step,
        match_timer = picker_options.match_timer,
        stream_step = picker_options.stream_step,
        stream_type = picker_options.stream_type,
        stream_debounce = picker_options.stream_debounce,
        prompt_debounce = picker_options.prompt_debounce,
        prompt_query = picker_options.prompt_query,
        prompt_decor = picker_options.prompt_decor,
        window_size = picker_options.window_size,
    }
end

function M.open_empty_picker(empty_message, picker_options)
    picker_options = picker_options or {}
    local picker = Picker.new({
        content = empty_message and { empty_message } or {},
        headers = M.build_picker_headers("Empty", picker_options),
        preview = false,
        actions = {
            ["<cr>"] = Select.noop_select,
        },
    })
    picker:open()
    return picker
end

function M.collect_history_entries(history_type)
    local history_entry_list = {}
    local history_count = vim.fn.histnr(history_type)
    for index = history_count, 1, -1 do
        local history_entry = vim.fn.histget(history_type, index)
        if type(history_entry) == "string" and #history_entry > 0 then
            history_entry_list[#history_entry_list + 1] = history_entry
        end
    end
    return history_entry_list
end

function M.parse_stack_entries(history_text)
    local history_entry_list = {}
    for _, line_text in ipairs(vim.split(history_text or "", "\n")) do
        local list_number = line_text:match("list%s+(%d+)")
        if list_number then
            history_entry_list[#history_entry_list + 1] = {
                number = tonumber(list_number),
                text = line_text,
            }
        end
    end
    return history_entry_list
end

function M.stream_buffer_lines(buf, chunk_size, stream_callback)
    local total_line_count = vim.api.nvim_buf_line_count(buf)
    local start_index = 0
    while start_index < total_line_count do
        local end_index = math.min(start_index + chunk_size, total_line_count)
        local line_chunk = vim.api.nvim_buf_get_lines(
            buf,
            start_index,
            end_index,
            false
        )
        for offset, line_text in ipairs(line_chunk) do
            stream_callback({
                bufnr = buf,
                lnum = start_index + offset,
                text = line_text,
            })
        end
        start_index = end_index
    end
end

function M.stream_line_numbers(buf, chunk_size, stream_callback)
    local total_line_count = vim.api.nvim_buf_line_count(buf)
    local start_index = 0
    while start_index < total_line_count do
        local end_index = math.min(start_index + chunk_size, total_line_count)
        for line_number = start_index + 1, end_index do
            stream_callback({
                bufnr = buf,
                lnum = line_number,
            })
        end
        start_index = end_index
    end
end

function M.normalize_query_text(query_text_value)
    if type(query_text_value) ~= "string" then
        return nil
    end
    if #query_text_value == 0 then
        return nil
    end
    local normalized_text_value = query_text_value:gsub("\n", " ")
    if #normalized_text_value == 0 then
        return nil
    end
    return normalized_text_value
end

return M
