local M = {
    picker_instance_map = {}
}

--- Open Register picker instance picker.
--- @param picker_key string
--- @param picker Picker
--- @return Picker
function M.register_picker_instance(picker_key, picker)
    M.picker_instance_map[picker_key] = picker
    return picker
end

--- Open Get picker instance picker.
--- @param picker_key string
--- @return Picker|nil
function M.get_picker_instance(picker_key)
    return M.picker_instance_map[picker_key]
end

--- Open Remove picker instance picker.
--- @param picker_key string
--- @return Picker|nil
function M.remove_picker_instance(picker_key)
    local picker = M.picker_instance_map[picker_key]
    M.picker_instance_map[picker_key] = nil
    return picker
end

--- Open Clear picker registry picker.
function M.clear_picker_registry()
    M.picker_instance_map = {}
end

--- Open Picker instance picker.
--- @param picker_key string
--- @return Picker
function M.open_picker_instance(picker_key)
    local picker = M.get_picker_instance(picker_key)
    assert(picker and picker.open)
    picker:open()
    return picker
end

return M
