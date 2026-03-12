local helpers = require("script.test_utils")
local Picker = require("fuzzy.picker")
local Pool = require("fuzzy.pool")
local M = {}

local sizes = {}

local query = "kqzv"
local match_every = 997
local noise = "abcdefghijlmnoprstuwxy"

local function now_ms()
    return vim.loop.hrtime() / 1e6
end

local function build_random_sizes(min_size, max_size, count)
    local out = {}
    for i = 1, count do
        out[i] = math.random(min_size, max_size)
    end
    return out
end

local function log_line(label, values, sink)
    local line = label .. " " .. table.concat(values, " ")
    print(line)
    if sink then
        sink[#sink + 1] = line
    end
end

local function reset_pool()
    if Pool.prune_timer and not vim.uv.is_closing(Pool.prune_timer) then
        Pool.prune_timer:stop()
    end
    Pool.tables = {}
    Pool.used = {}
    Pool.meta = {}
end

local function enable_pool_trace(sink)
    local orig_obtain = Pool.obtain
    local orig_return = Pool._return
    local orig_trace = Pool.trace
    local obtains = {}
    local returns = {}
    local events = {}
    local fresh = 0

    Pool.obtain = function(size)
        if #Pool.tables == 0 then
            fresh = fresh + 1
        end
        local info = debug.getinfo(2, "Sl")
        local key = string.format("%s:%s", info.short_src or "unknown", info.currentline or 0)
        obtains[key] = (obtains[key] or 0) + 1
        return orig_obtain(size)
    end

    Pool._return = function(tbl)
        local info = debug.getinfo(2, "Sl")
        local key = string.format("%s:%s", info.short_src or "unknown", info.currentline or 0)
        returns[key] = (returns[key] or 0) + 1
        return orig_return(tbl)
    end

    Pool.trace = function(event, data)
        local key = string.format(
            "%s requested=%s actual=%s target=%s tables=%s max_tables=%s",
            event,
            tostring(data.requested),
            tostring(data.actual),
            tostring(data.target),
            tostring(data.tables),
            tostring(data.max_tables)
        )
        events[key] = (events[key] or 0) + 1
        if orig_trace then
            orig_trace(event, data)
        end
    end

    local function dump(label, data)
        local keys = {}
        for key, _ in pairs(data) do
            keys[#keys + 1] = key
        end
        table.sort(keys)
        log_line(label, { "count=" .. tostring(#keys) }, sink)
        for _, key in ipairs(keys) do
            log_line("  " .. key, { "hits=" .. tostring(data[key]) }, sink)
        end
    end

    return function()
        log_line("pool_fresh_allocs", { "count=" .. tostring(fresh) }, sink)
        dump("pool_obtain_sites", obtains)
        dump("pool_return_sites", returns)
        dump("pool_events", events)
        Pool.obtain = orig_obtain
        Pool._return = orig_return
        Pool.trace = orig_trace
    end
end

local function build_line(i)
    local base = noise .. noise .. noise
    if i % match_every == 0 then
        if i % 3 == 0 then
            return query .. "_" .. base .. "_" .. i
        elseif i % 3 == 1 then
            return base:sub(1, 12) .. "_" .. query .. "_" .. base:sub(13) .. "_" .. i
        else
            return base:sub(1, 20) .. "_" .. i .. "_" .. query
        end
    end
    return base:sub(1, 20) .. "_" .. i .. "_" .. base:sub(21)
end

local function build_entries(size)
    local entries = {}
    for i = 1, size do
        entries[i] = build_line(i)
    end
    return entries
end

local function build_awk_args(size)
    local program = table.concat({
        "BEGIN{",
        "for(i=1;i<=n;i++){",
        "base=noise noise noise;",
        "if (i%" .. match_every .. "==0){",
        "if (i%3==0) line=pat \"_\" base \"_\" i;",
        "else if (i%3==1) line=substr(base,1,12) \"_\" pat \"_\" substr(base,13) \"_\" i;",
        "else line=substr(base,1,20) \"_\" i \"_\" pat;",
        "} else {",
        "line=substr(base,1,20) \"_\" i \"_\" substr(base,21);",
        "}",
        "print line;",
        "}",
        "}",
    })
    return {
        "-v", "n=" .. size,
        "-v", "pat=" .. query,
        "-v", "noise=" .. noise,
        program,
    }
end

local function open_picker(opts)
    local picker = Picker.new(opts)
    picker:open()
    return picker
end

local function wait_ready(picker, mode)
    if mode == "command" then
        helpers.wait_for_stream(picker, 600000)
    else
        helpers.wait_for_entries(picker, 600000)
    end
end

local function run_query(picker, size)
    local t0 = now_ms()
    helpers.type_query(picker, query)
    local results = helpers.wait_for_match(picker, 600000)
    local t1 = now_ms()
    local count = results and results[1] and #results[1] or 0
    return t1 - t0, count
end

local function close_picker(picker)
    local t0 = now_ms()
    picker:close()
    helpers.wait_for_picker_closed(picker, 600000)
    local t1 = now_ms()
    return t1 - t0
end

local function run_picker_cycles(mode, size, runs, sink)
    local picker
    if mode == "command" then
        picker = open_picker({
            content = "awk",
            context = {
                args = build_awk_args(size),
            },
            preview = false,
            prompt_debounce = 0,
            match_timer = 75,
            match_step = 75000,
            stream_step = 150000,
        })
    else
        local entries = build_entries(size)
        picker = open_picker({
            content = entries,
            preview = false,
            prompt_debounce = 0,
            match_timer = 75,
            match_step = 75000,
            stream_step = 150000,
        })
    end

    wait_ready(picker, mode)
    for run = 1, runs do
        local t_query, count = run_query(picker, size)
        local t_close = close_picker(picker)
        local t_open = now_ms()
        picker:open()
        wait_ready(picker, mode)
        local t_ready = now_ms() - t_open
        log_line("cycle", {
            "mode=" .. mode,
            "size=" .. size,
            "run=" .. run,
            string.format("query_ms=%.2f", t_query),
            string.format("close_ms=%.2f", t_close),
            string.format("open_ready_ms=%.2f", t_ready),
            "matches=" .. count,
            "pool_tables=" .. tostring(#Pool.tables),
        }, sink)
    end
    picker:close()
    helpers.reset_state()
    collectgarbage()
end

function M.run()
    local output = {}
    output[#output + 1] = "pool_perf benchmark"
    output[#output + 1] = "query=" .. query .. " match_every=" .. match_every
    reset_pool()
    output[#output + 1] = "pool_start tables=" .. tostring(#Pool.tables)

    math.randomseed(os.time())
    sizes = build_random_sizes(Pool.prime_min, Pool.prime_max, 16)
    local trace_done = enable_pool_trace(output)
    for _, size in ipairs(sizes) do
        log_line("bench", { "size=" .. size }, output)
        local runs = math.random(1, 6)
        run_picker_cycles("command", size, runs, output)
        run_picker_cycles("list", size, runs, output)
    end
    trace_done()

    local out_path = "/tmp/fuzzymatch_pool_bench.log"
    vim.fn.writefile(output, out_path)
    print("wrote " .. out_path)
end

return M
