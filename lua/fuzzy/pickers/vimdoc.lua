local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class VimdocPickerOptions
--- @field preview? boolean|Select.Preview Enable preview window
--- @field prefix? string|false Prefix filter for API names (default: "nvim_")
--- @field include_deprecated? boolean Include deprecated API items
--- @field deprecated_only? boolean Show only deprecated API items
--- @field include_private? boolean Include private/internal APIs (e.g. nvim__)
--- @field sort_by? "name"|"since" Sort order for entries

local M = {}

local function normalize_params(params)
    local parts = {}
    for _, param in ipairs(params or {}) do
        local ptype = type(param) == "table" and param[1] or nil
        local pname = type(param) == "table" and param[2] or nil
        if ptype and #ptype > 0 then
            if pname and #pname > 0 then
                parts[#parts + 1] = string.format("%s %s", ptype, pname)
            else
                parts[#parts + 1] = ptype
            end
        end
    end
    return parts
end

local function make_entry(fn_meta)
    local name = type(fn_meta) == "table" and fn_meta.name or nil
    if type(name) ~= "string" or #name == 0 then
        return nil
    end
    local params = normalize_params(fn_meta.parameters)
    local signature = string.format(
        "%s(%s) -> %s",
        name,
        table.concat(params, ", "),
        tostring(fn_meta.return_type or "Object")
    )
    return {
        name = name,
        tag = string.format("%s()", name),
        signature = signature,
        since = tonumber(fn_meta.since) or 0,
        deprecated_since = tonumber(fn_meta.deprecated_since),
        method = fn_meta.method == true,
        return_type = tostring(fn_meta.return_type or "Object"),
        params = params,
    }
end

local function pass_filters(entry, opts)
    if not entry or not entry.name then
        return false
    end
    if opts.prefix and #opts.prefix > 0
        and not vim.startswith(entry.name, opts.prefix)
    then
        return false
    end
    if opts.include_private ~= true and entry.name:find("__", 1, true) then
        return false
    end
    if opts.deprecated_only == true and not entry.deprecated_since then
        return false
    end
    if opts.include_deprecated == false and entry.deprecated_since then
        return false
    end
    return true
end

local function collect_api_entries(opts)
    local ok, api_info = pcall(vim.fn.api_info)
    if not ok or type(api_info) ~= "table" then
        return {}
    end
    local functions = api_info.functions
    if type(functions) ~= "table" then
        return {}
    end

    local entries = {}
    local seen = {}
    for _, fn_meta in ipairs(functions) do
        local entry = make_entry(fn_meta)
        if entry and pass_filters(entry, opts) and not seen[entry.name] then
            seen[entry.name] = true
            entries[#entries + 1] = entry
        end
    end

    table.sort(entries, function(left, right)
        if opts.sort_by == "since" then
            if left.since ~= right.since then
                return left.since > right.since
            end
        end
        return left.name < right.name
    end)
    return entries
end

local function open_api_help(entry)
    local tag = entry.tag
    if type(tag) ~= "string" or #tag == 0 then
        return false
    end

    local base = tag:gsub("%(%)$", "")
    local candidates = {
        tag,
        base,
        string.format("api-%s", base),
    }
    for _, candidate in ipairs(candidates) do
        local ok = pcall(vim.cmd, { cmd = "help", args = { candidate } })
        if ok then
            return true
        end
    end
    return false
end

local function display_entry(entry)
    local deprecated = entry.deprecated_since
        and string.format(" dep@%d", entry.deprecated_since) or ""
    local method = entry.method and " method" or ""
    return string.format(
        "%-38s  since:%-3d%s%s  %s",
        entry.tag,
        entry.since or 0,
        deprecated,
        method,
        entry.return_type
    )
end

local function build_preview()
    return Select.CustomPreview.new(function(entry)
        local lines = {}
        if entry.deprecated_since then
            lines[#lines + 1] = "Deprecated since: " .. tostring(entry.deprecated_since)
        end
        lines[#lines + 1] = entry.tag
        lines[#lines + 1] = "Signature: " .. entry.signature
        lines[#lines + 1] = "Return:    " .. tostring(entry.return_type)
        lines[#lines + 1] = "Since:     " .. tostring(entry.since or 0)
        lines[#lines + 1] = "Parameters:"
        if #entry.params == 0 then
            lines[#lines + 1] = "  (none)"
        else
            for _, param in ipairs(entry.params) do
                lines[#lines + 1] = "  - " .. param
            end
        end
        lines[#lines + 1] = "Press <CR> to open :help " .. entry.tag
        return lines, "markdown"
    end)
end

--- Open Vim docs picker.
--- @param opts VimdocPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_vimdoc_picker(opts)
    opts = util.merge_picker_options({
        preview = true,
        prefix = "nvim_",
        include_deprecated = true,
        deprecated_only = false,
        include_private = false,
        sort_by = "name",
    }, opts)

    if opts.preview == true then
        opts.preview = build_preview()
    elseif opts.preview == false or opts.preview == nil then
        opts.preview = false
    end

    local picker = Picker.new(vim.tbl_extend("force", {
        content = function(stream, args)
            for _, entry in ipairs(args.items) do
                stream(entry)
            end
            stream(nil)
        end,
        headers = util.build_picker_headers("Vimdoc", opts),
        context = {
            args = function(_)
                return {
                    items = collect_api_entries(opts),
                }
            end,
        },
        preview = opts.preview,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry)
                open_api_help(entry)
                return false
            end)),
        },
        display = display_entry,
    }, opts, {
        match_timer = 10,
        match_step = 5000,
        stream_step = 10000,
        stream_debounce = 0,
        prompt_debounce = 30,
    }))

    picker:open()
    return picker
end

return M
