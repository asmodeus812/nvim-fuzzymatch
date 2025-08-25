local Picker = require("user.fuzzy.picker")
local picker = Picker.new()

vim.keymap.set("n", "gz", function()
    picker:open("find", { vim.fn.getcwd(), "-type", "f" })
    -- picker:run(vim.fn.systemlist("find ."))
end)
