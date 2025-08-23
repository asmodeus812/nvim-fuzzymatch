local Stream = require("user.fuzzy.stream")
local Match = require("user.fuzzy.match")
local Select = require("user.fuzzy.prompt")
local utils = require("user.fuzzy.utils")

-- local list = vim.fn.systemlist("find .")
local list = nil

local stream = assert(Stream.new({
    ephemeral = true,
}))

local matcher = assert(Match.new({
    ephemeral = true,
}))

local select;
select = assert(Select.new({
    ephemeral = false,
    open_view = false,
    prompt_query = "",
    resume_view = true,
    prompt_list = true,
    prompt_cancel = Select.action(Select.close_view, function()
        vim.print("closed")
        matcher:stop()
        stream:stop()
    end),
    prompt_confirm = Select.action(Select.select_entry, function(selected)
        vim.print(selected)
        return select[1]
    end),
    prompt_input = vim.schedule_wrap(function(query, _)
        if not query then
            vim.print("interrupt")
            matcher:stop()
            stream:stop()
        else
            matcher:match(list, query, function(results)
                if not results then
                    vim.print({ "matcher", #matcher.results[1] })
                    select:render(nil, nil)
                else
                    select:render(results[1], results[2])
                end
            end)
        end
    end)
}))

vim.keymap.set("n", "gz", function()
    if not list then
        stream:start("find", {}, vim.schedule_wrap(function(total, buffer)
            if not total then
                vim.print({ "stream", #stream.results })
                select:render(nil, nil)
            else
                list = total
                local query = select:query()
                if query and #query > 0 then
                    matcher:match(list, query, function(r)
                        if not r then
                            select:render(nil, nil)
                        else
                            select:render(r[1], r[2])
                        end
                    end)
                else
                    select:render(total, nil)
                end
            end
        end))
    end
    select:open()
end)

-- local ss = 0
-- list = utils.resize_table({}, 100000, utils.EMPTY_STRING)
-- select = assert(Select.new({
-- ephemeral = false,
-- open_view = false,
-- prompt_query = "",
-- resume_view = true,
-- prompt_list = true,
-- prompt_cancel = Select.action(Select.close_view, function()
-- vim.print("closed: " .. #list)
-- matcher:stop()
-- end),
-- prompt_confirm = Select.action(Select.select_entry, function(selected)
-- vim.print(selected)
-- return select[1]
-- end),
-- prompt_input = function(query, _)
-- if not query then
-- vim.print("interrupt")
-- stream:stop()
-- else
-- stream:start("rg", { "--vimgrep", query }, vim.schedule_wrap(function(chunks, size)
-- for i = 1, size, 1 do
-- list[ss + 1] = chunks[i]
-- ss = ss + 1
-- end
-- vim.print(size)

-- if not chunks and size == 0 then
-- select:render(nil, nil)
-- ss = 0
-- else
-- select:render(list, nil)
-- end
-- end))
-- end
-- end
-- }))

-- vim.keymap.set("n", "gz", function()
-- select:open()
-- end)
