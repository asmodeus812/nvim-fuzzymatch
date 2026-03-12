local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class CommandsPickerOptions
--- @field include_builtin? boolean Include built-in commands
--- @field include_user? boolean Include user-defined commands

local M = {}

local function collect_command_names(opts)
    local items = {}
    local seen = {}

    if opts.include_builtin then
        local ok, builtin_command_map = pcall(vim.api.nvim_get_commands, { builtin = true })
        if ok and builtin_command_map then
            for name in pairs(builtin_command_map) do
                if not seen[name] then
                    seen[name] = true
                    items[#items + 1] = name
                end
            end
        end
    end

    if opts.include_user then
        local ok, user_command_map = pcall(vim.api.nvim_get_commands, {})
        if ok and user_command_map then
            for name in pairs(user_command_map) do
                if not seen[name] then
                    seen[name] = true
                    items[#items + 1] = name
                end
            end
        end
    end

    table.sort(items)
    return items
end

--- Open Commands picker.
--- @param opts CommandsPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_commands_picker(opts)
    opts = util.merge_picker_options({
        include_builtin = true,
        include_user = true,
        preview = false,
    }, opts)

    local picker = Picker.new(vim.tbl_extend("force", {
        content = function(stream, args)
            for _, name in ipairs(args.items) do
                stream(name)
            end
            stream(nil)
        end,
        headers = util.build_picker_headers("Commands", opts),
        context = {
            args = function(_)
                return {
                    items = collect_command_names(opts),
                }
            end,
        },
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry)
                vim.cmd(entry)
                return false
            end)),
        },
        highlighters = {
            Select.RegexHighlighter.new({
                { "^%S+", "Statement" },
            }),
        },
    }, opts, {
        match_timer = 5,
        match_step = 2000,
        stream_step = 4000,
        stream_debounce = 0,
        prompt_debounce = 25,
    }))

    picker:open()
    return picker
end

return M
