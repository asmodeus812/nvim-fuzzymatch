local Stream = require("fuzzy.stream")
local helpers = require("script.test_utils")

local M = { name = "stream" }

local function run_lines_case()
    local stream = Stream.new({ lines = true, step = 2 })
    helpers.assert_ok(stream:options() ~= nil, "stream options")
    helpers.eq(stream:options().step, 2, "stream options reference")
    local buf_size = 0
    local acc_size = 0
    stream:start(function(cb)
        cb("one\n")
        cb("two\n")
        cb("three\n")
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
    helpers.eq(#results, 3, "results count")
    helpers.eq(results[1], "one\n", "results one")
    helpers.eq(results[2], "two\n", "results two")
    helpers.eq(results[3], "three\n", "results three")
    helpers.assert_ok(buf_size > 0, "buffer")
    helpers.eq(acc_size, #results, "accum")
    stream:destroy()
end

local function run_transform_case()
    local stream = Stream.new({ lines = true, step = 2 })

    stream:start(function(cb)
        cb("keep\n")
        cb("keep-two\n")
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
    helpers.eq(#results, 2, "transform count")
    helpers.eq(results[1], "keep\n", "transform keep")
    helpers.eq(results[2], "keep-two\n", "transform keep two")
    stream:destroy()
end

local function run_bytes_case()
    helpers.assert_ok(vim.fn.executable("printf") == 1, "printf")
    local stream = Stream.new({
        bytes = true,
        lines = false,
        step = 3,
    })
    stream:start("printf", {
        args = { "abcd" },
        callback = function() end,
    })

    local results = stream:wait(1500)
    helpers.assert_ok(results ~= nil, "bytes nil")
    local joined = table.concat(results or {}, "")
    helpers.eq(joined, "abcd", "bytes")
    stream:destroy()
end

local function run_restart_case()
    local stream = Stream.new({
        lines = true,
        step = 1,
        ephemeral = false,
    })

    stream:start(function(cb)
        cb("one\n")
        cb(nil)
    end, {
        callback = function() end,
    })
    stream:wait(1500)

    stream:start(function(cb)
        cb("two\n")
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
    helpers.eq(#results, 1, "restart count")
    helpers.eq(results[1], "two\n", "restart value")
    stream:destroy()
end

local function run_context_case()
    local stream = Stream.new({ lines = true, step = 1 })
    local got_cwd
    local got_env
    stream:start(function(cb, _, cwd, env)
        got_cwd = cwd
        got_env = env
        cb("ok\n")
        cb(nil)
    end, {
        cwd = "/tmp",
        env = { "TEST_ENV=1" },
        callback = function() end,
    })
    local results = stream:wait(1500)
    helpers.assert_ok(results ~= nil, "context nil")
    helpers.eq(#results, 1, "context count")
    helpers.eq(results[1], "ok\n", "context value")
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

function M.run()
    helpers.run_test_case("stream_lines", run_lines_case)
    helpers.run_test_case("stream_transform", run_transform_case)
    helpers.run_test_case("stream_bytes", run_bytes_case)
    helpers.run_test_case("stream_restart", run_restart_case)
    helpers.run_test_case("stream_context", run_context_case)
    helpers.run_test_case("stream_partial_line", run_partial_line_case)
    helpers.run_test_case("stream_trailing_partial", run_trailing_partial_case)
end

return M
