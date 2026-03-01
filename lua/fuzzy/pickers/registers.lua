local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class RegistersPickerOptions
--- @field filter? string|nil Pattern to filter register names
--- @field preview? boolean Enable preview window

local M = {}

local function collect_register_list()
    local register_name_list = {
        '"',
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        "-", "+", "*", ".", ":", "%", "#", "=", "/", "_",
    }
    for code_point = string.byte("a"), string.byte("z") do
        table.insert(register_name_list, string.char(code_point))
    end
    for code_point = string.byte("A"), string.byte("Z") do
        table.insert(register_name_list, string.char(code_point))
    end
    return register_name_list
end

--- Open Registers picker.
--- @param opts RegistersPickerOptions|nil Picker options for this picker
--- @return Picker
function M.open_registers_picker(opts)
    opts = util.merge_picker_options({
        preview = false,
    }, opts)

    local picker = Picker.new(vim.tbl_extend("force", {
        content = function(stream_callback, args)
            local register_list = args.items
            for _, register_entry in ipairs(register_list) do
                local register_name = register_entry.name
                local register_info = vim.fn.getreginfo(register_name)
                local register_preview = ""
                if register_info and register_info.regcontents then
                    register_preview = table.concat(
                        register_info.regcontents,
                        "\\n"
                    )
                    register_preview = register_preview:gsub(
                        "\\r?\\n",
                        " "
                    )
                end
                if #register_preview > 80 then
                    register_preview = table.concat({
                        register_preview:sub(1, 77),
                        "..."
                    })
                end
                stream_callback({
                    name = register_name,
                    preview = register_preview,
                    regcontents = register_info and register_info.regcontents or nil,
                    regtype = register_info and register_info.regtype or nil,
                })
            end
            stream_callback(nil)
        end,
        headers = util.build_picker_headers("Registers", opts),
        context = {
            args = function(_)
                local register_name_list = collect_register_list()
                local items = {}
                for _, register_name in ipairs(register_name_list) do
                    items[#items + 1] = vim.fn["fuzzymatch#getregsig"](register_name)
                end
                return { items = items }
            end,
        },
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry_value)
                local register_name = entry_value and entry_value.name or nil
                local regcontents = entry_value and entry_value.regcontents or nil
                local regtype = entry_value and entry_value.regtype or nil
                if regcontents == nil then
                    local register_info = assert(vim.fn.getreginfo(register_name))
                    regcontents = register_info.regcontents
                    regtype = register_info.regtype
                end
                vim.fn.setreg('"', assert(regcontents), regtype)
                return false
            end)),
        },
        display = function(entry_value)
            local register_name = entry_value and entry_value.name or nil
            local register_preview = entry_value and entry_value.preview or ""
            return table.concat({ "[", register_name, "] ", register_preview })
        end,
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
