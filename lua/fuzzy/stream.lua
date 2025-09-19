local Scheduler = require("fuzzy.scheduler")
local Async = require("fuzzy.async")
local utils = require("fuzzy.utils")
local BASEMSG = "Stream failed with"

--- @class Stream
--- @field public results string[]|nil The results accumulated so far, this is only valid after the stream has finished, or if the stream is ephemeral and a new stream has not yet started.
--- @field private onexit fun(number, string) The function that will be invoked when the stream exits, this function reports the exit code and possible error messages to the consumer
--- @field private callback fun(buffer: string[], accum: string[]) The callback function to be called when new data is available, this function receives two arguments, the first is the current buffer of data, the second is the accumulation of all data so far.
--- @field private mapper? fun(data: string): string|nil A function to transform each line or chunk of data before it is added to the results, defaults to nil
--- @field private _options StreamOptions The options for the stream
--- @field private _state table The internal state of the stream, used to manage the stream's lifecycle
local Stream = {}
Stream.__index = Stream

local function close_handle(handle)
    if handle ~= nil then
        if handle.close and not handle:is_closing() then
            handle:close()
        elseif handle.cancel and handle:is_running() then
            handle:cancel()
        end
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
        utils.attach_table(self.results)
        utils.return_table(self.results)
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
        utils.return_table(self._state.buffer)
        self._state.buffer = nil
        self._state.size = 0
    end

    if self._state.accum then
        -- the accumulator must be detached from the pool, as closing the stream now implies no more results will come in, this frees
        -- the accumulator from the pool, allowing users to use the results as they see fit, through stream.results. The accumulator is also
        -- resized to ensure the total number of elements, this is useful if the stream did not find any results, in which case
        -- _flush_results would never be called, in all other cases this is a no op.
        utils.detach_table(self._state.accum)
        utils.resize_table(
            self._state.accum,
            self._state.total,
            utils.EMPTY_STRING
        )
        self.results = self._state.accum
        self._state.accum = nil
        self._state.total = 0
    end

    self.callback = nil
    self.transform = nil
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
        self._state.size,
        utils.EMPTY_STRING
    )

    -- ensure that the size of the accumulation buffer is also the current total accumulated size, again this is done to ensure that
    -- the accumulation buffer has no empty slots and its size is exact, the resize is here is relevant for each flush since the
    -- buffer grows.
    self._state.accum = utils.resize_table(
        self._state.accum,
        self._state.total,
        utils.EMPTY_STRING
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
        self:_flush_results()
    end

    data = self:_transform_data(data)
    if data ~= nil and self._state.buffer then
        -- keep accumulating non blank lines into the buffer, eventually the buffer size will be enough to be
        -- flushed, see above
        self._state.buffer[self._state.size + 1] = data
        self._state.size = self._state.size + 1
    end
end

function Stream:_handle_stdout(err, chunk)
    if err or not chunk then return end
    assert(type(chunk) == "string")
    if self._options.lines == true then
        -- when the type of stream is defined as lines, split the output based on new lines, this might produce some empty lines
        -- which are filtered afterwards.
        local content = vim.split(chunk, "\n")
        for _, line in ipairs(content) do
            if line and #line > 0 then
                local size = self._state.size
                self:_handle_data(line, size)
            end
        end
    elseif self._options.bytes == true then
        -- when the type of the stream is defined as bytes, simply append the string chunks to the buffer, once the buffer
        -- contains N number of chunks, where the total length of all chunks in the buffer, is greater than the allowed size,
        -- flush the buffer
        local length = 0
        local buffer = self._state.buffer
        for i = 1, self._state.size, 1 do
            length = length + #buffer[i]
        end
        self:_handle_data(chunk, length)
    end
end

function Stream:_handle_stderr(err, chunk)
    if err or not chunk then return end
    self:_handle_stdout(err, chunk)
end

function Stream:_handle_exit(code, chunk)
    local onexit = self._options.onexit
    if code and code == 1 then
        -- ensure that the error is reported to the user in some capacity, that can be useful to debug the state of the command
        -- that was being run and what went wrong.
        self:destroy()
        utils.safe_call(onexit, code, chunk)
    else
        -- on exit make sure that there is nothing more to flush, if there is any size accumulated over the very last call toThe handle
        -- of stdout or stderr, then we need to finally flush it as well, this is to ensure that there is no left over unprocessed data
        -- after the stream has closed
        local callback = self.callback
        if self._state.size > 0 then
            self:_flush_results()
        end
        self:stop()
        utils.safe_call(callback)
        utils.safe_call(onexit, code, chunk)
    end
end

--- Returns true if the stream is currently running, i.e. has been started and not yet stopped or exited, false otherwise
--- @return boolean True if the stream is running, false otherwise
function Stream:running()
    return self._state.handle ~= nil
end

-- Destroys the stream and any pending state that is currently being allocated into the stream, note that this is done automatically for
-- ephemeral streams when a new stream is started the resources for the previous ones are invalidated
function Stream:destroy()
    self:_destroy_stream()
end

--- Stops the stream if it is running, if the stream is ephemeral, also destroys the context and results, if ephemeral is true
function Stream:stop()
    self:_close_stream()
end

--- Waits for the stream to finish, or until the timeout is reached
--- @param timeout integer|nil The maximum time to wait in milliseconds, defaults to the timeout specified in the options, or utils.MAX_TIMEOUT
--- @return string[]|nil The results accumulated so far, or nil if the timeout was reached
function Stream:wait(timeout)
    local done = vim.wait(timeout or self._options.timeout or utils.MAX_TIMEOUT, function()
        return self.results ~= nil
    end, 25, true)

    if not done then
        self:stop()
    end
    return self.results
end

--- @class StreamStartOpts
--- @field cwd? string The current working directory to run the command in, defaults to the current working directory of Neovim
--- @field args? string[] The arguments to pass to the command, defaults to an empty table
--- @field env? string[] The environment variables to set for the command, defaults to nil
--- @field transform? fun(data: string): string|nil A function to transform each line or chunk of data before it is added to the results, defaults to nil
--- @field callback fun(buffer: string[], accum: string[]) A function to be called when new data is available, this function receives two arguments, the first is the current buffer of data, the second is the accumulation of all data so far, this function is required

--- Starts the stream with the given command and options, if a stream is already running it is stopped first, if the new stream is for
--- new command the previous results and state are destroyed.
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
        self:stop()
        if self._options.ephemeral then
            self:destroy()
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
        self._state.buffer = utils.obtain_table(size)
        self._state.buffer = utils.resize_table(
            self._state.buffer, size,
            utils.EMPTY_STRING
        )
    end

    -- the accumulator has to also be pulled form the pool, similarly to the buffer, the accumulator starts with a given size, at
    -- least enough to fit in the first batch of buffer entries, it will however grow further, unlike the buffer
    if not self._state.accum then
        self._state.accum = utils.obtain_table(size)
        self._state.accum = utils.resize_table(
            self._state.accum, size,
            utils.EMPTY_STRING
        )
    end

    if type(cmd) == "function" then
        local did_exit = false
        local callback = function(data)
            if not did_exit and data ~= nil then
                self:_handle_data(
                    data,
                    self._state.size
                )
            else
                assert(not did_exit)
                self:_handle_exit()
                did_exit = true
            end
            Async.yield()
        end
        local executor = Async.wrap(function(stream)
            local ok, err = utils.safe_call(
                cmd, callback, opts.args
            )
            local code = not ok and 1 or 0
            if did_exit == false then
                stream:_handle_exit(code, err)
            end
        end)
        self._state.handle = executor(self)
        Scheduler.add(self._state.handle)
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
        }, vim.schedule_wrap(self:_bind_method(
            Stream._handle_exit
        ))))

        vim.loop.read_start(
            self._state.stdout,
            vim.schedule_wrap(self:_bind_method(
                Stream._handle_stdout
            ))
        )
        vim.loop.read_start(
            self._state.stderr,
            vim.schedule_wrap(self:_bind_method(
                Stream._handle_stderr
            ))
        )
    end

    -- make sure the state is clear for the processing to start from the start
    self._state.total = 0
    self._state.size = 0
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
        ephemeral = true,
        bytes = false,
        lines = true,
        step = 100000,
        onexit = function(code, msg)
            if not code or code == 0 then
                return
            end
            if type(msg) ~= "string" then
                msg = string.format(
                    "%s code: %d",
                    BASEMSG, code
                )
            else
                msg = string.format(
                    "%s: %s and code: %d",
                    BASEMSG, msg, code
                )
            end
            vim.notify(msg, vim.log.levels.ERROR)
        end
    }, opts)

    local self = setmetatable({
        mapper = nil,
        results = nil,
        callback = nil,
        _options = opts,
        _state = {
            size = 0,
            total = 0,
            stdout = nil,
            stderr = nil,
            handle = nil,
            buffer = nil,
            accum = nil,
        },
    }, Stream)

    assert(opts.bytes ~= opts.lines)
    return self
end

return Stream
