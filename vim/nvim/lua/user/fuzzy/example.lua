local Picker = require("user.fuzzy.picker")
local picker = Picker.new()

vim.keymap.set("n", "gz", function()
    picker:run("find", { ".", "-type", "f" })
    -- picker:run(vim.fn.systemlist("find ."))
end)
