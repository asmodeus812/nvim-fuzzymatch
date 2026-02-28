local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

--- @class RegistersPickerOptions
--- @field filter? string|nil Pattern to filter register names
--- @field preview? boolean Enable preview window
--- @field match_step? integer Match batch size

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
    opts = util.merge_picker_options({        preview = false,
        match_step = 50000,
    }, opts)

    local register_name_list = collect_register_list()

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = register_name_list,
        headers = util.build_picker_headers("Registers", opts),
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry_value)
                assert(type(entry_value) == "string" and #entry_value > 0)
                local register_info = assert(vim.fn.getreginfo(entry_value))
                assert(register_info.regcontents ~= nil)
                vim.fn.setreg('"', register_info.regcontents, register_info.regtype)
                return false
            end)),
        },
        display = function(entry_value)
            assert(type(entry_value) == "string" and #entry_value > 0)
            local register_info = vim.fn.getreginfo(entry_value)
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
            return table.concat({ "[", entry_value, "] ", register_preview })
        end,
    }, util.build_picker_options(opts)))

    picker:open()
    return picker
end

return M
