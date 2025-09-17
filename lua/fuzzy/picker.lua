local Stream = require("fuzzy.stream")
local Select = require("fuzzy.select")
local Match = require("fuzzy.match")

local utils = require("fuzzy.utils")

--- @class Picker
--- @field private select Select
--- @field private stream Stream
--- @field private match Match
--- @field private _options PickerOptions
--- @field private _state table
--- @field private _state.context table
--- @field private _state.match Match
--- @field private _state.select Select
--- @field private _state.display function|string|nil
--- @field private _state.content string|function|table
--- @field private _state.staging boolean
--- @field private _state.stage? table|nil
--- @field private _state.stage.select Select
--- @field private _state.stage.match Match
local Picker = {}
Picker.__index = Picker

function Picker:_close_picker()
    self.match:stop()
    self.stream:stop()
    self.select:close()
end

function Picker:_hide_picker()
    self.match:stop()
    self.stream:stop()
    self.select:hide()
end

function Picker:_close_stage()
    local stage = self._state.stage
    if stage and next(stage) then
        stage.match:stop()
        stage.select:close()
    end
end

function Picker:_hide_stage(clear)
    local stage = self._state.stage
    if stage and next(stage) then
        stage.match:stop()
        stage.select:hide()
        if clear == true then
            stage.select:clear()
        end
    end
end

function Picker:_interactive_args(query)
    local command_args = vim.fn.copy(self._state.context.args)
    if type(self._state.context.interactive) == "string" then
        for indx, argument in ipairs(command_args or {}) do
            if argument == self._state.context.interactive then
                command_args[indx] = query
                break
            end
            assert(indx < #command_args)
        end
    elseif type(self._state.context.interactive) == "number" then
        table.insert(assert(command_args), self._state.context.interactive, query)
    else
        table.insert(assert(command_args), query)
    end
    return command_args
end

function Picker:_confirm_prompt()
    return Select.action(Select.default_select, function(e)
        vim.print(e)
        return false
    end)
end

function Picker:_cancel_prompt()
    return Select.action(Select.close_view, function()
        self:_close_stage()
        self:_close_picker()
    end)
end

function Picker:_hide_prompt()
    return Select.action(Select.close_view, function()
        self:_hide_stage()
        self:_hide_picker()
    end)
end

function Picker:_input_prompt()
    -- debounce the user input to avoid flooding the matching and rendering logic with too many updates, especially when dealing
    -- with large result sets or fast typers
    return utils.debounce_callback(self._options.prompt_debounce, function(query)
        if query == nil then
            self:_close_stage()
            self:_close_picker()
        elseif self:_is_interactive() then
            -- in interactive mode we need to restart the stream with the new query, so that the command can produce results
            -- based on the query, for example when using find -name <query>, we do not perform fuzzy matching on the stream
            -- in interactive mode, this is done on demand in the second stage
            local content = self._state.content
            assert(type(content) ~= "table")

            if type(query) == "string" and #query > 0 then
                -- when interactive string it means that the string is an argument placeholder, that should be replaced
                -- with the query, inside the arguments, otherwise the query is just appended to the args list as last
                -- argument
                self.stream:start(self._state.content, {
                    transform = self._state.context.map,
                    args = self:_interactive_args(query),
                    cwd = self._state.context.cwd,
                    env = self._state.context.env,
                    callback = function(_, all)
                        if all == nil then
                            -- notify that the streaming is done, so the renderer can update the status,
                            if not self.stream.results or #self.stream.results == 0 then
                                self.select:list(
                                    utils.EMPTY_TABLE,
                                    utils.EMPTY_TABLE
                                )
                                self.select:status("0/0")
                            end
                            self.select:list(nil, nil)
                        else
                            self.select:list(all, nil)
                            self.select:status(string.format(
                                "%d/%d", #all, #all
                            ))
                        end
                    end
                })
            else
                -- when there is no query we just render no results, there is nothing yet running, the stream is not
                -- started or if it was we have to ensure that no running stream is left in the background
                if self.stream:running() then
                    self.stream:stop()
                end
                self.select:list(
                    utils.EMPTY_TABLE,
                    utils.EMPTY_TABLE
                )
                self.select:list(nil, nil)
                self.select:status("0/0")
            end
            -- hide & clear the interactive second stage each time a new query arrives the old matches in the second stages would be
            -- invalid, the query would re-start the command with new interactive args which would invalidate the previous results inside
            -- the interactive stage, that might have been matched
            self:_hide_stage(true)
        elseif not self.stream:running() then
            -- when there is a query we need to match against it, in this scenario the picker is non-interactive, there are
            -- two options, either it was configured to use a stream or a user provided table of entries - strings, or other
            -- tables
            local data = assert(self.stream.results or self._state.content)
            if #data > 0 and type(query) == "string" and #query > 0 then
                self.match:match(data, query, function(matching)
                    if matching == nil then
                        -- notify that there matching has finished, so the renderer can update the status, also
                        -- check if there was actually nothing matched once the matching has signaled it has
                        -- finished if that is the case clear the selection list
                        if not self.match.results or #self.match.results == 0 or #self.match.results[1] == 0 then
                            self.select:list(
                                utils.EMPTY_TABLE,
                                utils.EMPTY_TABLE
                            )
                            self.select:status("0/0")
                        end
                        self.select:list(nil, nil)
                    else
                        -- render the new matching results, which would update the list view
                        self.select:list(
                            matching[1],
                            matching[2]
                        )
                        self.select:status(string.format(
                            "%d/%d", #matching[1], #data
                        ))
                    end
                end, self._state.match)
            else
                -- just render all the results as they are, when there is no query, nothing can be matched against, so we
                -- dump all the results into the list
                self.select:list(data, nil)
                self.select:list(nil, nil)
                self.select:status(string.format(
                    "%d/%d", #data, #data
                ))
            end
        end
    end)
end

function Picker:_flush_results()
    -- no need to debounce much here, however there might be cases where the stream buffer fills up too quickly if the step is small or if
    -- the executable is way too fast, debouncing the stream flush can still be useful, to avoid re-starting the matcher too often
    return utils.debounce_callback(self._options.stream_debounce, function(_, all)
        if all == nil then
            -- streaming is done, so we need to make sure that the renderer is notified about it
            if not self.stream.results or #self.stream.results == 0 then
                self.select:list(
                    utils.EMPTY_TABLE,
                    utils.EMPTY_TABLE
                )
                self.select:status("0/0")
            end
            self.select:list(nil, nil)
        else
            local query = self.select:query()
            if #all > 0 and type(query) == "string" and #query > 0 then
                -- when there is a query we need to match against it
                self.match:match(all, query, function(matching)
                    if matching == nil then
                        -- notify that there matching has finished, so the renderer can update the status, also
                        -- check if there was actually nothing matched once the matching has signaled it has
                        -- finished if that is the case clear the selection list from previous matches
                        if not self.match.results or #self.match.results == 0 or #self.match.results[1] == 0 then
                            self.select:list(
                                utils.EMPTY_TABLE,
                                utils.EMPTY_TABLE
                            )
                            self.select:status("0/0")
                        end
                        self.select:list(nil, nil)
                    else
                        -- render the new matching results, which would update the list view
                        self.select:list(
                            matching[1],
                            matching[2]
                        )
                        self.select:status(string.format(
                            "%d/%d", #matching[1], #all
                        ))
                    end
                end, self._state.match)
            else
                -- when there is no query yet, we just have to render all the results as they are, empty query means that
                -- we can certainly show all results, that the stream produced so far.
                self.select:list(all, nil)
                self.select:status(string.format(
                    "%d/%d", #all, #all
                ))
            end
        end
    end)
end

function Picker:_create_stage()
    local function _input_prompt()
        return utils.debounce_callback(self._options.prompt_debounce, function(query)
            local stage = self._state.stage
            assert(stage and next(stage))
            if query == nil then
                self:_close_stage()
                self:_close_picker()
            elseif self.stream.results then
                if #self.stream.results > 0 and type(query) == "string" and #query > 0 then
                    stage.match:match(self.stream.results, query, function(matching)
                        if matching == nil then
                            -- notify that there matching has finished, so the renderer can update the status, also
                            -- check if there was actually nothing matched once the matching has signaled it has
                            -- finished if that is the case clear the selection list from previous matches
                            if not stage.match.results or #stage.match.results == 0 or #stage.match.results[1] == 0 then
                                stage.select:list(
                                    utils.EMPTY_TABLE,
                                    utils.EMPTY_TABLE
                                )
                                stage.select:status("0/0")
                            end
                            stage.select:list(nil, nil)
                        else
                            stage.select:list(
                                matching[1],
                                matching[2]
                            )
                            stage.select:status(string.format(
                                "%d/%d",
                                #matching[1],
                                #self.stream.results
                            ))
                        end
                    end, self._state.match)
                else
                    stage.select:list(
                        self.stream.results,
                        nil -- no highlights
                    )
                    stage.select:list(nil, nil)
                    stage.select:status(string.format(
                        "%d/%d",
                        #self.stream.results,
                        #self.stream.results
                    ))
                end
            end
        end)
    end

    local function _cancel_prompt()
        return Select.action(Select.close_view, function()
            self:_close_stage()
            self:_close_picker()
        end)
    end

    local function _hide_prompt()
        return Select.action(Select.close_view, function()
            self:_hide_stage()
            self:_hide_picker()
        end)
    end

    -- @Speed: That should be cheap, since the actions contain callbacks
    -- and a few strings for the labels, but might require re-thinking
    local stage_actions = vim.fn.deepcopy(self._options.actions)
    assert(stage_actions)["<c-g>"][2] = "interactive"

    stage_actions = vim.tbl_deep_extend("force", stage_actions, {
        ["<esc>"] = _cancel_prompt(),
        ["<c-c>"] = _hide_prompt(),
    })

    local picker_options = self._options
    self._state.stage = {
        select = Select.new({
            display = picker_options.display,
            preview = picker_options.preview,
            decorators = picker_options.decorators,
            mappings = vim.tbl_map(function(a)
                return a ~= nil and type(a) == "table"
                    and assert(a[1]) or assert(a)
            end, picker_options.actions or {}),
            prompt_input = _input_prompt(),
            prompt_headers = self:_generate_headers(
                picker_options.headers, stage_actions
            ),
            prompt_decor = picker_options.prompt_decor,
            window_ratio = picker_options.window_size,
        }),
        match = Match.new({
            timer = picker_options.match_timer,
            limit = picker_options.match_limit,
            step = picker_options.match_step,
        })
    }
end

function Picker:_toggle_stage()
    local stage = self._state.stage
    if self.select:isempty() then
        vim.notify(
            "There are no results to match...",
            vim.log.levels.WARN
        )
    elseif self.select:isopen() then
        self._state.staging = true
        self:_hide_picker()
        stage.select:open()

        if stage.select:isempty() and self.stream.results then
            stage.select:list(
                self.stream.results,
                nil -- no highlights
            )
            stage.select:list(nil, nil)
            stage.select:status(string.format(
                "%d/%d",
                #self.stream.results,
                #self.stream.results
            ))
        end
    elseif stage.select:isopen() then
        self._state.staging = false
        self:_hide_stage()
        self.select:open()
    end
end

function Picker:_generate_headers(headers, actions)
    local action_headers = {}
    -- generate the labels for the picker actions, if any exist
    for key, action in pairs(actions or self._options.actions) do
        if type(action) == "table" and #action > 1 then
            local block = {}
            table.insert(block, { key, "PickerHeaderActionKey" })
            table.insert(block, { "::", "PickerHeaderActionSeparator" })
            if type(action[2]) == "string" then
                -- the 2nd value of the tupple is a string, representing the label
                table.insert(block, { assert(action[2]), "PickerHeaderActionLabel" })
            elseif type(action[2]) == "function" then
                -- the 2nd value of the tuple is a function that generates the label
                table.insert(block, { assert(action[2](self)), "PickerHeaderActionLabel" })
            end
            table.insert(action_headers, block)
        end
    end

    table.sort(action_headers, function(a, b)
        -- sort the actions by the action label
        return assert(a[3][1]) < assert(b[3][1])
    end)

    -- add the rest of the labels defined for the picker
    headers = headers or self._options.headers
    headers = headers and vim.fn.deepcopy(headers) or {}
    return vim.list_extend(headers, action_headers)
end

function Picker:_is_open()
    return self.select:isopen() or (
        self._state.stage
        and self._state.stage.select
        and self._state.stage.select:isopen()
    )
end

function Picker:_is_valid()
    return self.select:isvalid() or (
        self._state.stage
        and self._state.stage.select
        and self._state.stage.select:isvalid()
    )
end

function Picker:_is_interactive()
    local interactive = self._state.context.interactive
    return interactive ~= nil and interactive ~= false
end

--- Check whether the primary picker or a running stage is open. The picker is considered open when any of the primary components of the selection interface are within view.
--- @return boolean whether the picker or any running stage is open
function Picker:isopen()
    return self:_is_open()
end

--- Check whether the primary picker or a running stage is valid. The picker is considered valid when any of the primary components of the selection interfacece are valid themselves
--- @return boolean whether the picker or any running stage is open
function Picker:isvalid()
    return self:_is_valid()
end

--- Close the picker, along with any running stream or matching operations, and also close any running stage, permanently. The picker state will be destroyed upon closing it. To retain the persistent state of the picker at the present moment see and use the `hide` method
function Picker:close()
    self:_close_stage()
    self:_close_picker()
end

-- Hide the picker, does not destroy any of the internal state or context of the picker or internal interfaces or components, can be used to simply hide away the picker view and restore it later with open. This will retain the picker state as is while it remains hiddden from view.
function Picker:hide()
    self:_hide_stage()
    self:_hide_picker()
end

function Picker:open()
    if self:isopen() then
        return
    end

    local valid = self.select:isvalid()
    if valid == true then
        if self._state.staging then
            self._state.stage.select:open()
        else
            self.select:open()
        end
    else
        self.select:open()

        if type(self._state.content) ~= "table" then
            -- when a string or a function is provided the content is expected to be a command that produces output, or a function
            -- that produces output by calling a callback method for each entry in the stream
            assert(type(self._state.content) == "string" or type(self._state.content) == "function")
            if not self.stream.results and not self:_is_interactive() then
                self.stream:start(
                    self._state.content, {
                        cwd = self._state.context.cwd,
                        env = self._state.context.env,
                        args = self._state.context.args,
                        callback = self:_flush_results(),
                        transform = self._state.context.map,
                    })
            elseif self.stream.results and self.select:isempty() then
                self.select:list(
                    self.stream.results,
                    nil -- no highlights
                )
                self.select:list(nil, nil)
                self.select:status(string.format(
                    "%d/%d",
                    #self.stream.results,
                    #self.stream.results
                ))
            end
        else
            -- when a table is provided the content is expected to be a list of strings, each string being a separate entry, and in
            -- this mode the interactive option is not supported, as there is no way to passk the query to the command, because
            -- there is no command
            assert(type(self._state.content[1]) == "string" or type(self._state.content[1]) == "table")
            assert(not self._state.context.args or not next(self._state.context.args) and not self:_is_interactive())

            -- the content is either going to be a table of strings or a table of tables, either way simply display it directly to
            -- the select, as there is no async result loading happening at this moment
            self.select:list(
                self._state.content,
                nil -- no highlights
            )
            self.select:list(nil, nil)
            self.select:status(string.format(
                "%d/%d", #self._state.content,
                #self._state.content
            ))
        end
    end
end

--- @class PickerOptions
--- @field content string|function|table the content to use for the picker, can be a command string, a function that takes a callback and calls it for each entry, or a table of entries, if a string or function is provided the content is streamed, if a table is provided the content is static, and the picker can not be interactive. When a table or function is provided the entries can be either strings or tables, when tables are used the display option must be provided to extract a valid matching string from the table. The display function will be used for both displaying in the list and matching the entries against the user query, internally.
--- @field context? table a table of context to pass to the content function, can contain the following keys - `cwd` - string, `env` - table of environment variables, `args` a table of arguments to start the command with - table, and `map`, a function that transforms each entry before it is added to the stream. The mapper function is useful when the content function produces complex entries, that need to be transformed into useable entries for the picker components downstream. It is independent of the display function, which is used to extract a string from the entry (at which point it may already mapped with the mapper function) for displaying and matching. The mapper function is used to transform the stream entries before they are added to the stream itself. Return nil or false from this function to skip an entry from being added to the stream, `interactive` - boolean|string|number|nil whether the command is interactive, meaning that it will restart the stream on every query change, if a string is provided it is used as a placeholder in the `args` list to replace with the query, if number, the query is inserted at <index> position in `args`, if nil or false the picker is non-interactive, during an interactive mode the matching is done in the second stage, that can be entered with <c-g>.
--- @field decorators? Select.Decorator[]|nil a list of decorators to use for decorating the entries in the list, each decorator must be a child class derived from Select.Decorator.
--- @field preview? Select.Preview|boolean|nil a previewer to use for previewing the currently selected entry, can be a user provided previewer, must be an instance of a sub-class of Select.Preview.
--- @field actions? table<string, table<fun(select: Select): any, string|function>|fun(select: Select): any> a table of actions to use for the picker, where the key is the keybinding to trigger the action, and the value is either a function to call when the action is triggered, or a tuple of a function and a string or function, where the string or function is used as the label for the action in the header. If a function is provided as the second value of the tuple, it will be called with the picker instance as its only argument, and should return a string to use as the label. Some default actions are provided, that can be used directly, like `Select.select_entry`, `Select.send_quickfix`, etc.
--- @field display? string|fun(entry: any): string|string|nil Function or string to format the display of entries in the list. If a function is provided, it will be called with each entry and should return a string to display. If a string is provided, it will be used as the property name to extract from each entry for display.
--- @field headers? table[]|nil a list of headers to display in the picker, each header must be a list of tuples, where each tuple is a pair of a string and a highlight group name, the string is the text to display, and the highlight group name is the highlight group to use for displaying the text, for example: { {"<c-n>", "PickerHeaderActionKey"}, {"::", "PickerHeaderActionSeparator"}, {"next", "PickerHeaderActionLabel"} }.
--- @field match_limit? number|nil the maximum number of matches to keep, nil means no limit.
--- @field match_timer? number the time in milliseconds to wait before flushing the matching results, this is useful when dealing with large result sets.
--- @field match_step? number the number of entries to process in each matching step, this is useful when dealing with large result sets.
--- @field display_step? number of entries to process in a single batch when rendering items into the list, useful when using a more complex or demanding display function that takes some time to process.
--- @field stream_type? "lines"|"bytes" whether the stream produces lines or bytes, when lines is used the stream will be split on newlines, when bytes is used the stream will be split on byte size.
--- @field stream_step? number the number of bytes or lines to read in each streaming step, this is useful when dealing with large result sets.
--- @field stream_debounce? number the time in milliseconds to debounce the flush calls of the stream, this is useful to avoid stream batch flushes in quick succession, when the results accumulate fast enough that we can combine into a single flush call instead, caused by the executable being too fast, or the `stream_step` being too small.
--- @field window_size? number the size of the window to use for the picker, this is a ratio between 0 and 1, where 1 is the full screen.
--- @field prompt_debounce? number the time in milliseconds to debounce the user input, this is useful to avoid flooding the matching and streaming with too many updates at once.
--- @field prompt_query? string the initial query to use for the prompt.
--- @field prompt_decor? string|table the prefix or/and suffix to use for the prompt.

--- Create a new picker instance
--- @param opts PickerOptions
--- @return Picker
function Picker.new(opts)
    opts = opts or {}
    vim.validate({
        actions = { opts.actions, "table", true },
        headers = { opts.headers, "table", true },
        content = { opts.content, { "string", "function", "table" } },
        context = { opts.context, { "table", "nil" }, true },
        display = { opts.display, { "function", "string", "nil" }, true },
        preview = { opts.preview, { "table", "boolean", "nil" }, true },
        decorators = { opts.decorators, "table", true },
        match_limit = { opts.match_limit, { "number", "nil" }, true },
        match_timer = { opts.match_timer, "number", true },
        match_step = { opts.match_step, "number", true },
        display_step = { opts.display_step, "number", true },
        stream_step = { opts.stream_step, "number", true },
        stream_type = { opts.stream_type, { "string", "nil" }, true, { "lines", "bytes" } },
        stream_debounce = { opts.stream_debounce, { "number", "nil" }, true },
        window_size = { opts.window_size, "number", true },
        prompt_debounce = { opts.prompt_debounce, "number", true },
        prompt_query = { opts.prompt_query, "string", true },
        prompt_decor = { opts.prompt_decor, { "table", "string" }, true },
    })
    opts = vim.tbl_deep_extend("force", {
        actions = {},
        headers = {},
        content = nil,
        context = {
            args = {},
            env = nil,
            map = nil,
            cwd = vim.loop.cwd(),
            interactive = false,
        },
        preview = nil,
        display = nil,
        decorators = {},
        match_limit = nil,
        match_timer = 100,
        match_step = 50000,
        display_step = 100000,
        stream_step = 100000,
        stream_type = "lines",
        stream_debounce = 0,
        window_size = 0.15,
        prompt_debounce = 250,
        prompt_query = "",
        prompt_decor = {
            prefix = "› ",
            suffix = "‹ "
        },
    }, opts)

    local is_lines = opts.stream_type == "lines"
    local list_step = opts.display and opts.display_step
    if type(opts.display) == "function" then
        opts.match = { text_cb = opts.display }
    elseif type(opts.display) == "string" then
        opts.match = { key = opts.display }
    end

    local self = setmetatable({
        match = nil,
        stream = nil,
        select = nil,
        _options = opts,
        _state = {
            display = opts.display,
            content = opts.content,
            context = opts.context,
            match = opts.match,
            staging = false,
        },
    }, Picker)

    self.match = Match.new({
        timer = opts.match_timer,
        limit = opts.match_limit,
        step = opts.match_step,
    })

    self.stream = Stream.new({
        step = opts.stream_step,
        bytes = not is_lines,
        lines = is_lines,
    })

    if self:_is_interactive() then
        local stream = self.stream
        self._options.actions["<c-g>"] = { function()
            if assert(stream) and stream:running() then
                vim.notify(
                    "Content stream is still running...",
                    vim.log.levels.WARN
                )
                return
            end
            self:_toggle_stage()
        end, "fuzzy" }
    end

    self._options.actions = vim.tbl_deep_extend("keep", self._options.actions, {
        ["<cr>"]  = self:_confirm_prompt(),
        ["<esc>"] = self:_cancel_prompt(),
        ["<c-c>"] = self:_hide_prompt(),
    })

    self.select = Select.new({
        list_step = list_step,
        preview = opts.preview,
        display = opts.display,
        decorators = opts.decorators,
        mappings = vim.tbl_map(function(a)
            return a ~= nil and type(a) == "table"
                and assert(a[1]) or assert(a)
        end, opts.actions),
        prompt_input = self:_input_prompt(),
        prompt_headers = self:_generate_headers(),
        prompt_query = opts.prompt_query,
        prompt_decor = opts.prompt_decor,
        window_ratio = opts.window_size,
    })

    if self:_is_interactive() then
        self:_create_stage()
    end

    return self
end

return Picker
