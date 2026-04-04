# snacks Multi-Root Explorer Design

**Date:** 2026-04-04
**Plugin:** code-workspace.nvim

## Summary

Replace the current `Snacks.explorer({ roots = ... })` implementation (which uses a non-existent API) with a proper custom snacks picker source named `workspace_explorer`. The source uses snacks' internal `Tree` singleton to traverse multiple workspace folder roots in a single unified sidebar, with full feature parity to the standard snacks explorer (git status, diagnostics, file watching, follow-file). When a workspace is closed, the workspace explorer closes and the standard snacks explorer reopens at the cwd.

## User Setup

**Minimal (zero config):** snacks is auto-detected if installed with picker enabled.

```lua
require("code-workspace").setup()
```

**Disable the integration:**

```lua
require("code-workspace").setup({
    integrations = { snacks = false }
})
```

**Workspace-specific explorer overrides** (in snacks setup):

```lua
opts = {
    picker = {
        sources = {
            workspace_explorer = {
                -- any standard explorer option, e.g.:
                layout = { layout = { position = "right" } },
            }
        }
    }
}
```

**Force enable:**

```lua
require("code-workspace").setup({
    integrations = { snacks = true }
})
```

## Auto-Detection

Auto-detection in `init.lua` checks for snacks **and** the picker specifically:

```lua
local ok = pcall(require, "snacks")
snacks_enabled = ok and Snacks ~= nil and Snacks.picker ~= nil
```

This avoids false positives when snacks is installed but picker is disabled.

## Architecture

### Files

| File | Change | Purpose |
|------|--------|---------|
| `lua/code-workspace/integrations/snacks/init.lua` | New (replaces `snacks.lua`) | WorkspaceLoaded/Closed handlers; opens/closes workspace_explorer picker |
| `lua/code-workspace/integrations/snacks/source.lua` | New | Custom finder function + State class for event handling |
| `lua/code-workspace/init.lua` | Modify | Update auto-detection check for `Snacks.picker` |
| `lua/code-workspace/config.lua` | No change | `snacks = nil` default already added |
| `tests/snacks_spec.lua` | Replace | Tests for new behaviour |

The require path `code-workspace.integrations.snacks` resolves to `snacks/init.lua` automatically — no changes needed in `init.lua`'s require call.

### On WorkspaceLoaded

1. Deep-copy `Snacks.picker.sources.explorer` as the base config (inherits the user's standard explorer layout, keybindings, formatters, git/diagnostics flags, etc.)
2. Overlay workspace-specific overrides:
   - `source = "workspace_explorer"` — identifies this picker for toggle and snacks source config lookup
   - `finder = require("code-workspace.integrations.snacks.source").finder`
   - `roots = workspace.folders` — list of `{ name, path }` tables
3. Call `Snacks.picker.pick(config)` to open the sidebar

Because snacks merges `opts.picker.sources.workspace_explorer` from the user's snacks config when it sees `source = "workspace_explorer"`, users get a natural configuration override point without any special handling in code-workspace.nvim.

### On WorkspaceClosed

1. Find the open picker: `Snacks.picker.get({ source = "workspace_explorer" })[1]`
2. Close it if found: `picker:close()`
3. Open standard explorer at cwd: `Snacks.explorer({ cwd = vim.fn.getcwd() })`

Step 3 always runs — if the user manually closed the workspace explorer before closing the workspace, they still land back in the standard explorer.

## The Finder (`source.lua`)

`finder(opts, ctx)` receives `opts.roots` as the workspace folder list.

For each root in order:

1. `Tree:refresh(root.path)` — syncs git status into the shared Tree singleton
2. `Tree:get(root.path, cb, filter_opts)` — walks the tree from that root, yielding visible nodes
3. Convert each node to a picker item. Set `sort = string.format("%02d", root_index) .. node_sort` so root 1's items always sort before root 2's, preserving intra-root tree ordering
4. After all roots: ensure the final root's root-node has `last = true` and all preceding roots' root-nodes have `last = false`, so tree connectors (`└` vs `├`) render correctly at the inter-root boundary

Items are structurally identical to standard explorer items — all existing formatters, keybindings, and actions work without modification.

The `Tree` module is a shared singleton (`return Tree.new()` at the bottom of `tree.lua`). Multiple root paths coexist in it by design — each root's subtree has correct `parent` references and `last` flags within itself from `Tree:walk()`.

## State & Event Handling (`source.lua`)

A `State` class is instantiated once per picker on first `finder` call (same pattern as snacks' internal `State` in `picker/source/explorer.lua`). All autocmds are scoped to the picker's list window and torn down when the picker closes.

### Git Status
`require("snacks.explorer.git").update(root.path, { on_update = re_find })` called for each root on picker open. `re_find` calls `picker:find()` to refresh the list.

### Diagnostics
One `DiagnosticChanged` autocmd (global — diagnostics are not per-root). Debounced 200ms. Calls `require("snacks.explorer.diagnostics").update(root.path)` for each root, then `picker:find()`.

### File Watch
`require("snacks.explorer.watch").watch()` is already global and watches all open directories. One call on picker open. On `BufWritePost`, call `Tree:refresh(ev.file)` and `picker:find()`.

### Follow-File
On `BufEnter`, check if the current buffer's file falls within any root using `Tree:in_cwd(root.path, file)` for each root. If found, call `Actions.update(picker, { target = file })` to scroll the list to that item.

## Testing

`tests/snacks_spec.lua` is replaced with tests covering:

- **Finder:** yields items from all roots; sort prefixes are correct; `last` flags correct at root boundary; empty/nil roots guard
- **WorkspaceLoaded:** `Snacks.picker.pick` called with correct `source`, `roots`, and base config inherited from `Snacks.picker.sources.explorer`
- **WorkspaceClosed:** existing workspace_explorer picker is closed; `Snacks.explorer` opened with cwd
- **Auto-detection:** returns false when `Snacks.picker` is nil even if snacks loads

## Non-Goals

- No changes to the neo-tree integration
- No changes to LSP notifications, workspace parsing, or detection logic
- No support for `explorer_up` navigating above a workspace root (clamps at root — same as standard explorer behaviour)
