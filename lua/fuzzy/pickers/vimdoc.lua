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
        if type(ptype) == "string" and #ptype > 0 then
            if type(pname) == "string" and #pname > 0 then
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
    if type(opts.prefix) == "string" and #opts.prefix > 0
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

    local entry_list = {}
    local seen = {}
    for _, fn_meta in ipairs(functions) do
        local entry = make_entry(fn_meta)
        if entry and pass_filters(entry, opts) and not seen[entry.name] then
            seen[entry.name] = true
            entry_list[#entry_list + 1] = entry
        end
    end

    table.sort(entry_list, function(left, right)
        if opts.sort_by == "since" then
            if left.since ~= right.since then
                return left.since > right.since
            end
        end
        return left.name < right.name
    end)
    return entry_list
end

local function open_api_help(entry_value)
    local tag = type(entry_value) == "table" and entry_value.tag or entry_value
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
        local lines = {
            entry.tag,
            "",
            "Signature: " .. entry.signature,
            "Return:    " .. tostring(entry.return_type),
            "Since:     " .. tostring(entry.since or 0),
            "Method:    " .. tostring(entry.method == true),
        }
        if entry.deprecated_since then
            lines[#lines + 1] = "Deprecated:" .. " since " .. tostring(entry.deprecated_since)
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Parameters:"
        if #entry.params == 0 then
            lines[#lines + 1] = "  (none)"
        else
            for _, param in ipairs(entry.params) do
                lines[#lines + 1] = "  - " .. param
            end
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Press <CR> to open :help " .. entry.tag
        return lines, "markdown", ""
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
        content = function(stream_callback)
            local entry_list = collect_api_entries(opts)
            for _, entry in ipairs(entry_list) do
                stream_callback(entry)
            end
            stream_callback(nil)
        end,
        headers = util.build_picker_headers("Vimdoc", opts),
        preview = opts.preview,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry_value)
                open_api_help(entry_value)
                return false
            end)),
        },
        display = display_entry,
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
