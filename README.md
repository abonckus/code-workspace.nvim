# code-workspace.nvim

Open a VS Code `.code-workspace` file in Neovim and get a fully working multi-root workspace: all your folders appear in a unified file explorer, LSP knows about every root, and your working directory is set automatically.

## Requirements

- Neovim 0.10+
- [snacks.nvim](https://github.com/folke/snacks.nvim)

## Installation

```lua
-- lazy.nvim
{
    "abonckus/code-workspace.nvim",
    dependencies = { "folke/snacks.nvim" },
    opts = {},
}
```

That's it. The plugin works out of the box with no further configuration required.

## Opening a workspace

**From the terminal** — pass the workspace file directly to Neovim:

```sh
nvim my-project.code-workspace
```

The workspace loads automatically, your cwd moves to the workspace directory, and LSP is notified about all folders.

**From inside Neovim** — use the command palette:

```
:Workspace open
```

This scans your current directory for `.code-workspace` files and lets you pick one. You can also load a specific file directly:

```
:Workspace open /path/to/my-project.code-workspace
```

## Browsing files

Once a workspace is loaded, open the file explorer with:

```lua
require("code-workspace").explorer()
```

You'll get a Snacks.explorer sidebar showing all workspace folders as roots. The first folder is expanded; the rest start collapsed — click or press the expand key to open them. Everything else (git status, diagnostics, file watching, keybindings) works exactly as you've configured in Snacks.

A convenient keymap that opens the workspace explorer when a workspace is active, and falls back to a regular explorer otherwise:

```lua
vim.keymap.set("n", "<leader>e", function()
    local cw = require("code-workspace")
    if cw.active() then
        cw.explorer()
    else
        Snacks.explorer()
    end
end)
```

When you close the workspace (`:Workspace close`), the explorer automatically switches back to a standard Snacks.explorer at your current directory.

## Auto-detecting workspaces on startup

By default the plugin only loads a workspace when you explicitly open one (via the terminal or `:Workspace open`). If you'd like Neovim to scan your current directory on startup and load a workspace automatically, enable it in your config:

```lua
{
    "abonckus/code-workspace.nvim",
    dependencies = { "folke/snacks.nvim" },
    opts = {
        detect_on_startup = true,
    },
}
```

With `scan_depth` you can control how many parent directories to search (default is `1`, meaning cwd and one level up):

```lua
opts = {
    detect_on_startup = true,
    scan_depth        = 2,
}
```

## Running code when a workspace loads or closes

Use the `on_load` and `on_close` hooks:

```lua
opts = {
    on_load = function(workspace)
        -- workspace.name    — workspace name
        -- workspace.file    — full path to the .code-workspace file
        -- workspace.folders — list of { name, path } tables
        -- workspace.settings — raw settings table from the workspace file
        vim.notify("Loaded: " .. workspace.name)
    end,

    on_close = function(workspace)
        vim.notify("Closed: " .. workspace.name)
    end,
}
```

## Commands

| Command | Description |
|---------|-------------|
| `:Workspace open [file]` | Load a workspace (shows picker if no file given) |
| `:Workspace close` | Unload the current workspace |
| `:Workspace status` | Show the active workspace name and folder count |
