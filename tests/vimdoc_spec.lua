---@diagnostic disable: invisible
local helpers = require("script.test_utils")

local M = { name = "vimdoc" }

function M.run()
    helpers.run_test_case("vimdoc", function()
        helpers.with_mock(vim.fn, "api_info", function()
            return {
                functions = {
                    {
                        name = "nvim_buf_get_lines",
                        since = 1,
                        return_type = "Array",
                        parameters = { { "Buffer", "buffer" }, { "Integer", "start" } },
                    },
                    {
                        name = "nvim_win_get_cursor",
                        since = 2,
                        return_type = "Array",
                        method = true,
                        parameters = { { "Window", "window" } },
                    },
                    {
                        name = "nvim__private_test",
                        since = 3,
                        return_type = "Array",
                        deprecated_since = 7,
                    },
                    {
                        name = "nvim_buf_get_lines",
                        since = 1,
                        return_type = "Array",
                    },
                },
            }
        end, function()
            local api_picker = require("fuzzy.pickers.vimdoc")
            local picker = api_picker.open_vimdoc_picker({
                preview = false,
                prompt_debounce = 0,
            })
            helpers.wait_for_stream(picker)
            helpers.wait_for_entries(picker)
            helpers.wait_for_line_contains(picker, "nvim_buf_get_lines()")
            helpers.type_query(picker, "win_get")
            helpers.wait_for_stream(picker)
            helpers.wait_for_line_contains(picker, "nvim_win_get_cursor()")
            helpers.assert_line_missing(
                helpers.get_list_lines(picker),
                "nvim__private_test()",
                "private entries filtered by default"
            )
            picker:close()
        end)
    end)

    helpers.run_test_case("vimdoc_filters", function()
        helpers.with_mock(vim.fn, "api_info", function()
            return {
                functions = {
                    { name = "nvim_old_fn", since = 1, deprecated_since = 3 },
                    { name = "nvim_new_fn", since = 10 },
                    { name = "vim_old_fn",  since = 2, deprecated_since = 5 },
                },
            }
        end, function()
            local api_picker = require("fuzzy.pickers.vimdoc")
            local picker = api_picker.open_vimdoc_picker({
                preview = false,
                prompt_debounce = 0,
                deprecated_only = true,
                prefix = false,
            })
            helpers.wait_for_stream(picker)
            helpers.wait_for_entries(picker)
            helpers.assert_line_contains(helpers.get_list_lines(picker), "nvim_old_fn()", "deprecated shown")
            helpers.assert_line_contains(helpers.get_list_lines(picker), "vim_old_fn()", "non-prefix shown")
            helpers.assert_line_missing(helpers.get_list_lines(picker), "nvim_new_fn()", "non-deprecated hidden")
            picker:close()
        end)
    end)

    helpers.run_test_case("vimdoc_help_content", function()
        local original_rtp = vim.o.runtimepath
        local original_helplang = vim.o.helplang
        local dir_path = helpers.create_temp_dir()
        local doc_dir = vim.fs.joinpath(dir_path, "doc")
        vim.uv.fs_mkdir(doc_dir, 448)
        helpers.write_file(vim.fs.joinpath(doc_dir, "help.txt"), {
            "*nvim_buf_get_lines*",
            "vimdoc preview content",
        })
        helpers.write_file(vim.fs.joinpath(doc_dir, "tags"), {
            "nvim_buf_get_lines\thelp.txt\t/^nvim_buf_get_lines$/",
        })
        vim.o.runtimepath = dir_path
        vim.o.helplang = "en"
        local ok, err = pcall(function()
            helpers.with_mock(vim.fn, "api_info", function()
                return {
                    functions = {
                        {
                            name = "nvim_buf_get_lines",
                            since = 9,
                            return_type = "Array",
                            method = false,
                            parameters = { { "Buffer", "buffer" }, { "Integer", "start" } },
                        },
                    },
                }
            end, function()
                local api_picker = require("fuzzy.pickers.vimdoc")
                local picker = api_picker.open_vimdoc_picker({
                    preview = false,
                    prompt_debounce = 0,
                })
                helpers.wait_for(function()
                    return picker.stream and picker.stream:running()
                end, 1500)
                helpers.wait_for_stream(picker)
                helpers.wait_for_entries(picker)
                picker.select._options.mappings["<cr>"](picker.select)
                helpers.wait_for(function()
                    local buf = vim.api.nvim_get_current_buf()
                    if vim.bo[buf].filetype ~= "help" then
                        return false
                    end
                    local lines = helpers.get_buffer_lines(buf)
                    for _, line in ipairs(lines or {}) do
                        if line:find("vimdoc preview content", 1, true) then
                            return true
                        end
                    end
                    return false
                end, 1500)
            end)
        end)
        vim.o.runtimepath = original_rtp
        vim.o.helplang = original_helplang
        if not ok then
            error(err)
        end
    end)

    helpers.run_test_case("vimdoc_action", function()
        helpers.with_mock(vim.fn, "api_info", function()
            return {
                functions = {
                    { name = "nvim_buf_get_lines", since = 1 },
                },
            }
        end, function()
            helpers.with_cmd_capture(function(calls)
                local api_picker = require("fuzzy.pickers.vimdoc")
                local picker = api_picker.open_vimdoc_picker({
                    preview = false,
                    prompt_debounce = 0,
                })
                helpers.wait_for_stream(picker)
                helpers.wait_for_list(picker)
                helpers.wait_for_entries(picker)
                local map = picker.select._options.mappings
                map["<cr>"](picker.select)
                local saw_help = false
                for _, call in ipairs(calls) do
                    local arg = call.args and call.args[1] or nil
                    if type(arg) == "table" and arg.cmd == "help" then
                        saw_help = true
                    end
                end
                helpers.assert_ok(saw_help, "help cmd")
            end)
        end)
    end)

    helpers.run_test_case("vimdoc_preview_content", function()
        helpers.with_mock(vim.fn, "api_info", function()
            return {
                functions = {
                    {
                        name = "nvim_deprecated_fn",
                        since = 2,
                        return_type = "Array",
                        deprecated_since = 5,
                        parameters = { { "Buffer", "buffer" } },
                    },
                },
            }
        end, function()
            local api_picker = require("fuzzy.pickers.vimdoc")
            local picker = api_picker.open_vimdoc_picker({
                preview = true,
                prompt_debounce = 0,
            })
            helpers.wait_for_stream(picker)
            helpers.wait_for_entries(picker)
            helpers.wait_for_list(picker)
            helpers.wait_for_line_contains(picker, "nvim_deprecated_fn()")
            local previewer = picker.select._options.preview
            local entries = helpers.get_entries(picker)
            local entry = entries and entries[1] or nil
            helpers.assert_ok(
                previewer and type(previewer.callback) == "function",
                "previewer callback"
            )
            helpers.assert_ok(entry ~= nil, "preview entry")
            local ok, lines = pcall(previewer.callback, entry)
            helpers.assert_ok(ok and type(lines) == "table", "preview lines")
            local preview_dump = table.concat(lines or {}, "\\n")
            helpers.assert_ok(
                lines[1] == "Deprecated since: 5",
                "deprecated first line: " .. tostring(lines[1]) .. "\\n" .. preview_dump
            )
            helpers.assert_ok(
                lines[2] == "nvim_deprecated_fn()",
                "tag line: " .. tostring(lines[2]) .. "\\n" .. preview_dump
            )
            helpers.assert_ok(
                lines[3] == "Signature: nvim_deprecated_fn(Buffer buffer) -> Array",
                "signature line: " .. tostring(lines[3]) .. "\\n" .. preview_dump
            )
            helpers.assert_ok(
                lines[4] == "Return:    Array",
                "return line: " .. tostring(lines[4]) .. "\\n" .. preview_dump
            )
            helpers.assert_ok(
                lines[5] == "Since:     2",
                "since line: " .. tostring(lines[5]) .. "\\n" .. preview_dump
            )
            helpers.assert_ok(
                lines[6] == "Parameters:",
                "params header: " .. tostring(lines[6]) .. "\\n" .. preview_dump
            )
            helpers.assert_ok(
                lines[7] == "  - Buffer buffer",
                "param line: " .. tostring(lines[7]) .. "\\n" .. preview_dump
            )
            helpers.assert_ok(
                lines[#lines] and lines[#lines]:find("Press <CR> to open :help", 1, true),
                "footer line"
            )
            picker:close()
        end)
    end)
end

return M
