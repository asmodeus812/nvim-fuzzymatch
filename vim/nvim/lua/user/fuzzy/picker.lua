local Stream = require("user.fuzzy.stream")
local Select = require("user.fuzzy.select")
local Match = require("user.fuzzy.match")
local utils = require("user.fuzzy.utils")

local Picker = {}
Picker.__index = Picker

function Picker:_clear_content(content, args)
    self._state.content = assert(content)
    self._state.args = assert(args)

    self.stream:_destroy_results()
    self.match:_destroy_results()
end

function Picker:_close_picker()
    self.select:close()
    self.stream:stop()
    self.match:stop()
end

function Picker:_cancel_prompt()
    return Select.action(Select.close_view, function()
        self.stream:stop()
        self.match:stop()
        self.match:_destroy_results()
    end)
end

function Picker:_confirm_prompt()
    return Select.action(Select.select_entry, function(selected)
        vim.print(selected)
        return selected
    end)
end

function Picker:_input_prompt()
    -- @Note: the query received on the callback will always represent the latest input entered in the select,
    -- thus any intermediate characters can/will be skipped if within the debounce time, this implies that data
    -- will be "missing" but for the purposes of this use case we are okay with not always receiving the latest
    -- query state from the select
    return vim.schedule_wrap(utils.debounce_callback(self._options.prompt_debounce, function(query)
        if query == nil then
            self.select:stop()
            self.match:stop()
            self.match:_destroy_results()
        elseif self.stream.results then
            if type(query) == "string" and #query > 0 then
                self.match:match(self.stream.results, query, function(matching)
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
                self.select:render(
                    self.stream.results,
                    nil -- nohighlights
                )
                self.select:render(nil, nil)
            end
        end
    end))
end

function Picker:_flush_results()
    -- @Note: the stream is sending references to the results in the callback, therefore debouncing the
    -- callback has to be done with care, due to the fact that the callback receives two arguments (total, buffer) the total can be used
    -- with debounce since it is only accumulating results in to the same table reference, however the buffer table reference is re-used on
    -- every call, overriding the content of the buffer, debouncing that means we will never receive the current actual buffer contents being
    -- received on stdout/stderr
    return vim.schedule_wrap(utils.debounce_callback(0, function(_, all)
        if all == nil then
            self.select:render(nil, nil)
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
                self.select:render(nil, nil)
            end
        end
    end))
end

function Picker:close()
    self:_close_picker()
end

function Picker:open(content, args)
    args = args or {}
    if type(content) == "function" then
        content = content()
    end

    -- before each run make sure to clean all the current context, that has accumulated during the last run, note that we are not
    -- hard destroying anything, just making sure that used up resources are back into circulation for future re-use, and that is
    -- only done in the cases where the new open args are different from the last ones that was used to run the picker with
    if self._state.content ~= content then
        self:_clear_content(content, args)
    elseif self._state.args ~= args then
        local current_args = vim.fn.copy(self._state_args or {})
        local new_args = vim.fn.copy(args or {})
        ---@diagnostic disable-next-line: param-type-mismatch
        table.sort(new_args)
        ---@diagnostic disable-next-line: param-type-mismatch
        table.sort(current_args)
        if not utils.compare_tables(current_args, new_args) then
            self:_clear_content(content, args)
        end
    end

    if type(content) == "string" then
        -- when a string is provided we assume that a command line utilty or executable must be executed and obtain the stdout/stderr of
        -- it
        if not self.stream.results then
            assert(#content > 0 and vim.fn.executable(content) == 1)
            self.stream:start(
                content, args or {},
                self:_flush_results()
            )
        end
    elseif type(content) == "table" and #content > 0 then
        -- when a table is provided a table of strings is required, otherwise the behavior is undefined, for the underlyting
        -- matcher.
        assert(content and #content > 0 and type(content[1]) == "string")
        self.stream.results = content
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
        stream_debounce = 50,
        stream_type = "lines",
        window_size = 0.15
    }, opts or {})

    local is_lines = opts.stream_type == "lines"
    local self = setmetatable({
        match = nil,
        stream = nil,
        select = nil,
        _options = opts,
        _state = {
            content = nil,
            args = nil,
        },
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
        prompt_cancel = self:_cancel_prompt(),
        prompt_confirm = self:_confirm_prompt(),
        prompt_input = self:_input_prompt(),
        prompt_list = true,
        resume_view = true,
        providers = {
            icon_provider = true,
            status_provider = false,
        }
    })

    return self
end

return Picker
