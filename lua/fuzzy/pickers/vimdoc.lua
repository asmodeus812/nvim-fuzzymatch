local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class VimdocPickerOptions
--- @field preview? boolean Enable preview window
--- @field match_step? integer Match batch size

local M = {}

local function collect_api_entries()
    local ok, api_info = pcall(vim.fn.api_info)
    if not ok or type(api_info) ~= "table" then
        return {}
    end
    local functions = api_info.functions
    if type(functions) ~= "table" then
        return {}
    end

    local entry_list = {}
    local entry_map = {}
    for _, fn_meta in ipairs(functions) do
        local name = type(fn_meta) == "table" and fn_meta.name or nil
        if type(name) == "string" and #name > 0 then
            local entry = string.format("%s()", name)
            if not entry_map[entry] then
                entry_map[entry] = true
                entry_list[#entry_list + 1] = entry
            end
        end
    end
    table.sort(entry_list)
    return entry_list
end

local function open_api_help(entry_value)
    if type(entry_value) ~= "string" or #entry_value == 0 then
        return false
    end
    local candidates = { entry_value }
    if entry_value:sub(-2) == "()" then
        candidates[#candidates + 1] = entry_value:sub(1, -3)
    else
        candidates[#candidates + 1] = entry_value .. "()"
    end
    for _, tag in ipairs(candidates) do
        local ok = pcall(vim.cmd, { cmd = "help", args = { tag } })
        if ok then
            return true
        end
    end
    return false
end

--- Open Vim docs picker.
--- @param opts VimdocPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_vimdoc_picker(opts)
    opts = util.merge_picker_options({
        preview = false,
        match_step = 50000,
    }, opts)

    local picker = Picker.new(vim.tbl_extend("force", {
        content = function(stream_callback)
            local entry_list = collect_api_entries()
            for _, entry in ipairs(entry_list) do
                stream_callback(entry)
            end
            stream_callback(nil)
        end,
        headers = util.build_picker_headers("Vim API", opts),
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry_value)
                open_api_help(entry_value)
                return false
            end)),
        },
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
