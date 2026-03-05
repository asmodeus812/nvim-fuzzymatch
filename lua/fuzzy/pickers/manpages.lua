local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class ManpagesPickerOptions
--- @field preview? boolean Enable preview window

local M = {}

local function parse_manpage_entries(raw_output)
    local entries = {}
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
            entries[#entries + 1] = entry
        end
    end
    return entries
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
    }, opts)

    local picker = Picker.new(vim.tbl_extend("force", {
        content = function(stream, args)
            for _, manpage in ipairs(args.items) do
                stream(manpage)
            end
            stream(nil)
        end,
        headers = util.build_picker_headers("Manpages", opts),
        context = {
            args = function(_)
                return {
                    items = collect_manpage_entries(),
                }
            end,
        },
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry)
                vim.cmd({ cmd = "Man", args = { entry } })
                return false
            end)),
        },
    }, opts))

    picker:open()
    return picker
end

return M
