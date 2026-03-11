local Stream = require("fuzzy.stream")
local helpers = require("script.test_utils")

local M = { name = "stream" }

local function run_lines_case()
    local stream = Stream.new({ lines = true, step = 100 })
    helpers.assert_ok(stream:options() ~= nil, "stream options")
    helpers.eq(stream:options().step, 100, "stream options reference")
    local buf_size = 0
    local acc_size = 0
    stream:start(function(cb)
        for i = 1, 500 do
            cb(string.format("line-%03d\n", i))
        end
        cb(nil)
    end, {
        callback = function(buffer, accum)
            if buffer and accum then
                buf_size = #buffer
                acc_size = #accum
            end
        end,
        onexit = function() end,
    })

    local results = stream:wait(1500)
    helpers.assert_ok(results ~= nil, "stream nil")
    helpers.assert_ok(type(results) == "table", "results")
    helpers.eq(#results, 500, "results count")
    helpers.eq(results[1], "line-001\n", "results one")
    helpers.eq(results[2], "line-002\n", "results two")
    helpers.eq(results[3], "line-003\n", "results three")
    helpers.eq(results[500], "line-500\n", "results last")
    helpers.assert_ok(buf_size > 0, "buffer")
    helpers.eq(acc_size, #results, "accum")
    stream:destroy()
end

local function run_transform_case()
    local stream = Stream.new({ lines = true, step = 50 })

    stream:start(function(cb)
        for i = 1, 200 do
            cb(string.format("keep-%03d\n", i))
        end
        cb("drop\n")
        cb(nil)
    end, {
        transform = function(line)
            if line == "drop\n" then
                return nil
            end
            return line
        end,
        callback = function() end,
    })

    local results = stream:wait(1500)
    helpers.assert_ok(results ~= nil, "transform nil")
    helpers.assert_ok(type(results) == "table", "transform")
    helpers.eq(#results, 200, "transform count")
    helpers.eq(results[1], "keep-001\n", "transform keep")
    helpers.eq(results[2], "keep-002\n", "transform keep two")
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

    local results = stream:wait(1500)
    helpers.assert_ok(results ~= nil, "bytes nil")
    local joined = table.concat(results or {}, "")
    helpers.eq(joined, "abcdefghijklmnop", "bytes")
    stream:destroy()
end

local function run_restart_case()
    local stream = Stream.new({
        lines = true,
        step = 50,
        ephemeral = false,
    })

    stream:start(function(cb)
        for i = 1, 150 do
            cb(string.format("one-%03d\n", i))
        end
        cb(nil)
    end, {
        callback = function() end,
    })
    stream:wait(1500)

    stream:start(function(cb)
        for i = 1, 100 do
            cb(string.format("two-%03d\n", i))
        end
        cb(nil)
    end, {
        callback = function() end,
    })
    helpers.assert_ok(helpers.wait_for(function()
        return not stream:running()
    end, 1500), "restart done")
    local results = stream.results
    helpers.assert_ok(results ~= nil, "restart nil")
    helpers.assert_ok(type(results) == "table", "restart")
    helpers.eq(#results, 100, "restart count")
    helpers.eq(results[1], "two-001\n", "restart value")
    stream:destroy()
end

local function run_context_case()
    local stream = Stream.new({ lines = true, step = 1 })
    local got_cwd
    local got_env
    stream:start(function(cb, _, cwd, env)
        got_cwd = cwd
        got_env = env
        for i = 1, 300 do
            cb(string.format("ok-%03d\n", i))
        end
        cb(nil)
    end, {
        cwd = "/tmp",
        env = { "TEST_ENV=1" },
        callback = function() end,
    })
    local results = stream:wait(1500)
    helpers.assert_ok(results ~= nil, "context nil")
    helpers.eq(#results, 300, "context count")
    helpers.eq(results[1], "ok-001\n", "context value")
    helpers.eq(got_cwd, "/tmp", "context cwd")
    helpers.assert_ok(type(got_env) == "table", "context env")
    stream:destroy()
end

local function run_partial_line_case()
    local stream = Stream.new({ lines = true, step = 2 })
    stream:start(function(cb)
        stream:_handle_in(nil, "aaaa_kq")
        stream:_handle_in(nil, "zv_bbbb\n")
        cb(nil)
    end, {
        callback = function() end,
    })
    local results = stream:wait(1500)
    helpers.assert_ok(results ~= nil, "partial line nil")
    helpers.eq(#results, 1, "partial line count")
    helpers.eq(results[1], "aaaa_kqzv_bbbb", "partial line join")
    stream:destroy()
end

local function run_trailing_partial_case()
    local stream = Stream.new({ lines = true, step = 2 })
    stream:start(function(cb)
        stream:_handle_in(nil, "tail_only")
        cb(nil)
    end, {
        callback = function() end,
    })
    local results = stream:wait(1500)
    helpers.assert_ok(results ~= nil, "trailing partial nil")
    helpers.eq(#results, 1, "trailing partial count")
    helpers.eq(results[1], "tail_only", "trailing partial value")
    stream:destroy()
end

local function run_lines_multi_flush_case()
    local stream = Stream.new({ lines = true, step = 100 })
    local buffers = {}
    local accums = {}
    stream:start(function(cb)
        for i = 1, 350 do
            cb(string.format("item-%03d\n", i))
        end
        cb(nil)
    end, {
        callback = function(buffer, accum)
            if buffer and accum then
                buffers[#buffers + 1] = #buffer
                accums[#accums + 1] = #accum
            end
        end,
    })
    local results = stream:wait(1500)
    helpers.assert_ok(results ~= nil, "multi flush nil")
    helpers.eq(#results, 350, "multi flush count")
    helpers.eq(buffers, { 100, 100, 100, 50 }, "multi flush buffers")
    helpers.eq(accums, { 100, 200, 300, 350 }, "multi flush accums")
    stream:destroy()
end

local function run_lines_empty_lines_case()
    local stream = Stream.new({ lines = true, step = 100 })
    stream:start(function(cb)
        local payload = { "alpha\n\nbeta\n" }
        for i = 1, 200 do
            payload[#payload + 1] = string.format("line-%03d\n", i)
        end
        stream:_handle_in(nil, table.concat(payload))
        cb(nil)
    end, {
        callback = function() end,
    })
    local results = stream:wait(1500)
    helpers.assert_ok(results ~= nil, "empty lines nil")
    helpers.assert_list_contains(results, "alpha", "empty lines alpha")
    helpers.assert_list_contains(results, "beta", "empty lines beta")
    helpers.assert_list_contains(results, "", "empty lines entry")
    helpers.assert_list_contains(results, "line-100", "empty lines middle")
    stream:destroy()
end

local function run_lines_pending_multi_case()
    local stream = Stream.new({ lines = true, step = 100 })
    stream:start(function(cb)
        local chunks = { "foo", "bar\nbaz", "qux\n" }
        for i = 1, 100 do
            chunks[#chunks + 1] = string.format("line-%03d\n", i)
        end
        for _, chunk in ipairs(chunks) do
            stream:_handle_in(nil, chunk)
        end
        cb(nil)
    end, {
        callback = function() end,
    })
    local results = stream:wait(1500)
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
    stream:start(function(cb)
        for i = 1, 20 do
            stream:_handle_in(nil, "abcd")
        end
        cb(nil)
    end, {
        callback = function(buffer, accum)
            if buffer and accum then
                buffers[#buffers + 1] = #buffer
                accums[#accums + 1] = #accum
            end
        end,
    })
    local results = stream:wait(1500)
    helpers.assert_ok(results ~= nil, "bytes flush nil")
    helpers.eq(#results, 20, "bytes flush count")
    helpers.assert_ok(#buffers >= 2, "bytes flush buffers")
    helpers.eq(accums[#accums], 20, "bytes flush accums")
    stream:destroy()
end

local function run_transform_prefix_case()
    local stream = Stream.new({ lines = true, step = 100 })
    stream:start(function(cb)
        for i = 1, 300 do
            stream:_handle_in(nil, string.format("line-%03d\n", i))
        end
        cb(nil)
    end, {
        transform = function(line)
            return "x:" .. line
        end,
        callback = function() end,
    })
    local results = stream:wait(1500)
    helpers.assert_ok(results ~= nil, "transform prefix nil")
    helpers.eq(results[1], "x:line-001", "transform prefix one")
    helpers.eq(results[2], "x:line-002", "transform prefix two")
    helpers.eq(results[300], "x:line-300", "transform prefix last")
    stream:destroy()
end

local function run_callback_nil_case()
    local stream = Stream.new({ lines = true, step = 100 })
    local saw_nil = false
    stream:start(function(cb)
        for i = 1, 200 do
            cb(string.format("line-%03d\n", i))
        end
        cb(nil)
    end, {
        callback = function(buffer, accum)
            if buffer == nil and accum == nil then
                saw_nil = true
            end
        end,
    })
    stream:wait(1500)
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
    stream:start(function(cb)
        for i = 1, 200 do
            cb(string.format("line-%03d\n", i))
        end
        cb(nil)
    end, {
        callback = function() end,
    })
    stream:wait(1500)
    helpers.eq(code, nil, "onexit success code")
    helpers.eq(msg, nil, "onexit success msg")
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
    helpers.assert_ok(vim.fn.executable("sh") == 1, "sh missing")
    stream:start("sh", {
        args = { "-c", "exit 1" },
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
    stream:start(function(cb)
        for i = 1, 200 do
            cb(string.format("first-%03d\n", i))
        end
        cb(nil)
    end, {
        callback = function() end,
    })
    local results = stream:wait(1500)
    helpers.eq(#results, 200, "ephemeral false first count")
    stream:start(function(cb)
        for i = 1, 100 do
            cb(string.format("third-%03d\n", i))
        end
        cb(nil)
    end, {
        callback = function() end,
    })
    local next_results = stream:wait(1500)
    helpers.eq(#next_results, 200, "ephemeral false second count")
    helpers.eq(next_results[1], "first-001\n", "ephemeral false second value")
    stream:destroy()
end

local function run_accum_sizes_case()
    local stream = Stream.new({ lines = true, step = 100 })
    local accums = {}
    stream:start(function(cb)
        for i = 1, 250 do
            cb(string.format("line-%03d\n", i))
        end
        cb(nil)
    end, {
        callback = function(_, accum)
            if accum then
                accums[#accums + 1] = #accum
            end
        end,
    })
    stream:wait(1500)
    helpers.eq(accums, { 100, 200, 250 }, "accum sizes")
    stream:destroy()
end

function M.run()
    helpers.run_test_case("stream_lines", run_lines_case)
    helpers.run_test_case("stream_transform", run_transform_case)
    helpers.run_test_case("stream_bytes", run_bytes_case)
    helpers.run_test_case("stream_restart", run_restart_case)
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
end

return M
