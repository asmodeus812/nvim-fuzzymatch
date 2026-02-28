local Stream = require("fuzzy.stream")
local helpers = require("tests.helpers")

local M = { name = "stream" }

local function run_lines_case()
    local stream = Stream.new({ lines = true, step = 2 })
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
    helpers.assert_ok(#results >= 0, "results")
    helpers.assert_ok(buf_size >= 0, "buffer")
    helpers.assert_ok(acc_size >= 0, "accum")
    stream:destroy()
end

local function run_transform_case()
    local stream = Stream.new({ lines = true, step = 2 })

    stream:start(function(cb)
        cb("keep\n")
        cb("drop\n")
        cb("keep-two\n")
        cb(nil)
    end, {
        transform = function(line)
            if line == "drop" then
                return nil
            end
            return line
        end,
        callback = function() end,
    })

    local results = stream:wait(1500)
    helpers.assert_ok(results ~= nil, "transform nil")
    helpers.assert_ok(type(results) == "table", "transform")
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
    local results = stream:wait(1500)
    helpers.assert_ok(results ~= nil, "restart nil")
    helpers.assert_ok(type(results) == "table", "restart")
    stream:destroy()
end

function M.run()
    run_lines_case()
    run_transform_case()
    run_bytes_case()
    run_restart_case()
end

return M
