local M = {
    picker_instance_map = {}
}

function M.register_picker_instance(picker_key, picker)
    if type(picker_key) ~= "string" or #picker_key == 0 then
        return nil
    end
    M.picker_instance_map[picker_key] = picker
    return picker
end

function M.get_picker_instance(picker_key)
    if type(picker_key) ~= "string" or #picker_key == 0 then
        return nil
    end
    return M.picker_instance_map[picker_key]
end

function M.remove_picker_instance(picker_key)
    if type(picker_key) ~= "string" or #picker_key == 0 then
        return nil
    end
    local picker = M.picker_instance_map[picker_key]
    M.picker_instance_map[picker_key] = nil
    return picker
end

function M.clear_picker_registry()
    M.picker_instance_map = {}
end

function M.open_picker_instance(picker_key)
    local picker = M.get_picker_instance(picker_key)
    if picker and picker.open then
        picker:open()
        return picker
    end
    return nil
end

return M
