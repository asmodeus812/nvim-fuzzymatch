local Match = require("user.fuzzy.match")
local Select = require("user.fuzzy.prompt")
local list = vim.fn.systemlist("find .")

local matcher = Match.new({
    ephemeral = false,
})
assert(matcher)

local select = Select.new({
    ephemeral = false,
    open_view = false,
    prompt_query = "",
    resume_view = true,
    prompt_list = true,
    prompt_cancel = Select.action(Select.close_view, function()
        vim.print("closed")
        matcher:stop()
    end),
    prompt_confirm = Select.action(Select.select_entry, function(select)
        vim.print(select)
        return select[1]
    end),
    prompt_input = function(query, _, onlist)
        if not query then
            vim.print("interrupt")
            matcher:stop()
        else
            matcher:match(list, query, function(results)
                if not results then
                    onlist(nil, nil)
                else
                    onlist(results[1], results[2])
                end
            end
            )
        end
    end
})

vim.keymap.set("n", "gz", function()
    select:open()
end)
