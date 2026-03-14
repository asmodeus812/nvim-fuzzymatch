---@diagnostic disable: invisible
local helpers = require("script.test_utils")
local Worker = require("fuzzy.worker")
local Async = require("fuzzy.async")

local M = { name = "worker" }

function M.run()
    helpers.run_test_case("worker_trace_payload", function()
        local prev = Worker.trace
        local events = {}
        local w = Worker.coalesce()
        Worker.new({
            trace = function(kind, data)
                events[#events + 1] = { kind = kind, data = data }
            end,
        })
        w.enqueue(function() end)
        helpers.assert_ok(helpers.wait_for(function()
            for _, item in ipairs(events) do
                if item.kind == "coalesce_enqueue" then
                    return item.data
                        and type(item.data.running) == "boolean"
                        and type(item.data.sealed) == "boolean"
                end
            end
            return false
        end, 1500), "trace payload")
        helpers.assert_ok(helpers.wait_for(function()
            return vim.tbl_contains(
                vim.tbl_map(function(item) return item.kind end, events),
                "coalesce_start"
            )
        end, 1500), "trace start")
        helpers.assert_ok(helpers.wait_for(function()
            return vim.tbl_contains(
                vim.tbl_map(function(item) return item.kind end, events),
                "coalesce_idle"
            )
        end, 1500), "trace idle")
        Worker.trace = prev
    end)

    helpers.run_test_case("worker_coalesce_latest_wins", function()
        local w = Worker.coalesce()
        local calls = {}
        w.enqueue(function() calls[#calls + 1] = "a" end)
        w.enqueue(function() calls[#calls + 1] = "b" end)
        helpers.assert_ok(helpers.wait_for(function()
            return #calls >= 1
        end, 1500), "coalesce ran")
        helpers.eq(#calls, 1, "coalesce drops intermediate")
        helpers.eq(calls[1], "b", "coalesce keeps latest")
    end)

    helpers.run_test_case("worker_coalesce_idle_enqueue", function()
        local prev = Worker.trace
        local calls = {}
        local w = Worker.coalesce()
        local injected = false
        local seen_reschedule = false
        Worker.new({
            trace = function(kind)
                if kind == "coalesce_idle" and not injected then
                    injected = true
                    w.enqueue(function()
                        calls[#calls + 1] = "injected"
                    end)
                end
                if kind == "coalesce_reschedule" then
                    seen_reschedule = true
                end
            end,
        })
        w.enqueue(function() calls[#calls + 1] = "first" end)
        helpers.assert_ok(helpers.wait_for(function()
            return #calls >= 2
        end, 1500), "idle enqueue ran")
        helpers.eq(calls[1], "first", "first ran")
        helpers.eq(calls[2], "injected", "idle enqueue ran last")
        helpers.assert_ok(seen_reschedule, "rescheduled after idle enqueue")
        Worker.trace = prev
    end)

    helpers.run_test_case("worker_coalesce_finalize_waits", function()
        local w = Worker.coalesce()
        local calls = {}
        w.enqueue(function() calls[#calls + 1] = "a" end)
        w.finalize(function() calls[#calls + 1] = "final" end)
        helpers.assert_ok(helpers.wait_for(function()
            return #calls >= 2
        end, 1500), "final ran")
        helpers.eq(calls[1], "a", "final after pending")
        helpers.eq(calls[2], "final", "final last")
    end)

    helpers.run_test_case("worker_coalesce_cancel_runs_callback", function()
        local w = Worker.coalesce()
        local calls = {}
        w.enqueue(function()
            Async.yield()
            calls[#calls + 1] = "a"
        end)
        w.cancel(function() calls[#calls + 1] = "cancel" end)
        helpers.assert_ok(helpers.wait_for(function()
            return vim.tbl_contains(calls, "cancel")
        end, 1500), "cancel callback")
    end)

    helpers.run_test_case("worker_queue_fifo", function()
        local w = Worker.queue()
        local calls = {}
        w.enqueue(function() calls[#calls + 1] = "a" end)
        w.enqueue(function() calls[#calls + 1] = "b" end)
        helpers.assert_ok(helpers.wait_for(function()
            return #calls >= 2
        end, 1500), "queue ran")
        helpers.eq(calls[1], "a", "fifo first")
        helpers.eq(calls[2], "b", "fifo second")
    end)

    helpers.run_test_case("worker_queue_idle_enqueue", function()
        local prev = Worker.trace
        local calls = {}
        local w = Worker.queue()
        local injected = false
        local seen_reschedule = false
        Worker.new({
            trace = function(kind)
                if kind == "queue_idle" and not injected then
                    injected = true
                    w.enqueue(function()
                        calls[#calls + 1] = "injected"
                    end)
                end
                if kind == "queue_reschedule" then
                    seen_reschedule = true
                end
            end,
        })
        w.enqueue(function() calls[#calls + 1] = "first" end)
        helpers.assert_ok(helpers.wait_for(function()
            return #calls >= 2
        end, 1500), "idle enqueue ran")
        helpers.eq(calls[1], "first", "first ran")
        helpers.eq(calls[2], "injected", "idle enqueue ran last")
        helpers.assert_ok(seen_reschedule, "rescheduled after idle enqueue")
        Worker.trace = prev
    end)

    helpers.run_test_case("worker_queue_finalize_waits", function()
        local w = Worker.queue()
        local calls = {}
        w.enqueue(function() calls[#calls + 1] = "a" end)
        w.enqueue(function() calls[#calls + 1] = "b" end)
        w.finalize(function() calls[#calls + 1] = "final" end)
        helpers.assert_ok(helpers.wait_for(function()
            return #calls >= 3
        end, 1500), "final ran")
        helpers.eq(calls[1], "a", "fifo a")
        helpers.eq(calls[2], "b", "fifo b")
        helpers.eq(calls[3], "final", "final last")
    end)

    helpers.run_test_case("worker_queue_cancel_runs_callback", function()
        local w = Worker.queue()
        local calls = {}
        w.enqueue(function()
            Async.yield()
            calls[#calls + 1] = "a"
        end)
        w.cancel(function() calls[#calls + 1] = "cancel" end)
        helpers.assert_ok(helpers.wait_for(function()
            return vim.tbl_contains(calls, "cancel")
        end, 1500), "cancel callback")
    end)
end

return M
