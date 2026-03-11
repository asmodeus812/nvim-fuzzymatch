local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class RegistersPickerOptions
--- @field filter? string|nil Pattern to filter register names
--- @field preview? boolean|Select.Preview Enable preview window or provide a custom previewer

local M = {}

local function collect_register_list()
    local names = {
        '"',
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        "-", "+", "*", ".", ":", "%", "#", "=", "/", "_",
    }
    for code_point = string.byte("a"), string.byte("z") do
        table.insert(names, string.char(code_point))
    end
    for code_point = string.byte("A"), string.byte("Z") do
        table.insert(names, string.char(code_point))
    end
    return names
end

--- Open Registers picker.
--- @param opts RegistersPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_registers_picker(opts)
    opts = util.merge_picker_options({
        preview = true,
        filter = nil,
    }, opts)

    if opts.preview == true then
        opts.preview = Select.CustomPreview.new(function(entry, _, _)
            local regcontents = entry and entry.regcontents
            if regcontents == nil then
                local info = vim.fn.getreginfo(entry.name)
                regcontents = info and info.regcontents
            end
            if type(regcontents) ~= "table" or #regcontents == 0 then
                regcontents = { "" }
            end
            return regcontents, "text"
        end)
    elseif opts.preview == false or opts.preview == nil then
        opts.preview = false
    end

    local picker = Picker.new(vim.tbl_extend("force", {
        content = function(stream, args)
            for _, register_entry in ipairs(args.items) do
                local name = register_entry.name
                if opts.filter ~= nil and name
                    and not name:match(opts.filter)
                then
                    goto continue
                end
                local info = vim.fn.getreginfo(name)
                local preview = ""
                if info and info.regcontents then
                    preview = table.concat(info.regcontents, "\\n")
                    preview = preview:gsub("\\r?\\n", " ")
                end
                local width = 80
                if #preview > width then
                    preview = table.concat({
                        preview:sub(1, width - 3),
                        "..."
                    })
                end
                stream({
                    name = name,
                    preview = preview,
                    regcontents = info and info.regcontents or nil,
                    regtype = info and info.regtype or nil,
                })
                ::continue::
            end
            stream(nil)
        end,
        headers = util.build_picker_headers("Registers", opts),
        context = {
            args = function(_)
                local items = {} -- collect the registers items
                local names = collect_register_list()
                for _, name in ipairs(names) do
                    items[#items + 1] = vim.fn["fuzzymatch#getregsig"](name)
                end
                return { items = items }
            end,
        },
        preview = opts.preview,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry)
                local regcontents = entry.regcontents
                local regtype = entry.regtype
                if regcontents == nil then
                    local info = assert(vim.fn.getreginfo(entry.name))
                    regcontents = info.regcontents
                    regtype = info.regtype
                end
                vim.fn.setreg('"', assert(regcontents), regtype)
                return false
            end)),
        },
        highlighters = {
            Select.RegexHighlighter.new({
                { "^%[[^%]]+%]", "Identifier" },
                { "^%[[^%]]+%]%s(.+)$", "String", 1 },
            }),
        },
        display = function(entry)
            return table.concat({ "[", entry.name, "] ", entry.preview or "" })
        end,
    }, opts, {
        match_timer = 5,
        match_step = 1000,
        stream_step = 2000,
        stream_debounce = 0,
        prompt_debounce = 20,
    }))

    picker:open()
    return picker
end

return M
