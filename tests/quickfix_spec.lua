---@diagnostic disable: invisible
local helpers = require("script.test_utils")

local M = { name = "quickfix" }

function M.run()
    helpers.run_test_case("quickfix_basic", function()
        local dir_path = helpers.create_temp_dir()
        local file_path = vim.fs.joinpath(dir_path, "quickfix.txt")
        helpers.write_file(file_path, "alpha\nbeta\n")
        local buf = helpers.create_named_buffer(file_path, { "alpha", "beta" })
        local item_list = {
            { bufnr = buf, lnum = 1, col = 1, text = "alpha", filename = file_path },
        }
        helpers.with_mock(vim.fn, "getqflist", function()
            return {
                title = "Quickfix",
                items = item_list,
            }
        end, function()
            local qf_picker = require("fuzzy.pickers.quickfix")
            local picker = qf_picker.open_quickfix_picker({
                preview = false,
                icons = false,
                prompt_debounce = 0,
            })
            local highlighters = picker.select:options().highlighters
            helpers.assert_ok(highlighters and #highlighters > 0, "quickfix highlighters")
            local entry = item_list[1]
            helpers.assert_ok(entry ~= nil, "quickfix entry")
            local line = picker.select:options().display(entry, 1)
            helpers.assert_ok(type(line) == "string" and #line > 0, "quickfix line")
            local spans = highlighters[1]:highlight({}, line) or {}
            local span_hls = {}
            for _, span in ipairs(spans) do
                span_hls[span[3]] = true
            end
            helpers.assert_ok(span_hls.Number, "quickfix prefix hl")
            if line:find("%.txt", 1, true) then
                helpers.assert_ok(span_hls.Directory, "quickfix path hl")
            end
            helpers.assert_ok(span_hls.Function, "quickfix name hl")
            helpers.assert_ok(span_hls.Number, "quickfix line hl")
            helpers.assert_ok(span_hls.Comment, "quickfix text hl")
            picker:close()
        end)
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    helpers.run_test_case("quickfix_cwd_visual", function()
        local dir_path = helpers.create_temp_dir()
        local other_dir = helpers.create_temp_dir()
        local file_one = vim.fs.joinpath(dir_path, "one.txt")
        local file_two = vim.fs.joinpath(other_dir, "two.txt")
        helpers.write_file(file_one, "one\n")
        helpers.write_file(file_two, "two\n")
        local buf_one = helpers.create_named_buffer(file_one, { "one" })
        local buf_two = helpers.create_named_buffer(file_two, { "two" })

        helpers.with_mock(vim.fn, "getqflist", function()
            return {
                title = "Quickfix",
                items = {
                    { bufnr = buf_one, lnum = 1, col = 1, text = "one", filename = file_one },
                    { bufnr = buf_two, lnum = 1, col = 1, text = "two", filename = file_two },
                },
            }
        end, function()
            helpers.with_mock(require("fuzzy.utils"), "get_visual_text", function()
                return "one"
            end, function()
                local qf_picker = require("fuzzy.pickers.quickfix")
                local picker = qf_picker.open_quickfix_visual({
                    preview = false,
                    icons = false,
                    cwd = dir_path,
                    prompt_debounce = 0,
                })
                helpers.wait_for_stream(picker)
                helpers.wait_for_list(picker)
                helpers.wait_for_entries(picker)
                    helpers.wait_for_prompt_text(picker, "one")
                helpers.wait_for_prompt_cursor(picker)
                local entries = helpers.get_entries(picker)
                if #entries ~= 1 then
                    error("cwd filtered: " .. tostring(#entries))
                end
                local entry_name = entries[1].filename or ""
                local expected = vim.fs.normalize(file_one)
                helpers.eq(vim.fs.normalize(entry_name), expected, "cwd include")
                picker:close()
            end)
        end)

        vim.api.nvim_buf_delete(buf_one, { force = true })
        vim.api.nvim_buf_delete(buf_two, { force = true })
    end)

    helpers.run_test_case("quickfix_cwd_content_arg", function()
        local Picker = require("fuzzy.picker")
        local captured = nil
        local dir_a = helpers.create_temp_dir()
        local dir_b = helpers.create_temp_dir()
        local file_a = vim.fs.joinpath(dir_a, "a.txt")
        local file_b = vim.fs.joinpath(dir_b, "b.txt")
        helpers.write_file(file_a, "a\n")
        helpers.write_file(file_b, "b\n")
        local buf_a = helpers.create_named_buffer(file_a, { "a" })
        local buf_b = helpers.create_named_buffer(file_b, { "b" })
        helpers.with_mock(vim.fn, "getqflist", function()
            return {
                title = "Quickfix",
                items = {
                    { bufnr = buf_a, lnum = 1, col = 1, text = "a", filename = file_a },
                    { bufnr = buf_b, lnum = 1, col = 1, text = "b", filename = file_b },
                },
            }
        end, function()
            helpers.with_mock(Picker, "new", function(opts)
                captured = opts
                return { _options = opts, open = function() end }
            end, function()
                require("fuzzy.pickers.quickfix").open_quickfix_picker({
                    preview = false,
                    icons = false,
                    cwd = "/should/not/use",
                    prompt_debounce = 0,
                })
            end)
            helpers.assert_ok(captured and captured.content, "content missing")
            local entries = {}
            local content_args = {
                items = vim.fn.getqflist({ items = 1, title = 1 }).items or {},
            }
            captured.content(function(entry)
                if entry ~= nil then
                    entries[#entries + 1] = entry
                end
            end, content_args, dir_a)
            helpers.eq(#entries, 1, "cwd filtered")
            local entry_name = entries[1].filename or ""
            helpers.eq(vim.fs.normalize(entry_name), vim.fs.normalize(file_a), "cwd include")
        end)
        vim.api.nvim_buf_delete(buf_a, { force = true })
        vim.api.nvim_buf_delete(buf_b, { force = true })
    end)
end

return M
