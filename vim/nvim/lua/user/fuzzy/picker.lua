local Stream = require("user.fuzzy.stream")
local Select = require("user.fuzzy.select")
local Match = require("user.fuzzy.match")
local utils = require("user.fuzzy.utils")

local Picker = {}
Picker.__index = Picker

function Picker:_close_picker()
    self.select:close()
    self.stream:stop()
    self.match:stop()
end

function Picker:_cancel_prompt()
    return Select.action(Select.close_view, function()
        self.stream:stop()
        self.match:stop()
    end)
end

function Picker:_confirm_prompt()
    return Select.action(Select.select_entry, function(selected)
        vim.print(selected)
        return select[1]
    end)
end

function Picker:_input_prompt()
    return vim.schedule_wrap(function(query, _)
        if query == nil then
            self.seelct:stop()
            self.match:stop()
        elseif self._state.list then
            self.match:match(self._state.list, query, function(matching)
                if not matching then
                    self.select:render(nil, nil)
                else
                    self.select:render(
                        matching[1],
                        matching[2]
                    )
                end
            end)
        end
    end)
end

function Picker:_flush_results()
    return vim.schedule_wrap(utils.debounce_callback(self._options.stream_debounce, function(all, _)
        if all == nil then
            self.select:render(nil, nil)
            self._state.list = self.stream.results
        else
            local query = self.select:query()
            if type(query) == "string" and #query > 0 then
                self.match:match(all, query, function(matching)
                    if matching == nil then
                        self.select:render(nil, nil)
                    else
                        self.select:render(
                            matching[1],
                            matching[2]
                        )
                    end
                end)
            else
                self.select:render(all, nil)
            end
            self._state.list = all
        end
    end))
end

function Picker:run(content, args)
    if type(content) == "function" then
        content = content(args or {})
    end

    if type(content) == "string" then
        if not self._state.list then
            self.stream:start(
                content, args or {},
                self:_flush_results()
            )
        end
    elseif type(content) == "table" then
        self._state.list = content
        self.stream.results = nil
    end
    self.select:open()
end

function Picker.new(opts)
    opts = vim.tbl_deep_extend("force", {
        ephemeral = false,
        match_limit = nil,
        match_timer = 100,
        prompt_debounce = 200,
        prompt_prefix = "> ",
        prompt_query = "",
        stream_debounce = 100,
        stream_type = "lines",
        window_size = 0.15
    }, opts or {})

    local is_lines = opts.stream_type == "lines"
    local self = setmetatable({
        _options = opts, _state = { list = nil },
    }, Picker)

    self.match = Match.new({
        ephemeral = opts.ephemeral,
        timer = opts.match_timer,
        limit = opts.match_limit,
        step = 50000,
    })

    self.stream = Stream.new({
        ephemeral = opts.ephemeral,
        bytes = not is_lines,
        lines = is_lines,
        step = 100000,
    })

    self.select = Select.new({
        ephemeral = opts.ephemeral,
        window_ratio = opts.window_size,
        prompt_query = opts.prompt_query,
        prompt_prefix = opts.prompt_prefix,
        prompt_debounce = opts.prompt_debounce,
        prompt_cancel = self:_cancel_prompt(),
        prompt_confirm = self:_confirm_prompt(),
        prompt_input = self:_input_prompt(),
        prompt_list = true,
        resume_view = true,
    })

    return self
end

return Picker
