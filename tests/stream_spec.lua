local Stream = require("fuzzy.stream")
local helpers = require("script.test_utils")

local M = { name = "stream" }

local function build_large_awk_args(size)
    local query = "kqzv"
    local match_every = 997
    local noise = "abcdefghijlmnoprstuwxy"
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

local function build_exit_before_eof_args()
    return {
        "-c",
        "(sleep 0.05; printf 'ld\\n') & printf 'hello\\nwor'; exit 0",
    }
end

local function run_lines_case()
    local stream = Stream.new({ lines = true, step = 100 })
    helpers.assert_ok(stream:options() ~= nil, "stream options")
    helpers.eq(stream:options().step, 100, "stream options reference")
    local buf_size = 0
    local acc_size = 0
    helpers.assert_ok(vim.fn.executable("awk") == 1, "awk missing")
    stream:start("awk", {
        args = {
            "BEGIN{for(i=1;i<=500;i++) printf \"line-%03d\\n\", i}",
        },
        callback = function(buffer, accum)
            if buffer and accum then
                buf_size = #buffer
                acc_size = #accum
            end
        end,
        onexit = function() end,
    })

    local results = assert(assert(stream:wait(1500)))
    helpers.assert_ok(results ~= nil, "stream nil")
    helpers.assert_ok(type(results) == "table", "results")
    helpers.eq(#results, 500, "results count")
    helpers.eq(results[1], "line-001", "results one")
    helpers.eq(results[2], "line-002", "results two")
    helpers.eq(results[3], "line-003", "results three")
    helpers.eq(results[500], "line-500", "results last")
    helpers.assert_ok(buf_size > 0, "buffer")
    helpers.eq(acc_size, #results, "accum")
    stream:destroy()
end

local function run_transform_case()
    local stream = Stream.new({ lines = true, step = 50 })

    helpers.assert_ok(vim.fn.executable("awk") == 1, "awk missing")
    stream:start("awk", {
        args = {
            "BEGIN{for(i=1;i<=200;i++) printf \"keep-%03d\\n\", i; printf \"drop\\n\"}",
        },
        transform = function(line)
            if line == "drop" then
                return nil
            end
            return line
        end,
        callback = function() end,
    })

    local results = assert(assert(stream:wait(1500)))
    helpers.assert_ok(results ~= nil, "transform nil")
    helpers.assert_ok(type(results) == "table", "transform")
    helpers.eq(#results, 200, "transform count")
    helpers.eq(results[1], "keep-001", "transform keep")
    helpers.eq(results[2], "keep-002", "transform keep two")
    stream:destroy()
end

local function run_bytes_case()
    helpers.assert_ok(vim.fn.executable("printf") == 1, "printf")
    local stream = Stream.new({
        bytes = true,
        lines = false,
        step = 8,
    })
    stream:start("printf", {
        args = { "abcdefghijklmnop" },
        callback = function() end,
    })

    local results = assert(stream:wait(1500))
    helpers.assert_ok(results ~= nil, "bytes nil")
    local joined = table.concat(results or {}, "")
    helpers.eq(joined, "abcdefghijklmnop", "bytes")
    stream:destroy()
end

local function run_trim_results_case()
    local stream = Stream.new({ lines = true, step = 6048 })
    stream:start(function(cb)
        for i = 1, 4 do
            cb(string.format("item-%02d", i))
        end
        cb(nil)
    end, {
        callback = function() end,
    })
    local results = assert(assert(stream:wait(1500)))
    helpers.assert_ok(type(results) == "table", "empty type")
    helpers.eq(results[1], "item-01", "empty one")
    helpers.eq(results[4], "item-04", "empty last")
    helpers.eq(#results, 4, "empty count")
    stream:destroy()
end

local function run_restart_case()
    local stream = Stream.new({
        lines = true,
        step = 50,
        ephemeral = false,
    })

    helpers.assert_ok(vim.fn.executable("awk") == 1, "awk missing")
    stream:start("awk", {
        args = {
            "BEGIN{for(i=1;i<=150;i++) printf \"one-%03d\\n\", i}",
        },
        callback = function() end,
    })
    assert(stream:wait(1500))

    stream:start("awk", {
        args = {
            "BEGIN{for(i=1;i<=100;i++) printf \"two-%03d\\n\", i}",
        },
        callback = function() end,
    })
    helpers.assert_ok(helpers.wait_for(function()
        return not stream:running()
    end, 1500), "restart done")
    local results = assert(stream.results)
    helpers.assert_ok(results ~= nil, "restart nil")
    helpers.assert_ok(type(results) == "table", "restart")
    helpers.eq(#results, 100, "restart count")
    helpers.eq(results[1], "two-001", "restart value")
    stream:destroy()
end

local function run_restart_token_case()
    local Async = require("fuzzy.async")
    local stream = Stream.new({
        lines = true,
        step = 2,
        ephemeral = true,
    })
    local state = { allow_old_finish = false }

    stream:start(function(cb)
        cb("old-1")
        while not state.allow_old_finish do
            Async.yield()
        end
        cb("old-2")
        cb(nil)
    end, {
        callback = function() end,
    })

    helpers.assert_ok(helpers.wait_for(function()
        return stream:running()
    end, 500), "restart token running")

    stream:start(function(cb)
        cb("new-1")
        cb("new-2")
        cb(nil)
    end, {
        callback = function() end,
    })

    state.allow_old_finish = true
    helpers.assert_ok(helpers.wait_for(function()
        return not stream:running()
    end, 1500), "restart token done")

    local results = stream.results or {}
    helpers.eq(#results, 2, "restart token count")
    helpers.eq(results[1], "new-1", "restart token first")
    helpers.eq(results[2], "new-2", "restart token second")
    stream:destroy()
end

local function run_context_case()
    local stream = Stream.new({ lines = true, step = 1 })
    helpers.assert_ok(vim.fn.executable("awk") == 1, "awk missing")
    stream:start("awk", {
        cwd = "/tmp",
        env = { "TEST_ENV=1", "PWD=/tmp" },
        args = {
            "BEGIN{print ENVIRON[\"PWD\"]; print \"TEST_ENV=\" ENVIRON[\"TEST_ENV\"]; for(i=1;i<=300;i++) printf \"ok-%03d\\n\", i}",
        },
        callback = function() end,
    })
    local results = assert(assert(stream:wait(1500)))
    helpers.assert_ok(results ~= nil, "context nil")
    helpers.eq(results[1], "/tmp", "context cwd")
    helpers.eq(results[2], "TEST_ENV=1", "context env")
    helpers.eq(results[3], "ok-001", "context value")
    stream:destroy()
end

local function run_partial_line_case()
    local stream = Stream.new({ lines = true, step = 2 })
    helpers.assert_ok(vim.fn.executable("printf") == 1, "printf missing")
    stream:start("printf", {
        args = { "aaaa_kqzv_bbbb\n" },
        callback = function() end,
    })
    local results = assert(assert(stream:wait(1500)))
    helpers.assert_ok(results ~= nil, "partial line nil")
    helpers.eq(#results, 1, "partial line count")
    helpers.eq(results[1], "aaaa_kqzv_bbbb", "partial line join")
    stream:destroy()
end

local function run_trailing_partial_case()
    local stream = Stream.new({ lines = true, step = 2 })
    helpers.assert_ok(vim.fn.executable("printf") == 1, "printf missing")
    stream:start("printf", {
        args = { "tail_only" },
        callback = function() end,
    })
    local results = assert(assert(stream:wait(1500)))
    helpers.assert_ok(results ~= nil, "trailing partial nil")
    helpers.eq(#results, 1, "trailing partial count")
    helpers.eq(results[1], "tail_only", "trailing partial value")
    stream:destroy()
end

local function run_lines_multi_flush_case()
    local stream = Stream.new({ lines = true, step = 100 })
    local buffers = {}
    local accums = {}
    helpers.assert_ok(vim.fn.executable("awk") == 1, "awk missing")
    stream:start("awk", {
        args = {
            "BEGIN{for(i=1;i<=350;i++) printf \"item-%03d\\n\", i}",
        },
        callback = function(buffer, accum)
            if buffer and accum then
                buffers[#buffers + 1] = #buffer
                accums[#accums + 1] = #accum
            end
        end,
    })
    local results = assert(stream:wait(1500))
    helpers.assert_ok(results ~= nil, "multi flush nil")
    helpers.eq(#results, 350, "multi flush count")
    helpers.eq(buffers, { 100, 100, 100, 50 }, "multi flush buffers")
    helpers.eq(accums, { 100, 200, 300, 350 }, "multi flush accums")
    stream:destroy()
end

local function run_lines_empty_lines_case()
    local stream = Stream.new({ lines = true, step = 100 })
    helpers.assert_ok(vim.fn.executable("awk") == 1, "awk missing")
    stream:start("awk", {
        args = {
            "BEGIN{print \"alpha\"; print \"\"; print \"beta\"; for(i=1;i<=200;i++) printf \"line-%03d\\n\", i}",
        },
        callback = function() end,
    })
    local results = assert(stream:wait(1500))
    helpers.assert_ok(results ~= nil, "empty lines nil")
    helpers.assert_list_contains(results, "alpha", "empty lines alpha")
    helpers.assert_list_contains(results, "beta", "empty lines beta")
    helpers.assert_list_contains(results, "", "empty lines entry")
    helpers.assert_list_contains(results, "line-100", "empty lines middle")
    stream:destroy()
end

local function run_lines_pending_multi_case()
    local stream = Stream.new({ lines = true, step = 100 })
    helpers.assert_ok(vim.fn.executable("awk") == 1, "awk missing")
    stream:start("awk", {
        args = {
            "BEGIN{print \"foobar\"; print \"bazqux\"; for(i=1;i<=100;i++) printf \"line-%03d\\n\", i}",
        },
        callback = function() end,
    })
    local results = assert(stream:wait(1500))
    helpers.assert_ok(results ~= nil, "pending multi nil")
    helpers.assert_ok(#results >= 102, "pending multi count")
    helpers.eq(results[1], "foobar", "pending multi first")
    helpers.eq(results[2], "bazqux", "pending multi second")
    stream:destroy()
end

local function run_bytes_flush_case()
    local stream = Stream.new({ bytes = true, lines = false, step = 16 })
    local buffers = {}
    local accums = {}
    helpers.assert_ok(vim.fn.executable("awk") == 1, "awk missing")
    stream:start("awk", {
        args = {
            "BEGIN{for(i=1;i<=20;i++) printf \"abcd\"}",
        },
        callback = function(buffer, accum)
            if buffer and accum then
                buffers[#buffers + 1] = #buffer
                accums[#accums + 1] = #accum
            end
        end,
    })
    local results = assert(stream:wait(1500))
    helpers.assert_ok(results ~= nil, "bytes flush nil")
    local joined = table.concat(results or {}, "")
    helpers.eq(#joined, 80, "bytes flush count")
    helpers.eq(joined:sub(1, 4), "abcd", "bytes flush prefix")
    helpers.assert_ok(#buffers >= 1, "bytes flush buffers")
    helpers.eq(accums[#accums], #results, "bytes flush accums")
    stream:destroy()
end

local function run_transform_prefix_case()
    local stream = Stream.new({ lines = true, step = 100 })
    helpers.assert_ok(vim.fn.executable("awk") == 1, "awk missing")
    stream:start("awk", {
        args = {
            "BEGIN{for(i=1;i<=300;i++) printf \"line-%03d\\n\", i}",
        },
        transform = function(line)
            return "x:" .. line
        end,
        callback = function() end,
    })
    local results = assert(stream:wait(1500))
    helpers.assert_ok(results ~= nil, "transform prefix nil")
    helpers.eq(results[1], "x:line-001", "transform prefix one")
    helpers.eq(results[2], "x:line-002", "transform prefix two")
    helpers.eq(results[300], "x:line-300", "transform prefix last")
    stream:destroy()
end

local function run_callback_nil_case()
    local stream = Stream.new({ lines = true, step = 100 })
    local saw_nil = false
    helpers.assert_ok(vim.fn.executable("awk") == 1, "awk missing")
    stream:start("awk", {
        args = {
            "BEGIN{for(i=1;i<=200;i++) printf \"line-%03d\\n\", i}",
        },
        callback = function(buffer, accum)
            if buffer == nil and accum == nil then
                saw_nil = true
            end
        end,
    })
    assert(stream:wait(1500))
    helpers.assert_ok(saw_nil, "callback nil")
    stream:destroy()
end

local function run_onexit_success_case()
    local code, msg
    local stream = Stream.new({
        lines = true,
        step = 100,
        onexit = function(exit_code, exit_msg)
            code = exit_code
            msg = exit_msg
        end,
    })
    helpers.assert_ok(vim.fn.executable("awk") == 1, "awk missing")
    stream:start("awk", {
        args = {
            "BEGIN{for(i=1;i<=200;i++) printf \"line-%03d\\n\", i}",
        },
        callback = function() end,
    })
    assert(stream:wait(1500))
    helpers.eq(code, 0, "onexit success code")
    helpers.assert_ok(msg == nil or type(msg) == "number", "onexit success msg")
    stream:destroy()
end

local function run_onexit_error_case()
    local code, msg
    local stream = Stream.new({
        lines = true,
        step = 100,
        onexit = function(exit_code, exit_msg)
            code = exit_code
            msg = exit_msg
        end,
    })
    helpers.assert_ok(vim.fn.executable("false") == 1, "false missing")
    stream:start("false", {
        callback = function() end,
    })
    stream:wait(1500)
    helpers.eq(code, 1, "onexit error code")
    helpers.assert_ok(msg ~= nil, "onexit error msg")
    helpers.eq(stream.results, nil, "onexit error results")
    stream:destroy()
end

local function run_ephemeral_false_case()
    local stream = Stream.new({ lines = true, step = 100, ephemeral = false })
    helpers.assert_ok(vim.fn.executable("awk") == 1, "awk missing")
    stream:start("awk", {
        args = {
            "BEGIN{for(i=1;i<=200;i++) printf \"first-%03d\\n\", i}",
        },
        callback = function() end,
    })
    local results = assert(stream:wait(1500))
    helpers.eq(#results, 200, "ephemeral false first count")
    stream:start("awk", {
        args = {
            "BEGIN{for(i=1;i<=100;i++) printf \"third-%03d\\n\", i}",
        },
        callback = function() end,
    })
    local next_results = assert(stream:wait(1500))
    helpers.eq(#next_results, 200, "ephemeral false second count")
    helpers.eq(next_results[1], "first-001", "ephemeral false second value")
    stream:destroy()
end

local function run_accum_sizes_case()
    local stream = Stream.new({ lines = true, step = 100 })
    local accums = {}
    helpers.assert_ok(vim.fn.executable("awk") == 1, "awk missing")
    stream:start("awk", {
        args = {
            "BEGIN{for(i=1;i<=250;i++) printf \"line-%03d\\n\", i}",
        },
        callback = function(_, accum)
            if accum then
                accums[#accums + 1] = #accum
            end
        end,
    })
    assert(stream:wait(1500))
    helpers.eq(accums, { 100, 200, 250 }, "accum sizes")
    stream:destroy()
end

local function run_command_large_integrity_case()
    local size = 500000
    helpers.assert_ok(vim.fn.executable("awk") == 1, "awk missing")

    for _ = 1, 3 do
        local stream = Stream.new({ lines = true, step = 150000 })
        stream:start("awk", {
            args = build_large_awk_args(size),
            callback = function() end,
        })

        local results = assert(stream:wait(600000))
        helpers.assert_ok(results ~= nil, "large command nil")
        helpers.eq(#results, size, "large command count")
        helpers.assert_ok(results[1] ~= nil, "large command first")
        helpers.assert_ok(results[size] ~= nil, "large command last")
        helpers.assert_ok(results[size]:find("_" .. size), "large command tail marker")
        stream:destroy()
    end
end

local function run_exit_before_eof_case()
    local callback_nil = false
    local exit_code, exit_msg
    local stream = Stream.new({
        lines = true,
        step = 8,
        onexit = function(code, msg)
            exit_code = code
            exit_msg = msg
        end,
    })
    helpers.assert_ok(vim.fn.executable("sh") == 1, "sh missing")
    stream:start("sh", {
        args = build_exit_before_eof_args(),
        callback = function(buffer, accum)
            if buffer == nil and accum == nil then
                callback_nil = true
            end
        end,
    })

    local results = assert(stream:wait(1500))
    helpers.assert_ok(results ~= nil, "exit before eof nil")
    helpers.eq(results, { "hello", "world" }, "exit before eof final results")
    helpers.eq(exit_code, 0, "exit before eof code")
    helpers.assert_ok(exit_msg == nil or type(exit_msg) == "number", "exit before eof msg")
    helpers.assert_ok(callback_nil, "exit before eof callback nil")
    stream:destroy()
end

function M.run()
    helpers.run_test_case("stream_lines", run_lines_case)
    helpers.run_test_case("stream_transform", run_transform_case)
    helpers.run_test_case("stream_bytes", run_bytes_case)
    helpers.run_test_case("stream_trim_results_case", run_trim_results_case)
    helpers.run_test_case("stream_restart", run_restart_case)
    helpers.run_test_case("stream_restart_token", run_restart_token_case)
    helpers.run_test_case("stream_context", run_context_case)
    helpers.run_test_case("stream_partial_line", run_partial_line_case)
    helpers.run_test_case("stream_trailing_partial", run_trailing_partial_case)
    helpers.run_test_case("stream_lines_multi_flush", run_lines_multi_flush_case)
    helpers.run_test_case("stream_lines_empty_lines", run_lines_empty_lines_case)
    helpers.run_test_case("stream_lines_pending_multi", run_lines_pending_multi_case)
    helpers.run_test_case("stream_bytes_flush", run_bytes_flush_case)
    helpers.run_test_case("stream_transform_prefix", run_transform_prefix_case)
    helpers.run_test_case("stream_callback_nil", run_callback_nil_case)
    helpers.run_test_case("stream_onexit_success", run_onexit_success_case)
    helpers.run_test_case("stream_onexit_error", run_onexit_error_case)
    helpers.run_test_case("stream_ephemeral_false", run_ephemeral_false_case)
    helpers.run_test_case("stream_accum_sizes", run_accum_sizes_case)
    helpers.run_test_case("stream_command_large_integrity", run_command_large_integrity_case)
    helpers.run_test_case("stream_exit_before_eof", run_exit_before_eof_case)
end

return M
