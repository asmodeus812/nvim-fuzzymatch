local Scheduler = require("fuzzy.scheduler")
local Async = require("fuzzy.async")
local Pool = require("fuzzy.pool")
local utils = require("fuzzy.utils")

--- @class Stream
--- @field public results string[]|nil The results accumulated so far, this is only valid after the stream has finished, or if the stream is ephemeral and a new stream has not yet started.
--- @field private onexit fun(number, string) The function that will be invoked when the stream exits, this function reports the exit code and possible error messages to the consumer
--- @field private callback fun(buffer: string[], accum: string[]) The callback function to be called when new data is available, this function receives two arguments, the first is the current buffer of data, the second is the accumulation of all data so far.
--- @field private transform? fun(data: string): string|nil A function to transform each line or chunk of data before it is added to the results, defaults to nil
--- @field private _options StreamOptions The options for the stream
--- @field private _state table The internal state of the stream, used to manage the stream's lifecycle
local Stream = {}
Stream.__index = Stream

local function close_handle(handle)
    if handle ~= nil and handle.close and not handle:is_closing() then
        handle:close()
    end
end

function Stream:_destroy_stream()
    -- the results can be re-claimed back into the pool, when a new stream is starting up, this ensures that old references to the
    -- values held by the results are correctly freed and avoid holding references for too long
    if self.results then
        utils.fill_table(
            self.results,
            utils.EMPTY_STRING
        )
        Pool.attach(self.results)
        Pool._return(self.results)
        self.results = nil
    end
end

function Stream:_close_stream()
    -- this method ensures that handles are correctly cleaned, however it also ensures that any helper tables are cleared up, for
    -- subsequent invokations of new streams through :start
    if self._state.stdout then
        self._state.stdout:read_stop()
        close_handle(self._state.stdout)
        self._state.stdout = nil
    end
    if self._state.stderr then
        self._state.stderr:read_stop()
        close_handle(self._state.stderr)
        self._state.stderr = nil
    end
    if self._state.handle then
        close_handle(self._state.handle)
        self._state.handle = nil
    end

    if self._state.buffer then
        -- clean up the string references to avoid any memory leaks, the buffer could still be reused in future calls to start
        -- new streams, see `ephemeral`
        utils.fill_table(
            self._state.buffer,
            utils.EMPTY_STRING
        )
        -- make sure that the buffer itself is also returned back to the pool, this will ensure that future stream instances, or this
        -- one can pick it from the pool and use it.
        Pool._return(self._state.buffer)
        self._state.buffer = nil
        self._state.size = 0
    end

    if self._state.accum then
        -- the accumulator must be detached from the pool, as closing the stream now implies no more results will come in, this frees
        -- the accumulator from the pool, allowing users to use the results as they see fit, through stream.results. The accumulator is also
        -- resized to ensure the total number of elements, this is useful if the stream did not find any results, in which case
        -- _flush_results would never be called, in all other cases this is a no op.
        Pool.detach(self._state.accum)
        self.results = self._state.accum
        self._state.accum = nil
        self._state.total = 0
    end

    self._state.pending = nil
    self._state.exitdata = nil
    self._state.stdouteof = false
    self._state.stderreof = false

    self.callback = nil
    self.transform = nil

    self:_stop_streaming()
end

function Stream:_make_stream()
    -- the stream is curerntly only working with stdout/err there is no handle for stdin, as it is not expected for the stream to
    -- accept any input while it is sending data back to us.
    self._state.stdout = assert(vim.loop.new_pipe(false))
    self._state.stderr = assert(vim.loop.new_pipe(false))

    -- the stdio array needs to contain these in a very specific order, the first entry is the stdin pipe, the rest are the stdout
    -- and stderr is the last one always.
    local stdio = {
        nil,
        self._state.stdout,
        self._state.stderr,
    }
    return stdio
end

function Stream:_bind_method(method)
    return function(...)
        return method(self, ...)
    end
end

function Stream:_transform_data(data)
    if type(self.transform) == "function" then
        return self.transform(data)
    else
        return data
    end
end

function Stream:_flush_results()
    for i = 1, self._state.size, 1 do
        self._state.accum[self._state.total + i] = self._state.buffer[i]
    end
    self._state.total = self._state.total + self._state.size

    -- ensure that the size of the buffer is exactly the currently accumulated size, this is done since our buffer is constantly
    -- being re-used, for the very first flush the buffer might be bigger and contain empty slots, subsequent resizes will probably
    -- be noops
    self._state.buffer = utils.resize_table(
        self._state.buffer,
        self._state.size
    )

    -- ensure that the size of the accumulation buffer is also the current total accumulated size, again this is done to ensure that
    -- the accumulation buffer has no empty slots and its size is exact, the resize is here is relevant for each flush since the
    -- buffer grows.
    self._state.accum = utils.resize_table(
        self._state.accum,
        self._state.total
    )

    -- invoke the user supplied callback which is supposed to process the results, this callback must not modify the input arguments
    -- but can use-them to process the results,
    utils.safe_call(
        self.callback,
        self._state.buffer,
        self._state.accum
    )

    -- reset the state for the next flush call
    self._state.size = 0
end

function Stream:_handle_data(data, size)
    if size == self._options.step then
        -- when the size has reached the maximum allowed, flush the buffer, and send it over for processing to
        -- the user provided callback
        utils.timed_call(Stream._flush_results, self)
    end

    if self._state.buffer then
        -- keep accumulating non blank lines into the buffer, eventually the buffer size will be enough to be
        -- flushed, see above
        self._state.buffer[self._state.size + 1] = self:_transform_data(data)
        self._state.size = self._state.size + 1
    end
end

function Stream:_handle_out(code, chunk, kind)
    assert(kind and kind > 0)
    local callback = self.callback
    local onexit = self._options.onexit

    -- when we hit some type of error we can immediately close and destroy the stream that is non-negotiable as there is something wrong that has happened with it
    if code and code > 0 then
        -- ensure that the error is reported to the user in some capacity, that can be useful to debug the state of the command
        -- that was being run and what went wrong.
        self:destroy()
        utils.safe_call(callback, nil, nil)
        utils.safe_call(onexit, code, chunk)
        return
    end

    -- track the exit data for the stream, that is only valid when we receive a handle out that is of kind 3 that signals that the
    -- exit code and message status have been seen, however we might still have bufferred i/o pending from pipes on the OS level
    if kind == 3 then self._state.exitdata = { code, chunk } end

    -- in case we have not yet seen exit and any of the eof from both stdout and stderr, we can not yet close or flush the stream or finalize it,
    -- that can only happen if EOF on both pipes is met
    if not self._state.exitdata or
        not self._state.stderreof or
        not self._state.stdouteof
    then
        return
    end

    -- in case on exit there was any partial pending data that was read but never finalized and flushed down to the client we can do
    -- it here before killing the stream, that is important as otherwise data might be lost
    local pending_data = self._state.pending
    if pending_data ~= nil and #pending_data > 0 then
        self:_handle_data(pending_data, self._state.size)
        self._state.pending = nil
    end

    -- on exit make sure that there is nothing more to flush, if there is any size accumulated over the very last call toThe handle
    -- of stdout or stderr, then we need to finally flush it as well, this is to ensure that there is no left over unprocessed data
    -- after the stream has closed
    if self._state.size > 0 then
        utils.timed_call(Stream._flush_results, self)
    end

    -- finally stop the stream, and notify the user of the finalization of the stream itself, with both the exit
    local exitdata = assert(self._state.exitdata)
    self:stop() -- first ensure cleanup
    utils.safe_call(callback, nil, nil)
    utils.safe_call(onexit, exitdata[1], exitdata[2])
end

function Stream:_handle_in(err, chunk, kind)
    if err ~= nil then
        self:_handle_out(1, err, kind)
    elseif not chunk then
        if kind == 1 then
            self._state.stdouteof = true
        elseif kind == 2 then
            self._state.stderreof = true
        end
        self:_handle_out(0, nil, kind)
    else
        assert(type(chunk) == "string")

        if self._options.lines == true then
            local pending_line = self._state.pending
            if pending_line ~= nil and #pending_line > 0 then
                chunk = pending_line .. chunk
                self._state.pending = nil
            end
            -- when the type of stream is defined as lines, split the output based on new lines, this might produce some empty lines
            -- which are filtered afterwards.
            local start = 1
            local count = 0
            local separator = "\n"

            -- manually split the chunk into lines, this is done to avoid creating intermediate tables and strings, which would
            -- then need to be garbage collected, instead we simply iterate over the chunk and extract substrings as needed, this
            -- should be more efficient and avoid unnecessary allocations.
            while true do
                local size = self._state.size
                local pos, next = chunk:find(
                    separator, start, false
                )

                -- not finding the final new line does not mean the job is done there is still data pending that means
                -- that we have to store this data for further processing, the first new line we find in the next chunk
                -- we will append to this one. This needs deterministic ordering in chunk execution order
                if not pos then
                    if start <= #chunk then
                        local line = chunk:sub(start)
                        self._state.pending = line
                    end
                    break
                end

                local line = chunk:sub(start, pos - 1)
                self:_handle_data(line, size)

                start = next + 1
                count = count + 1
            end
        elseif self._options.bytes == true then
            -- when the type of the stream is defined as bytes, simply append the string chunks to the buffer, once the buffer contains N number
            -- of chunks, whose total summed string length, is greater than the allowed size (interpreted as byte length), flush the buffer.
            -- Keep in mind that this is not exact, it will likely exceed the step size, but it is much more efficient to take the entire buffer
            -- instead of hard splitting it exactly on the step size, which would require more string manipulation and allocations
            local length = 0
            local buffer = self._state.buffer
            for i = 1, self._state.size, 1 do
                length = length + #buffer[i]
            end
            self:_handle_data(chunk, length)
        end
    end
end

function Stream:_handle_stdout(err, chunk)
    local executor = Async.wrap(Stream._handle_in)

    local streamer = function()
        self._state.streamer = executor(self, err, chunk, 1)
        Scheduler.add(self._state.streamer)
    end

    if self:_is_streaming() then
        self._state.streamer:await(streamer)
    else
        streamer()
    end
end

function Stream:_handle_stderr(err, chunk)
    local executor = Async.wrap(Stream._handle_in)

    local streamer = function()
        self._state.streamer = executor(self, err, chunk, 2)
        Scheduler.add(self._state.streamer)
    end

    if self:_is_streaming() then
        self._state.streamer:await(streamer)
    else
        streamer()
    end
end

function Stream:_handle_exit(e, c)
    local executor = Async.wrap(Stream._handle_out)

    local streamer = function()
        self._state.streamer = executor(self, e, c, 3)
        Scheduler.add(self._state.streamer)
    end

    if self:_is_streaming() then
        self._state.streamer:await(streamer)
    else
        streamer()
    end
end

function Stream:_is_streaming()
    return self._state.streamer ~= nil
end

function Stream:_stop_streaming()
    if self._state.streamer then
        self._state.streamer:abort()
        self._state.streamer = nil
    end
end

--- Returns true if the stream is considered finalized and no longer processing data in-flight, and there is a valid set of data present for consumption produced by the stream
--- @return boolean True if the stream has finalized and results data is ready to be consumed by the client
function Stream:isvalid()
    return not self:running() and self.results ~= nil and #self.results >= 0
end

--- Checks if the stream finalized and has accumulated any entries at all ready for consumption
--- @return boolean True if the streamer has no entries accumulated, false otherwise.
function Stream:isempty()
    return self:isvalid() and #self.results == 0
end

--- Returns true if the stream is started or is already running, i.e. has been started and not yet stopped, exited or aborted, false otherwise
--- @return boolean True if the stream is started or running, false otherwise
function Stream:running()
    return self._state.handle ~= nil or self:_is_streaming()
end

--- Return the stream options table.
--- This returns the live internal options reference and is intended for read-only access.
--- @return StreamOptions
function Stream:options()
    return assert(self._options)
end

--- Waits for the stream to finish, or until the timeout is reached
--- @param timeout integer|nil The maximum time to wait in milliseconds, defaults to the timeout specified in the options, or utils.MAX_TIMEOUT
--- @return string[]|nil The results accumulated so far, or nil if the timeout was reached
function Stream:wait(timeout)
    local wait_timeout = timeout or self._options.timeout or utils.MAX_TIMEOUT
    local done = vim.wait(wait_timeout, function()
        return self.results ~= nil
    end, 25, false)

    if not done and self:running() then
        self:stop()
    end
    return self.results
end

-- Destroys the stream and any pending state that is currently being allocated into the stream, note that this is done automatically for
-- ephemeral streams when a new stream is re-started the resources for the previous ones are invalidated
function Stream:destroy()
    self:_close_stream()
    self:_destroy_stream()
end

--- Stops the stream if it is running and finalizes the current buffered results without destroying them
function Stream:stop()
    self:_close_stream()
    self:_stop_streaming()
end

--- @class StreamStartOpts
--- @field cwd? string The current working directory to run the command in, defaults to the current working directory of Neovim
--- @field args? string[] The arguments to pass to the command, defaults to an empty table
--- @field env? string[] The environment variables to set for the command, defaults to nil
--- @field transform? fun(data: string): string|nil A function to transform each line or chunk of data before it is added to the results, defaults to nil
--- @field callback fun(buffer: string[], accum: string[]) A function to be called when new data is available, this function receives two arguments, the first is the current buffer of data, the second is the accumulation of all data so far, this function is required

--- Starts the stream with the given command and options, if a stream is already running it is stopped first, if the new stream is for
--- new command the previous results and state are destroyed. Starting a stream does not imply that it will begin emitting values
--- immediately but it implies that is considered `running`, guaranteeing that at some future point values will be emitted and streamed to consumers
--- @param cmd string|function The command to run, or a function which accepts a callback to be invoked with data chunks to supply data to the stream
--- @param opts StreamStartOpts|nil The options for starting the stream, see StreamStartOpts for details
function Stream:start(cmd, opts)
    opts = opts or {}
    vim.validate({
        cmd = { cmd, { "string", "function" }, false },
        opts = { opts, "table", true },
    })
    -- each time we start a new stream we make sure to stop any ongoing streams and clean up the context, any old state will be lost,
    -- depending on the ephemeral option more aggressive clean up might be done
    if self:running() then
        if self._options.ephemeral then
            self:destroy()
        else
            self:stop()
        end
    end

    self.transform = opts.transform
    self.callback = assert(opts.callback)

    -- based on the type of the stream the step either governs how many bytes to read, or how many lines into the buffer before
    -- flushing
    local size = self._options.lines and self._options.step or 8

    -- ensure that a buffer is claimed from the pool, a buffer with the required size, or close to it will be pulled from the pool
    -- for future use
    if not self._state.buffer then
        self._state.buffer = Pool.obtain(size)
    end

    -- the accumulator has to also be pulled form the pool, similarly to the buffer, the accumulator starts with a given size, at
    -- least enough to fit in the first batch of buffer entries, it will however grow further, unlike the buffer
    if not self._state.accum then
        self._state.accum = Pool.obtain(size)
    end

    if type(cmd) == "function" then
        local did_finalize = false
        local callback = function(data)
            if not did_finalize and data ~= nil then
                self:_handle_data(
                    data,
                    self._state.size
                )
            else
                self._state.stdouteof = true
                self._state.stderreof = true
                assert(did_finalize == false)
                self:_handle_out(0, nil, 3)
                did_finalize = true
            end
        end
        local executor = Async.wrap(function(stream)
            local ok, err = utils.safe_call(
                cmd, callback, opts.args, opts.cwd, opts.env
            )
            local code = not ok and 1 or 0
            if did_finalize == false then
                self._state.stdouteof = true
                self._state.stderreof = true
                stream:_handle_out(code, err, 3)
                did_finalize = true
            end
        end)
        self._state.streamer = executor(self)
        Scheduler.add(self._state.streamer)
    else
        local stdio = self:_make_stream()
        assert(vim.fn.executable(cmd) == 1)

        self._state.handle = assert(vim.loop.spawn(cmd, {
            detached = false,
            args = opts.args,
            cwd = opts.cwd,
            env = opts.env,
            stdio = stdio,
            hide = true,
        }, self:_bind_method(
            Stream._handle_exit)
        ))

        vim.loop.read_start(
            self._state.stdout,
            self:_bind_method(
                Stream._handle_stdout
            )
        )

        vim.loop.read_start(
            self._state.stderr,
            self:_bind_method(
                Stream._handle_stderr
            )
        )
    end

    -- make sure the state is clear for the processing to start from the start
    self._state.total = 0
    self._state.size = 0
    self._state.pending = nil
end

--- @class StreamOptions
--- @field ephemeral? boolean Whether the stream is ephemeral, if true, starting a new stream will destroy the previous results and state, defaults to true
--- @field bytes? boolean Whether the stream processes data in bytes, mutually exclusive with `lines`, defaults to false
--- @field lines? boolean Whether the stream processes data in lines, mutually exclusive with `bytes`, defaults to true
--- @field step? integer The number of lines or bytes to accumulate before flushing to the callback, defaults to 100000
--- @field timeout? integer The maximum time to wait in milliseconds when calling :wait, defaults to utils.MAX_TIMEOUT
--- @field onexit? fun(number, msg): any Report the exit status of the stream to the consumer, this function receives two arguments, the exit code and an optional message, defaults to a function which notifies the user of non zero exit code.

--- Creates a new Stream instance with the given options, or default options if none are provided
--- @param opts StreamOptions|nil The options for the stream
--- @return Stream The new Stream instance
function Stream.new(opts)
    opts = opts or {}
    vim.validate({
        ephemeral = { opts.ephemeral, "boolean", true },
        bytes = { opts.bytes, "boolean", true },
        lines = { opts.lines, "boolean", true },
        step = { opts.step, "number", true },
        timeout = { opts.timeout, "number", true },
        onexit = { opts.onexit, "function", true },
    })
    opts = vim.tbl_deep_extend("force", {
        onexit = utils.handle_exit,
        ephemeral = true,
        bytes = false,
        lines = true,
        step = 131072,
    }, opts)

    local self = setmetatable({
        transform = nil,
        results = nil,
        callback = nil,
        _options = opts,
        _state = {
            size = 0,
            total = 0,
            pending = 0,
            accum = nil,
            buffer = nil,
            stdout = nil,
            stderr = nil,
            handle = nil,
            streamer = nil,
            exitdata = nil,
            stdouteof = false,
            stderreof = false,
        },
    }, Stream)

    assert(opts.bytes ~= opts.lines)
    return self
end

return Stream
