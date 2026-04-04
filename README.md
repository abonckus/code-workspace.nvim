# code-workspace.nvim

Brings [VS Code `.code-workspace`](https://code.visualstudio.com/docs/editor/workspaces) support to Neovim.

When a workspace file is loaded, the plugin:

- Sets Neovim's working directory to the workspace file's location
- Notifies active LSP clients about all workspace folders (multi-root LSP)
- Displays workspace folders in neo-tree

## Requirements

- Neovim 0.10+
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) (tests only)
- [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim) (optional, for file tree integration)

## Installation

### lazy.nvim

```lua
{
    "your-username/code-workspace.nvim",
    config = function()
        require("code-workspace").setup()
    end,
}
```

## Configuration

```lua
require("code-workspace").setup({
    -- Auto-detect .code-workspace files on startup (scan cwd upward)
    detect_on_startup  = true,
    -- Auto-load when a .code-workspace file is opened in a buffer
    detect_on_buf_read = true,
    -- How many directory levels above cwd to scan on startup (0 = cwd only)
    scan_depth         = 1,

    integrations = {
        neo_tree = nil, -- nil = auto-detect, true = enable, false = disable
    },

    -- Called after a workspace is loaded; useful for applying workspace settings
    on_load  = nil, -- function(workspace) end
    on_close = nil, -- function(workspace) end
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:Workspace open [file]` | Load a workspace file (opens picker if no file given) |
| `:Workspace close` | Unload the current workspace |
| `:Workspace status` | Show the active workspace name and folder count |

## Events

Other plugins and user config can react to workspace changes:

```lua
vim.api.nvim_create_autocmd("User", {
    pattern  = "WorkspaceLoaded",
    callback = function(ev)
        local workspace = ev.data
        -- workspace.file, workspace.name, workspace.folders, workspace.settings
    end,
})

vim.api.nvim_create_autocmd("User", {
    pattern  = "WorkspaceClosed",
    callback = function(ev)
        -- ev.data.file
    end,
})
```

## Known Limitations

- `.code-workspace` files use JSONC (JSON with Comments). Comments and trailing commas are not supported — standard JSON only.
- Neo-tree v1 integration shows additional workspace folders as separate splits rather than a single unified tree (VS Code-style single-panel multi-root is planned for a future version).
- Workspace `settings` are stored but not automatically applied as Neovim options. Use the `on_load` hook to apply settings yourself.
