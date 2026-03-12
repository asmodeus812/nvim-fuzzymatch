local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class ManpagesPickerOptions
--- @field args? string[] Override the arguments passed to the command

local M = {}

local function parse_manpage_entry(line)
    local name, section = tostring(line or ""):match("^%s*([^%s%(,]+)[^%(]*%(([^%)]+)%)")
    if name and section then
        return string.format("%s(%s)", name, section)
    end
    return line and line:match("^%s*(%S+)") or false
end

--- Open Manpages picker.
--- @param opts ManpagesPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_manpages_picker(opts)
    opts = util.merge_picker_options({
        preview = false,
        args = { "-k", "." },
    }, opts)
    local cmd = util.pick_first_command({ "apropos", "man" })

    local picker = Picker.new(vim.tbl_extend("force", {
        content = assert(cmd),
        headers = util.build_picker_headers("Manpages", opts),
        context = { args = opts.args },
        stream_map = parse_manpage_entry,
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry)
                vim.cmd({ cmd = "Man", args = { entry } })
                return false
            end)),
        },
        highlighters = {
            Select.RegexHighlighter.new({
                { "^[^(]+", "Function" },
                { "%(([^)]+)%)", "Number", 1 },
                { "%(", "Delimiter" },
                { "%)", "Delimiter" },
            }),
        },
    }, opts))

    picker:open()
    return picker
end

return M
