local Picker = require("fuzzy.picker")
local Select = require("fuzzy.select")
local util = require("fuzzy.pickers.util")

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

local function get_register_preview(register_name)
    local register_info = vim.fn.getreginfo(register_name)
    if not register_info or not register_info.regcontents then
        return ""
    end
    local register_text = table.concat(register_info.regcontents, "\\n")
    register_text = register_text:gsub("\\r?\\n", " ")
    return register_text
end

function M.open_registers_picker(opts)
    opts = util.merge_picker_options({
        reuse = true,
        preview = false,
        match_step = 50000,
    }, opts)

    local register_name_list = collect_register_list()

    local picker = Picker.new(vim.tbl_deep_extend("force", {
        content = register_name_list,
        headers = util.build_picker_headers("Registers", opts),
        preview = false,
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry_value)
                local register_info = vim.fn.getreginfo(entry_value)
                if register_info and register_info.regcontents then
                    vim.fn.setreg('"', register_info.regcontents, register_info.regtype)
                end
                return false
            end)),
        },
        display = function(entry_value)
            local register_preview = get_register_preview(entry_value)
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
