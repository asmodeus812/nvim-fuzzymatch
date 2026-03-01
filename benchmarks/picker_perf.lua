local helpers = require("script.test_utils")
local Picker = require("fuzzy.picker")

local M = {}

local sizes = {
    100000,
    500000,
    1000000,
    2000000,
    5000000,
}

local query = "kqzv"
local match_every = 997
local noise = "abcdefghijlmnoprstuwxy"

local function expected_count(size)
    return math.floor(size / match_every)
end

local function now_ms()
    return vim.loop.hrtime() / 1e6
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

local function run_command_bench(size)
    local picker = open_picker({
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

    helpers.wait_for_stream(picker, 600000)

    local t0 = now_ms()
    helpers.type_query(picker, query)
    local results = helpers.wait_for_match(picker, 600000)
    local t1 = now_ms()

    local count = results and results[1] and #results[1] or 0
    picker:close()
    helpers.reset_state()
    return {
        size = size,
        expected = expected_count(size),
        count = count,
        ms = t1 - t0,
        mode = "command",
    }
end

local function build_entries(size, mode)
    local entries = {}
    if mode == "object" then
        for i = 1, size do
            local line = build_line(i)
            entries[i] = {
                display = line,
                value = line,
            }
        end
    else
        for i = 1, size do
            entries[i] = build_line(i)
        end
    end
    return entries
end

local function run_content_bench(entries, mode)
    local display = mode == "object" and "display" or nil

    local picker = open_picker({
        content = entries,
        display = display,
        preview = false,
        prompt_debounce = 0,
        match_timer = 75,
        match_step = 75000,
        stream_step = 150000,
    })

    local t0 = now_ms()
    helpers.type_query(picker, query)
    local results = helpers.wait_for_match(picker, 600000)
    local t1 = now_ms()

    local count = results and results[1] and #results[1] or 0
    picker:close()
    helpers.reset_state()
    local size = #entries
    return {
        size = size,
        expected = expected_count(size),
        count = count,
        ms = t1 - t0,
        mode = mode,
    }
end

local function log_result(result, sink)
    local line = string.format(
        "%s size=%d expected=%d count=%d ms=%.2f",
        result.mode,
        result.size,
        result.expected,
        result.count,
        result.ms
    )
    print(line)
    if sink then
        sink[#sink + 1] = line
    end
end

function M.run()
    local output = {}
    output[#output + 1] = "picker_perf benchmark"
    output[#output + 1] = "query=" .. query .. " match_every=" .. match_every

    for _, size in ipairs(sizes) do
        log_result(run_command_bench(size), output)
        collectgarbage()

        local string_entries = build_entries(size, "string")
        log_result(run_content_bench(string_entries, "string"), output)
        string_entries = nil
        collectgarbage()

        local object_entries = build_entries(size, "object")
        log_result(run_content_bench(object_entries, "object"), output)
        object_entries = nil
        collectgarbage()
    end

    local out_path = "/tmp/fuzzymatch_picker_bench.log"
    vim.fn.writefile(output, out_path)
    print("wrote " .. out_path)
end

return M
