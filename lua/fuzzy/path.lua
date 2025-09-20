local SYS_MAPPING = {
    -- map the currently supported main system or platform names
    linux = vim.fn.has("wsl") == 0 and vim.fn.has("linux") == 1,
    windows = vim.fn.has("win64") == 1 or vim.fn.has("win32") == 1,
    unix = vim.fn.has("wsl") == 0 and vim.fn.has("unix") == 1,
    macos = vim.fn.has("mac") == 1,
    wsl = vim.fn.has("wsl") == 1,
}

local M = {}

function M.normalize_base_path(path)
    local norm = vim.fs.normalize(path)
    local simple = vim.fn.simplify(norm)
    local r, _ = string.gsub(simple, '[\\/]+$', '')
    return r
end

function M.check_absolute_path(path)
    if SYS_MAPPING.windows then
        return path:match("^[A-Z]:[/\\]") ~= nil
    else
        return path:match("^[/\\]") ~= nil
    end
end

return M
