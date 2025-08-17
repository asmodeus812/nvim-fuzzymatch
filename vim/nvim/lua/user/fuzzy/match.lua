local EMPTY_TABLE = {}

local results_buffer = { {}, {}, {} }
local current_offset = 1
local list_chunks = {}
local timer_id = nil

local M = {
    state = {
        list = nil,
        pattern = '',
        callback = nil,
        results = { {}, {}, {} },
    },
    step = 50000,
    limit = 4096,
    timer = 100,
}

local function table_resize(tbl, size, default)
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

local function clean_context(context)
    timer_id = nil
    current_offset = 1

    context.state.list = nil
    context.state.pattern = ''
    context.state.callback = nil
end

local function initialize_chunks(context)
    local current_size = 0
    if context.state.list and #context.state.list > 0 then
        local async_range = current_offset + context.step
        local iteration_limit = async_range - 1
        if #context.state.list < async_range then
            iteration_limit = #context.state.list
            local new_size = iteration_limit - current_offset
            list_chunks = table_resize(list_chunks, new_size)
        end
        for i = current_offset, iteration_limit do
            list_chunks[current_size + 1] = context.state.list[i]
            current_size = current_size + 1
        end
        current_offset = current_offset + context.step
    end
    return current_size
end

local function convert_positions(positions)
    if not positions or #positions == 0 then
        return {}
    end
    -- table.sort(positions)

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

local function match_worker()
    local results
    local context = M
    local offset = current_offset
    if context.state.callback then
        if initialize_chunks(context) == 0 then
            pcall(vim.fn.timer_stop, timer_id)
            invoke_callback(
                context.state.callback,
                nil -- terminate stream
            )
            clean_context(context)
            return
        end
        results = time_execution(vim.fn.matchfuzzypos, list_chunks, context.state.pattern)
    else
        results = time_execution(vim.fn.matchfuzzypos, context.state.list, context.state.pattern)
        clean_context(context)
    end

    local strings = results[1]
    local positions = results[2]
    local scores = results[3]

    assert(#list_chunks >= #strings)
    if strings and #strings > 0 then
        for idx, pos in ipairs(positions) do
            positions[idx] = convert_positions(pos)
        end
        if offset == 1 then
            local state = context.state
            state.results[1] = strings
            state.results[2] = positions
            state.results[3] = scores
        else
            local result = time_execution(context.merge_results,
                results_buffer, context.state.results,
                { strings, positions, scores }
            )
            results_buffer = context.state.results
            context.state.results = result
            assert(#result[1] == #result[2])
            assert(#result[2] == #result[3])
        end
        invoke_callback(
            context.state.callback,
            context.state.results
        )
    end

    return context.state.results
end

function M.merge_results(source, left, right)
    local final_size = #left[1] + #right[1]
    for sub_index = 1, 3 do
        table_resize(
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

function M.fuzzy_match(list, pattern, opts)
    if timer_id ~= nil then
        pcall(vim.fn.timer_stop, timer_id)
        clean_context(M)
    end

    if not list or #list == 0 or not pattern or #pattern == 0 then
        return
    end

    opts = opts or {}
    local context = M
    current_offset = 1
    context.state.list = list
    context.state.pattern = pattern
    context.state.callback = opts.callback
    table_resize(list_chunks, M.step, EMPTY_STRING)

    if type(context.state.callback) == "function" then
        timer_id = vim.fn.timer_start(context.timer, match_worker, {
            ["repeat"] = -1,
        })
        return timer_id
    else
        return match_worker()
    end
end

return M
