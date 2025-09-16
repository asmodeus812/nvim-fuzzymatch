# Nvim-Fuzzymatch

## Features

- **Fast**: Utilizes built-in `fuzzymatch` functions for quick matching.
- **Preview Support**: Built-in previewers for selected items.
- **Non-blocking**: Designed to minimize UI blocking with batching and debouncing.
- **Asynchronous**: Handles large datasets without freezing the UI, ensuring a smooth user experience.
- **Customizable**: Flexible configuration options for various use cases.
- **Interactive**: Real-time filtering as you type for both system executable and user defined streams.
- **Lightweight**: Minimal dependencies, easy to integrate into existing setups.
- **Extensible**: Modular design allows for easy addition of new features and sources.
- **Multiselect**: Supports selecting multiple items and performing batch actions.
- **Decorators**: Customizable list item entry decorations such as icons or user defined decorators.
- **Action Handlers**: Predefined actions for common operations like editing files, sending to quickfix, etc.
- **Cross-Platform**: Works on any system with a modern version of Neovim or Vim, does not depend on external binaries.
- **Built-in Sources**: Includes example sources for files, buffers, and more.

## Description

A fast and Interactive fuzzy matching interface built on the native `fuzzymatch` functions family of functions. The plugin is designed to
offer a minimal and modular framework that enables the creation of flexible item pickers capable of operating on arbitrary user-defined data
sources or item lists. Its primary focus is to deliver efficiency, simplicity, and responsiveness by leveraging a small set of core
components: Select, Match, and Stream. The `Select` component facilitates the user interface by allowing interactive query input, displaying
visualized lists of items, and enabling previews during selection. The `Match` component performs the fuzzy matching operation by
identifying the best results based on the query while working efficiently with the provided item list. The `Stream` component manages the
dynamic and performant streaming of user-defined data, or stdout/err streaming of executables ensuring seamless handling of even large
datasets in a non-blocking way.

The Picker components are taking a great deal of effort to prevent UI blocking and user input lag, when the matching is performed by
leveraging input debouncing, processing the user items in batches, grouping results and more. This should in the end help alleviate most
of the traditional issues often connected to built-in fuzzy matchers which do not utilize external tools like `fzf`. The plugin aims to
be an ultra light and performant solution that can be quickly implemented in user configurations, and replace more chunky solutions like
`fzf-lua` or `telescope`. The goal of this plugin is not to implement or have a feature parity match to the aforementioned plugins, rather
we are aiming at giving the core tools necessary to implement most of these features if required or needed

The main goal of this plugin is to provide a fast and performant solution for fuzzy matching entries of up to at least 1 million items, of
any type, regardless of the source, user defined stream or executable command, and to do so in a way that is non-blocking and does not
interfere with the user experience and usability of the editor. Another goal of this plugin is to minimize spawning external processes and
leverage only built-in solutions to filter and match list items (With the exception of course when the executable is a provider of content)

## Installation

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'asmodeus812/nvim-fuzzymatch',
  config = function()
    require('fuzzy').setup({})
  end
}
```

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'asmodeus812/nvim-fuzzymatch',
  opts = {
    -- your configuration here
  },
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'asmodeus812/nvim-fuzzymatch'
```

## Configuration

The plugin does require a setup function, that should be called to instantiate the global plugin configuration, at the present moment
there are minimal set of user defined options that can be overridden but that will change in future releases

```lua
require("fuzzy").setup({
    override_select = true -- override the built-in vim.ui.select with custom implementation using the fuzzy picker
})
```

### Basic Properties

| Field             | Type                     | Description                                                                                                                                                                                                                                                                   |
| ----------------- | ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `content`         | `string,function,table`  | The content for the picker. Can be a string (command), function (generates entries dynamically), or table (static entries). Tables make the picker non-interactive by default. Functions/tables can contain strings or tables (requires a `display` function for extracting). |
| `context`         | `table?`                 | Context to pass to `content`. Includes `cwd` (string), `env` (env vars), `args` (table of args), `map` (function to transform entries from the content stream), and `interactive` (boolean, string, or number to configure interactivity).                                    |
| `display`         | `function,string,nil`    | Custom function for displaying entries. If `nil`, the entry itself is displayed. If a string, it’s treated as a key to extract from the entry table. If a function, it is used as a callback which receives the entry as its only input and must return a string              |
| `actions`         | `table?`                 | Key mappings for actions in the picker interface. Specify as `["key"] = callback` OR `["key"] = { callback, label }`. Labels (optional) can be `string` or `function`.                                                                                                        |
| `headers`         | `table?`                 | Help or information headers for the prompt interface. Can be a user-provided table or auto-generated based on `actions`.                                                                                                                                                      |
| `preview`         | `Select.Preview,boolean` | Configures whether entries generate a preview. Set `false` for none, `true` for the `Select.BufferPreview`. A provided child class instance of `Select.Preview` overrides the default behavior.                                                                               |
| `decorators`      | `Select.Decorator[]`     | Table of decorators for the entries. The decoration providers are instances of `Select.Decorators` and by default the Select module provides several built in ones like Select.IconDecorator.                                                                                 |
| `match_limit`     | `number?`                | Maximum number of matches. `nil` means no limit. If a valid non nil number value is provided the fuzzy matching will stop the moment this number is reached.                                                                                                                  |
| `match_timer`     | `number`                 | Time in milliseconds between processing matching result batches (useful for large result sets).                                                                                                                                                                               |
| `match_step`      | `number`                 | Number of entries to process in each matching step or batch (useful for large result sets).                                                                                                                                                                                   |
| `display_step`    | `number`                 | Number of entries rendered in a single batch during display rendering. Useful in combination with `display` for complex or slow `display` functions.                                                                                                                          |
| `stream_type`     | `"lines","bytes"`        | Type of the stream content (`lines` splits on newlines, `bytes` splits on byte chunks).                                                                                                                                                                                       |
| `stream_step`     | `number`                 | Number of lines/bytes to read per streaming step determining when to flush the stream items batch (useful for large data streams).                                                                                                                                            |
| `window_size`     | `number`                 | Ratio (0-1) specifying the picker window size relative to the screen.                                                                                                                                                                                                         |
| `prompt_debounce` | `number`                 | Debounce time in ms to delay handling input (helps avoid overwhelming the matching process).                                                                                                                                                                                  |
| `prompt_confirm`  | `function?`              | A custom callback for user confirmation. If `nil`, default selection is used.                                                                                                                                                                                                 |
| `prompt_query`    | `string`                 | Initial user query for starting the picker prompt with.                                                                                                                                                                                                                       |
| `prompt_decor`    | `string,table`           | Prefix/suffix for the prompt. Can take the form of a string (just one) or a table (both) providing a table with `{ suffix = "", prefix = "" }` keys.                                                                                                                          |

### Detailed Description

- **content**: The content can be a string, function, or table. If it’s a string, it’s treated as an executable command. This is your
  entrypoint into the picker. If it’s a function, it should accept a callback and an `args` table, and call the callback with each entry to
  stream them in. If it’s a table, it should be a static list of entries (strings or tables). Tables require a `display` function to extract
  the display and matching string.

- **context**: The context provides additional information to the content provider. It tells the picker how to run the command (if content
  is a string), what arguments to pass, the working directory, environment variables, and more. The `interactive` field marks the picker as
  interactive if set to `true`, or can be a string(template/placeholder name)/number to specify how to embed the user prompt in the `args`.

- **display**: The display option configures how entries are shown in the picker. It can be a function that takes an entry and returns a
  string, or a string key to extract from the entry table. If `nil`, the entry itself is displayed (works for simple strings). This is also
  the same string used for the fuzzy matching.

- **actions**: Key mappings for actions in the picker interface. This is a table where keys are the keybindings (e.g., `"<CR>"`, `"<C-q>"`)
  and values are either a callback function or a tuple of `{ callback, label }`. The label is optional and can be a string or a function that
  returns a string. Labels are used to generate headers automatically if no custom headers are provided. The action callback signature is the
  same as for prompt_confirm and prompt_cancel

- **decorators**: A table of selection list entry decorators. The decorators govern how the entries are visually decorated - the decorations
  are always inserted in front of the entry line in the list interface. They must of sub-classes of `Select.Decorator`, each decorator must
  override the decorate function which receives the current raw entry as provided by the stream along with the display line for the same entry

- **preview**: Configures whether entries generate a preview. If set to `false`, no preview is shown. If set to `true`, the default
  `Select.BufferPreview` is used. You can also provide a custom instance of a child class of `Select.Preview`. Each previewer must override
  the preview function which receives as single argument the raw entry as it was provided by the stream

- **headers**: Headers are optional lines of text shown at the top of the picker interface. They can provide help or information to the
  user. If not provided, headers can be auto-generated based on the configured actions, that have labels, to give the user hints on how to
  interact with the picker. The headers consists of blocks, each block is separated with a comma, each block can contain multiple lines, each
  block contains the components of a single header block, and must be a table of strings or tuple of string and highlight group, i.e. `{
"Header Text", "HighlightGroup" }`

- **match_limit**: The maximum number of matches to stop after, if `nil` there is no limit and all matches will be kept, the matcher will
  not stop until all entries have been processed.

- **match_timer**: The time in milliseconds between processing match batches, the content stream is processed in batches of `match_step`
  entries, after each batch the matcher will wait for `match_timer` milliseconds before processing the next batch. This is useful when dealing
  with large result sets to avoid blocking the UI for too long.

- **match_step**: The number of entries to process in each matching step or batch, the content stream is processed in batches of size
  `match_step`.

- **stream_type**: The type of the stream content. Can be either `lines` or `bytes`. If `lines`, the content is split on newlines. If
  `bytes`, the content is split on byte chunks, both types are restricted by the `stream_step` option, which processes the stream in chunks of
  the specified size.

- **stream_step**: The number of lines/bytes to read per streaming step. This determines when to flush the stream batch. This is useful for
  large data streams to avoid blocking the UI for too long.

- **display_step**: The number of entries to render in a single batch during list rendering. This is useful in combination with a complex or
  slow `display` function to avoid blocking the UI for too long. Otherwise all entries passed for rendering are rendered in a single call to
  `nvim_buf_set_lines` once.

- **window_size**: The ratio (0-1) specifying the picker window size relative to the screen. A value of 0.5 means the picker will take up
  half the screen. If the preview is enabled the picker will take up half that height, the rest will be used for the preview window.

- **prompt_debounce**: The debounce time in milliseconds to delay handling input. This helps avoid overwhelming the matching process with
  too many updates in quick succession. A value of 100-200ms is usually a good starting point.

- **prompt_confirm**: A custom callback for user confirmation. If `nil`, the default selection action is used. This function should handle
  what happens when the user confirms their selection. The function receives the current Select instance as its first argument, use the
  provided Select actions as a base e.g Select.bind(Select.default_select, custom_handler). default_select will call the custom handler with
  the currently selected items as its argument. If you want more control over the selection provide a direct callback but extracting and
  matching the current entries from the list manually would be required.

- **prompt_query**: The initial user query to start the picker prompt with. This can be used to pre-fill the prompt with a default value,
  which would also trigger prompt_input automatically

- **prompt_decor**: The prefix/suffix for the prompt. This can be a single string (used as a prefix), or a table providing both a `prefix`
  and `suffix` key. This can be used to add visual cues to the prompt

### In-depth inspection

There are a few key elements which need a bit more attention, when using the picker in different scenarios, these are the actions,
previewers and decorators. And more specifically when using the built-in provided `actions`, `previewers` and `decorators`

The content stream result or in other words the entries which are fed into the picker produced by a stream can be of any type however
certain default and built-in components such as `actions` and `previewers` require a precise entry structure to make use of them An entry
which is to be used within the default `actions` and `previewers` be of only 3 valid distinct types - strings, tables or a number. The
structure of these entries is important as they determine how the picker will handle them specifically in the default Select.actions and
Select.previewers. These entries can be of the following types:

- `Numbers` are interpreted and are required to be valid loaded or unloaded buffer number handles in the current neovim instance

- `Strings` they represent a single line of text, and by default they are interpreted as filename, these are required to be valid
  paths to files or directories.

- `Tables`, may be table with a specific structure that contain at least one of the keys - `{ filename = "path-to-file", bufnr = 2 }`,
  optionally `lnum` and `col` fields can also be present to signal a position at which to position the cursor. Similarly if `filename` or
  `bufnr` is provided those are expected to be valid in the current neovim context. The `bufnr` takes precedence over `filename` if both are
  provided.

`If entry is a string or a number, that does not represent a valid file or directory location, or a valid neovim buffer number, that is
considered an invalid entry and will throw and error`

```lua
-- The basic structure of a valid entry is as follows, as returned by the content stream directly or after a conversion if conversion is
-- provided, a converter is required to return a valid entry being one of the following:
local entry = 2                 -- a valid buffer number handle in the current neovim instance
local entry = "path-to-file"    -- a valid path to a file or directory on the file system
local entry = {                 -- a valid entry table, must contain at least one of the following keys
    filename = "path-to-file",  -- required if bufnr is not provided
    bufnr = 2,                  -- required if filename is not provided
    lnum = 10,                  -- optional line number to position the cursor at
    col = 5,                    -- optional column number to position the cursor at
    [other keys...]             -- other keys are allowed and will be ignored by default
}
```

`All entries are normalized to the above table structure before being processed by actions, previewers, this means that if the entry is a
string or a number it will be converted to a table with the appropriate keys, first.`

#### Actions

The actions are key mappings for the picker interface, they allow the user to interact with the picker in various ways, That includes
`prompt_confirm` and `prompt_cancel` which are special actions that are triggered when the user confirms or cancels the selection
respectively, however their signature and internal mode of operation is the same as for any action provided in the `actions` table

```lua
-- Example using the built-in select entry action, which edits a resource into a neovim buffer. As mentioned default actions require a
-- specific structure for the entries, and in this case we ensure that this is the case by adding a converter to the action which takes
-- care of normalizing each entry into a valid structure understood by the internal actions.
prompt_confirm = Select.action(Select.select_entry, Select.all(function(entries)
    local pat = "^([^:]+):(%d+):(%d+):(.+)$"
    local filename, line_num, col_num = entry:match(pat)
    if filename and #filename > 0 then
        return {
            filename = filename,
            col = col_num and tonumber(col_num),
            lnum = line_num and tonumber(line_num),
        }
    end
end))

-- As mentioned if a more fine grained control is required, a custom action function can be provided for prompt_confirm, however the user has to
-- extract the current selection manually, here we are showing what that might look like
prompt_confirm = function(select)
    -- we extract the cursor position from the select window, and use that to get the current selection from the list of entries with which
    -- the list is currently populated, closing the view is optional but it makes sense in most scenarios
    local cursor = vim.api.nvim_win_get_cursor(select.list_window)
    local selection = callback and select:_list_selection(cursor[1])
    select:_close_view()
end
```

The default actions exposed by Select module invoke the user provided custom converter on all selected items, meaning that the first and
only argument will always be a table of `size 1 or N where N is the number of items selected`. This is relevant when more than one items are
selected in a multi selection picker when an action for multi select is bound to the picker like `Select.toggle_entry` usually bound to the
`<tab>` key by default. If no converter is provided to the action, a default converter is used that attempts to convert the entry to a valid
structure, a table with structure as described in the Entries section above to quick fix list, editing a file etc, can be invoked correctly

`A converter function can return false to signal that the conversion did not complete successfully, this will result in no-op for the
executed action, useful if you wish to gracefully cancel or abort action handling for specific cases`

The built-in actions such as `Select.select_entry` and `Select.send_quickfix` and others, can be bound with additional converter function,
as an optional argument by using the `Select.action(Select.select_entry, converter)`, which is used to convert the raw entries into a valid
entries structure before acting upon them, this is useful when the stream entries are not in a valid format for the action to handle
directly. These built-in actions require the same structure as specified for the picker `actions` in the entries section. Otherwise a
default internal converter is used which is the same default converter used for `previewers` (see below) as well, when no converter is
provided to them.

#### Previewers

Are responsible for generating a preview of the currently selected entry, they represent classes sub-classing off of `Select.Preview`,
and must override the preview function which receives two arguments - the raw entry from the entries list to preview and the preview window
handle where the preview will needs to be shown

By default the Select module provides a built-in previewers similarly to the Select actions. These previewers also make use of the same
format for their entries as described above, more precisely the Command and Buffer previewers. However a user might desire to create his own
previewer which would give much more control over how an entry from the stream is displayed

```lua
-- Example of using a built-in previewer with a converter that matches grep entries and parses them into the required table structure. This
-- structure is required by the built-in `SelectBufferPreview` to correctly be able to preview the entry.
preview = Select.BufferPreview.new(function()
    local pat = "^([^:]+):(%d+):(%d+):(.+)$"
    local filename, line_num, col_num = entry:match(pat)
    return {
        filename = filename,
        col = col_num and tonumber(col_num),
        lnum = line_num and tonumber(line_num),
    }
end)

-- Example of a custom previewer which simply echoes the entry in the preview window, this is mostly for demonstration purposes, it is
-- useful to preview complex table entries, that otherwise have a simple display function for fuzzy matching and rendering
local EchoPreviewer = {}
EchoPreviewer.__index = EchoPreviewer
setmetatable(EchoPreviewer, { __index = Select.Preview })

function EchoPreviewer:new()
    local obj = Select.Preview.new()
    setmetatable(obj, Select.EchoPreviewer)
    obj.buf = vim.api.nvim_create_buf(false, true)
    return obj
end

function EchoPreviewer:clean()
    -- do cleanup actions for this previewer, this will ensure that the state of the previewer is destroyed when no longer needed,
    -- be careful as this might invalidate the preview instance for subsequent preview calls
    vim.api.nvim_buf_delete(self.buf, { force = true })
    self.buf = nil
end

function EchoPreviewer:preview(entry, win)
    -- user is responsible for managing the buffer if needed, here we are simply reusing a single buffer and clearing it on each preview call
    -- if the buffer needs to be cleared after the selection interface is closed return the buffer number from the preview function as well
    local lines = type(entry) == "string" and { entry } or vim.split(vim.inspect(entry), "\n")
    vim.api.nvim_win_set_option(win, "wrap", false)
    vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
end
```

The built-in previewers such as `Select.CustomPreview` and `Select.BufferPreview` are accepting a converter as an optional argument, which
is used to convert the raw entry into a valid entry structure before previewing it, this is useful when the stream entries are not in a
valid format for the previewer to handle directly. These previewers require the same structure as specified for the picker `actions` in the
entries section. Otherwise a default internal converter is used which is the same default converter used for `actions` as well, when no
converter is passed to them.

#### Decorators

The decorators are responsible for decorating the entries in the picker interface, they are optional and must be sub-classes of
`Select.Decorator`. They require you to implement the decorate function which receive the current entry and the raw display line, of the
entry alone, before any decoration is done, and should return a string or a tuple of string and highlight group, can also return a table
of strings. To not include the decorator for the current entry, simply return nil or empty string, and table of highlight groups, which
will be used to prepended to the entry line in the picker interface.

```lua
-- Example shows how to add a decorator to the picker, in this case we are using the default one which is provided by the select module.
-- Which requires a converter to be instantiated, the same converter function that can be passed to the `actions` or the `previewer` to
-- obtain a valid entry structure table tuple
decorators = {
    Select.IconDecorator.new(function()
        local pat = "^([^:]+):(%d+):(%d+):(.+)$"
        local filename, line_num, col_num = entry:match(pat)
        return {
            filename = filename,
            col = col_num and tonumber(col_num),
            lnum = line_num and tonumber(line_num),
        }
    end)
}

-- Example of a custom defined user decorator instance, which simply does add a prefix symbol to each entry in the list, notice that the
-- decorate function accepts two arguments, the raw entry form the list as well as the display line of the entry, that is the result of the
-- display function (if any) applied on the entry, and the actual raw line that will represent the entry in the list when it is displayed.
local PrefixDecorator = {}
PrefixDecorator.__index = PrefixDecorator
setmetatable(PrefixDecorator, { __index = Select.Decorator })

function PrefixDecorator.new(converter)
    local obj = Select.Decorator.new()
    setmetatable(obj, PrefixDecorator)
    return obj
end

function PrefixDecorator:clean()
    -- do cleanup actions for this decorator, this might make sense if additional resources were allocated during the decoration computation
    -- or process, take extra care to avoid invaliding the decorator instance for subsequent calls to the decorate method
end

function PrefixDecorator:decorate(entry, line)
    -- add something simple, to each entry, to simply demonstrate what the decoration provider can return from its function, the hl group is
    -- optional and if not provided a default one will be added - `SelectDecoratorDefault`. Returning nil or "" for the decoration text tells
    -- the decorator handler that this decorator is going to be skipped entirely from being added to the final decorated line
    return "[*]", "ErrorMsg"
end
```

The built-in previewers such as `Select.IconDecorator` is accepting a converter as an optional argument, which is used to convert the raw
entry into a valid entry structure before calculating the decorations for it, this is useful when the stream entries are not in a valid
format for the previewer to handle directly. The decorator require the same structure as specified for the picker `actions` in the entries
section. Otherwise a default internal converter is used which is the same default converter used for `actions` or `previewers` well, when no
converter is passed.

## Sources

The internal sources are currently only provided to flex and test the features of the plugin, it is however planned for this plugin to
eventually provide a core set of sources such as - buffers, tabs, user-commands, as well as sources based on system utilities such as
`ripgrep`, find and more.

| Module     | Description                                                                                  |
| ---------- | -------------------------------------------------------------------------------------------- |
| `Files`    | Provides a list of system file and directory related sources and pickers                     |
| `Buffers`  | Provides a list of neovim buffer related sources and pickers                                 |
| `Examples` | Provides a list of example sources and pickers demonstrating the core features of the plugin |

## Basic Usage

The sources provided in the `fuzzy.sources.example` module are purely a collection of examples to demonstrate the features of the internal
core they are not meant to be used in user configurations. Below we provide a few examples of our own, demonstrating the various ways one
can use the plugin to create rich and interactive fuzzy matching pickers.

### Basic Usage

Shows which modules to require to get started with creating a basic picker, the actual configuration of the picker is left out, please refer
to the other sections to see how to configure the picker for different purposes.

```lua
local Select = require("fuzzy.select")
local Picker = require("fuzzy.picker")

local picker = Picker.new({
    -- picker configuration goes here
})
```

### Interactive executable streams

```lua
local picker = Picker.new({
    -- content is an executable program, in this case ripgrep, which is used to generate the list of items to be matched against
    content = "rg",
    -- context tells the picker how to run the executable, what arguments to pass to it, as well as the working directory, and more,
    -- this also marks the picker as interactive, meaning that the user prompt query will be passed to the executable as an argument,
    -- and for every change in the user input the executable will be re-run with the new prompt value. The prompt value is embedded in
    -- the args table as `{prompt}` which will be replaced with the actual user input value.
    context = {
        args = {
            "--column",
            "--line-number",
            "--no-heading",
            "{prompt}",
        },
        cwd = vim.loop.cwd(),
        interactive = "{prompt}",
    },
    -- tells the picker what preview provider to use, in this case a simple command preview that uses `cat` to display the contents of the
    -- files, again using the grep_converter to properly parse the entry into a tuple of { filename, lnum, col }
    preview = Select.CommandPreview.new("cat", grep_converter),
    -- adds default actions to the picker, in this case sending the selected entries to the quickfix list, and opening them in various ways,
    -- again using the grep_converter to properly parse the entry into a tuple of { filename, lnum, col }, on top of that it provides a
    -- `label` for each action which will be displayed in the picker header section as a hint to the user
    actions = {
        ["<c-q>"] = { Select.action(Select.send_quickfix, Select.all(grep_converter)), "qflist" },
        ["<c-t>"] = { Select.action(Select.send_quickfix, Select.all(grep_converter)), "tabe" },
        ["<c-v>"] = { Select.action(Select.send_quickfix, Select.all(grep_converter)), "vert" },
        ["<c-s>"] = { Select.action(Select.send_quickfix, Select.all(grep_converter)), "split" },
    }
    -- tells the picker how to handle user confirmation, using the default selection, with a combination of a custom converter, that
    -- ensures that an entry from the output of ripgrep is properly parsed into a valid tuple of { filename, lnum, col }, as well as
    -- handling multiple selections via the `many` helper function
    prompt_confirm = Select.action(Select.select_entry, Select.all(grep_converter)),
})
picker:open()
return picker
```

### Static Executable streams

```lua
local picker = Picker.new({
    -- content is an executable program, in this case ripgrep, which is used to generate the list of items to be matched against, in
    -- this case a list of all files will be statically obtained form ripgrep
    content = "rg",
    -- context tells the picker how to run the executable, what arguments to pass to it, as well as the working directory, and more,
    -- this is a non-interactive picker, meaning that the command is run only once, and the output is used as the list of items to be
    -- fuzzy matched against. The picker will not have a multi stage option to switch between the interactive command and the fuzzy
    -- matcher.
    context = {
        args = {
            "--files",
            "--hidden",
        },
        cwd = vim.loop.cwd(),
    },
    -- tells the picker what preview provider to use, in this case a simple buffer preview that will open the selected file in a
    -- buffer, again no converter is needed as the output of ripgrep is a straight up filename string, no location information to parse
    -- as well.
    preview = Select.BufferPreview.new(),
    -- adds default actions to the picker, in this case sending the selected entries to the quickfix list, and opening them in
    -- various ways, binding directly to the default select actions without additional conversion or parsing
    actions = {
        ["<c-q>"] = Select.send_quickfix,
        ["<c-t>"] = Select.select_tab,
        ["<c-v>"] = Select.select_vertical,
        ["<c-s>"] = Select.select_horizontal,
    }
    -- tells the picker how to handle user confirmation, in this case using the default select entry action, the output of ripgrep
    -- is a straight up filename string, which will be handled by default, without the need of any converter or parsing, there is also
    -- no location information to parse
    prompt_confirm = Select.select_entry,
})
picker:open()
return picker
```

### Interactive user streams

```lua
local picker = Picker.new({
    content = function(cb, args)
        --- Generate 1 million entries based on the user input, the user input is passed in as the second argument to the content function,
        -- the first, the first argument is a callback which delivers items to the stream, upon completion the callback should be called with
        -- nil to signal the end of the stream. This is not mandatory as the stream will be automatically closed after the functions exits
        -- normally.
        for i = 1, 1000000, 1 do
            -- create an entry from the user input and the current index
            -- send that to the stream via the callback, the stream will
            -- handle batching and grouping of items internally
            cb({ name = string.format("%d-%s-name-entry", i, args[1]) })
        end
        -- terminate the stream, signal to the stream that no more items
        -- will be delivered, this is optional, however it is a good practice
        cb(nil)
    end,
    context = {
        -- arguments that will be passed as the second argument to the content function, here the user prompt is embedded as an entry in the
        -- `args` table which is controlled by the `interactive` option below. The `args` option are shared with an executable based streams
        -- and can contain as many arguments as required
        args = {
            "{prompt}",
        },
        --- both marks this picker as interactive, as well as provides the user input prompt to the content function
        interactive = "{prompt}",
    },
    -- tells the select how to display the items in the picker, used when the stream represents a complex table like structure this can be a
    -- string key or a function that receives the entry and returns a string. The display will also be used to perform the fuzzy matching on
    -- the entry, in this case matching will be against the name property of the entry
    display = "name",
    -- default selection, in this case is a no op function, which simply prints the current entry selection, this is mostly for demonstration
    -- purposes, in a real world scenario this should be replaced with a proper action that handles the entry
    prompt_confirm = Select.action(Select.default_select, Select.all(function(entry)
        print(vim.inspect(entry))
        return entry
    end)),
})
```

### Static user streams

```lua
local buffers = {
    { bufnr = 1, filename = "init.lua", display = "1 init.lua" },
    { bufnr = 2, filename = "select.lua", display = "2 select.lua" },
    { bufnr = 3, filename = "README.md", display = "3 README.md" },
    { bufnr = 4, filename = "CHANGELOG.md", display = "4 CHANGELOG.md" },
    { bufnr = 5, filename = "LICENSE", display = "5 LICENSE" },
}
local picker = Picker.new({
    -- the content is a static table of items, in this case a list of buffers, each buffer is represented as a table with bufnr and
    -- filename
    content = buffers,
    -- context is empty as this is a static stream, there is no need for any additional context to be passed to the stream, the table is
    -- consumed when the picker is started
    context = nil,
    -- tells the select how to display the items in the picker, in this case we simply want to display the display property of the
    -- entry, note that here we are using a function for display instead of a string key, this is to demonstrate that both are
    -- supported, the function receives the entry as an argument and should return a string always
    display = function(e)
        return e.display or e.filename
    end,
    -- the same is true for the preview provider, the entry contains valid fields which do not require any additional parsing or
    -- conversion, so we can simply use the default buffer preview provider
    preview = Select.BufferPreview.new(),
    -- adds default actions to the picker, in this case sending the selected entries to the quickfix list, and opening them in
    -- various ways, again using the default select actions without any additional parsing or conversion, no labels are provided, and
    -- no custom header as well
    actions = {
        ["<c-q>"] = { Select.send_quickfix, "qflist" },
        ["<c-t>"] = { Select.select_tab, "tabe" },
        ["<c-v>"] = { Select.select_vertical, "vert" },
        ["<c-s>"] = { Select.select_horizontal, "split" },
    }
    -- tell the stream how to handle user confirmation, in this case the entry contains valid fields which do not require any
    -- additional parsing or conversion, so we can simply use the default select entry action
    prompt_confirm = Select.select_entry,
})
return picker:open()
```

### Basic ui.select replacement

Override the built-in vim.ui.select function to use a fuzzy picker instead, this is a basic example and can be further customized to
make it more or less complex based on the requirements

```lua
vim.ui.select = function(items, opts, choice)
    local picker = Picker.new({
        -- content is a static table of items, in this case the items passed to the select function can be directly used as an argument to the picker content
        content = items,
        -- display can be a string key or a function, if opts.format_item is provided it will be used as the display function,
        -- otherwise an entry from the `items` will be interpreted as a plain string
        display = opts and opts.format_item,
        -- confirm action, in this case we use a custom function that calls the choice callback with the selected entry, we use
        -- the default_select action with a custom handler/converter which picks the first selection and calls the choice callback
        -- with it
        prompt_confirm = Select.action(Select.default_select, Select.first(function(entry)
            choice(entry)
            return entry
        end)),
    })
    picker:open()
    return picker
end
```

### Advanced ui.select replacement

Below we demonstrate a more advanced replacement for vim.ui.select, which includes decoration providers, as well as additional actions such
as sending the selected entries to the quickfix list, a more complex prompt_confirm handler which converts the selected entry actually binds
to Select.select_entry which would by default edit the selected resource in the source window on top of invoking the choice callback.

```lua
vim.ui.select = function(items, opts, on_choice)
    local picker = Picker.new({
    -- content is a static table of items, in this case the items passed to the select function can be directly used as an argument to the picker content
    content = items,
    -- display can be a string key or a function, if opts.format_item is provided it will be used as the display function,
    -- otherwise an entry from the `items` will be interpreted as a plain string
    display = opts and opts.format_item,
    -- confirm action, in this case we use a custom function that calls the on_choice callback with the selected entry, we use
    -- the default_select action with a custom handler/converter which picks the first selection and calls the on_choice callback
    -- with it
    prompt_confirm = Select.action(Select.select_entry, Select.first(function(entry)
        -- assume that the entry is a string representing a valid filename
        local e = { filename = entry, lnum = 1, col = 1 }
        on_choice(e)
        return e
    end)),
    -- adds default actions to the picker, in this case allow sending the selected entries to the quickfix list
    actions = {
        ["<c-q>"] = { Select.action(Select.send_quickfix, Select.all(function(entry)
            -- assume that the entry is a string representing a valid filename
            return { filename = entry, lnum = 1, col = 1 }
        end), "qflist" },
    },
    -- adds decoration providers to enhance the selection interface visually, here we are using a simple status provider, that was
    -- demonstrated already above
    decorators = {
        PrefixDecorator.new()
    },
```

### Builtin Buffers module

The sources provided in the `fuzzy.sources.buffer` module are mostly experimental, used to demonstrate the features of the internal core
components of the fuzzy matcher.

```lua
require("fuzzy.sources.buffer").buffers({
    -- source configuration goes here
})
```

### Builtin Files module

The sources provided in the `fuzzy.sources.buffer` module are mostly experimental, used to demonstrate the features of the internal core
components of the fuzzy matcher.

```lua
-- list all files in the target directory
require("fuzzy.sources.files").files({
    cwd = vim.loop.cwd()
})

-- list only the directories in target directory
require("fuzzy.sources.files").dirs({
    cwd = vim.loop.cwd()
})

-- list files and directory permissions in target directory
require("fuzzy.sources.files").ls({
    cwd = vim.loop.cwd()
})

-- interactive grep file content within a target directory
require("fuzzy.sources.files").grep({
    cwd = vim.loop.cwd()
})
```

## Requirements

- Neovim 0.11.0 or higher

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the GNU GENERAL PUBLIC LICENSE - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [fzf-lua](https://github.com/ibhagwan/fzf-lua)
- [telescope](https://github.com/nvim-telescope/telescope.nvim)

## Changelog

### [Unreleased]

- Initial core components and sources release

See [CHANGELOG.md](CHANGELOG.md) for full history.
