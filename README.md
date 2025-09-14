# Plugin Name

A fast interactive built-in fuzzy matching interface which utilizes the built-in `fuzzymatch` and family of functions which vim and
neovim both implement. The goal of this plugin is to provide a small set of core components which can be used to create any type of
picker based on an arbitrary user defined set of entries or a list of items.

To use the fuzzy match functionality, one needs to first setup a picker, a picker comprises of a few core components - Select, Match and
Stream. These 3 components drive the internal workings of the Picker. The Select components is purely used to allow the user to
interactively provide a query or a prompt and visualize a list of arbitrary items, as well as preview them. The Match component is used
to pick fuzzy search for the best matches within a list of arbitrary user provided list of items. The Stream component is responsible
for supplying user defined items in an efficient and performant way.

The Picker components are taking a great deal of effort to prevent UI blocking and user input lag, when the matching is performed by
leveraging input debouncing, processing the user items in batches, grouping results and more. This should in the end help alleviate most
of the traditional issues often connected to built-in fuzzy matchers which do not utilize external tools like `fzf`. The plugin aims to
be an ultra light and performant solution that can be quickly implemented in user configurations, and replace more chunky solutions like
`fzf-lua` or `telescope`. The goal of this plugin is not to implement or have a feature parity match to the aforementioned plugins, rather
we are aiming at giving the core tools necessary to implement most of these features if required or needed

## Features

- \*\*\*\*:
- **Feature 1**: Description of what this feature does
- **Feature 2**: Description of what this feature does
- **Feature 3**: Description of what this feature does
- **Feature 4**: Description of what this feature does

## Installation

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'asmodeus812/nvim-fuzzymatch',
  config = function()
    require('plugin-name').setup()
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
there are no user defined options that can be overridden but that will change in future releases

```lua
require("fuzzy").setup({
    -- customize user options
})
```

| Option              | Type                              | Default    | Description                                                                                                                                                                                                                                                                  |
| ------------------- | --------------------------------- | ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **content**         | `string` \| `function` \| `table` | _Required_ | Content source - command string, callback function, or static table. Strings/functions stream content; tables are static. Tables/functions can contain strings or complex entries (requires `display` function).                                                             |
| **context**         | `table` \| `nil`                  | `nil`      | Context for content function with keys: `cwd` (string), `env` (table), `args` (table), `map` (function), `interactive` (boolean \| string \| number \| nil). `map` transforms entries before streaming (return `nil` to skip). `interactive` enables query-restart behavior. |
| **display**         | `function` \| `string` \| `nil`   | `nil`      | Custom display function or key string to extract display text from entries. Used for both display and matching.                                                                                                                                                              |
| **headers**         | `table` \| `nil`                  | `nil`      | Help/information headers displayed in prompt. Auto-generated from labeled `actions` if present.                                                                                                                                                                              |
| **ephemeral**       | `boolean`                         | `false`    | Destroy picker when closed if `true`.                                                                                                                                                                                                                                        |
| **match_limit**     | `number` \| `nil`                 | `nil`      | Maximum matches to keep (`nil` = no limit).                                                                                                                                                                                                                                  |
| **match_timer**     | `number`                          | _Varies_   | Milliseconds to wait before flushing matches (useful for large datasets).                                                                                                                                                                                                    |
| **match_step**      | `number`                          | _Varies_   | Entries to process per matching step (useful for large datasets).                                                                                                                                                                                                            |
| **prompt_preview**  | `Select.Preview` \| `boolean`     | `true`     | Preview strategy on focus. `false` = no preview, `true` = default `Select.BufferPreview`, custom preview instance for specialized behavior.                                                                                                                                  |
| **prompt_debounce** | `number`                          | _Varies_   | Milliseconds to debounce user input (prevents flooding).                                                                                                                                                                                                                     |
| **prompt_confirm**  | `function` \| `nil`               | `nil`      | Custom confirmation function (replaces default action).                                                                                                                                                                                                                      |
| **prompt_decor**    | `string`                          | `""`       | Prompt prefix decoration.                                                                                                                                                                                                                                                    |
| **prompt_query**    | `string`                          | `""`       | Initial query value.                                                                                                                                                                                                                                                         |
| **stream_type**     | `"lines"` \| `"bytes"`            | `"lines"`  | Stream content type - split on newlines (`"lines"`) or byte size (`"bytes"`).                                                                                                                                                                                                |
| **stream_step**     | `number`                          | _Varies_   | Bytes/lines to read per streaming step (useful for large datasets).                                                                                                                                                                                                          |
| **window_size**     | `number`                          | `0.8`      | Picker window size ratio (0-1, where 1 = full screen).                                                                                                                                                                                                                       |
| **actions**         | `table`                           | `{}`       | Key-action mappings. Syntax: `["key"] = callback` or `["key"] = {callback, label}`. Labels (string/function) auto-generate headers if enabled.                                                                                                                               |
| **providers**       | `table`                           | `{}`       | Icon/status providers (see `Select.providers`).                                                                                                                                                                                                                              |

## Usage

### Basic Usage

```lua
local Select = require("fuzzy.select")
local Picker = require("fuzzy.picker")

local picker = Picker.new({
    -- picker configuration goes here
})
```

### Sources

The internal sources are currently only provided to flex and test the features of the plugin, it is however planned for this plugin to
eventually provide a core set of sources such as - buffers, tabs, user-commands, as well as sources based on system utilities such as
ripgrep, find and more.

| Command   | Description                                                              |
| --------- | ------------------------------------------------------------------------ |
| `Buffers` | Provides a list of neovim buffer related sources and pickers             |
| `Files`   | Provides a list of system file and directory related sources and pickers |

#### Buffers

The sources provided in the `fuzzy.sources.buffer` module are mostly experimental, used to demonstrate the features of the internal core
components of the fuzzy matcher.

```lua
require("fuzzy.sources.buffer").buffers({
    -- source configuration goes here
})
```

#### Files

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

- Inspired by [Another Plugin](link)

## Changelog

### [Unreleased]

- Initial core components and sources release

See [CHANGELOG.md](CHANGELOG.md) for full history.
