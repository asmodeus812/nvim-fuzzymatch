# Pickers

This page documents the builtin picker modules. Each picker lives in its own module under `fuzzy.pickers.*`. The APIs
are intentionally small, but the behavior is rich. The pickers are designed to be performant by default and avoid
expensive transforms up front. Matching happens on the content you provide. Display and decoration are used for extra
context without altering the matching corpus.

Each section below explains what the picker does, what its options mean, how those options change behavior, and when
certain options are or are not suitable. Examples are included as a quick reference, but the primary focus here is
descriptive guidance.

## Contents

- [Pickers](#pickers)
    - [Contents](#contents)
    - [Git](#git)
        - [Git Files](#git-files)
        - [Git Status](#git-status)
        - [Git Branches](#git-branches)
        - [Git Commits](#git-commits)
        - [Git Buffer Commits](#git-buffer-commits)
        - [Git Stash](#git-stash)
    - [Files](#files)
        - [Files](#files)
        - [Oldfiles](#oldfiles)
    - [Buffers](#buffers)
        - [Buffers](#buffers)
        - [Tabs](#tabs)
    - [Lines](#lines)
        - [Lines (All Buffers)](#lines-all-buffers)
        - [Lines (Current Buffer)](#lines-current-buffer)
    - [Grep](#grep)
        - [Grep](#grep)
        - [Grep Word](#grep-word)
        - [Grep Visual](#grep-visual)
    - [Lists](#lists)
        - [Quickfix](#quickfix)
        - [Location List](#location-list)
        - [Quickfix Stack](#quickfix-stack)
        - [Location List Stack](#location-list-stack)
    - [Editor](#editor)
        - [Commands](#commands)
        - [Keymaps](#keymaps)
        - [Registers](#registers)
        - [Marks](#marks)
        - [Jumps](#jumps)
        - [Changes](#changes)
        - [Command History](#command-history)
        - [Search History](#search-history)
        - [Colorscheme](#colorscheme)
        - [Spell Suggest](#spell-suggest)
    - [Help](#help)
        - [Helptags](#helptags)
        - [Manpages](#manpages)
        - [Vimdoc](#vimdoc)
    - [Tags](#tags)
        - [Tags](#tags)
        - [Buffer Tags](#buffer-tags)
    - [Registry](#registry)

## Git

The Git pickers are built around `git` commands and stream their output. They are designed for repositories of any size
while keeping UI latency low by batching and debouncing. All of them accept the standard picker options (preview, icons,
stream and match steps), and then add Git-specific knobs.

### Git Files

Lists files from the current git repository. The matcher uses the file path as the content, while the display layer adds
icons, path shortening, and visual separators.

```lua
local git_picker = require("fuzzy.pickers.git")

git_picker.open_git_files({
  cwd = vim.loop.cwd,
  untracked = true,
  preview = true,
  icons = true,
  stream_step = 100000,
  match_step = 75000,
})
```

Options and behavior:

- `cwd`: Controls where the git command is executed. If you work in nested repositories, pass the root to avoid
  confusing output. If omitted, the picker detects the git root from the current buffer when possible.

- `untracked`: Includes untracked files in addition to tracked files. This is useful for new files during development.
  It is less suitable when you want a clean list of tracked files only.

- `preview`: If enabled, a file previewer is created. The preview is lazy and only materializes for the selection, so it
  does not inflate memory usage.

- `icons`: Adds file icons. Display only.

- `stream_step`, `match_step`: Higher values process more items per iteration. Use lower values if you notice UI
  hitching on extremely large repos.

### Git Status

Lists `git status --porcelain` entries. The raw status line is preserved as content, and the display layer expands it
into a readable line with filename and status hint. This is the right picker when you want quick triage of a working
tree.

```lua
local git_picker = require("fuzzy.pickers.git")

git_picker.open_git_status({
  cwd = vim.loop.cwd,
  preview = true,
  icons = true,
  stream_step = 50000,
  match_step = 50000,
})
```

Options and behavior:

- `cwd`: Must be inside a repository. The picker asserts if a repo root cannot be found. This is intentional so failures
  are obvious.

- `preview`: Previews the selected file if the status entry can be mapped to a path.

- `icons`: Adds file icons. Display only.

- `stream_step`, `match_step`: Tune for very large status lists, usually unnecessary unless you have a massive working
  tree with many untracked files.

### Git Branches

Lists local and remote branches, sorted by committer date. Use this as a fast branch switcher and as a quick way to
discover recently updated branches.

```lua
local git_picker = require("fuzzy.pickers.git")

git_picker.open_git_branches({
  cwd = vim.loop.cwd,
  stream_step = 50000,
  match_step = 50000,
})
```

Options and behavior:

- `cwd`: Repository root or a path inside the repo.

- `stream_step`, `match_step`: For very large repos with many branches, lowering these values can smooth UI.

### Git Commits

Lists commits for the repository. The match content includes the commit hash and subject so searching by hash fragment
or message works naturally.

```lua
local git_picker = require("fuzzy.pickers.git")

git_picker.open_git_commits({
  cwd = vim.loop.cwd,
  stream_step = 50000,
  match_step = 50000,
})
```

Options and behavior:

- `cwd`: Repository root. If you are inside a submodule, pass its root explicitly to avoid ambiguity.

- `stream_step`, `match_step`: Useful only for repos with very long histories.

### Git Buffer Commits

Lists commits for the current buffer file. This is meant to answer “when did this change” and is optimized for file
history.

```lua
local git_picker = require("fuzzy.pickers.git")

git_picker.open_git_bcommits({
  stream_step = 50000,
  match_step = 50000,
})
```

Options and behavior:

- Uses the current buffer path as input. If the buffer has not been written to disk, the picker will assert.

- `stream_step`, `match_step` behave as above.

### Git Stash

Lists stash entries. The match content includes stash ref and subject. This is optimized for inspection and quick
selection, not for bulk stash manipulation.

```lua
local git_picker = require("fuzzy.pickers.git")

git_picker.open_git_stash({
  cwd = vim.loop.cwd,
  stream_step = 50000,
  match_step = 50000,
})
```

Options and behavior:

- `cwd` should be inside a repository.

- Use this picker when you need fast stash inspection. It is not ideal for bulk stash manipulation since actions are
  intentionally minimal.

## Files

File-related pickers are tuned for performance and minimal allocations. They use display functions and decorators to
enrich the list without touching the content used for matching.

### Files

Lists files using `rg`, `fd`, or `find` (first available). This is the primary files picker and the most common entry
point.

```lua
local files_picker = require("fuzzy.pickers.files")

files_picker.open_files_picker({
  cwd = vim.loop.cwd,
  cwd_prompt = true,
  cwd_prompt_shorten_val = 1,
  cwd_prompt_shorten_len = 32,
  hidden = true,
  follow = false,
  no_ignore = false,
  no_ignore_vcs = false,
  preview = true,
  icons = true,
  stream_step = 100000,
  match_step = 75000,
})
```

Options and behavior:

- `cwd`: Root for the file scan. Set this explicitly if you work in multiple projects.

- `cwd_prompt`, `cwd_prompt_shorten_val`, `cwd_prompt_shorten_len`: Control the prompt header that shows the current
  working directory. These are display-only and do not affect matching. Use these if you often open the picker from
  different locations.

- `hidden`: Include hidden files. Recommended when working with dotfiles or config directories, not always ideal in
  large repos where hidden folders contain huge caches.

- `follow`: Follow symlinks. Use with caution if you have symlink loops.

- `no_ignore`, `no_ignore_vcs`: Bypass ignore rules. This is helpful for debugging or searching vendor trees, but it can
  drastically increase the number of results.

- `preview`, `icons`: Display only.

- `stream_step`, `match_step`: Tune for large trees. Lower these if you see stutter.

### Oldfiles

Lists `:oldfiles` entries. The content uses the raw file path so fuzzy matching works by path segment, while display can
shorten and decorate the line.

```lua
local oldfiles_picker = require("fuzzy.pickers.oldfiles")

oldfiles_picker.open_oldfiles_picker({
  cwd = vim.loop.cwd,
  stat_file = true,
  preview = true,
  icons = true,
})
```

Options and behavior:

- `cwd`: Base directory for filtering and path display. When set, only entries under `cwd` are included.

- `stat_file`: When true, performs a stat call to filter missing files and optionally surface extra info. This is useful
  when your oldfiles list is noisy, but it does add I/O cost, so consider disabling on slow filesystems.

- `preview`, `icons`: Display only.

## Buffers

Buffer pickers use buffer numbers as content so matching is efficient and stable. Display is responsible for human-
friendly labels and state markers.

### Buffers

Lists buffers with filtering and optional sorting. This is optimized to avoid unnecessary string creation up front,
while still letting the matcher filter by filename.

```lua
local buffers_picker = require("fuzzy.pickers.buffers")

buffers_picker.open_buffers_picker({
  current_tab = false,
  show_unlisted = false,
  show_unloaded = false,
  include_special = false, -- false | true | { "terminal", "quickfix" } | { terminal = true }
  ignore_current_buffer = true,
  sort_lastused = true,
  cwd = vim.loop.cwd,
  filename_only = false,
  path_shorten = nil,
  home_to_tilde = true,
  preview = true,
  icons = true,
})
```

Options and behavior:

- `current_tab`: Restrict results to buffers visible in the current tab. Useful for focused workflows, less suitable
  when you want global navigation.

- `show_unlisted`, `show_unloaded`: Include unlisted or unloaded buffers. Use these when you need a full buffer
  inventory; otherwise keep them off for cleaner lists.

- `include_special`: Controls special `buftype` entries.
  - `false`: only normal buffers (`buftype == ""`).
  - `true`: include all special buftypes.
  - `table`: include only listed buftypes, as either an array (`{ "terminal", "quickfix" }`) or a map
    (`{ terminal = true }`).

- `ignore_current_buffer`: Exclude the active buffer. Useful when you are looking for a jump target.

- `sort_lastused`: Sort buffers by recent use with current and alternate buffers pinned at the top. Disable if you want
  raw buffer order.

- `cwd`: Base directory for filtering and path display. When set, only buffers under `cwd` are included.

- `filename_only`: Display just the filename, not the full path.

- `path_shorten`, `home_to_tilde`: Path display helpers. They do not affect matching.

- `preview`, `icons`: Display only.

### Tabs

Lists open tabpages. Content uses tab numbers and buffer names. The display favors a concise summary rather than full
buffer details, giving you a lightweight overview of which files are visible in each tab.

```lua
local tabs_picker = require("fuzzy.pickers.tabs")

tabs_picker.open_tabs_picker({
  tab_marker = "",
  preview = false,
})
```

Options and behavior:

- `tab_marker`: A display marker for the current tab. Use a small symbol; it does not affect matching.

- `preview`: Tabs are not preview-heavy; keep this off unless you add a custom previewer.

## Lines

Line pickers prioritize keeping memory usage low. Content is lightweight, and line text is resolved at display time so
you do not pay the cost of building a massive list of strings.

### Lines (All Buffers)

Lists lines across buffers. Text is fetched lazily for display, while content uses buffer and line references for
matching. This is ideal when you want to search across many files without creating huge strings up front.

```lua
local lines_picker = require("fuzzy.pickers.lines")

lines_picker.open_lines_picker({
  show_unlisted = false,
  show_unloaded = false,
  ignore_current_buffer = false,
  include_special = false, -- false | true | { "terminal", "quickfix" } | { terminal = true }
  preview = false,
  match_step = 50000,
})
```

Options and behavior:

- `show_unlisted`, `show_unloaded`: Include buffers that are not normally visible. This is useful for global searches
  but increases the total item count.

- `ignore_current_buffer`: Excludes the active buffer from the line list.

- `include_special`: Controls special `buftype` entries.
  - `false`: only normal buffers (`buftype == ""`).
  - `true`: include all special buftypes.
  - `table`: include only listed buftypes, as either an array (`{ "terminal", "quickfix" }`) or a map
    (`{ terminal = true }`).

- `preview`: Previewing full lines can be redundant; keep off unless you add a custom previewer.

- `match_step`: Tune if you are working in a large codebase with very large buffers.

Word and visual variants pre-fill the prompt with `<cword>` or the visual selection.

```lua
local lines_picker = require("fuzzy.pickers.lines")

lines_picker.open_lines_word({
  match_step = 50000,
})

lines_picker.open_lines_visual({
  match_step = 50000,
})
```

### Lines (Current Buffer)

Lists lines in the current buffer only. This is the quick “jump to line” workflow that stays fast even on very large
files because content stays minimal.

```lua
local blines_picker = require("fuzzy.pickers.blines")

blines_picker.open_blines_picker({
  cwd = vim.loop.cwd,
  preview = false,
  match_step = 50000,
})
```

Options and behavior:

- `preview`: Usually unnecessary for current-buffer lines.

Word and visual variants pre-fill the prompt with `<cword>` or the visual selection.

```lua
local blines_picker = require("fuzzy.pickers.blines")

blines_picker.open_buffer_lines_word({
  match_step = 50000,
})

blines_picker.open_buffer_lines_visual({
  match_step = 50000,
})
```

## Grep

The grep picker is first-class. It is interactive, debounced, and can re-run the underlying command as the query
changes. This is the right choice for fast project searches without the overhead of external fuzzy tools.

### Grep

Interactive grep using `rg` or `grep` (first available). Supports `query -- args` parsing when `rg_glob` is enabled.

```lua
local grep_picker = require("fuzzy.pickers.grep")

grep_picker.open_grep_picker({
  cwd = vim.loop.cwd,
  hidden = false,
  follow = false,
  no_ignore = false,
  no_ignore_vcs = false,
  rg_glob = true,
  rg_glob_fn = nil,
  glob_flag = "--iglob",
  glob_separator = "%s%-%-",
  rg_opts = "--hidden --column --line-number --no-heading --color=never --smart-case -e",
  grep_opts = "-n -H -r --line-buffered",
  RIPGREP_CONFIG_PATH = vim.env.RIPGREP_CONFIG_PATH,
  preview = true,
  icons = true,
  stream_step = 25000,
  match_step = 25000,
  prompt_debounce = 200,
})
```

Options and behavior:

- `cwd`: Search root. This matters for performance and accuracy, especially in monorepos.

- `hidden`, `follow`, `no_ignore`, `no_ignore_vcs`: Pass-through flags to the underlying command. These can drastically
  change result volume, so use them deliberately.

- `rg_glob`: Enables the `query -- args` form. When true, the picker splits the input into two parts: the regex query
  and extra arguments that are passed back to the command. This is ideal for ad hoc globbing and exclusions during
  interactive use. If you do not need dynamic args, disable it for simpler input.

- `rg_glob_fn`: Custom split logic. It receives the raw query and returns two values: `(regex, args)`. Use this if you
  need a different separator, or if you want to parse custom flags. The picker uses your returned `args` verbatim when
  re-running the grep.

- `glob_flag`, `glob_separator`: Convenience helpers for the default `rg_glob` parser. `glob_separator` defines the
  split point (default matches `" --"`), and `glob_flag` is used when you convert glob fragments into arguments.

- `rg_opts`, `grep_opts`: Startup arguments for the command. Keep these aligned with your expectations for case
  sensitivity and regex engine.

- `RIPGREP_CONFIG_PATH`: Allows the picker to respect your ripgrep config even when the shell environment is not
  sourced.

- `preview`, `icons`: Display only.

- `stream_step`, `match_step`: Lower these to keep UI responsive while typing with extremely large result sets.

- `prompt_debounce`: Controls how quickly the grep is re-run as you type. Lower values are more responsive but may re-
  run too often.

### Grep Word

Same as the main grep picker, but the prompt is prefilled with `<cword>`.

```lua
local grep_picker = require("fuzzy.pickers.grep")

grep_picker.open_grep_word({
  cwd = vim.loop.cwd,
})
```

### Grep Visual

Same as the main grep picker, but the prompt is prefilled with the visual selection.

```lua
local grep_picker = require("fuzzy.pickers.grep")

grep_picker.open_grep_visual({
  cwd = vim.loop.cwd,
})
```

## Lists

Quickfix and location list pickers use the list entries as content but keep display lightweight. They are designed to
avoid heavy per-entry processing.

### Quickfix

Lists items from the quickfix list. Each entry shows file, line, column, and text while keeping the raw list item as the
match target so filtering remains fast.

```lua
local quickfix_picker = require("fuzzy.pickers.quickfix")

quickfix_picker.open_quickfix_picker({
  filename_only = false,
  path_shorten = nil,
  home_to_tilde = true,
  cwd = vim.loop.cwd,
  preview = true,
  icons = true,
  match_step = 50000,
})
```

Options and behavior:

- `filename_only`: Display just the filename rather than full path. Matching still uses the content from the list entry.

- `path_shorten`, `home_to_tilde`: Display helpers. These are not part of the match content.

- `cwd`: Base directory for filtering and path display. When set, only entries under `cwd` are included.

- `preview`, `icons`: Display only.

- `match_step`: For very large lists.

The visual variant pre-fills the prompt with the visual selection.

```lua
local quickfix_picker = require("fuzzy.pickers.quickfix")

quickfix_picker.open_quickfix_visual({
  preview = true,
})
```

### Location List

Lists items from the current window location list, with the same display style as the quickfix picker but scoped to the
active window.

```lua
local loclist_picker = require("fuzzy.pickers.loclist")

loclist_picker.open_loclist_picker({
  filename_only = false,
  path_shorten = nil,
  home_to_tilde = true,
  cwd = vim.loop.cwd,
  preview = true,
  icons = true,
  match_step = 50000,
})
```

Options and behavior:

- `filename_only`, `path_shorten`, `home_to_tilde`: Display helpers. These are not part of the match content.

- `cwd`: Base directory for filtering and path display. When set, only entries under `cwd` are included.

- `preview`, `icons`, `match_step`: Same meaning as quickfix; tune for large lists.

The visual variant pre-fills the prompt with the visual selection.

```lua
local loclist_picker = require("fuzzy.pickers.loclist")

loclist_picker.open_loclist_visual({
  preview = true,
})
```

### Quickfix Stack

Lists quickfix history entries. Each entry captures the list title and context so you can jump back to a previous
quickfix state without rebuilding it.

```lua
local quickfix_stack_picker = require("fuzzy.pickers.quickfix_stack")

quickfix_stack_picker.open_quickfix_stack({
  preview = false,
})
```

### Location List Stack

Lists location list history entries for the current window. This mirrors the quickfix stack picker but keeps the scope
local.

```lua
local loclist_stack_picker = require("fuzzy.pickers.loclist_stack")

loclist_stack_picker.open_loclist_stack({
  preview = false,
})
```

## Editor

Editor pickers expose built-in Neovim lists. These are intentionally light, focusing on fast filtering rather than heavy
formatting.

### Commands

Lists user commands. Each entry includes the command name and a brief description where available, which makes this
useful as a command palette when combined with fuzzy search.

```lua
local commands_picker = require("fuzzy.pickers.commands")

commands_picker.open_commands_picker({
  include_builtin = false,
  sort_lastused = true,
})
```

Options and behavior:

- `include_builtin`: Include built-in commands. Turn this on if you want a global command palette; leave it off for a
  smaller list focused on your config.

- `sort_lastused`: When true, recently used commands bubble up. Disable if you prefer alphabetical order.

### Keymaps

Lists keymaps with their modes and, optionally, descriptions. The picker balances readability and density so you can
search for a mapping by its LHS, RHS, or description without clutter.

```lua
local keymaps_picker = require("fuzzy.pickers.keymaps")

keymaps_picker.open_keymaps_picker({
  show_desc = true,
  show_details = false,
})
```

Options and behavior:

- `show_desc`: Adds keymap descriptions to display. This is highly recommended for discoverability.

- `show_details`: Adds verbose details and is useful for debugging, but it makes the list denser and harder to skim.

### Registers

Lists registers and their contents. The display keeps the register name and a concise preview of its contents, which
makes it easy to find the right register without loading full blobs into the match content.

```lua
local registers_picker = require("fuzzy.pickers.registers")

registers_picker.open_registers_picker({
  filter = nil,
})
```

Options and behavior:

- `filter`: Restrict which registers are included. Use this if you want to avoid large named registers or special
  registers.

### Marks

Lists marks with enough context to understand where each mark points. Each entry reflects the mark name, the buffer or
file it belongs to, and the line and column where it lands. Local marks (like `a` to `z`) are scoped to a buffer, while
global marks (like `A` to `Z` and numbered marks) can jump across files. This picker presents them in a compact form so
you can filter by mark letter or by the file path, and still see the destination at a glance without loading more data
up front.

```lua
local marks_picker = require("fuzzy.pickers.marks")

marks_picker.open_marks_picker({
  marks = "[a-z]",
})
```

Options and behavior:

- `marks`: A pattern of marks to include. Use lowercase ranges for local marks, uppercase ranges for global marks, or a
  combined pattern if you want both.

### Jumps

Lists jump list entries. Each entry includes the target buffer or file and the recorded cursor position, so you can
retrace navigation history quickly. The list favors brevity so it stays fast even when the jumplist is long.

```lua
local jumps_picker = require("fuzzy.pickers.jumps")

jumps_picker.open_jumps_picker({
  preview = false,
})
```

Options and behavior:

- `preview`: Jumps are lightweight; enable only if you need a previewer.

### Changes

Lists change list entries. Each entry represents a position where the buffer changed, so this picker is useful for
stepping backward through recent edits.

```lua
local changes_picker = require("fuzzy.pickers.changes")

changes_picker.open_changes_picker({
  preview = false,
})
```

Options and behavior:

- `preview`: Enable if you want a buffer preview when stepping through changes.

### Command History

Lists command history entries. This is a quick way to re-run or inspect previous `:` commands without digging through
history manually.

```lua
local command_history_picker = require("fuzzy.pickers.command_history")

command_history_picker.open_command_history({
  preview = false,
})
```

### Search History

Lists search history entries. Use this to recall previous `/` or `?` searches, especially when you want to reuse a
complex regex.

```lua
local search_history_picker = require("fuzzy.pickers.search_history")

search_history_picker.open_search_history({
  preview = false,
})
```

### Colorscheme

Lists installed colorschemes and lets you preview them. This is intentionally lightweight and only applies the theme to
the UI when you change selection.

```lua
local colorscheme_picker = require("fuzzy.pickers.colorscheme")

colorscheme_picker.open_colorscheme_picker({
  preview = true,
})
```

Options and behavior:

- `preview`: Applies schemes on selection. Use cautiously if you are sensitive to rapid theme changes.

### Spell Suggest

Lists spell suggestions for the word under cursor. The list is small and focused, and matches by suggestion text so you
can quickly filter close alternatives.

```lua
local spell_suggest_picker = require("fuzzy.pickers.spell_suggest")

spell_suggest_picker.open_spell_suggest({
  target_word_text = nil,
  suggest_limit_count = 25,
})
```

Options and behavior:

- `target_word_text`: Override the target word instead of using the word under cursor.

- `suggest_limit_count`: Limit the number of suggestions. Use lower values for speed, higher values for completeness.

## Help

Help pickers are intentionally simple and defer most work to Neovim’s help system and previewers.

### Helptags

Lists helptags. Each entry is a help tag identifier; the preview uses the help system to show the relevant section
without loading more content into the picker itself.

```lua
local helptags_picker = require("fuzzy.pickers.helptags")

helptags_picker.open_helptags_picker({
  preview = true,
})
```

### Manpages

Lists manpages. Entries are collected from `apropos -k .` (fallback: `man -k .`) and normalized to `name(section)`.

```lua
local manpages_picker = require("fuzzy.pickers.manpages")

manpages_picker.open_manpages_picker({
  preview = true,
})
```

### Vimdoc

Lists Neovim API function docs from `vim.fn.api_info()`. Entries are normalized to `nvim_*()` tags and open with help.

```lua
local vimdoc_picker = require("fuzzy.pickers.vimdoc")

vimdoc_picker.open_vimdoc_picker({
  preview = false,
})
```

## Tags

Tags pickers rely on ctags output and are meant for code navigation. They keep content small to avoid storing huge tag
lines in memory.

### Tags

Lists tags in the project. Each entry shows the tag name and kind, and the picker opens the corresponding location on
confirm.

```lua
local tags_picker = require("fuzzy.pickers.tags")

tags_picker.open_tags_picker({
  preview = true,
})
```

### Buffer Tags

Lists tags for the current buffer. This is the smallest tag picker and is useful when you want fast symbol navigation
within a single file.

```lua
local btags_picker = require("fuzzy.pickers.btags")

btags_picker.open_btags_picker({
  preview = true,
})
```

## Registry

The picker registry stores and reuses picker instances. This is a small helper module that lets you register a picker
under a key, retrieve it later, and open it without recreating a new instance. It is intentionally minimal and keeps the
caching policy explicit in user code.

```lua
local registry = require("fuzzy.pickers.registry")

local picker = registry.register_picker_instance("buffers", my_buffers_picker)
local same_picker = registry.get_picker_instance("buffers")
registry.open_picker_instance("buffers")
registry.remove_picker_instance("buffers")
registry.clear_picker_registry()
```
