package.path = package.path
    .. ";./?.lua;./?/init.lua"

local helpers = require("script.test_utils")
helpers.setup_global_state()
helpers.setup_runtime()

require("benchmarks.picker_perf").run()

vim.cmd("qa!")
