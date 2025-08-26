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
    end)
end

function Picker:_confirm_prompt()
    return Select.action(Select.select_entry, function(selected)
        vim.print(selected)
        return selected
    end)
end

-- function Picker:_stage_filter()
-- end

function Picker:_input_prompt()
    return utils.debounce_callback(self._options.prompt_debounce, function(query)
        if query == nil then
            self.select:stop()
            self.match:stop()
        elseif self._options.interactive then
            local content = self._state.content
            assert(type(content) == "string")

            local args_copy = vim.fn.copy(self._state.args)
            table.insert(args_copy or {}, 1, query)
            if type(query) == "string" and #query > 0 then
                self.stream:start(self._state.content, args_copy, function(_, all)
                    if not all then
                        self.select:render(nil, nil)
                    else
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
                    end
                end)
            else
                self.select:render({}, {})
            end
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
    end)
end

function Picker:_flush_results()
    return utils.debounce_callback(0, function(_, all)
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
    end)
end

function Picker:close()
    self:_close_picker()
end

function Picker:open(content, opts)
    opts = opts or {}
    local args = opts.args or {}
    if type(content) == "function" then
        content = content()
    end

    -- before each run make sure to clean all the current context, that has accumulated during the last run, note that we are not
    -- hard destroying anything, just making sure that used up resources are back into circulation for future re-use, and that is
    -- only done in the cases where the new open args are different from the last ones that was used to run the picker with
    if self._state.content ~= content then
        self:_clear_content(content, args)
    elseif self._state.args ~= args then
        if not utils.compare_tables(self._state.args, args) then
            self:_clear_content(content, args)
        end
    elseif not self.select._options.resume_view then
        self:_clear_content(content, args)
    end

    self._options.interactive = opts.interactive or false
    self.select:open()

    if type(content) == "string" then
        -- when a string is provided we assume that a command line utilty or executable must be executed and obtain the stdout/stderr of
        -- it
        if not self.stream.results then
            assert(#content > 0 and vim.fn.executable(content) == 1)
            self.stream:start(
                content, args,
                self:_flush_results()
            )
        end
    elseif type(content) == "table" and #content > 0 then
        -- when a table is provided a table of strings is required, otherwise the behavior is undefined, for the underlyting
        -- matcher.
        assert(content and #content > 0 and type(content[1]) == "string")
        assert(self._options.interactive == false)
        if not self.stream.results then
            self.select:render(content, nil)
            self.stream.results = content
        end
    end
end

function Picker.new(opts)
    opts = vim.tbl_deep_extend("force", {
        ephemeral = false,
        match_limit = nil,
        match_timer = 100,
        prompt_debounce = 200,
        prompt_prefix = "> ",
        prompt_query = "",
        stream_type = "lines",
        window_size = 0.15,
        resume_view = true,
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
        resume_view = opts.resume_view,
        window_ratio = opts.window_size,
        prompt_query = opts.prompt_query,
        prompt_prefix = opts.prompt_prefix,
        prompt_input = self:_input_prompt(),
        prompt_cancel = self:_cancel_prompt(),
        prompt_confirm = self:_confirm_prompt(),
        prompt_list = true,
        -- mappings = {
        -- ["<c-g>"] = opts.interactive and self:_stage_filter()
        -- },
        providers = {
            icon_provider = true,
            status_provider = false,
        }
    })

    if opts.resume_view == true then
        assert(opts.ephemeral == false)
    end
    return self
end

return Picker
