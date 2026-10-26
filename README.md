# project-picker

A project folder picker for Neovim on Windows. All drives as a folder tree, fuzzy search,
pinned / recent / root folders, notes, project detection, git info, mouse, an animation.

Requires Neovim 0.10+, Windows (drive letters), a Nerd Font for the icons.

## Install

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'Kepopep/project-picker',
  cmd = 'Projects',
  opts = {}, -- see Options
}
```

From a local clone (https://github.com/Kepopep/project-picker), with lazy.nvim:

```lua
{ dir = 'C:/path/to/project-picker', name = 'project-picker', cmd = 'Projects', opts = {} }
```

or without a plugin manager:

```lua
vim.opt.rtp:append('C:/path/to/project-picker')
```

Then `:Projects` (or `require('project_picker').open()`).

### Open at startup

To show the picker instead of the dashboard when nvim starts, call `open()` before `VimEnter`,
for example from a small script started with `nvim -S`:

```lua
vim.opt.rtp:append('C:/path/to/project-picker')
require('project_picker').open()
```

## Options

`require('project_picker').setup({ ... })`, defaults:

```lua
{
  anim_dir = vim.fn.stdpath('data') .. '/project-picker/animations', -- *.txt animations
  anim_fps = 20,      -- playback rate of those .txt animations
  anim_speed = 1.5,   -- speed of the built-in dashboard frames
  recent_max = 30,    -- remembered recent folders
  crawl_depth = 4,    -- background search index depth
  crawl_max = 30000,  -- ... and folder count limit
  store_file = vim.fn.stdpath('data') .. '/project-picker.json',
}
```

## Keys

`?` (or `F1`) inside the picker shows all keys. Short version: `j`/`k` move, `l`/`h` expand and
collapse, `Enter` opens, `.` hidden folders, `p` projects only, `r` recent view, `P` pin,
`R` root, `n` note, `x` forget in recent, `Alt-1..9` open the Nth pinned, `Alt-a` next animation.

## Layout

```
plugin/project_picker.lua       the :Projects command
lua/project_picker/
  init.lua      public API: setup, open, close
  config.lua    options
  picker.lua    creates the windows and wires the modules together
  view.lua      what the list shows and how it is drawn
  actions.lua   moving, folding, pin / root / note, opening a folder
  keys.lua  mouse.lua  help.lua  status.lua   input and the small UI parts
  tree.lua  project.lua  fuzzy.lua  store.lua  data: folder tree, project detection, search, saved data
  anim.lua  layout.lua  util.lua
```
