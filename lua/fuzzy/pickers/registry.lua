local M = {
    picker_instance_map = {}
}

function M.register_picker_instance(picker_key, picker)
    assert(type(picker_key) == "string" and #picker_key > 0)
    M.picker_instance_map[picker_key] = picker
    return picker
end

function M.get_picker_instance(picker_key)
    assert(type(picker_key) == "string" and #picker_key > 0)
    return M.picker_instance_map[picker_key]
end

function M.remove_picker_instance(picker_key)
    assert(type(picker_key) == "string" and #picker_key > 0)
    local picker = M.picker_instance_map[picker_key]
    M.picker_instance_map[picker_key] = nil
    return picker
end

function M.clear_picker_registry()
    M.picker_instance_map = {}
end

function M.open_picker_instance(picker_key)
    local picker = M.get_picker_instance(picker_key)
    assert(picker and picker.open)
    picker:open()
    return picker
end

return M
