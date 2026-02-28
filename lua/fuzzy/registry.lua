--- @class Registry
--- Tracks picker instances and prunes idle hidden pickers.
--- @field items table
--- @field max_idle number|nil Maximum idle time in milliseconds before a picker is destroyed
--- @field prune_interval number Prune interval in milliseconds
--- @field prune_timer uv_timer_t|nil Timer used to run periodic pruning
--- @field now fun(): number Returns a millisecond timestamp
local Registry = {}
Registry.__index = Registry

--- Create a new registry instance.
--- @param opts table|nil
---   opts.max_idle: Maximum idle time in milliseconds before a picker is destroyed
---   opts.prune_interval: Timer interval in milliseconds
---   opts.now: Optional time provider returning milliseconds
--- @return Registry
function Registry.new(opts)
    assert(not Registry.items)
    local self = Registry
    opts = opts or {}
    self.items = {}
    self.max_idle = opts.max_idle
    self.prune_interval = opts.prune_interval or 30000
    self.now = opts.now or function()
        return vim.uv.hrtime() / 1e6
    end
    self.prune_timer = vim.uv.new_timer()
    self.prune_timer:start(self.prune_interval, self.prune_interval, function()
        Registry.prune(Registry.now())
    end)
    return self
end

--- Register a picker instance.
--- @param picker Picker
--- @return Picker
function Registry.register(picker)
    assert(picker)
    Registry.items[picker] = {
        last_used = Registry.now(),
    }
    return picker
end

--- Touch a picker instance and update its last used timestamp.
--- @param picker Picker
function Registry.touch(picker)
    local meta = Registry.items and Registry.items[picker]
    if not meta then
        return
    end
    meta.last_used = Registry.now()
end

--- Remove a picker instance from the registry.
--- @param picker Picker
function Registry.remove(picker)
    if Registry.items then
        Registry.items[picker] = nil
    end
end

local function picker_in_use(picker)
    if not picker then
        return false
    end
    if picker.isopen and picker:isopen() then
        return true
    end
    if picker.isvalid and picker:isvalid() then
        return true
    end
    if picker.stream and picker.stream.running and picker.stream:running() then
        return true
    end
    if picker.match and picker.match.running and picker.match:running() then
        return true
    end
    return false
end

--- Prune idle hidden pickers.
--- @param now number
function Registry.prune(now)
    if not Registry.items then
        return
    end
    local max_idle = Registry.max_idle
    if not max_idle or max_idle <= 0 then
        return
    end
    for picker, meta in pairs(Registry.items) do
        if meta and (now - meta.last_used) > max_idle then
            if not picker_in_use(picker) then
                if picker.close then
                    picker:close()
                end
                Registry.items[picker] = nil
            end
        end
    end
end

return Registry
