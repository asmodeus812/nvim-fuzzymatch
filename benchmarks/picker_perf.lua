local helpers = require("script.test_utils")
local Picker = require("fuzzy.picker")

local M = {}

local sizes = {
    25000,
    50000,
    100000,
    500000,
    1000000,
    2000000,
}

local query = "kqzv"
local match_every = 997
local noise = "abcdefghijlmnoprstuwxy"

local function expected_count(size)
    return math.floor(size / match_every)
end

local function now_ms()
    return vim.uv.hrtime() / 1e6
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

local function cancel_and_reopen(picker)
    picker:_cancel_picker()
    picker:open()
end

local function wait_ready(picker, mode)
    if mode == "command" then
        helpers.wait_for_stream(picker, 600000)
    else
        helpers.wait_for_entries(picker)
    end
end

local function run_cycle(picker, size)
    local t0 = now_ms()
    helpers.type_query(picker, query)
    local results = helpers.wait_for_match(picker, 600000)
    local t1 = now_ms()

    local count = results and results[1] and #results[1] or 0
    local target = expected_count(size)
    if count ~= target then
        print(string.format(
            "bench mismatch expected=%d count=%d",
            target, count
        ))
    end
    return t1 - t0, count
end

local function run_reusable_bench(picker, mode, size, runs)
    local output = {}
    wait_ready(picker, mode)

    for _ = 1, runs do
        local ms, count = run_cycle(picker, size)
        output[#output + 1] = {
            size = size,
            expected = expected_count(size),
            count = count,
            ms = ms,
            mode = mode,
        }
        cancel_and_reopen(picker)
        wait_ready(picker, mode)
    end

    return output
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
        print(string.format("bench size=%d", size))

        print("Command entries\n")
        local command_picker = open_picker({
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
        for _, result in ipairs(run_reusable_bench(command_picker, "command", size, 3)) do
            log_result(result, output)
        end
        command_picker:close()
        helpers.reset_state()
        collectgarbage()

        print("String entries\n")
        local string_entries = build_entries(size, "string")
        local string_picker = open_picker({
            content = string_entries,
            preview = false,
            prompt_debounce = 0,
            match_timer = 75,
            match_step = 75000,
            stream_step = 150000,
        })
        for _, result in ipairs(run_reusable_bench(string_picker, "string", size, 3)) do
            log_result(result, output)
        end
        string_picker:close()
        helpers.reset_state()
        string_entries = nil
        collectgarbage()

        print("Object entries (key)\n")
        local object_entries = build_entries(size, "object")
        local object_key_picker = open_picker({
            content = object_entries,
            display = "display",
            preview = false,
            prompt_debounce = 0,
            match_timer = 75,
            match_step = 75000,
            stream_step = 150000,
        })
        for _, result in ipairs(run_reusable_bench(object_key_picker, "object_key", size, 6)) do
            log_result(result, output)
        end
        object_key_picker:close()
        helpers.reset_state()
        collectgarbage()

        print("Object entries (cb)\n")
        local display_cb = function(entry)
            local value = entry.display
            local work = value
            work = work:gsub("[aeiou]", value)
            work = work:reverse()
            work = work:sub(1, 12) .. tostring(1)
            return value
        end
        local object_cb_picker = open_picker({
            content = object_entries,
            display = display_cb,
            preview = false,
            prompt_debounce = 0,
            match_timer = 75,
            match_step = 75000,
            stream_step = 150000,
        })
        for _, result in ipairs(run_reusable_bench(object_cb_picker, "object_cb", size, 6)) do
            log_result(result, output)
        end
        object_cb_picker:close()
        helpers.reset_state()
        object_entries = nil
        collectgarbage()

        print("\n")
    end

    local out_path = "/tmp/fuzzymatch_picker_bench.log"
    vim.fn.writefile(output, out_path)
    print("wrote " .. out_path)
end

return M
