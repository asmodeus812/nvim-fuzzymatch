local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class ManpagesPickerOptions
--- @field command_args? string[] Override the arguments passed to the command

local M = {}

local function parse_manpage_entry(line)
    local name, section = tostring(line or ""):match("^%s*([^%s%(,]+)[^%(]*%(([^%)]+)%)")
    if name and section then
        return string.format("%s(%s)", name, section)
    end
    return tostring(line or ""):match("^%s*(%S+)")
end

--- Open Manpages picker.
--- @param opts ManpagesPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_manpages_picker(opts)
    local cmd = util.pick_first_command({ "apropos", "man" })
    opts = util.merge_picker_options({
        command_args = { "-k", "." }
    }, opts)

    local picker = Picker.new(vim.tbl_extend("force", {
        content = assert(cmd),
        headers = util.build_picker_headers("Manpages", opts),
        context = {
            args = opts.command_args,
        },
        stream_map = parse_manpage_entry,
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
