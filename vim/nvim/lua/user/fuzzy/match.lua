local utils = require("user.fuzzy.utils")

local Match = {}
Match.__index = Match

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
        local range = self._state.offset + self._options.step
        local iteration_limit = range - 1
        local destination = self._state.chunks
        if #self.list < range then
            iteration_limit = #self.list
            local new_size = iteration_limit - self._state.offset
            if not new_size or new_size <= 0 then return false end

            self._state.tail = utils.obtain_table(new_size)
            utils.resize_table(self._state.tail, new_size)
            destination = self._state.tail
        end
        for i = self._state.offset, iteration_limit do
            destination[size + 1] = self.list[i]
            size = size + 1
        end
        self._state.offset = self._state.offset + self._options.step
    end
    return size > 0
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
            utils.return_table(value)
        end
        self._state.buffer = nil
    end

    if self._state.chunks then
        utils.return_table(self._state.chunks)
        self._state.chunks = nil
    end
end

function Match:_destroy_results()
    if self.results then
        for index, value in ipairs(self.results) do
            if index == 1 then
                value = utils.fill_table(
                    value, utils.EMPTY_STRING
                )
            elseif index == 2 then
                value = utils.fill_table(
                    value, utils.EMPTY_TABLE
                )
            else
                value = utils.fill_table(
                    value, 0
                )
            end
            assert(value ~= nil)
            utils.attach_table(value)
            utils.return_table(value)
        end
        self.results = nil
    end
end

function Match:_clean_context()
    if self._state.accum then
        for _, value in ipairs(self._state.accum) do
            utils.detach_table(value)
        end
        self.results = self._state.accum
        self._state.accum = nil
    end

    if self._state.buffer then
        utils.fill_table(
            self._state.buffer[1],
            utils.EMPTY_STRING
        )
    end

    if self._state.chunks then
        utils.fill_table(
            self._state.chunks,
            utils.EMPTY_STRING
        )
    end

    if self._state.tail then
        utils.fill_table(
            self._state.tail,
            utils.EMPTY_STRING
        )
        utils.return_table(self._state.tail)
        self._state.tail = nil
    end

    self.list = nil
    self.pattern = nil
    self.callback = nil
end

function Match:_bind_method(method)
    return function(...)
        return method(self, ...)
    end
end

function Match:_match_worker(timer)
    assert(timer == self._state.timer_id)
    if not self:_initialize_chunks() then
        local callback = self.callback
        self:stop()
        utils.safe_call(callback, nil)
        return
    end

    local items = self._state.tail or self._state.chunks
    local results = utils.time_execution(
        vim.fn.matchfuzzypos, items, self.pattern
    )

    local strings = results[1]
    local positions = results[2]
    local scores = results[3]

    assert(#self._state.chunks >= #strings)
    if strings and #strings > 0 then
        for idx, pos in ipairs(positions) do
            positions[idx] = convert_positions(pos)
        end
        if #self._state.accum == 0 then
            self._state.accum[1] = utils.attach_table(strings)
            self._state.accum[2] = utils.attach_table(positions)
            self._state.accum[3] = utils.attach_table(scores)
        else
            local result = utils.time_execution(Match.merge,
                self._state.buffer, self._state.accum,
                { strings, positions, scores }
            )
            self._state.buffer = self._state.accum
            self._state.accum = result
            assert(#result[1] == #result[2])
            assert(#result[2] == #result[3])
        end
        utils.safe_call(
            self.callback,
            self._state.accum
        )
    else
        utils.safe_call(
            self.callback,
            {
                utils.EMPTY_TABLE,
                utils.EMPTY_TABLE,
                utils.EMPTY_TABLE,
            }
        )
    end
end

function Match:running()
    if self._state.timer_id ~= nil then
        local ok, info = pcall(vim.fn.timer_info, self._state.timer_id)
        return ok and info ~= nil and next(info)
    end
    return false
end

function Match:wait(timeout)
    local done = vim.wait(timeout or self.state._options.timeout or utils.MAX_TIMEOUT, function()
        return self.state.results ~= nil
    end, nil, true)

    if not done then
        self:stop()
    end
    return self.results
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

    self.list = assert(list)
    self.pattern = assert(pattern)
    self.callback = assert(callback)
    if self._options.ephemeral then
        self:_destroy_results()
    else
        self.results = nil
    end

    self._state.offset = 1

    if not self._state.accum then
        self._state.accum = {}
    end

    if not self._state.chunks then
        local size = self._options.step
        self._state.chunks = utils.obtain_table(size)
        utils.resize_table(
            self._state.chunks,
            self._options.step,
            utils.EMPTY_STRING
        )
    end

    if not self._state.buffer then
        self._state.buffer = {
            utils.obtain_table(),
            utils.obtain_table(),
            utils.obtain_table(),
        }
    end

    self._state.timer_id = vim.fn.timer_start(
        self._options.timer,
        self:_bind_method(
            Match._match_worker
        ),
        { ["repeat"] = -1 }
    )
end

function Match.merge(source, left, right)
    local final_size = #left[1] + #right[1]
    for sub_index = 1, 3 do
        utils.resize_table(
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
        _state = {
            timer_id = nil,
            tail = nil,
            offset = 0,
            chunks = nil,
            buffer = nil,
            accum = nil,
        },
    }, Match)

    return self
end

return Match
