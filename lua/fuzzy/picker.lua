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
local Picker = {}
Picker.__index = Picker

function Picker:_destroy_picker()
    self.select:destroy()
    self.match:destroy()
    self.stream:destroy()
end

function Picker:_destroy_stage()
    local stage = self._state.stage
    if stage and next(stage) then
        stage.select:destroy()
        stage.match:destroy()
    end
end

function Picker:_close_picker()
    self.match:stop()
    self.stream:stop()
    self.select:close()
end

function Picker:_close_stage()
    local stage = self._state.stage
    if stage and next(stage) then
        stage.match:stop()
        stage.select:close()
    end
end

function Picker:_interactive_args(query)
    local args = vim.fn.copy(self._state.context.args)
    if type(self._state.interactive) == "string" then
        for _idx, _arg in ipairs(args or {}) do
            if _arg == self._state.interactive then
                args[_idx] = query
                break
            end
            assert(_idx < #args)
        end
    elseif type(self._state.interactive) == "number" then
        table.insert(assert(args), self._state.interactive, query)
    else
        table.insert(assert(args), query)
    end
    return args
end

function Picker:_cancel_prompt()
    return Select.action(Select.close_view, function()
        self:_close_picker()
        self:_close_stage()
    end)
end

function Picker:_input_prompt()
    -- debounce the user input to avoid flooding the matching and rendering logic with too many updates, especially when dealing
    -- with large result sets or fast typers
    return utils.debounce_callback(self._options.prompt_debounce, function(query)
        if query == nil then
            -- the input has been interrupted, so we need to stop everything
            if self.select:isempty() then
                self.select:status("0/0")
            end
            self.select:list(nil, nil)
            self.select:close()
            self.match:stop()
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
                    transform = self._state.context.mapper,
                    args = self:_interactive_args(query),
                    cwd = self._state.context.cwd,
                    env = self._state.context.env,
                    callback = function(_, all)
                        if not all then
                            -- notify that the streaming is done, so the renderer can update the status, the accumulated
                            -- result here would directly represent the stream contents that have been collected, matching
                            -- is not performed when the picker is interactive mode, the matching will be done in the
                            -- second stage.
                            if self.select:isempty() then
                                self.select:status("0/0")
                            end
                            self.select:list(nil, nil)
                        else
                            self.select:status(string.format(
                                "%d/%d", #all, #all
                            ))
                            self.select:list(
                                all, -- accum results
                                nil  -- no highlights
                            )
                            self.select:list(nil, nil)
                        end
                    end
                })
            else
                -- when there is no query we just render no results, there is nothing yet running, the stream is not
                -- started on empty query in interactive mode
                self.select:list(
                    utils.EMPTY_TABLE,
                    utils.EMPTY_TABLE
                )
                self.select:status("0/0")
            end
            -- clear the interactive second stage each time a new query arrives the old matches in the second stages would be invalid, the
            -- query would re-start the command with new interactive args which would invalidate the previous results against the stage
            -- might have been matching
            local stage = self._state.stage
            assert(stage and next(stage))
            stage.match:stop()
            stage.select:close()
            stage.select:destroy()
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
                        if #self.match.results == 0 then
                            self.select:list({}, {})
                            self.select:status("0/0")
                        end
                        self.select:list(nil, nil)
                    else
                        self.select:status(string.format(
                            "%d/%d", #matching[1], #data
                        ))
                        -- render the new matching results, which would update the list view
                        self.select:list(
                            matching[1],
                            matching[2]
                        )
                    end
                end, self._state.transform)
            else
                -- just render all the results as they are, when there is no query, nothing can be matched against, so we
                -- dump all the results into the list
                self.select:status(string.format(
                    "%d/%d", #data, #data
                ))
                self.select:list(
                    data, -- fill in data
                    nil   -- no highlights
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
            if self.select:isempty() then
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
                        if #self.match.results == 0 then
                            self.select:list({}, {})
                            self.select:status("0/0")
                        end
                        self.select:list(nil, nil)
                    else
                        -- render the new matching results, which would update the list view
                        self.select:status(string.format(
                            "%d/%d", #matching[1], #all
                        ))
                        self.select:list(
                            matching[1],
                            matching[2]
                        )
                    end
                end, self._state.transform)
            else
                -- when there is no query yet, we just have to render all the results as they are, empty query means that
                -- we can certainly show all results, that the stream produced so far.
                self.select:status(string.format(
                    "%d/%d", #all, #all
                ))
                self.select:list(
                    all, nil
                )
                self.select:list(nil, nil)
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
                                stage.select:status("0/0")
                            end
                            stage.select:list(nil, nil)
                        else
                            stage.select:status(string.format(
                                "%d/%d",
                                #matching[1],
                                #self.stream.results
                            ))
                            stage.select:list(
                                matching[1],
                                matching[2]
                            )
                        end
                    end, self._state.transform)
                else
                    stage.select:status(string.format(
                        "%d/%d",
                        #self.stream.results,
                        #self.stream.results
                    ))
                    stage.select:list(
                        self.stream.results,
                        nil -- no highlights
                    )
                    stage.select:list(nil, nil)
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

    local picker_options = self._options
    self._state.stage = {
        select = Select.new({
            mappings = picker_options.actions,
            providers = picker_options.providers,
            ephemeral = picker_options.ephemeral,
            resume_view = not picker_options.ephemeral,
            window_ratio = picker_options.window_size,
            prompt_prefix = picker_options.prompt_prefix,
            prompt_confirm = picker_options.prompt_confirm,
            prompt_cancel = _cancel_prompt(),
            prompt_input = _input_prompt(),
        }),
        match = Match.new({
            ephemeral = picker_options.ephemeral,
            timer = picker_options.match_timer,
            limit = picker_options.match_limit,
            step = picker_options.match_step,
        })
    }
end

function Picker:_toggle_stage()
    local stage = self._state.stage
    if self.select:isopen() then
        self:_close_picker()
        stage.select:open()

        if stage.select:isempty() and self.stream.results then
            stage.select:status(string.format(
                "%d/%d", #self.stream.results,
                #self.stream.results
            ))
            stage.select:list(self.stream.results, nil)
            stage.select:list(nil, nil)
        end
    elseif stage.select:isopen() then
        self:_close_stage()
        self.select:open()
    end
end

function Picker:_is_open()
    return self.select:isopen() or (
        self._state.stage
        and self._state.stage.select
        and self._state.stage.select:isopen()
    )
end

function Picker:_is_interactive()
    local int = self._state.interactive
    return int ~= nil and int ~= false
end

--- Check whether the picker or a running stage is open
--- @return boolean whether the picker or any running stage is open
function Picker:isopen()
    return self:_is_open()
end

--- Close the picker, along with any running stream or matching operations, and also close any running stage
function Picker:close()
    self:_close_stage()
    self:_close_picker()
    if self._options.ephemeral then
        self:_destroy_stage()
        self:_destroy_picker()
    end
end

function Picker:open()
    if self:isopen() then
        self:close()
    end
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
                    transform = self._state.context.mapper,
                })
        elseif self.stream.results and self.select:isempty() then
            self.select:status(string.format(
                "%d/%d",
                #self.stream.results,
                #self.stream.results
            ))
            self.select:list(self.stream.results, nil)
            self.select:list(nil, nil)
        end
    else
        -- when a table is provided the content is expected to be a list of strings, each string being a separate entry, and in
        -- this mode the interactive option is not supported, as there is no way to passk the query to the command, because
        -- there is no command
        assert(type(self._state.content[1]) == "string" or type(self._state.content[1]) == "table")
        assert(not self._state.context.args or not next(self._state.context.args))
        assert(not self:_is_interactive())

        -- the content is either going to be a table of strings or a table of tables, either way simply display it directly to
        -- the select, as there is no async result loading happening at this moment
        self.select:list(self._state.content, nil)
        self.select:list(nil, nil)
        self.select:status(string.format(
            "%d/%d", #self._state.content,
            #self._state.content
        ))
    end
end

-- Generic converter that converts grep line into a location triplet - filename, col and lnum, the column and line number are optional in the triplet
-- and will default gracefuly when not provided
--- @param entry string the line to match against, that line should be a valid line coming from a grep like tool, the general format is as follows filename:line:col:grep-matching-content
--- @return table|false returns the location triplet when a valid filename can be parsed from the line, otherwise false, signaling the select action to skip this selection entry, as it might be invalid
function Picker.grep_converter(entry)
    local pat = "^([^:]+):(%d+):(%d+):(.+)$"
    assert(type(entry) == "string" and #entry > 0)
    local filename, line_num, col_num = entry:match(pat)
    if filename and #filename > 0 then
        return {
            filename = filename,
            col = col_num and tonumber(col_num),
            lnum = line_num and tonumber(line_num),
        }
    end
    return false
end

function Picker.ls_converter(entry)
    assert(type(entry) == "string" and #entry > 0)
    local trimmed = entry:gsub("^%s*(.-)%s*$", "%1")
    local filename = trimmed:match("([^%s]+)$")
    if filename then
        return {
            col = 1,
            lnum = 1,
            filename = filename,
        }
    end
    return false
end

function Picker.err_converter(entry)
    assert(type(entry) == "string" and #entry > 0)
    local pat = "^([^:]+):(%d+):(%d+):%s*[^:]+:%s*(.+)$"
    local filename, line_num, col_num = entry:match(pat)
    if filename then
        return {
            filename = filename,
            col = col_num and tonumber(col_num),
            line = line_num and tonumber(line_num),
        }
    end
    return false
end

function Picker.many(converter)
    return function(e)
        return vim.tbl_map(converter, e)
    end
end

--- @class PickerOptions
--- @field content string|function|table the content to use for the picker, can be a command string, a function that takes a callback and calls it for each entry, or a table of entries, if a string or function is provided the content is streamed, if a table is provided the content is static, and the picker can not be interactive. When a table or function is provided the entries can be either strings or tables, when tables are used the display option must be provided to extract a valid matching string from the table. The display function will be used for both displaying in the list and matching the entries against the user query, internally.
--- @field context? table a table of context to pass to the content function, can contain the following keys - cwd - string, env - table, args - table, and mapper, a function that transforms each entry before it is added to the stream. The mapper function is useful when the content function produces complex entries, that need to be transformed into useable entries for the picker components downstream. It is independent of the display function, which is used to extract a string from the entry (at which point it may already mapped with the mapper function) for displaying and matching. The mapper function is used to transform the stream entries before they are added to the stream itself. It is less versatile than the display function, as it may be called only once per entry per unique stream evaluation, while the display is called when matching and displaying interactively.
--- @field interactive? boolean|string|number|nil whether the picker is interactive, meaning that it will restart the stream with the query as an argument, if a string is provided it is used as a placeholder in the args list to replace with the query, if number, the user input is inserted in the provided <index> in the args table, if nil or false the picker is non-interactive, during the interactive mode the matching is done in a second stage, that can be toggled with <c-g>
--- @field display? function|string|nil a custom function to use for displaying the entries, if nil the entry itself is used, if a string is provided it is used as a key to extract from the entry table
--- @field ephemeral? boolean whether the picker should be ephemeral, meaning that it will be destroyed when closed
--- @field match_limit? number|nil the maximum number of matches to keep, nil means no limit
--- @field match_timer? number the time in milliseconds to wait before flushing the matching results, this is useful when dealing with large result sets
--- @field match_step? number the number of entries to process in each matching step, this is useful when dealing with large result sets
--- @field prompt_preview? Select.Preview|boolean speficies the preview strategy to be used when entries are focused, false means no preview will be active, and a correct instance of a child class derived from Select.Preview will use that preview instead, Select.BufferPreview is used by default if the value of this field is true.
--- @field prompt_debounce? number the time in milliseconds to debounce the user input, this is useful to avoid flooding the matching and streaming with too many updates at once
--- @field prompt_confirm? function|nil a custom function to call when the user confirms the prompt, if nil the default action is used
--- @field prompt_prefix? string the prefix to use for the prompt
--- @field prompt_query? string the initial query to use for the prompt
--- @field stream_type? "lines"|"bytes" whether the stream produces lines or bytes, when lines is used the stream will be split on newlines, when bytes is used the stream will be split on byte size
--- @field stream_step? number the number of bytes or lines to read in each streaming step, this is useful when dealing with large result sets
--- @field window_size? number the size of the window to use for the picker, this is a ratio between 0 and 1, where 1 is the full screen
--- @field actions? table a table of key mappings to actions to use for the picker, see Select.mappings for the usage
--- @field providers? table a table of providers to use for the select, can contain icon_provider and status_provider, see Select.providers for the usage

--- Create a new picker instance
--- @param opts PickerOptions
--- @return Picker
function Picker.new(opts)
    opts = opts or {}
    vim.validate({
        actions = { opts.actions, "table", true },
        content = { opts.content, { "string", "function", "table" } },
        context = { opts.context, "table", true },
        display = { opts.display, { "function", "string", "nil" }, true },
        ephemeral = { opts.ephemeral, "boolean", true },
        interactive = { opts.interactive, { "boolean", "string", "number", "nil" }, true },
        match_limit = { opts.match_limit, { "number", "nil" }, true },
        match_step = { opts.match_step, "number", true },
        match_timer = { opts.match_timer, "number", true },
        prompt_confirm = { opts.prompt_confirm, { "function", "nil" }, true },
        prompt_debounce = { opts.prompt_debounce, "number", true },
        prompt_prefix = { opts.prompt_prefix, "string", true },
        prompt_preview = { opts.prompt_preview, { "table", "boolean" }, true },
        prompt_query = { opts.prompt_query, "string", true },
        providers = { opts.providers, "table", true },
        stream_step = { opts.stream_step, "number", true },
        stream_type = { opts.stream_type, { "string", "nil" }, true, { "lines", "bytes" } },
        window_size = { opts.window_size, "number", true },
    })
    opts = vim.tbl_deep_extend("force", {
        actions = {},
        content = nil,
        context = {},
        display = nil,
        ephemeral = false,
        interactive = false,
        match_limit = nil,
        match_step = 50000,
        match_timer = 100,
        prompt_confirm = nil,
        prompt_debounce = 250,
        prompt_prefix = "> ",
        prompt_preview = false,
        prompt_query = "",
        stream_step = 100000,
        stream_type = "lines",
        window_size = 0.15,
        providers = {
            icon_provider = true,
            status_provider = true,
        },
    }, opts)

    local transform
    local is_lines = opts.stream_type == "lines"
    local list_step = opts.display and 25000 or nil
    if type(opts.display) == "function" then
        transform = { text_cb = opts.display }
    elseif type(opts.display) == "string" then
        transform = { key = opts.display }
    end

    local self = setmetatable({
        match = nil,
        stream = nil,
        select = nil,
        _options = opts,
        _state = {
            interactive = opts.interactive,
            display = opts.display,
            content = opts.content,
            context = opts.context,
            transform = transform,
        },
    }, Picker)

    if self:_is_interactive() then
        self._options.actions["<c-g>"] = function()
            if self.stream:running() then
                vim.notify(
                    "Data stream is still running...",
                    vim.log.levels.WARN
                )
                return
            end
            self:_toggle_stage()
        end
    end

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
        list_display = opts.display,
        list_step = list_step,
        mappings = opts.actions,
        prompt_input = self:_input_prompt(),
        prompt_cancel = self:_cancel_prompt(),
        prompt_confirm = opts.prompt_confirm,
        prompt_prefix = opts.prompt_prefix,
        prompt_preview = opts.prompt_preview,
        prompt_query = opts.prompt_query,
        providers = opts.providers,
        resume_view = not opts.ephemeral,
        window_ratio = opts.window_size,
    })

    if self:_is_interactive() then
        self:_create_stage()
    end
    return self
end

return Picker
