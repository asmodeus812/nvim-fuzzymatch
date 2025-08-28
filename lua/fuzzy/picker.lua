local Stream = require("fuzzy.stream")
local Select = require("fuzzy.select")
local Match = require("fuzzy.match")
local utils = require("fuzzy.utils")

--- @class Picker
--- @field match Match
--- @field stream Stream
--- @field select Select
--- @field _options PickerOptions
--- @field _state table
--- @field _state.stage table
local Picker = {}
Picker.__index = Picker

function Picker:_clear_content(content, args)
    -- replace the current content and args with the new ones, this implies that any previous runs are not going to be valid
    -- anymore, that is why we also destroy the current results in the stream and matchers below
    self._state.content = assert(content)
    self._state.args = assert(args)

    self.match:stop()
    self.stream:stop()

    -- forcefully clear the results, returning them to the pool for re-use, this is important to avoid huge performance penalties
    -- and possible memory fragmentation
    self.stream:_destroy_results()
    self.match:_destroy_results()
end

function Picker:_clear_stage()
    local stage = self._state.stage
    if stage and next(stage) then
        stage.match:stop()

        stage.match:_destroy_results()
        stage.select:_destroy_view()
    end
end

function Picker:_close_picker()
    -- close the select view, and stop any running stream or matching operations, but destroying the internal state is not
    -- necessary, as we would like to be able to re-open the picker and continue where we left off.
    self.select:close()
    self.stream:stop()
    self.match:stop()
end

function Picker:_close_stage()
    local stage = self._state.stage
    if stage and next(stage) then
        stage.select:close()
        stage.match:stop()
    end
end

function Picker:_interactive_args(query)
    local key = self._state.interactive
    local args = vim.fn.copy(self._state.args)
    if type(key) == "string" then
        for _idx, _arg in ipairs(args or {}) do
            if _arg == key then
                args[_idx] = query
                break
            end
            assert(_idx < #args)
        end
    else
        table.insert(args or {}, 1, query)
    end
    return args
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
            self.select:list(nil, nil)
            self.select:close()
            self.match:stop()
        elseif self._state.interactive then
            -- in interactive mode we need to restart the stream with the new query, so that the command can produce results
            -- based on the query, for example when using find -name <query>, we do not perform fuzzy matching on the stream
            -- in interactive mode, this is done on demand in the second stage
            local content = self._state.content
            assert(type(content) ~= "table")

            if type(query) == "string" and #query > 0 then
                self.stream:start(self._state.content, {
                    -- when interactive is a string it means that the string is an argument placeholder, that should be replaced
                    -- with the query, otherwise the query is just prepended to the args list
                    args = self:_interactive_args(query),
                    callback = function(_, all)
                        if not all then
                            -- notify that the streaming is done, so the renderer can update the status, the accumulated
                            -- result here would directly represent the stream contents that have been collected, matching
                            -- is not performed when the picker is interactive mode, the matching will be done in the
                            -- second stage.
                            self.select:list(nil, nil)
                        else
                            self.select:list(
                                all, -- accum results
                                nil, -- nohighlights
                                self._state.display
                            )
                            self.select:list(nil, nil)
                        end
                    end
                })
            else
                -- when there is no query we just render no results, there is nothing yet running, the stream is not
                -- started on empty query in interactive mode
                self.select:list({}, {})
            end
            -- clear the interactive second stage each time a new query arrives the old matches in the second stages would be invalid, the
            -- query would re-start the command with new interactive args which would invalidate the previous results against the stage
            -- might have been matching
            self:_clear_stage()
        elseif self.stream.results then
            -- when there is a query we need to match against it, in this scenario the stream is non-interactive and the output is being
            -- matched or filtered against the current stream results accumulation
            if type(query) == "string" and #query > 0 then
                self.match:match(self.stream.results, query, function(matching)
                    if matching == nil then
                        -- notify that there matching has finished, so the renderer can update the status, also
                        -- check if there was actually nothing matched once the matching has signaled it has
                        -- finished if that is the case clear the selection list
                        if #self.match.results == 0 then
                            self.select:list({}, {})
                        end
                        self.select:list(nil, nil)
                    else
                        -- render the new matching results, which would update the list view
                        self.select:list(
                            matching[1],
                            matching[2],
                            self._state.display
                        )
                    end
                end, self._state.transform)
            else
                -- just render all the results as they are, when there is no query, nothing can be matched against, so we
                -- dump all the results.
                self.select:list(
                    self.stream.results,
                    nil, -- nohighlights
                    self._state.display
                )
                self.select:list(nil, nil)
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
            self.select:list(nil, nil)
        else
            local query = self.select:query()
            if type(query) == "string" and #query > 0 then
                -- when there is a query we need to match against it
                self.match:match(all, query, function(matching)
                    if matching == nil then
                        -- notify that there matching has finished, so the renderer can update the status, also
                        -- check if there was actually nothing matched once the matching has signaled it has
                        -- finished if that is the case clear the selection list from previous matches
                        if #self.match.results == 0 then
                            self.select:list({}, {})
                        end
                        self.select:list(nil, nil)
                    else
                        -- render the new matching results, which would update the list view
                        self.select:list(
                            matching[1],
                            matching[2],
                            self._state.display
                        )
                    end
                end, self._state.transform)
            else
                -- when there is no query yet, we just have to render all the results as they are, empty query means that
                -- we can certainly show all results, that the stream produced so far.
                self.select:list(
                    all, nil,
                    self._state.display
                )
                self.select:list(nil, nil)
            end
            self:_clear_stage()
        end
    end)
end

function Picker:_create_stage()
    self:_clear_stage()

    local function _input_prompt()
        return utils.debounce_callback(self._options.prompt_debounce, function(query)
            local stage = self._state.stage
            if query == nil then
                stage.select:list(nil, nil)
                stage.select:close()
                stage.match:stop()
            elseif self.stream.results then
                if type(query) == "string" and #query > 0 then
                    stage.match:match(self.stream.results, query, function(matching)
                        if matching == nil then
                            -- notify that there matching has finished, so the renderer can update the status, also
                            -- check if there was actually nothing matched once the matching has signaled it has
                            -- finished if that is the case clear the selection list from previous matches
                            if #stage.match.results == 0 then
                                stage.select:list({}, {})
                            end
                            stage.select:list(nil, nil)
                        else
                            stage.select:list(
                                matching[1],
                                matching[2],
                                self._state.display
                            )
                        end
                    end, self._state.transform)
                else
                    stage.select:list(
                        stage.stream.results,
                        nil, -- nohighlights
                        self._state.display
                    )
                    stage.select:list(nil, nil)
                end
            end
        end)
    end

    local function _cancel_prompt()
        return Select.action(Select.close_view, function()
            local stage = self._state.stage
            stage.match:stop()
        end)
    end

    local function _confirm_prompt()
        return Select.action(Select.select_entry, function(selected)
            vim.print(selected)
            return selected
        end)
    end

    local opts = self._options
    self._state.stage = {
        select = Select.new({
            ephemeral = opts.ephemeral,
            resume_view = not opts.ephemeral,
            window_ratio = opts.window_size,
            prompt_query = opts.prompt_query,
            prompt_prefix = opts.prompt_prefix,
            prompt_input = _input_prompt(),
            prompt_cancel = _cancel_prompt(),
            prompt_confirm = _confirm_prompt(),
            prompt_list = true,
            providers = {
                icon_provider = true,
                status_provider = false,
            },
            mappings = {
                ["<c-g>"] = function()
                    self:_toggle_stage()
                end
            }
        }),
        match = Match.new({
            ephemeral = opts.ephemeral,
            timer = opts.match_timer,
            limit = opts.match_limit,
            step = opts.match_step,
        })
    }
end

function Picker:_toggle_stage()
    local stage = self._state.stage
    if self.select:isopen() then
        self:_close_picker()
        stage.select:open()

        if stage.select:isempty() and self.stream.results then
            stage.select:list(self.stream.results, nil)
            stage.select:list(nil, nil)
        end
    elseif stage.select:isopen() then
        self:_close_stage()
        self.select:open()
    end
end

function Picker:close()
    self:_close_stage()
    self:_close_picker()
end

--- @class PickerOpenOptions
--- @field args? table arguments to pass to the command or function, default is {}
--- @field display? string|function when the content is table or function that consists of tables, match by this string table field name, or by an item produced by function, the function receives the item currently being tested for matches
--- @field interactive? boolean|string when set to true the picker will restart the stream with the query as the first argument, when set to a string the string will be used as a placeholder in the args list to be replaced with the query, default is false

--- @param content string|function(function(string|table))|table<string|table> the content to use for the picker, can be a command string, a function that produces results, by calling a supplied callback as first argument, or a table. When a function or a table is provided the items produced by the function can be either a string or a table, or when table is supplied it can consists of raw strings or tables, in case a table is provided per entry, a display functiona must be supplied
--- @param opts? PickerOpenOptions options to configure the picker with
function Picker:open(content, opts)
    opts = opts or {}

    -- holds the new updated properties for the select, selector may require update in case the arguments to the open command have
    -- changed compared to last time, a new content source is provided, new arguments or options governing the picker state
    local select_options = {}
    local args = opts.args or {}

    -- before each run make sure to clean all the current context, that has accumulated during the last run, note that we are not
    -- hard destroying anything, just making sure that used up resources are back into circulation for future re-use. The state
    -- can be destroyed if the new content or args are differing from the old ones, which would prompt a new result generation
    if self._state.content ~= content or not utils.compare_tables(self._state.args, args) or not self.select._options.resume_view then
        self:_clear_content(content, args)
    end

    if self._state.display ~= opts.display then
        -- when there is a provided display transformer, executing for each entry, limit the number of rendered entries to a
        -- specific limit or a cap, lines are going to be rendered in groups or batches
        select_options.listing_step = self._options.display_step

        -- update the display transformer, that can either be a string property name or a function, the step above will govern
        -- how many entries are transformed in a batch at a given moment
        if type(opts.display) == "function" then
            self._state.transform = { text_cb = opts.display }
        elseif type(opts.display) == "string" then
            self._state.transform = { key = opts.display }
        end
        self._state.display = opts.display or nil
    end

    if opts.interactive ~= self._state.interactive then
        -- update the interactive state, re-create the second matching stage, along with updating the mappings, otherwise if
        -- the new interactive state is not enabled or `false` we can simply clear old stages if there were any created
        if opts.interactive ~= nil and opts.interactive ~= false then
            self:_create_stage()
            select_options.mappings = {
                ["<c-g>"] = function()
                    self:_toggle_stage()
                end
            }
        else
            self:_clear_stage()
        end
        self._state.interactive = opts.interactive or false
    end

    self.select:open(select_options)

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
    elseif content and #content > 0 then
        -- when a table is provided the content is expected to be a list of strings, each string being a separate entry, and in
        -- this mode the interactive option is not supported, as there is no way to passk the query to the command, because
        -- there is no command
        assert(type(content[1]) == "string"
            or type(content[1]) == "table")
        assert(self._state.interactive == false)

        -- the content is either going to be a table of strings or a table of tables, either way simply display it directly to
        -- the select, as there is no async result loading happening at this moment
        if not self.stream.results then
            self.select:list(
                content, nil,
                self._state.display
            )
            self.select:list(nil, nil)
            self.stream.results = content
        end
    end
end

--- @class PickerOptions
--- @inlinedoc
--- @field ephemeral boolean whether the picker should be ephemeral or not, default is false
--- @field match_limit number? optional limit on the number of matches to return, default is
--- @field match_timer number time in milliseconds to wait before returning partial matches, default is 100
--- @field match_step number the maximum number eleemnts to process in a single batch of fuzzy matching
--- @field prompt_debounce number time in milliseconds to debounce the prompt input, default is 200
--- @field prompt_prefix string prefix to use for the prompt, default is "> "
--- @field prompt_query string initial query to use for the prompt, default is ""
--- @field stream_type string type of stream to use, either "lines" or "bytes", default is "lines"
--- @field stream_step integer the maximum number of elements to accumulate before flushing the stream
--- @field window_size number size of the picker window as a ratio of the screen size, default is 0.15
--- @field resume_view boolean whether to resume the view on close, default is true
--- @field display_step integer the maximum number of elements to accumulate before display the selection matches, that is only relevant when using a display function for the data

--- @param opts? PickerOptions options to configure the picker with
--- @return Picker
function Picker.new(opts)
    opts = vim.tbl_deep_extend("force", {
        ephemeral = false,
        match_limit = nil,
        match_timer = 100,
        match_step = 50000,
        prompt_debounce = 250,
        prompt_prefix = "> ",
        prompt_query = "",
        stream_type = "lines",
        stream_step = 100000,
        window_size = 0.15,
        resume_view = true,
        display_step = 25000,
    }, opts or {})

    local is_lines = opts.stream_type == "lines"
    local self = setmetatable({
        match = nil,
        stream = nil,
        select = nil,
        _options = opts,
        _state = {
            interactive = false,
            transform = nil,
            display = nil,
            content = nil,
            stage = nil,
            args = nil,
        },
    }, Picker)

    self.match = Match.new({
        ephemeral = opts.ephemeral,
        timer = opts.match_timer,
        limit = opts.match_limit,
        step = opts.match_step,
    })

    self.stream = Stream.new({
        ephemeral = opts.ephemeral,
        step = opts.stream_step,
        bytes = not is_lines,
        lines = is_lines,
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
        providers = {
            icon_provider = true,
            status_provider = true,
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
