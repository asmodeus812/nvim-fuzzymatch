local M = {}

local SKIP_MODULES = {
    util = true,
    registry = true,
    select = true,
    excmd = true,
}

local COMMON_ARGS = {
    cwd = "string",
    args = "list",
    env = "list",
    preview = "bool",
    icons = "bool",
    watch = "bool",
    prompt_query = "string",
    prompt_debounce = "number",
    match_limit = "number",
    match_timer = "number",
    match_step = "number",
    stream_type = "string",
    stream_step = "number",
    stream_debounce = "number",
    window_size = "number",
    interactive = "bool",
}

local VALUE_HINTS = {
    preview = { "true", "false" },
    icons = { "true", "false" },
    watch = { "true", "false" },
    interactive = { "true", "false" },
    stream_type = { "lines", "bytes" },
}

local function list_picker_modules()
    local files = vim.api.nvim_get_runtime_file("lua/fuzzy/pickers/*.lua", true)
    local seen = {}
    local modules = {}
    for _, path in ipairs(files or {}) do
        local name = vim.fn.fnamemodify(path, ":t:r")
        if name and not SKIP_MODULES[name] and not seen[name] then
            seen[name] = true
            modules[#modules + 1] = name
        end
    end
    table.sort(modules)
    return modules
end

local function open_command_name(fn_name)
    local name = fn_name:match("^open_(.+)$")
    if not name then
        return nil
    end
    name = name:gsub("_picker$", "")
    return name
end

local function parse_csv_values(text)
    if text == "" then
        return {}
    end
    local values = {}
    local current = {}
    local quote = nil
    local i = 1
    while i <= #text do
        local ch = text:sub(i, i)
        if ch == "\\" and i < #text then
            current[#current + 1] = text:sub(i + 1, i + 1)
            i = i + 2
        elseif (ch == "'" or ch == '"') then
            if quote == ch then
                quote = nil
            elseif quote == nil then
                quote = ch
            else
                current[#current + 1] = ch
            end
            i = i + 1
        elseif ch == "," and quote == nil then
            local value = table.concat(current)
            if value ~= "" then
                values[#values + 1] = value
            end
            current = {}
            i = i + 1
        else
            current[#current + 1] = ch
            i = i + 1
        end
    end
    local value = table.concat(current)
    if value ~= "" then
        values[#values + 1] = value
    end
    return values
end

local function parse_string_value(text)
    if text == "" then
        return text
    end
    local quote = text:sub(1, 1)
    if quote ~= '"' and quote ~= "'" then
        return text
    end
    if text:sub(-1) == quote and #text >= 2 then
        local inner = text:sub(2, -2)
        return (inner:gsub("\\([" .. quote .. "\\])", "%1"))
    end
    return text
end

local function parse_value(key, value)
    local kind = COMMON_ARGS[key]
    if kind == "bool" then
        if value == "true" then
            return true
        end
        if value == "false" then
            return false
        end
        return nil
    end
    if kind == "number" then
        local as_number = tonumber(value)
        if as_number ~= nil and value:match("^%d+%.?%d*$") then
            return as_number
        end
        return nil
    end
    if kind == "list" then
        return parse_csv_values(parse_string_value(value))
    end
    return parse_string_value(value)
end

function M.collect_picker_commands()
    local commands = {}
    for _, module_name in ipairs(list_picker_modules()) do
        local ok, module = pcall(require, "fuzzy.pickers." .. module_name)
        if ok and type(module) == "table" then
            for key, value in pairs(module) do
                if type(value) == "function" then
                    local command_name = open_command_name(key)
                    if command_name then
                        commands[command_name] = value
                    end
                end
            end
        end
    end
    return commands
end

function M.open_picker(command_name, opts)
    local commands = M.collect_picker_commands()
    local picker = commands[command_name]
    if not picker then
        vim.notify(
            string.format("Unknown picker: %s", tostring(command_name)),
            vim.log.levels.WARN
        )
        return
    end
    return picker(opts or {})
end

local function parse_kv_args(args)
    local opts = {}
    for _, arg in ipairs(args or {}) do
        local key, value = arg:match("^([^=]+)=(.*)$")
        if key and value ~= nil then
            if COMMON_ARGS[key] then
                local parsed = parse_value(key, value)
                if parsed ~= nil then
                    opts[key] = parsed
                else
                    vim.notify(
                        string.format("Invalid value for %s: %s", key, value),
                        vim.log.levels.WARN
                    )
                end
            else
                vim.notify(
                    string.format("Unknown option: %s", key),
                    vim.log.levels.WARN
                )
            end
        end
    end
    return opts
end

function M.complete_pickers(arg_lead)
    local matches = {}
    local commands = M.collect_picker_commands()
    for name in pairs(commands) do
        if arg_lead == "" or vim.startswith(name, arg_lead) then
            matches[#matches + 1] = name
        end
    end
    table.sort(matches)
    return matches
end

local function complete_args(arg_lead, cmdline)
    local tokens = vim.split(cmdline or "", "%s+")
    if #tokens <= 2 then
        return M.complete_pickers(arg_lead)
    end
    local key = arg_lead:match("^([^=]+)=")
    if key == "cwd" then
        local prefix = arg_lead:match("^[^=]+=(.*)$") or ""
        local matches = {}
        for _, path in ipairs(vim.fn.getcompletion(prefix, "file") or {}) do
            matches[#matches + 1] = "cwd=" .. path
        end
        return matches
    end
    if key and VALUE_HINTS[key] then
        local matches = {}
        for _, value in ipairs(VALUE_HINTS[key]) do
            if value:find("^" .. vim.pesc(arg_lead:match("=([^=]*)$") or ""), 1) then
                matches[#matches + 1] = key .. "=" .. value
            end
        end
        return matches
    end
    local matches = {}
    for name in pairs(COMMON_ARGS) do
        local suggestion = name .. "="
        if arg_lead == "" or vim.startswith(suggestion, arg_lead) then
            matches[#matches + 1] = suggestion
        end
    end
    table.sort(matches)
    return matches
end

function M.register_user_commands(command_name)
    local name = command_name or "Fzm"
    vim.api.nvim_create_user_command(name, function(cmd_opts)
        local args = cmd_opts.fargs or {}
        local picker_name = args[1]
        if not picker_name or picker_name == "" then
            vim.notify(
                string.format("Usage: %s {picker} [key=value ...]", name),
                vim.log.levels.WARN
            )
            return
        end
        local opts = parse_kv_args({ unpack(args, 2) })
        M.open_picker(picker_name, opts)
    end, {
        nargs = "+",
        complete = function(arg_lead, cmdline)
            return complete_args(arg_lead, cmdline)
        end,
    })
end

return M
