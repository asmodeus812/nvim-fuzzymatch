local utils = require("fuzzy.utils")

--- @class Match
--- @field public results (string[]|integer[]|number[])[] The results of the matching operation, containing matched strings, their positions, and scores.
--- @field private list string[] The list of strings to match against.
--- @field private pattern string The pattern to match.
--- @field private callback fun(results: (string[]|integer[]|number[])[]|nil) The callback function to be called on each match iteration.
--- @field private transform? table A table of transformation rules to apply to the strings before matching, if items are of type table, using matchfuzzypos options, key or/and text_cb
--- @field private _options MatchOptions The options for the matcher.
--- @field private _state table The internal state of the matcher, used for managing the matching process.
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

function Match:_populate_chunks()
    local size = 0
    if assert(self.list) and #self.list > 0 then
        -- each time we are called we fill the chunks with the next step of items from the source list, the chynks aer always
        -- the  same size except for the last one which can be smaller.
        local iteration_range = self._state.offset + self._options.step
        local iteration_limit = iteration_range - 1
        local destination = self._state.chunks
        if #self.list < iteration_range then
            -- in case the list has less items than the current step we create a smaller tail chunk to avoid re-sizing the
            -- chunks, instead we use a smaller tail table which accepts the very last items, if the new size is invalid
            -- return false to signal there is nothing more to process for the matching process
            iteration_limit = #self.list
            local new_size = iteration_limit - self._state.offset
            if not new_size or new_size <= 0 then return false end

            -- quickly pull a table from the pool, we are going to use for the tail eleements, to avoid nuking the size of
            -- the main chunk table re-used for the bulk of the results and matches
            self._state.tail = utils.obtain_table(new_size)
            utils.resize_table(self._state.tail, new_size)
            destination = self._state.tail
        end
        -- ensure that the iteration range is within the iteration range for each step, the range has to be valid and only
        -- within the absolute size of the list passed for filtering
        assert(self._state.offset < iteration_limit and iteration_limit <= #self.list)

        -- move the items into the destination chunk, either the regular chunks or the tail chunk, based on the left over size
        -- of the total items in the list, and update the offsets accordingly
        for i = self._state.offset, iteration_limit do
            destination[size + 1] = self.list[i]
            size = size + 1
        end

        -- update the offset to pick the next chunk of items from the source list, each match step processes a given amount of
        -- items from the list as defined by the step option
        self._state.offset = iteration_range
    end
    return size and size > 0
end

function Match:_stop_processing()
    if self._state.timer ~= nil then
        -- kill the timer if it is still active, this will stop any further processing, we do not wait for the current processing to finish,
        -- since it is expected that the callback will handle nil results as a signal that processing was aborted
        if vim.loop.is_closing(self._state.timer) == false then
            pcall(vim.loop.stop, self._state.timer)
        end
        self._state.timer = nil
    end
end

function Match:_destroy_context()
    if self.results then
        -- destroy the results, returning them to the pool, this is only done to forcefully free internally used tables, and reuse them
        -- again, the results consists of 3 sublists, strings, positions, and scores, each we return to the pool, each we fill with a
        -- default value to avoid holding references to old data
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
            -- attach the sublist to the pool before returning it, at this point the results subset tables can be safely returned to the pool and be reused
            assert(value ~= nil)
            utils.attach_table(value)
            utils.return_table(value)
        end
        self.results = nil
    end
end

function Match:_clean_context()
    if self._state.buffer then
        -- clear the buffer to avoid holding references to old data, do return them to the pool, from where we can easily pull them back
        for i, value in ipairs(self._state.buffer) do
            if i == 1 then
                utils.fill_table(
                    value,
                    utils.EMPTY_STRING
                )
            elseif i == 2 then
                utils.fill_table(
                    value,
                    utils.EMPTY_TABLE
                )
            else
                utils.fill_table(
                    value, 0
                )
            end
            utils.return_table(value)
        end
        self._state.buffer = nil
    end

    if self._state.chunks then
        -- clear the chunks to avoid holding references to old data, do return them to the pool, from where we can easily pull them back
        utils.fill_table(
            self._state.chunks,
            utils.EMPTY_STRING
        )
        -- destroy the chunks, returning them to the pool, the chunks will always point to a single list which was originally obtained from
        -- the pool
        utils.return_table(self._state.chunks)
        self._state.chunks = nil
    end

    if self._state.tail then
        -- clear the tail to avoid holding references to old data, however we do return it to the pool since it can be easily pulled back
        -- from the pool
        utils.fill_table(
            self._state.tail,
            utils.EMPTY_STRING
        )
        utils.return_table(self._state.tail)
        self._state.tail = nil
    end

    if self._state.accum then
        -- accumulated results are detached from the pool to avoid returning them, they will be returned back to the user, if ephemeral is set
        -- however the results will be returned back to the pool, on the next match:start
        for _, value in ipairs(self._state.accum) do
            utils.detach_table(value)
        end
        -- move the accumulated results to the public results field, signaling that the matching is done and can be used by the user, user
        -- is responsible for not holding references to this field moer than needed since it might contain huge amounts of data
        self.results = self._state.accum
        self._state.accum = nil
    end

    -- reset the rest of the state
    self.list = nil
    self.pattern = nil
    self.callback = nil
    self.transform = nil
end

function Match:_bind_method(method)
    return function(...)
        return method(self, ...)
    end
end

function Match:_match_worker()
    -- verify we are still running and there is something to process
    if not self:running() or not self:_populate_chunks() then
        local callback = self.callback
        -- stop processing, make sure to clean up the timer, and context
        self:stop()
        -- call the callback one final time with nil to signal we are done
        utils.safe_call(callback, nil)
        return
    end

    -- the current items will be either the tail (last chunk) or the regular chunks, this is done for efficiency, all chunks are of
    -- equal size, only the tail can be smaller and usually it is.
    local items = self._state.tail or self._state.chunks
    local args = { items, self.pattern, self.transform }
    local results = utils.time_execution(vim.fn.matchfuzzypos, unpack(args))

    local strings = results[1]
    local positions = results[2]
    local scores = results[3]

    -- there should never be more results than items processed
    assert(#self._state.chunks >= #strings)
    if strings and #strings > 0 then
        -- when there are results convert positions to offset continuous pairs
        for idx, pos in ipairs(positions) do
            positions[idx] = convert_positions(pos)
        end
        if #self._state.accum == 0 then
            -- the very first time we just move the results into the accumulator, no need to merge
            self._state.accum[1] = utils.attach_table(strings)
            self._state.accum[2] = utils.attach_table(positions)
            self._state.accum[3] = utils.attach_table(scores)
        else
            -- merge the new results with the accumulated ones, using double buffering to avoid allocations
            local result = utils.time_execution(Match.merge,
                self._state.buffer, self._state.accum,
                { strings, positions, scores }
            )
            -- here is where we swap buffers, the buffer now becomes the accumulator and the accumulator becomes the buffer, accum always holds the latest accumulated results however
            self._state.buffer = self._state.accum
            self._state.accum = result
            assert(#result[1] == #result[2])
            assert(#result[2] == #result[3])
        end

        -- call the callback with the current accumulated results, note that we do that only when there are any new results, at
        -- all, otherwise there is no need to execute it as there are no new matches to be added to the final accumulated result
        utils.safe_call(
            self.callback,
            self._state.accum
        )
    end
end

--- Checks if there is an ongoing matching operation, i.e., if the timer is active, which indicates that matching is in progress.
--- @return boolean True if a matching operation is currently running, false otherwise.
function Match:running()
    return self._state.timer ~= nil
end

--- Waits for the matching operation to complete or until the specified timeout is reached, and returns the results.
--- @param timeout? integer The maximum time in milliseconds to wait for the matching operation to complete. If not provided, uses the timeout from options or a default maximum timeout.
--- @return (string[]|integer[]|number[])[]|nil The results of the matching operation, or nil if the operation timed out.
function Match:wait(timeout)
    local done = vim.wait(timeout or self._options.timeout or utils.MAX_TIMEOUT, function()
        return self._state.results ~= nil
    end, nil, true)

    if not done then
        self:stop()
    end
    return self.results
end

-- Destroys the matcher and any pending state that is currently being allocated into the matcher, note that this is done automatically
-- for ephemeral matcher when a new matching is started the resources for the previous ones are invalidated
function Match:destroy()
    self:_destroy_context()
end

--- Stops any ongoing match operation, cleans up the context, and if ephemeral option is set destroys the context as well This will make
--- sure that any ongoing processing is aborted, the callback will be called one final time with nil to signal
function Match:stop()
    self:_stop_processing()
    self:_clean_context()
end

--- Starts a new match operation on the given list with the specified pattern and callback
--- @param list? string[] The list of strings to match against.
--- @param pattern? string The pattern to match.
--- @param callback? fun(results: (string[]|integer[]|number[])[]|nil) The callback function to be called on each match iteration.
--- @param transform? table A table of transformation rules to apply to the strings before matching, if items are of type table, using matchfuzzypos options, key or/and text_cb
function Match:match(list, pattern, callback, transform)
    vim.validate({
        list = { list, "table" },
        pattern = { pattern, "string" },
        callback = { callback, {  "function" }, true },
        transform = { transform, { "table", "nil" }, true },
    })
    -- each time we start a new match we make sure to stop any ongoing processing and clean up the context, any old state will be lost,
    -- depending on the ephemeral option more aggressive clean up might be done
    if self:running() then
        self:stop()
        if self._options.ephemeral == true then
            self:destroy()
        end
    end

    -- initialize the core matching context
    self.list = assert(list)
    self.pattern = assert(pattern)
    self.callback = assert(callback)
    self.transform = transform or nil

    self._state.offset = 0

    if not self._state.accum then
        -- prepare accumulator for results, these will hold the results across multiple matches, together with the buffer we are
        -- using a double buffering strategy, not using pool since this table is just a holder for the 3 sub-tables which
        -- actually contain the matching results, positions and scoress
        self._state.accum = {}
    end

    if not self._state.chunks then
        -- chunks are reused to avoid frequent allocations, they represent the part of the whole source list currently being processed
        -- for matches
        local size = self._options.step
        self._state.chunks = utils.obtain_table(size)
        utils.resize_table(
            self._state.chunks,
            self._options.step,
            utils.EMPTY_STRING
        )
    end

    if not self._state.buffer then
        -- prepare buffer for storing intermediate results, the very first time buffer will be come the accumulator, we can try to pull at
        -- most #list size tables from the pool, since in the worst case we might have to hold all items, if it turns out we do not need
        -- that much, the merge will resize the source table anyway
        self._state.buffer = {
            utils.obtain_table(#list),
            utils.obtain_table(#list),
            utils.obtain_table(#list),
        }
    end

    -- initialize timer, start processing immediately, we need to schedule the callback to avoid issues with uv loop, being executed outside
    -- the main loop in nvim
    self._state.timer = vim.loop.new_timer()
    self._state.timer:start(0,
        self._options.timer,
        vim.schedule_wrap(self:_bind_method(
            Match._match_worker
        ))
    )
end

-- Merges two sorted lists into a single sorted list, both input lists must be sorted in descending order by score, in the first place,
-- then they are merged into the source list also sorted in descending order
--- @param source (string[]|integer[]|number[])[]
function Match.merge(source, left, right)
    vim.validate({
        source = { source, "table" },
        left = { left, "table" },
        right = { right, "table" },
    })
    -- ensure source has enough capacity to hold all items from left and right
    local final_size = #left[1] + #right[1]
    for sub_index = 1, 3 do
        utils.resize_table(
            source[sub_index],
            final_size
        )
    end

    -- keep pointers to left, right, and results lists
    local left_pointer = 1
    local right_pointer = 1
    local results_pointer = 1

    -- merge until we reach the end of either left or right
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

--- @class MatchOptions
--- @field ephemeral? boolean If true, the matcher will clean up its context after each match operation, making it suitable for one-off matches. Default is true.
--- @field step? integer The number of items to process in each iteration. Default is 50000.
--- @field limit? integer The maximum number of results to keep. Default is 4096.
--- @field timer? integer The interval in milliseconds between each match iteration. Default is 100.
--- @field timeout? integer The maximum time in milliseconds to wait for the matching operation to complete when using the wait method. Default is 5000.

--- Creates a new Match instance with the specified options, or default options if none are provided.
--- @param opts? MatchOptions
--- @return Match
function Match.new(opts)
    opts = opts or {}
    vim.validate({
        ephemeral = { opts.ephemeral, "boolean", true },
        step = { opts.step, "number", true },
        limit = { opts.limit, "number", true },
        timer = { opts.timer, "number", true },
        timeout = { opts.timeout, "number", true },
    })
    opts = vim.tbl_deep_extend("force", {
        ephemeral = true,
        step = 50000,
        limit = 4096,
        timer = 100,
    }, opts)

    local self = setmetatable({
        list = nil,
        results = nil,
        pattern = nil,
        callback = nil,
        transform = nil,
        _options = opts,
        _state = {
            timer = nil,
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
