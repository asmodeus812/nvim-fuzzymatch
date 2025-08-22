local EMTPY_STRING = ""
local table_pool = {
    tables = {},
    used = {},
}

local Match = {}
Match.__index = Match

local function init_pool(size)
    table_pool.tables = {}
    table_pool.used = {}

    for i = 1, size, 1 do
        table.insert(table_pool.tables, i, {})
    end
end

local function pop_table()
    if #table_pool.tables > 0 then
        local tbl = table.remove(table_pool.tables)
        table_pool.used[tbl] = true
        return tbl
    else
        local tbl = {}
        table_pool.used[tbl] = true
        return tbl
    end
end

local function put_table(tbl)
    assert(table_pool.used[tbl])
    table_pool.used[tbl] = nil
    table.insert(table_pool.tables, tbl)
    return tbl
end

local function del_table(tbl)
    assert(table_pool.used[tbl])
    table_pool.used[tbl] = nil
    return tbl
end

local function ins_table(tbl)
    assert(not table_pool.used[tbl])
    table_pool.used[tbl] = true
    return tbl
end

local function resize_table(tbl, size, default)
    if size < 0 then
        return tbl
    end
    if size > #tbl then
        for i = #tbl + 1, size, 1 do
            tbl[i] = default
        end
        return tbl
    elseif size < #tbl then
        for i = size + 1, #tbl, 1 do
            tbl[i] = nil
        end
        return tbl
    elseif size == 0 then
        return {}
    end
    return tbl
end

local function time_execution(func, ...)
    local start_time = vim.loop.hrtime()
    local ok, result = pcall(func, ...)
    local end_time = vim.loop.hrtime()
    local duration_ms = (end_time - start_time) / 1e6

    vim.notify(string.format("Elapsed time: %.3f ms", duration_ms))
    assert(ok, string.format("Execution error: %s", result))
    return result
end

local function invoke_callback(callback, payload)
    if type(callback) == "function" then
        local ok, res = pcall(callback, payload)
        if not ok and res and #res > 0 then
            vim.notify(res, vim.log.levels.WARN)
        else
            return res
        end
    end
    return nil
end

local function convert_positions(positions)
    if not positions or #positions == 0 then
        return {}
    end

    local start_pos = positions[1]
    local last_pos = positions[1]
    local total_len = 1

    local matchpos = {}
    for i = 2, #positions do
        local pos = positions[i]
        if pos == last_pos + 1 then
            total_len = total_len + 1
        else
            matchpos[#matchpos + 1] = start_pos
            matchpos[#matchpos + 1] = total_len
            start_pos = pos
            total_len = 1
        end
        last_pos = pos
    end

    matchpos[#matchpos + 1] = start_pos
    matchpos[#matchpos + 1] = total_len
    return matchpos
end

function Match:_initialize_chunks()
    local size = 0
    if self.list and #self.list > 0 then
        local async_range = self._state.offset + self._options.step
        local iteration_limit = async_range - 1
        if #self.list < async_range then
            iteration_limit = #self.list
            local new_size = iteration_limit - self._state.offset
            self._state.chunks = resize_table(self._state.chunks, new_size)
        end
        for i = self._state.offset, iteration_limit do
            self._state.chunks[size + 1] = self.list[i]
            size = size + 1
        end
        self._state.offset = self._state.offset + self._options.step
    end
    return size
end

function Match:_create_context(exec)
    self._state.offset = 1

    if not self._state.results then
        self._state.results = {}
    end

    if not self._state.chunks then
        self._state.chunks = pop_table()
    end

    if not self._state.buffer then
        self._state.buffer = {
            pop_table(),
            pop_table(),
            pop_table(),
        }
    end

    resize_table(
        self._state.chunks,
        self._options.step,
        EMTPY_STRING
    )

    if exec == true then
        if type(self.callback) == "function" then
            local function worker(timer) self:_match_worker(timer) end
            self._state.timer_id = vim.fn.timer_start(self._options.timer, worker, {
                ["repeat"] = -1,
            })
            return self
        else
            return self:_match_worker(nil)
        end
    end
    return self
end

function Match:_stop_processing()
    if self._state.timer_id ~= nil then
        pcall(vim.fn.timer_stop, self._state.timer_id)
        self._state.timer_id = nil
    end
end

function Match:_destroy_context()
    if self._state.buffer then
        for _, value in ipairs(self._state.buffer) do
            put_table(value)
        end
        self._state.buffer = nil
    end

    if self._state.chunks then
        put_table(self._state.chunks)
        self._state.chunks = nil
    end
end

function Match:_clean_context()
    if self._state.results then
        for _, value in ipairs(self._state.results) do
            del_table(value)
        end
        self.results = self._state.results
        self._state.results = nil
    end
    self.list = nil
    self.pattern = nil
    self.callback = nil
end

function Match:_match_worker(timer)
    local results
    local offset = self._state.offset
    if timer ~= nil then
        if self:_initialize_chunks() == 0 then
            self:stop()
            invoke_callback(
                self.callback,
                nil -- terminate stream
            )
            return
        end
        results = time_execution(vim.fn.matchfuzzypos, self._state.chunks, self.pattern)
    else
        results = time_execution(vim.fn.matchfuzzypos, self.list, self.pattern)
        self:stop()
    end

    local strings = results[1]
    local positions = results[2]
    local scores = results[3]

    assert(#self._state.chunks >= #strings)
    if strings and #strings > 0 then
        for idx, pos in ipairs(positions) do
            positions[idx] = convert_positions(pos)
        end
        if offset == 1 then
            local state = self._state
            state.results[1] = ins_table(strings)
            state.results[2] = ins_table(positions)
            state.results[3] = ins_table(scores)
        else
            local result = time_execution(Match.merge,
                self._state.buffer, self._state.results,
                { strings, positions, scores }
            )
            self._state.buffer = self._state.results
            self._state.results = result
            assert(#result[1] == #result[2])
            assert(#result[2] == #result[3])
        end
        invoke_callback(
            self.callback,
            self._state.results
        )
    end

    return self._state.results
end

function Match:results()
    return self.results
end

function Match:running()
    if self._state.timer_id ~= nil then
        local ok, info = pcall(vim.fn.timer_info, self._state.timer_id)
        return ok and info ~= nil and next(info)
    end
    return false
end

function Match:stop()
    self:_stop_processing()
    self:_clean_context()
    if self._options.ephemeral == true then
        self:_destroy_context()
    end
end

function Match:destroy()
    self:_stop_processing()
    self:_clean_context()
    self:_destroy_context()
end

function Match:match(list, pattern, callback)
    self:stop()

    if not list or #list == 0 or not pattern or #pattern == 0 then
        return
    end

    self.list = list
    self.pattern = pattern
    self.callback = callback

    return self:_create_context(true)
end

function Match.merge(source, left, right)
    local final_size = #left[1] + #right[1]
    for sub_index = 1, 3 do
        resize_table(
            source[sub_index],
            final_size
        )
    end

    local left_pointer = 1
    local right_pointer = 1
    local results_pointer = 1

    while results_pointer <= final_size do
        local left_score = left_pointer <= #left[1] and left[3][left_pointer] or nil
        local right_score = right_pointer <= #right[1] and right[3][right_pointer] or nil

        if left_score ~= nil and (right_score == nil or left_score > right_score) then
            for sub_index = 1, 3 do
                source[sub_index][results_pointer] = left[sub_index][left_pointer]
            end
            left_pointer = left_pointer + 1
        else
            for sub_index = 1, 3 do
                source[sub_index][results_pointer] = right[sub_index][right_pointer]
            end
            right_pointer = right_pointer + 1
        end
        results_pointer = results_pointer + 1
    end

    return source
end

function Match.new(opts)
    opts = vim.tbl_deep_extend("force", {
        ephemeral = true,
        step = 50000,
        limit = 4096,
        timer = 100,
    }, opts or {})

    local self = setmetatable({
        list = nil,
        results = nil,
        pattern = nil,
        callback = nil,
        _options = opts,
        _state = {},
    }, Match)

    return self:_create_context(false)
end

init_pool(16)
return Match
