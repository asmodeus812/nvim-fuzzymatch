package.path = package.path
    .. ";./?.lua;./?/init.lua"

local helpers = require("script.test_utils")
helpers.setup_global_state()
helpers.setup_runtime()

local tests = require("tests").tests
local failures = {}

for _, test in ipairs(tests) do
    local name = test and test.name or "anonymous"
    helpers.start_spec(name)
    vim.api.nvim_echo({ { "spec: " .. name .. "\n", "MoreMsg" } }, false, {})
    local ok, err = pcall(function()
        if test and test.run then
            test.run()
        else
            error("test missing run()")
        end
    end)
    local spec_total = helpers.finish_spec(name)
    vim.api.nvim_echo({
        { string.format("spec: %s (cases: %d)\n", name, spec_total), "MoreMsg" },
    }, false, {})
    if not ok then
        table.insert(failures, { name = name, err = err })
    end
end

if #failures > 0 then
    for _, item in ipairs(failures) do
        vim.api.nvim_err_writeln("[FAIL] " .. item.name .. ": " .. tostring(item.err))
    end
    vim.cmd.cq()
else
    vim.api.nvim_echo({
        { string.format("All tests passed (total cases: %d)\n", helpers.total_cases()), "MoreMsg" },
    }, false, {})
    vim.cmd("qa!")
end
