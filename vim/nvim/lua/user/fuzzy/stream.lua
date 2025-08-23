local utils = require("user.fuzzy.utils")
local uv = vim.loop

local Stream = {}
Stream.__index = Stream

local function close_handle(handle)
    if handle and not handle:is_closing() then
        handle:close()
    end
end

function Stream:_destroy_stream()
    if self._state.buffer then
        utils.return_table(self._state.buffer)
        self._state.buffer = nil
        self._state.size = 0
    end
end

function Stream:_close_stream()
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
        utils.fill_table(
            self._state.buffer,
            utils.EMPTY_STRING
        )
        self._state.size = 0
    end

    if self._state.accum then
        assert(self.results == nil)
        utils.detach_table(self._state.accum)
        self.results = self._state.accum
        self._state.accum = nil
        self._state.total = 0
    end
    self.callback = nil
end

function Stream:_make_stream()
    self._state.stdout = assert(uv.new_pipe(false))
    self._state.stderr = assert(uv.new_pipe(false))
    self._state.total = 0
    self._state.size = 0

    local stdio = {
        nil,
        self._state.stdout,
        self._state.stderr,
    }
    return stdio
end

function Stream:bind_method(method)
    return function(...)
        return method(self, ...)
    end
end

function Stream:_flush_results()
    for i = 1, self._state.size, 1 do
        self._state.accum[self._state.total + i] = self._state.buffer[i]
    end
    self._state.total = self._state.total + self._state.size

    self._state.buffer = utils.resize_table(
        self._state.buffer,
        self._state.size,
        utils.EMPTY_STRING
    )
    self._state.accum = utils.resize_table(
        self._state.accum,
        self._state.total,
        utils.EMPTY_STRING
    )
    utils.safe_call(
        self.callback,
        self._state.accum,
        self._state.buffer
    )
    self._state.size = 0
end

function Stream:_handle_stdout(err, chunk)
    if chunk then
        assert(not err)
        local content
        if self._options.lines == true then
            content = vim.split(chunk, "\n")
            for _, line in ipairs(content) do
                if self._state.size == self._options.step then
                    self:_flush_results()
                elseif line and #line > 0 then
                    self._state.buffer[self._state.size + 1] = line
                    self._state.size = self._state.size + 1
                end
            end
        elseif self._options.bytes == true then
            assert(nil, "not implemented")
            content = chunk
        end
    end
end

function Stream:_handle_stderr(err, chunk)
    if chunk then assert(not err, chunk) end
end

function Stream:_handle_exit()
    local callback = self.callback
    if self._state.size > 0 then
        self:_flush_results()
    end
    self:stop()
    utils.safe_call(callback, nil)
end

function Stream:running()
    return self._state.handle ~= nil
end

function Stream:start(cmd, args, callback)
    self:stop()

    local size = self._options.step
    if not self._state.buffer then
        self._state.buffer = utils.obtain_table(size)
        self._state.buffer = utils.resize_table(
            self._state.buffer, size,
            utils.EMPTY_STRING
        )
    end

    local stdio = self:_make_stream()
    if not self._state.accum then
        self._state.accum = utils.obtain_table(size)
    end
    self.callback = assert(callback)
    self.results = nil

    self._state.handle = assert(uv.spawn(assert(cmd), {
        cwd = vim.fn.getcwd(),
        detached = false,
        args = args or {},
        stdio = stdio,
    }, self:bind_method(Stream._handle_exit)))

    uv.read_start(
        self._state.stdout,
        self:bind_method(
            Stream._handle_stdout
        )
    )

    uv.read_start(
        self._state.stderr,
        self:bind_method(
            Stream._handle_stderr
        )
    )
end

function Stream:stop()
    self:_close_stream()
    if self._options.ephemeral then
        self:_destroy_stream()
    end
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

    return self
end

return Stream
