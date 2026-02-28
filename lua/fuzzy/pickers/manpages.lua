local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class ManpagesPickerOptions
--- @field preview? boolean Enable preview window
--- @field match_step? integer Match batch size

local M = {}

local function parse_manpage_entries(raw_output)
    local entry_list = {}
    local entry_map = {}
    for line in tostring(raw_output or ""):gmatch("[^\r\n]+") do
        local name, section = line:match("^%s*([^%s%(,]+)[^%(]*%(([^%)]+)%)")
        local entry = nil
        if name and section then
            entry = string.format("%s(%s)", name, section)
        else
            entry = line:match("^%s*(%S+)")
        end
        if entry and #entry > 0 and not entry_map[entry] then
            entry_map[entry] = true
            entry_list[#entry_list + 1] = entry
        end
    end
    return entry_list
end

local function collect_manpage_entries()
    local command_name = util.pick_first_command({ "apropos", "man" })
    if not command_name then
        return {}
    end
    local result = vim.system({ command_name, "-k", "." }, {
        text = true,
    }):wait()
    if not result or result.code ~= 0 then
        return {}
    end
    return parse_manpage_entries(result.stdout)
end

--- Open Manpages picker.
--- @param opts ManpagesPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_manpages_picker(opts)
    opts = util.merge_picker_options({
        preview = false,
        match_step = 50000,
    }, opts)

    local picker = Picker.new(vim.tbl_extend("force", {
        content = function(stream_callback)
            local manpage_list = collect_manpage_entries()
            for _, manpage in ipairs(manpage_list) do
                stream_callback(manpage)
            end
            stream_callback(nil)
        end,
        headers = util.build_picker_headers("Manpages", opts),
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry_value)
                assert(type(entry_value) == "string" and #entry_value > 0)
                vim.cmd({ cmd = "Man", args = { entry_value } })
                return false
            end)),
        },
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
