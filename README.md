# Fuzzymatch

![picker]()

## Features

- **Fast**: Utilizes the built-in `fuzzymatch` function family for quick fuzzy matching.
- **Non-blocking**: Designed to minimize UI blocking with batching and debouncing.
- **Asynchronous**: Handles large datasets without freezing the UI, ensuring a smooth user experience.
- **Customizable**: Flexible configuration options for various use cases.
- **Interactive**: Real-time filtering as you type for both system executable and user defined streams.
- **Standalone**: No external dependencies, easy to integrate into existing setups.
- **Extensible**: Modular design allows adding new features and sources.
- **Multiselect**: Supports selecting multiple items and performing batch actions.
- **Actions**: Predefined actions for common operations like editing, sending selection to quickfix, etc.
- **Preview**: Predefined previewers allowing previewing common types of resources like files, directories, etc.
- **Decoration**: Predefined decorators enhancing the visual appearance of the items in the list
- **Cross-Platform**: Works on any system with a modern version of Neovim or Vim, does not depend on external binaries.
- **Built-in Sources**: Includes example sources for user-streams, files, buffers, and more.

## Description

A fast and Interactive fuzzy matching interface built on the native `fuzzymatch` family of functions. The plugin is designed to offer a
minimal and modular framework that enables the creation of flexible item pickers capable of operating on arbitrary user-defined data sources
or item lists. Its primary focus is to deliver efficiency, simplicity, and responsiveness using a small set of core components: `Select,
Match, and Stream`. The `Select` component facilitates the user interface by allowing interactive query input, displaying visualized lists
of items, and enabling previews during selection. The `Match` component performs the fuzzy matching operation by identifying the best
results based on the query while working efficiently with the provided item list. The `Stream` component takes care of streaming
user-defined data or streaming stdout/err of executables ensuring handling large datasets is non-blocking.

The Picker components are taking a great deal of effort to prevent UI blocking and user input lag, when the matching is performed by
leveraging input debouncing, processing the user items in batches, grouping results and more. This should in the end help alleviate most
of the traditional issues often connected to built-in fuzzy matchers which do not utilize external tools like `fzf`. The plugin aims to
be an ultra light and performant solution that can be quickly implemented in user configurations, and replace more chunky solutions like
`fzf-lua` or `telescope`. The goal of this plugin is not to implement or have a feature parity match to the aforementioned plugins, rather
we are aiming at giving the core tools necessary to implement most of these features if required or needed

The main goal of this plugin is to provide a fast and performant solution for fuzzy matching entries of up to at least 1 million items, of
any type, regardless of the source, user defined stream or executable command, and to do so in a way that is non-blocking and does not
interfere with the user experience and usability of the editor. Another goal of this plugin is to minimize spawning external processes and
leverage only built-in solutions to filter and match list items (With the exception of course when the executable is a provider of content).

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

### Interaction

By default the picker provides several default action bindings to act and interface with the picker, the following are most of the basic
bindings which are provided out of the box, to perform actions with the picker, those of course can be customized by overriding the
`actions` property, described below

```text
["<cr>"]  = confirm current selection
["<esc>"] = close the picker
["<c-c>"] = hide the picker
["<tab>"] = toggle entry selection
["<c-p>"] = select next entry
["<c-n>"] = select next entry
["<c-k>"] = select prev entry
["<c-j>"] = select prev entry
["<c-f>"] = preview page down
["<c-b>"] = preview page up
["<c-d>"] = preview half page down
["<c-u>"] = preview half page up
["<c-e>"] = preview line down
["<c-y>"] = preview line down
```

Take a good note of the `close` and `hide` actions, those are different and very powerful, when used together, the `hide` action allows you
to hide the current picker away, retaining all of its state, and the picker state can be resumed again at any time by calling `open` method
again on the same instance that was hidden. The `close` action is different and it usually destroys the state of the `picker` instance.
However you can still call `open` on the same picker instance, which would cause the internal state to be re-initialized.

Lets take an example, imagine you have created a picker that shows all files in the current directory, you have done some matching on it and
now you `hide` it, calling `open` on the same picker instance will resume its state exactly as you have left it off. The same list of files
will be visible, the prompt query, the last item that was in under preview, your cursor position in the list and preview windows and so on.

However lets say now you create a new file in this directory, if you keep showing/hiding the picker the new file will not be part of the
list, and now instead of hiding the picker you instead `close` the picker, calling `open` again on the closed picker instance will cause the
underlying content stream to be re-run, the new file that was created will be now part of the list, the old query will of course be lost and
all previous matches and the last item that was under preview.

`Be careful leaving pickers in a hidden state, you should take care of making sure that if a picker remains hidden, at some point if it is
no longer used and never re-opened it is closed or destroyed to avoid retaining persistent state`

### Basic Properties

| Field             | Type                     | Description                                                                                                                                                                                                                                                                                                        |
| ----------------- | ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `content`         | `string,function,table`  | The content for the picker. Can be a string (command), function (generates entries dynamically), or table (static entries). Tables make the picker non-interactive by default. Functions/tables can contain strings or tables (requires a `display` function for extracting).                                      |
| `context`         | `table?`                 | Context to pass to `content`. Includes `cwd` (string), `env` (env vars), `args` (table of args), `map` (function to transform entries from the content stream), and `interactive` (boolean, string, or number to configure interactivity).                                                                         |
| `display`         | `function,string,nil`    | Custom function for displaying entries. If `nil`, the entry itself is displayed. If a string, it’s treated as a key to extract from the entry table. If a function, it is used as a callback which receives the entry as its only input and must return a string                                                   |
| `actions`         | `table?`                 | Key mappings for actions in the picker interface. Specify as `["key"] = callback` OR `["key"] = { callback, label }`. Labels (optional) can be `string` or `function`.                                                                                                                                             |
| `headers`         | `table?`                 | Help or information headers for the prompt interface. Can be a user-provided table or auto-generated based on `actions`.                                                                                                                                                                                           |
| `preview`         | `Select.Preview,boolean` | Configures whether entries generate a preview. Set `false` for none, Or provide an instance of a class sub-classing off of `Select.Preview` such as - `Select.BufferPreview`.                                                                                                                                      |
| `decorators`      | `Select.Decorator[]`     | Table of decorators for the entries. The decoration providers are instances of `Select.Decorators` and by default the Select module provides several built in ones like Select.IconDecorator.                                                                                                                      |
| `match_limit`     | `number?`                | Maximum number of matches. `nil` means no limit. If a valid non nil number value is provided the fuzzy matching will stop the moment this number is reached.                                                                                                                                                       |
| `match_timer`     | `number`                 | Time in milliseconds between processing matching result batches (useful for large result sets).                                                                                                                                                                                                                    |
| `match_step`      | `number`                 | Number of entries to process in each matching step or batch (useful for large result sets).                                                                                                                                                                                                                        |
| `display_step`    | `number`                 | Number of entries rendered in a single batch during display rendering. Useful in combination with `display` for complex or slow `display` functions.                                                                                                                                                               |
| `stream_type`     | `"lines","bytes"`        | Type of the stream content (`lines` splits on newlines, `bytes` splits on byte chunks).                                                                                                                                                                                                                            |
| `stream_step`     | `number`                 | Number of lines, or byte count to read per streaming step determining when to flush the stream items batch, based on the stream content type - lines or bytes.                                                                                                                                                     |
| `stream_debounce` | `number`                 | The time in milliseconds to debounce the flush calls of the stream, this is useful to avoid stream batch flushes in quick succession, when the results accumulate fast enough that we can combine into a single flush call instead, caused by the executable being too fast, or the `stream_step` being too small. |
| `window_size`     | `number`                 | Ratio (0-1) specifying the picker window size relative to the screen.                                                                                                                                                                                                                                              |
| `prompt_debounce` | `number`                 | Debounce time in ms to delay handling input (helps avoid overwhelming the matching process).                                                                                                                                                                                                                       |
| `prompt_query`    | `string`                 | Initial user query for starting the picker prompt with.                                                                                                                                                                                                                                                            |
| `prompt_decor`    | `string,table`           | Prefix/suffix for the prompt. Can take the form of a string (just one) or a table (both) providing a table with `{ suffix = "", prefix = "" }` keys.                                                                                                                                                               |

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
  returns a string. Labels are used to generate headers automatically if no custom headers are provided. By default the picker provides a
  very minimal set of operations

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
  entries, after each batch the `matcher` will wait for `match_timer` milliseconds before processing the next batch. This is useful when dealing
  with large result sets to avoid blocking the UI for too long.

- **match_step**: The number of entries to process in each matching step or batch, the content stream is processed in batches of size
  `match_step`. This should usually be value smaller than `stream_step`, or a value equal to `stream_step`.

- **stream_type**: The type of the stream content. Can be either `lines` or `bytes`. If `lines`, the content is split on newlines. If
  `bytes`, the content is split on byte chunks, both types are restricted by the `stream_step` option, which processes the stream in chunks of
  the specified size.

- **stream_step**: The number of lines/bytes to read per streaming step. This determines when to flush the stream batch. This is useful for
  large data streams to avoid blocking the UI for too long.

- **stream_debounce**: The number of milliseconds between successive stream flush calls, can help if the stream_step is too small or the
  executable is too fast and can accumulate `stream_step` entries into the stream fast enough that can cause the `matcher` to be overwhelmed,
  by default it is set to 0, as for most use cases it is never really required

- **display_step**: The number of entries to render in a single batch during list rendering. This is useful in combination with a complex or
  slow `display` function to avoid blocking the UI for too long. Otherwise all entries passed for rendering are rendered in a single call to
  `nvim_buf_set_lines` once.

- **window_size**: The ratio (0-1) specifying the picker window size relative to the screen. A value of 0.5 means the picker will take up
  half the screen. If the preview is enabled the picker will take up half that height, the rest will be used for the preview window.

- **prompt_debounce**: The debounce time in milliseconds to delay handling input. This helps avoid overwhelming the matching process with
  too many updates in quick succession. A value of 100-200ms is usually a good starting point.

- **prompt_query**: The initial user query to start the picker prompt with. This can be used to pre-fill the prompt with a default value,
  which would also trigger prompt_input automatically

- **prompt_decor**: The prefix/suffix for the prompt. This can be a single string (used as a prefix), or a table providing both a `prefix`
  and `suffix` key. This can be used to add visual cues to the prompt

### In-depth inspection

There are a few key elements which need a bit more attention, when using the picker in different scenarios, these are the actions,
previewers and decorators. And more specifically when using the built-in provided `actions`, `previewers` and `decorators`

The content stream result or in other words the entries which are fed into the picker produced by a stream can be of any type however
certain default and built-in components such as `actions`, `previewers` and `decorators` require a precise entry structure to make use of
them An entry which is to be used within the default `actions`, `previewers` and `decorators` be of only 3 valid distinct types - strings,
tables or a number. The structure of these entries is important as they determine how the picker will handle them specifically in the
default Select.actions and Select.previewers. These entries can be of the following types:

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

The actions are key mappings for the picker interface, they allow the user to interact with the picker in various ways. All actions receive
and are called by default as first argument the `select` instance being acted upon, some of the built-in actions have a second argument
which is a callback, that is usually the converter that is invoked before the actual action execution - like `:edit` a file or buffer,
sending to the quick fix list and so on. The special `Select.default_select` is a no-op action which does nothing, but simply invoke its
callback with the current selection, this is the action entry point that can be used to provide your custom behavior.

```lua
-- Example using the built-in select entry action, which edits a resource into a neovim buffer. As mentioned default actions require a
-- specific structure for the entries, and in this case we ensure that this is the case by adding a converter to the action which takes
-- care of normalizing each entry into a valid structure understood by the internal actions.
actions = {
    ["<cr>"] = Select.action(Select.select_entry, Select.all(function(entries)
        local pat = "^([^:]+):(%d+):(%d+):(.+)$"
        local filename, line_num, col_num = entry:match(pat)
        return {
            filename = filename,
            col = col_num and tonumber(col_num),
            lnum = line_num and tonumber(line_num),
        }
    end))
}

-- As mentioned if a more fine grained control is required, a custom action function can be provided for confirming, however the user has to
-- extract the current selection manually, here we are showing what that might look like
actions = {
    ["<cr>"] = function(select)
        -- we extract the cursor position from the select window, and use that to get the current selection from the list of entries with which
        -- the list is currently populated, closing the interface is optional but it makes sense in most scenarios
        local selection = select:_list_selection()
        select:_close_view(true)
        -- we can now use the selection, which will be a table of 0 or more entries, depending on the selection state, usually
        -- the selection table will contain single item, unless multi select picker is involved.
        vim.print(selection[1])
    end
}
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
entry alone, before any decoration is done, and should return a string or a tuple of string and highlight group, can also return a table of
strings and table of highlight groups. To not include the decorator for the current entry, simply return nil or empty string, and table of
highlight groups, which will be used to prepended to the entry line in the picker interface.

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
to the other sections to see how to configure the picker for different purposes. Most of the time you will need to use the Select and Picker
modules. The Select module provides a number of built-in `previewer, decorator and actions` which can be used as building blocks to make
most types of pickers.

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
    -- tells the picker what preview provider to use, in this case a simple command preview that uses `bat` to display the contents of the
    -- file, again using the grep_converter to properly parse the entry into a tuple of { filename, lnum, col }
    preview = Select.CommandPreview.new({
        "bat",
        "--plain",
        "--paging=never",
    }, grep_converter),
    -- adds default actions to the picker, in this case sending the selected entries to the quickfix list, and opening them in various ways,
    -- again using the grep_converter to properly parse the entry into a tuple of { filename, lnum, col }, on top of that it provides a
    -- `label` for each action which will be displayed in the picker header section as a hint to the user
    actions = {
        ["<cr>"] = Select.action(Select.select_entry, Select.all(grep_converter)),
        ["<c-q>"] = { Select.action(Select.send_quickfix, Select.all(grep_converter)), "qflist" },
        ["<c-t>"] = { Select.action(Select.send_quickfix, Select.all(grep_converter)), "tabe" },
        ["<c-v>"] = { Select.action(Select.send_quickfix, Select.all(grep_converter)), "vert" },
        ["<c-s>"] = { Select.action(Select.send_quickfix, Select.all(grep_converter)), "split" },
    }
    -- tells the picker how to handle user confirmation, using the default selection, with a combination of a custom converter, that
    -- ensures that an entry from the output of ripgrep is properly parsed into a valid tuple of { filename, lnum, col }, as well as
    -- handling multiple selections via the `many` helper function
})
picker:open()
return picker
```

### Static Executable streams

```lua
local picker = Picker.new({
    -- content is an executable program, in this case `ripgrep`, which is used to generate the list of items to be matched against, in
    -- this case a list of all files will be statically obtained form `ripgrep`
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
    -- buffer, again no converter is needed as the output of `ripgrep` is a straight up filename string, no location information to parse
    -- as well.
    preview = Select.BufferPreview.new(),
    -- adds default actions to the picker, in this case sending the selected entries to the quickfix list, and opening them in
    -- various ways, binding directly to the default select actions without additional conversion or parsing
    actions = {
        ["<cr>"] = Select.select_entry,
        ["<c-q>"] = Select.send_quickfix,
        ["<c-t>"] = Select.select_tab,
        ["<c-v>"] = Select.select_vertical,
        ["<c-s>"] = Select.select_horizontal,
    }
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
    -- default selection, in this case is a no op function, which simply prints the current entries selection, this is mostly for demonstration
    -- purposes, in a real world scenario this should be replaced with a proper action that handles the entry.
    actions = {
        ["<cr>"] = Select.action(Select.default_select, Select.all(function(entry)
            print(vim.inspect(entry))
            return entry
        end)),
    },
    -- tells the select how to display the items in the picker, used when the stream represents a complex table like structure this can be a
    -- string key or a function that receives the entry and returns a string. The display will also be used to perform the fuzzy matching on
    -- the entry, in this case matching will be against the name property of the entry
    display = "name",
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
        ["<cr>"] = Select.select_entry,
        ["<c-q>"] = { Select.send_quickfix, "qflist" },
        ["<c-t>"] = { Select.select_tab, "tabe" },
        ["<c-v>"] = { Select.select_vertical, "vert" },
        ["<c-s>"] = { Select.select_horizontal, "split" },
    }
    -- tell the stream how to handle user confirmation, in this case the entry contains valid fields which do not require any
    -- additional parsing or conversion, so we can simply use the default select entry action
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
        -- with it. Note we are returning false, to avoid any further processing. Select.default_select does not do any further
        -- actions, but this is a demonstration on how we can limit the action to only our own handler in this case `choice`
        actions = {
            ["<cr>"] = Select.action(Select.default_select, Select.first(function(entry)
                choice(entry)
                return false
            end)),
            ["<tab>"] = Select.noop_select
        },
    })
    picker:open()
    return picker
end
```

### Advanced ui.select replacement

Below we demonstrate a more advanced replacement for `vim.ui.select`, which includes previewers, decoration providers, as well as additional
actions such as sending the selected entries to the `quickfix` list, a more complex confirm handler allows the select to interact with
multiple items based on the number of entries in the selection

```lua
vim.ui.select = function(items, opts, on_choice)
    local converter = function(entry)
        -- assume that the entry is a string representing a valid filename
        return { filename = entry, lnum = 1, col = 1 }
    end

    local picker = Picker.new({
    -- content is a static table of items, in this case the items passed to the select function can be directly used as an argument to the
    -- picker content
    content = items,
    -- display can be a string key or a function, if opts.format_item is provided it will be used as the display function,
    -- otherwise an entry from the `items` will be interpreted as a plain string
    display = opts and opts.format_item,
    -- add a default entry preview, we pass our own converter to the `BufferPreview` which would ensure that the entry is correctly
    -- converted and prepared to be handled by the built-in previewer
    preview = BufferPreview.new(converter),
    -- adds decoration providers to enhance the selection interface visually, here we are using a simple status provider, that was
    -- demonstrated already above
    decorators = {
        PrefixDecorator.new()
    },
    -- confirm action, in this case we use a custom function that calls the on_choice callback with the selected entry, we use
    -- the default_select action with a custom handler/converter which picks the first selection and calls the on_choice callback
    -- with it adds default actions to the picker, in this case allow sending the selected entries to the quickfix list when confirming
    -- always pick all entries, which would cause all entries to be :edit`ed, if a multi select is active in the picker
    actions = {
        ["<cr>"] = Select.action(Select.select_entry, Select.all(converter)),
        ["<c-q>"] = { Select.action(Select.send_quickfix, Select.all(converter), "qflist" },
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
