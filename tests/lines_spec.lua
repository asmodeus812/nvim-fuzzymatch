---@diagnostic disable: invisible
local helpers = require("tests.helpers")

local M = { name = "lines" }

function M.run()
    helpers.run_test_case("lines", function()
        local buf_one = helpers.create_named_buffer("line_one.txt", {
            "alpha line",
            "beta line",
        })
        local buf_two = helpers.create_named_buffer("line_two.txt", {
            "gamma line",
        })
        vim.api.nvim_set_current_buf(buf_one)

        local lines_picker = require("fuzzy.pickers.lines")
        local picker = lines_picker.open_lines_picker({
            preview = false,
            show_unlisted = true,
            show_unloaded = true,
            prompt_debounce = 0,
        })

        helpers.wait_for_list(picker)
        helpers.wait_for_line_contains(picker, "line_one.txt")
        helpers.wait_for_line_contains(picker, "alpha line")
        helpers.wait_for_line_contains(picker, "line_two.txt")
        helpers.wait_for_line_contains(picker, "gamma line")

        local prompt_input = picker.select._options.prompt_input
        assert(type(prompt_input) == "function")
        --- @cast prompt_input fun(string)
        prompt_input("gamma")
        helpers.wait_for_line_contains(picker, "gamma line")
        picker:close()

        vim.api.nvim_buf_delete(buf_two, { force = true })
        vim.api.nvim_buf_delete(buf_one, { force = true })
    end)

    helpers.run_test_case("lines_ignore_current", function()
        local buf_one = helpers.create_named_buffer("line_ignore.txt", {
            "ignore me",
        })
        local buf_two = helpers.create_named_buffer("line_keep.txt", {
            "keep me",
        })
        vim.api.nvim_set_current_buf(buf_one)

        local lines_picker = require("fuzzy.pickers.lines")
        local picker = lines_picker.open_lines_picker({
            preview = false,
            show_unlisted = true,
            show_unloaded = true,
            ignore_current_buffer = true,
            prompt_debounce = 0,
        })

        helpers.wait_for_list(picker)
        helpers.assert_line_missing(helpers.get_list_lines(picker), "ignore me", "ignore current")
        helpers.wait_for_line_contains(picker, "line_keep.txt")
        helpers.wait_for_line_contains(picker, "keep me")
        picker:close()

        vim.api.nvim_buf_delete(buf_two, { force = true })
        vim.api.nvim_buf_delete(buf_one, { force = true })
    end)

    helpers.run_test_case("lines_word_visual", function()
        local buf = helpers.create_named_buffer("line_word.txt", {
            "alpha line",
        })
        vim.api.nvim_set_current_buf(buf)

        helpers.with_mock(vim.fn, "expand", function()
            return "alpha"
        end, function()
            local lines_picker = require("fuzzy.pickers.lines")
            local picker = lines_picker.open_lines_word({
                preview = false,
                show_unlisted = true,
                show_unloaded = true,
                prompt_debounce = 0,
            })
            helpers.wait_for(function()
                return helpers.get_query(picker) == "alpha"
            end, 1500)
            helpers.wait_for_prompt_cursor(picker)
            picker:close()
        end)

        helpers.with_mock(require("fuzzy.utils"), "get_visual_text", function()
            return "line"
        end, function()
            local lines_picker = require("fuzzy.pickers.lines")
            local picker = lines_picker.open_lines_visual({
                preview = false,
                show_unlisted = true,
                show_unloaded = true,
                prompt_debounce = 0,
            })
            helpers.wait_for(function()
                return helpers.get_query(picker) == "line"
            end, 1500)
            helpers.wait_for_prompt_cursor(picker)
            picker:close()
        end)

        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    helpers.run_test_case("lines_cwd_content_arg", function()
        local Picker = require("fuzzy.picker")
        local captured = nil
        helpers.with_mock(Picker, "new", function(opts)
            captured = opts
            return { _options = opts, open = function() end }
        end, function()
            require("fuzzy.pickers.lines").open_lines_picker({
                show_unlisted = true,
                show_unloaded = true,
                preview = false,
                cwd = "/should/not/use",
            })
        end)
        helpers.assert_ok(captured and captured.content, "content missing")
        local dir_a = helpers.create_temp_dir()
        local dir_b = helpers.create_temp_dir()
        local path_a = vim.fs.joinpath(dir_a, "a.txt")
        local path_b = vim.fs.joinpath(dir_b, "b.txt")
        helpers.write_file(path_a, "alpha\n")
        helpers.write_file(path_b, "beta\n")
        local buf_a = helpers.create_named_buffer(path_a, { "alpha" }, true)
        local buf_b = helpers.create_named_buffer(path_b, { "beta" }, true)
        vim.api.nvim_set_current_buf(buf_a)

        local entries = {}
        captured.content(function(entry)
            if entry ~= nil then
                entries[#entries + 1] = entry
            end
        end, { buf = buf_a }, dir_a)

        local found_a = false
        local found_b = false
        for _, entry in ipairs(entries) do
            if entry.bufnr == buf_a then
                found_a = true
            elseif entry.bufnr == buf_b then
                found_b = true
            end
        end
        helpers.assert_ok(found_a, "cwd lines missing")
        helpers.assert_ok(not found_b, "other lines present")
    end)

    helpers.run_test_case("lines_cwd_filter_and_preview", function()
        local dir_one = helpers.create_temp_dir()
        local dir_two = helpers.create_temp_dir()
        local file_one = vim.fs.joinpath(dir_one, "cwd_line.txt")
        local file_two = vim.fs.joinpath(dir_two, "other_line.txt")
        helpers.write_file(file_one, { "alpha line", "beta line" })
        helpers.write_file(file_two, { "gamma line" })

        local buf_one = helpers.create_named_buffer(file_one, {
            "alpha line",
            "beta line",
        })
        local buf_two = helpers.create_named_buffer(file_two, {
            "gamma line",
        })
        vim.api.nvim_set_current_buf(buf_one)

        helpers.with_cwd(dir_one, function()
            local lines_picker = require("fuzzy.pickers.lines")
            local picker = lines_picker.open_lines_picker({
                preview = true,
                cwd = true,
                show_unlisted = true,
                show_unloaded = true,
                prompt_debounce = 0,
            })
            helpers.wait_for_list(picker)
            helpers.wait_for_line_contains(picker, "cwd_line.txt")
            helpers.wait_for_line_contains(picker, "alpha line")
            helpers.assert_line_missing(helpers.get_list_lines(picker), "other_line.txt", "cwd filter")
            helpers.assert_line_missing(helpers.get_list_lines(picker), "gamma line", "cwd filter")

            helpers.wait_for(function()
                local buf = picker.select.preview_buffer
                local lines = helpers.get_buffer_lines(buf, 0, 1)
                return lines and #lines > 0 and lines[1]:find("alpha line", 1, true)
            end, 1500)
            picker:close()
        end)

        vim.api.nvim_buf_delete(buf_two, { force = true })
        vim.api.nvim_buf_delete(buf_one, { force = true })
    end)

    helpers.run_test_case("lines_include_special_true", function()
        local Picker = require("fuzzy.picker")
        local captured = nil
        helpers.with_mock(Picker, "new", function(opts)
            captured = opts
            return { _options = opts, open = function() end }
        end, function()
            require("fuzzy.pickers.lines").open_lines_picker({
                include_special = true,
                show_unlisted = true,
                show_unloaded = true,
                preview = false,
            })
        end)
        local normal_path = vim.fs.joinpath(helpers.create_temp_dir(), "normal.txt")
        helpers.write_file(normal_path, "normal\n")
        local normal_buf = helpers.create_named_buffer(normal_path, { "normal line" }, true)
        local special_buf = helpers.create_named_buffer("", { "special line" }, true)
        vim.bo[special_buf].buftype = "nofile"
        local entries = {}
        captured.content(function(entry)
            if entry ~= nil then
                entries[#entries + 1] = entry
            end
        end, { buf = normal_buf }, nil)
        local found_special = false
        for _, entry in ipairs(entries) do
            if entry.bufnr == special_buf then
                found_special = true
                break
            end
        end
        helpers.assert_ok(found_special, "special lines missing")
        vim.api.nvim_buf_delete(special_buf, { force = true })
        vim.api.nvim_buf_delete(normal_buf, { force = true })
    end)

    helpers.run_test_case("lines_include_special_table", function()
        local Picker = require("fuzzy.picker")
        local captured = nil
        helpers.with_mock(Picker, "new", function(opts)
            captured = opts
            return { _options = opts, open = function() end }
        end, function()
            require("fuzzy.pickers.lines").open_lines_picker({
                include_special = { "nofile" },
                show_unlisted = true,
                show_unloaded = true,
                preview = false,
            })
        end)
        local term_buf = helpers.create_named_buffer("", { "nofile line" }, true)
        vim.bo[term_buf].buftype = "nofile"
        local qf_buf = helpers.create_named_buffer("", { "prompt line" }, true)
        vim.bo[qf_buf].buftype = "prompt"
        local entries = {}
        captured.content(function(entry)
            if entry ~= nil then
                entries[#entries + 1] = entry
            end
        end, { buf = term_buf }, nil)
        local found_term = false
        local found_qf = false
        for _, entry in ipairs(entries) do
            if entry.bufnr == term_buf then
                found_term = true
            elseif entry.bufnr == qf_buf then
                found_qf = true
            end
        end
        helpers.assert_ok(found_term, "nofile lines missing")
        helpers.assert_ok(not found_qf, "prompt lines should be filtered")
        vim.api.nvim_buf_delete(term_buf, { force = true })
        vim.api.nvim_buf_delete(qf_buf, { force = true })
    end)
end

return M
