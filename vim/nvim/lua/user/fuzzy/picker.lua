local Stream = require("user.fuzzy.stream")
local Select = require("user.fuzzy.select")
local Match = require("user.fuzzy.match")
local utils = require("user.fuzzy.utils")

--- @class Picker
--- @field match Match
--- @field stream Stream
--- @field select Select
--- @field _options PickerOptions
--- @field _state table
local Picker = {}
Picker.__index = Picker

function Picker:_clear_content(content, args)
    -- replace the current content and args with the new ones, this implies that any previous runs are not going to be valid
    -- anymore, that is why we also destroy the current results in the stream and matchers below
    self._state.content = assert(content)
    self._state.args = assert(args)

    -- forcefully clear the results, returning them to the pool for re-use, this is important to avoid huge performance penalties
    -- and possible memory fragmentation
    self.stream:_destroy_results()
    self.match:_destroy_results()
end

function Picker:_close_picker()
    -- close the select view, and stop any running stream or matching operations, but destroying the internal state is not
    -- necessary, as we would like to be able to re-open the picker and continue where we left off.
    self.select:close()
    self.stream:stop()
    self.match:stop()
end

function Picker:_cancel_prompt()
    return Select.action(Select.close_view, function()
        -- only stop the stream and matching when the view is closed, otherwise the user might want to re-open the view and continue where they left off, destroying their internal results  is not going to allow resuming the view, next time they are started the results tables are going to be reused, see _clear_content
        self.stream:stop()
        self.match:stop()
    end)
end

function Picker:_confirm_prompt()
    return Select.action(Select.select_entry, function(selected)
        -- transform the selected entry before returning it, for example certain lines might contain line and column information along with the file path
        vim.print(selected)
        return selected
    end)
end

function Picker:_input_prompt()
    -- debounce the user input to avoid flooding the matching and rendering logic with too many updates, especially when dealing
    -- with large result sets or fast typers
    return utils.debounce_callback(self._options.prompt_debounce, function(query)
        if query == nil then
            -- the input has been interrupted, so we need to stop everything
            self.select:close()
            self.match:stop()
        elseif self._options.interactive then
            -- in interactive mode we need to restart the stream with the new query, so that the command can produce results based on the query, for example when using find -name <query>
            local content = self._state.content
            assert(type(content) ~= "table")

            -- when interactive is a string it means that the string is an argument placeholder, that should be replaced
            -- with the query, otherwise the query is just prepended to the args list
            local arg = self._options.interactive
            local args_copy = vim.fn.copy(self._state.args)
            if type(arg) == "string" then
                for _idx, _arg in ipairs(args_copy or {}) do
                    if _arg == arg then
                        args_copy[_idx] = query
                        break
                    end
                    assert(_idx < #args_copy)
                end
            else
                table.insert(args_copy or {}, 1, query)
            end

            if type(query) == "string" and #query > 0 then
                -- when there is a query we need to match against it, so we restart the stream with the new args, and match
                -- the results as they come in
                self.stream:start(self._state.content, {
                    args = args_copy,
                    callback = function(_, all)
                        if not all then
                            -- notify that the streaming is done, so the renderer can update the status
                            self.select:render(nil, nil)
                        else
                            -- match the new results against the query and render them, which would update the list view
                            self.match:match(all, query, function(matching)
                                if matching == nil then
                                    -- notify that there matching has finished, so the renderer can update the status
                                    self.select:render(nil, nil)
                                else
                                    -- render the new matching results, which would update the list view
                                    self.select:render(
                                        matching[1],
                                        matching[2]
                                    )
                                end
                            end)
                        end
                    end
                })
            else
                -- when there is no query we just render no results, there is nothing yet running, the stream is not
                -- started on empty query in interactive mode
                self.select:render({}, {})
            end
        elseif self.stream.results then
            if type(query) == "string" and #query > 0 then
                -- when there is a query we need to match against it, note we are using the current stream.results, which hold the current most up to date results produced by the stream / command
                self.match:match(self.stream.results, query, function(matching)
                    if matching == nil then
                        -- notify that there matching has finished, so the renderer can update the status
                        self.select:render(nil, nil)
                    else
                        -- render the new matching results, which would update the list view
                        self.select:render(
                            matching[1],
                            matching[2]
                        )
                    end
                end)
            else
                -- just render all the results as they are, when there is no query, nothing can be matched against, so we
                -- dump all the results.
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
    -- no need to debounce here, because the stream is already debounced internally, it is going to be flushed only when the buffer
    -- reaches a limit or all results are alreay in
    return utils.debounce_callback(0, function(_, all)
        if all == nil then
            -- streaming is done, so we need to make sure that the renderer is notified about it
            self.select:render(nil, nil)
        else
            local query = self.select:query()
            if type(query) == "string" and #query > 0 then
                -- when there is a query we need to match against it
                self.match:match(all, query, function(matching)
                    if matching == nil then
                        -- notify that there matching has finished, so the renderer can update the status
                        self.select:render(nil, nil)
                    else
                        -- render the new matching results, which would update the list view
                        self.select:render(
                            matching[1],
                            matching[2]
                        )
                    end
                end)
            else
                -- when there is no query we just render all the results as they are
                self.select:render(all, nil)
                self.select:render(nil, nil)
            end
        end
    end)
end

function Picker:close()
    self:_close_picker()
end

--- @class PickerOpenOptions
--- @field args table arguments to pass to the command or function, default is {}
--- @field interactive boolean|string when set to true the picker will restart the stream with

--- @param content string|function|table the content to use for the picker, can be a command string, a function that produces results, by calling a supplied callback as first argument, or a table of strings
--- @param opts PickerOpenOptions options to configure the picker with
function Picker:open(content, opts)
    opts = opts or {}
    local args = opts.args or {}

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

    -- each time we open we need to reset the interactive mode, as it might be different from the last time, that is only valid for
    -- string executable {cmd} content type.
    self._options.interactive = opts.interactive or false
    self.select:open()

    if type(content) ~= "table" then
        -- when a string or a function is provided the content is expected to be a command that produces output, or a function
        -- that produces output
        if not self.stream.results then
            self.stream:start(
                content, {
                    args = args,
                    callback = self:_flush_results(),
                })
        end
    elseif #content > 0 then
        -- when a table is provided the content is expected to be a list of strings, each string being a separate entry, and in
        -- this mode the interactive option is not supported, as there is no way to passk the query to the command, because
        -- there is no command
        assert(content and #content > 0 and type(content[1]) == "string")
        assert(self._options.interactive == false)
        if not self.stream.results then
            self.select:render(content, nil)
            self.stream.results = content
        end
    end
end

--- @class PickerOptions
--- @inlinedoc
--- @field ephemeral boolean whether the picker should be ephemeral or not, default is false
--- @field match_limit number? optional limit on the number of matches to return, default is
--- @field match_timer number time in milliseconds to wait before returning partial matches, default is 100
--- @field prompt_debounce number time in milliseconds to debounce the prompt input, default is 200
--- @field prompt_prefix string prefix to use for the prompt, default is "> "
--- @field prompt_query string initial query to use for the prompt, default is ""
--- @field stream_type string type of stream to use, either "lines" or "bytes", default is "lines"
--- @field window_size number size of the picker window as a ratio of the screen size, default is 0.15
--- @field resume_view boolean whether to resume the view on close, default is true
--- @field interactive boolean|string when set to true the picker will restart the stream with the query as the first argument, when set to a string the string will be used as a placeholder in the args list to be replaced with the query, default is false

--- @param opts PickerOptions options to configure the picker with
--- @return Picker
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
        resume_view = not opts.ephemeral,
        window_ratio = opts.window_size,
        prompt_query = opts.prompt_query,
        prompt_prefix = opts.prompt_prefix,
        prompt_input = self:_input_prompt(),
        prompt_cancel = self:_cancel_prompt(),
        prompt_confirm = self:_confirm_prompt(),
        prompt_list = true,
        -- TODO: fix this, action is not working at the moment
        -- mappings = {
        -- ["<c-g>"] = opts.interactive and self:_stage_filter()
        -- },
        providers = {
            icon_provider = true,
            status_provider = false,
        }
    })

    if opts.resume_view == true then
        -- ensure that if resume_view is enabled then ephemeral must be false, otherwise the behavior does not make sense, as
        -- there is nothing to resume to when the state is destroyed
        assert(opts.ephemeral == false)
    end
    return self
end

return Picker
