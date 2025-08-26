local utils = require("user.fuzzy.utils")
local async = require("user.fuzzy.async")

--- @class Stream
--- @field results string[]|nil The results accumulated so far, this is only valid after the stream has finished, or if the stream is ephemeral and a new stream has not yet started.
--- @field callback fun(buffer: string[], accum: string[]) The callback to be invoked when new data is available, this is only valid when the stream is running.
--- @field _options table The options for the stream.
--- @field _state table The internal state of the stream.
--- @field _state.size integer The current size of the buffer.
--- @field _state.total integer The total number of items accumulated so far.
--- @field _state.stdout userdata|nil The stdout pipe of the stream.
--- @field _state.stderr userdata|nil The stderr pipe of the stream.
--- @field _state.handle userdata|nil The handle of the stream.
--- @field _state.buffer string[]|nil The buffer to hold the current batch of data.
--- @field _state.accum string[]|nil The accumulator to hold all the data accumulated so far.
local Stream = {}
Stream.__index = Stream

local function close_handle(handle)
    if handle and not handle:is_closing() then
        handle:close()
    end
end

function Stream:_destroy_results()
    -- the results can be re-claimed back into the pool, when a new stream is starting up, this ensures that old references to the
    -- _state.accum which are now pointing to stream.results are re-used.
    if self.results then
        self.results = utils.fill_table(
            self.results,
            utils.EMPTY_STRING
        )
        utils.attach_table(self.results)
        utils.return_table(self.results)
        self.results = nil
    end
end

function Stream:_destroy_context()
    if self._state.buffer then
        -- make sure that the buffer itself is also returned back to the pool, this will ensure that future stream instances, or this
        -- one can pick it from the pool and use it.
        utils.return_table(self._state.buffer)
        self._state.buffer = nil
        self._state.size = 0
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
        -- we do not want to return the buffer back to the pool, just clean up the string references to avoid any memory leaks, the
        -- buffer could still be reused in future calls to start new streams, see `ephemeral`
        utils.fill_table(
            self._state.buffer,
            utils.EMPTY_STRING
        )
        self._state.size = 0
    end

    if self._state.accum then
        -- the accumulator must be detached from the pool, as closing the stream now implies no more results will come in, this frees
        -- the accumulator from the pool, allowing users to use the results as they see fit, through stream.results.
        utils.detach_table(self._state.accum)
        self.results = self._state.accum
        self._state.accum = nil
        self._state.total = 0
    end
    self.callback = nil
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
    if type(self._options.transform) == "function" then
        return self._options.transform(data)
    end
    return data
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

function Stream:_handle_stdout(err, chunk)
    if err or not chunk then return end
    if self._options.lines == true then
        -- when the type of stream is defined as lines, split the output based on new lines, this might produce some empty lines
        -- which are filtered afterwards.
        local content = vim.split(chunk, "\n")
        for _, line in ipairs(content) do
            if self._state.size == self._options.step then
                -- when the size has reached the maximum allowed, flush the buffer, and send it over for processing to
                -- the user provided callback
                self:_flush_results()
            end

            line = self:_transform_data(line)
            if line and #line > 0 then
                -- keep accumulating non blank lines into the buffer, eventually the buffer size will be enough to be
                -- flushed, see above
                self._state.buffer[self._state.size + 1] = line
                self._state.size = self._state.size + 1
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
        if length >= self._options.step then
            -- the length is more than the size so we flush the buffer, note that this might flush more bytes than the size,
            -- we have intentionally not strictly clamped the buffer to the allowed size to avoid extra string re-allocation
            -- and copying.
            self:_flush_results()
        end

        chunk = self:_transform_data(chunk)
        if chunk and #chunk > 0 then
            -- keep adding the chunks that are non empty to the buffer eventually the buffer will contain enough chunks
            -- whose total length exeeds or equals the maximum allowed size
            self._state.buffer[self._state.size + 1] = chunk
            self._state.size = self._state.size + 1
        end
    end
end

function Stream:_handle_stderr(err, chunk)
    -- handle stderr, some processes output on stderr instead of stdout, and should also be handled
    if chunk then assert(not err, chunk) end
end

function Stream:_handle_exit()
    local callback = self.callback
    -- on exit make sure that there is nothing more to flush, if there is any size accumulated over the very last call toThe handle
    -- of stdout or stderr, then we need to finally flush it as well, this is to ensure that there is no left over unprocessed data
    -- after the stream has closed
    if self._state.size > 0 then
        self:_flush_results()
    end
    self:stop()
    utils.safe_call(callback)
end

function Stream:running()
    return self._state.handle ~= nil
end

function Stream:stop()
    -- close the stream handles, and if the stream is ephemeral, also destroy the context and results, this would invalidate any
    -- references that the user might hold.
    self:_close_stream()
    if self._options.ephemeral then
        self:_destroy_context()
        self:_destroy_results()
    end
end

function Stream:wait(timeout)
    -- wait util results are available, or the timeout expires, if the timeout expires the stream is stopped and whatever
    -- results are available are returned
    local done = vim.wait(timeout or self._options.timeout or utils.MAX_TIMEOUT, function()
        return self.results ~= nil
    end, nil, true)

    if not done then
        self:stop()
    end
    return self.results
end

--- @class StreamStartOpts
--- @field args? string[] The arguments to pass to the command
--- @field env? table The environment variables to set for the command
--- @field callback fun(buffer: string[], accum: string[]) The callback to invoke when new data is available, this is required

--- @param cmd string|function The command to run, or a function which accepts a callback to be invoked with data chunks to supply data to the stream
--- @param opts StreamStartOpts|nil The options for starting the stream
function Stream:start(cmd, opts)
    opts = opts or {}
    self:stop()

    -- prepare the state, make sure to re-claim state if it can be done
    self.callback = assert(opts.callback)

    -- based on the type of the stream the step either governs how many bytes to read, or how many lines into the buffer before
    -- flushing
    local size = self._options.lines and self._options.step

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
        local callback = function(data)
            self:_handle_stdout(nil, data)
            async.yield()
        end
        local executor = async.wrap(function()
            utils.safe_call(cmd, callback)
            self:_handle_exit()
        end)
        executor()
    else
        local stdio = self:_make_stream()

        -- crreate the handles for the stream, and bind
        self._state.handle = assert(vim.loop.spawn(assert(cmd), {
            cwd = vim.fn.getcwd(),
            args = opts.args or {},
            detached = false,
            env = opts.env,
            stdio = stdio,
        }, vim.schedule_wrap(self:_bind_method(
            Stream._handle_exit
        ))))

        -- start reading from the stdout/err pipes attached to the stream
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
    return self
end

function Stream.new(opts)
    opts = vim.tbl_deep_extend("force", {
        ephemeral = true,
        bytes = false,
        lines = true,
        step = 100000,
    }, opts or {})

    local self = setmetatable({
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
