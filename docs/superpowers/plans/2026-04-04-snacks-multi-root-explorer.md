# snacks Multi-Root Explorer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the broken `Snacks.explorer({ roots = ... })` integration with a proper custom `workspace_explorer` picker source that shows all workspace folders as a unified multi-root tree with full feature parity to the standard snacks explorer.

**Architecture:** A new `snacks/` integration directory replaces `snacks.lua`. `snacks/init.lua` handles WorkspaceLoaded/Closed events, opening a picker with `source = "workspace_explorer"` whose config is inherited from the standard explorer. `snacks/source.lua` provides the multi-root finder (using snacks' Tree singleton) and a State class for git/diagnostics/watch/follow-file event handling.

**Tech Stack:** Lua, Neovim plugin API, snacks.nvim (Tree singleton, picker, explorer actions), busted via plenary

---

### Task 1: Update auto-detection to check for `Snacks.picker`

**Files:**
- Modify: `lua/code-workspace/init.lua`

- [ ] **Step 1: Update the detection block**

In `lua/code-workspace/init.lua`, replace:

```lua
    -- Snacks integration (priority); fall back to neo-tree
    local snacks_enabled = cfg.integrations.snacks
    if snacks_enabled == nil then
        snacks_enabled = pcall(require, "snacks")
    end
```

With:

```lua
    -- Snacks integration (priority); fall back to neo-tree
    local snacks_enabled = cfg.integrations.snacks
    if snacks_enabled == nil then
        local ok = pcall(require, "snacks")
        snacks_enabled = ok and _G.Snacks ~= nil and _G.Snacks.picker ~= nil
    end
```

- [ ] **Step 2: Run full test suite to verify nothing broke**

```
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}"
```

Expected: same pass counts as before (snacks, config, loader, parser, detector, smoke). The auto-detection returns false in headless tests because `_G.Snacks` is nil — same behaviour as before, just more precise.

- [ ] **Step 3: Commit**

```bash
git add lua/code-workspace/init.lua
git commit -m "fix: check Snacks.picker in auto-detection, not just snacks module"
```

---

### Task 2: Replace `snacks.lua` with `snacks/init.lua` and update tests

**Files:**
- Delete: `lua/code-workspace/integrations/snacks.lua`
- Create: `lua/code-workspace/integrations/snacks/init.lua`
- Create: `lua/code-workspace/integrations/snacks/source.lua` (stub)
- Replace: `tests/snacks_spec.lua`

- [ ] **Step 1: Write failing tests for new WorkspaceLoaded/Closed behaviour**

Replace the entire contents of `tests/snacks_spec.lua`:

```lua
local function fire(pattern, data)
    vim.api.nvim_exec_autocmds("User", { pattern = pattern, data = data })
end

describe("integrations/snacks/init", function()
    local integration
    local pick_calls
    local get_result
    local explorer_calls
    local mock_picker

    before_each(function()
        package.loaded["code-workspace.integrations.snacks"] = nil
        package.loaded["code-workspace.integrations.snacks.source"] = nil

        pick_calls    = {}
        explorer_calls = {}
        mock_picker   = { closed = false, close = function(self) self.closed = true end }
        get_result    = {}

        _G.Snacks = {
            picker = {
                sources = {
                    explorer = {
                        layout   = { preset = "sidebar" },
                        tree     = true,
                        git_status = true,
                    },
                },
                pick = function(opts)
                    table.insert(pick_calls, opts)
                end,
                get = function(opts)
                    return get_result
                end,
            },
            explorer = function(opts)
                table.insert(explorer_calls, opts)
            end,
        }

        -- Stub source so init.lua can require it without loading snacks internals
        package.loaded["code-workspace.integrations.snacks.source"] = {
            finder = function() end,
        }

        integration = require("code-workspace.integrations.snacks")
        integration.setup()
    end)

    after_each(function()
        _G.Snacks = nil
        package.loaded["code-workspace.integrations.snacks"] = nil
        package.loaded["code-workspace.integrations.snacks.source"] = nil
        vim.api.nvim_clear_autocmds({ event = "User", pattern = "WorkspaceLoaded" })
        vim.api.nvim_clear_autocmds({ event = "User", pattern = "WorkspaceClosed" })
    end)

    describe("WorkspaceLoaded", function()
        it("calls Snacks.picker.pick with source workspace_explorer", function()
            fire("WorkspaceLoaded", {
                folders = { { name = "app", path = "/srv/app" } },
            })

            assert.equals(1, #pick_calls)
            assert.equals("workspace_explorer", pick_calls[1].source)
        end)

        it("passes workspace folders as roots", function()
            local folders = {
                { name = "app", path = "/srv/app" },
                { name = "lib", path = "/srv/lib" },
            }
            fire("WorkspaceLoaded", { folders = folders })

            assert.same(folders, pick_calls[1].roots)
        end)

        it("inherits standard explorer config as base", function()
            fire("WorkspaceLoaded", {
                folders = { { name = "app", path = "/srv/app" } },
            })

            -- layout from Snacks.picker.sources.explorer is present
            assert.same({ preset = "sidebar" }, pick_calls[1].layout)
            assert.is_true(pick_calls[1].tree)
        end)

        it("does not mutate Snacks.picker.sources.explorer", function()
            fire("WorkspaceLoaded", {
                folders = { { name = "app", path = "/srv/app" } },
            })

            -- source field must not leak into the original table
            assert.is_nil(Snacks.picker.sources.explorer.source)
        end)

        it("does nothing when folders list is empty", function()
            fire("WorkspaceLoaded", { folders = {} })
            assert.equals(0, #pick_calls)
        end)

        it("does nothing when workspace data is nil", function()
            fire("WorkspaceLoaded", { data = nil })
            assert.equals(0, #pick_calls)
        end)
    end)

    describe("WorkspaceClosed", function()
        it("closes open workspace_explorer picker", function()
            get_result = { mock_picker }
            fire("WorkspaceClosed", { file = "/tmp/test.code-workspace" })

            assert.is_true(mock_picker.closed)
        end)

        it("opens standard explorer at cwd", function()
            local cwd = vim.fn.getcwd()
            fire("WorkspaceClosed", { file = "/tmp/test.code-workspace" })

            assert.equals(1, #explorer_calls)
            assert.equals(cwd, explorer_calls[1].cwd)
        end)

        it("still opens standard explorer when no workspace_explorer picker is open", function()
            get_result = {}
            fire("WorkspaceClosed", { file = "/tmp/test.code-workspace" })

            assert.equals(1, #explorer_calls)
        end)
    end)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

```
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/snacks_spec.lua"
```

Expected: FAIL — module `code-workspace.integrations.snacks` not found (we haven't created it yet).

- [ ] **Step 3: Delete the old snacks.lua**

```bash
git rm lua/code-workspace/integrations/snacks.lua
```

- [ ] **Step 4: Create `lua/code-workspace/integrations/snacks/init.lua`**

```lua
local M = {}

function M.setup()
    vim.api.nvim_create_autocmd("User", {
        pattern  = "WorkspaceLoaded",
        callback = function(ev)
            local workspace = ev.data
            if not workspace or not workspace.folders or #workspace.folders == 0 then
                return
            end
            local base   = vim.deepcopy(Snacks.picker.sources.explorer)
            local config = vim.tbl_deep_extend("force", base, {
                source = "workspace_explorer",
                finder = require("code-workspace.integrations.snacks.source").finder,
                roots  = workspace.folders,
            })
            Snacks.picker.pick(config)
        end,
    })

    vim.api.nvim_create_autocmd("User", {
        pattern  = "WorkspaceClosed",
        callback = function()
            local pickers = Snacks.picker.get({ source = "workspace_explorer" })
            if pickers[1] then
                pickers[1]:close()
            end
            Snacks.explorer({ cwd = vim.fn.getcwd() })
        end,
    })
end

return M
```

- [ ] **Step 5: Create stub `lua/code-workspace/integrations/snacks/source.lua`**

```lua
local M = {}

function M.finder(opts, ctx)
    return function(cb) end
end

return M
```

- [ ] **Step 6: Run tests to verify they pass**

```
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/snacks_spec.lua"
```

Expected: all 9 tests PASS.

- [ ] **Step 7: Run full suite to verify nothing else broke**

```
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}"
```

Expected: all previous tests still pass.

- [ ] **Step 8: Commit**

```bash
git add lua/code-workspace/integrations/snacks/init.lua lua/code-workspace/integrations/snacks/source.lua tests/snacks_spec.lua
git commit -m "feat: replace snacks integration with workspace_explorer picker source"
```

---

### Task 3: Implement the multi-root finder in `source.lua`

**Files:**
- Modify: `lua/code-workspace/integrations/snacks/source.lua`
- Modify: `tests/snacks_spec.lua`

- [ ] **Step 1: Add finder tests to `tests/snacks_spec.lua`**

Add a new top-level `describe` block **after** the existing `integrations/snacks/init` block:

```lua
describe("integrations/snacks/source", function()
    local source
    local tree_calls   -- { refresh = [...], get = [...] }
    local yielded      -- items collected by calling the finder's return function

    local function make_node(path, opts)
        opts = opts or {}
        return {
            path     = path,
            name     = vim.fs.basename(path),
            dir      = opts.dir,
            open     = opts.open,
            hidden   = opts.hidden or false,
            ignored  = opts.ignored or false,
            status   = opts.status,
            dir_status = opts.dir_status,
            type     = opts.dir and "directory" or "file",
            severity = opts.severity,
            parent   = opts.parent,
        }
    end

    before_each(function()
        package.loaded["code-workspace.integrations.snacks.source"] = nil
        tree_calls = { refresh = {}, get = {} }
        yielded    = {}

        -- Mock Tree singleton
        package.loaded["snacks.explorer.tree"] = {
            refresh = function(self, path)
                table.insert(tree_calls.refresh, path)
            end,
            get = function(self, cwd, cb, filter_opts)
                -- record call
                table.insert(tree_calls.get, { cwd = cwd, filter_opts = filter_opts })
                -- caller must push nodes via tree_calls.get[n].push = cb
                tree_calls.get[#tree_calls.get].push = cb
            end,
            in_cwd = function(self, cwd, path)
                return path:find(cwd, 1, true) == 1
            end,
        }

        -- Mock Actions
        package.loaded["snacks.explorer.actions"] = {
            actions = {},
            update  = function() end,
        }

        source = require("code-workspace.integrations.snacks.source")
    end)

    after_each(function()
        package.loaded["code-workspace.integrations.snacks.source"] = nil
        package.loaded["snacks.explorer.tree"] = nil
        package.loaded["snacks.explorer.actions"] = nil
    end)

    local function run_finder(roots, nodes_per_root)
        -- nodes_per_root: list of lists of nodes, one list per root.
        -- Replaces Tree.get on the already-captured mock object so source.lua
        -- sees the updated implementation (Tree is captured by reference at load time).
        local call_index = 0
        package.loaded["snacks.explorer.tree"].get = function(self, cwd, cb, filter_opts)
            call_index = call_index + 1
            table.insert(tree_calls.get, { cwd = cwd })
            for _, node in ipairs(nodes_per_root[call_index] or {}) do
                cb(node)
            end
        end

        local ctx = { picker = {} }
        local gen = source.finder({ roots = roots }, ctx)
        gen(function(item) table.insert(yielded, item) end)
    end

    it("yields items from all roots in order", function()
        local virtual_root = { path = "" }
        local node_a = make_node("/a", { dir = true, parent = virtual_root })
        local node_b = make_node("/b", { dir = true, parent = virtual_root })

        run_finder(
            { { name = "a", path = "/a" }, { name = "b", path = "/b" } },
            { { node_a }, { node_b } }
        )

        assert.equals(2, #yielded)
        assert.equals("/a", yielded[1].file)
        assert.equals("/b", yielded[2].file)
    end)

    it("sets last=false on all root nodes except the final one", function()
        local virtual_root = { path = "" }
        local node_a = make_node("/a", { dir = true, parent = virtual_root })
        local node_b = make_node("/b", { dir = true, parent = virtual_root })
        local node_c = make_node("/c", { dir = true, parent = virtual_root })

        run_finder(
            {
                { name = "a", path = "/a" },
                { name = "b", path = "/b" },
                { name = "c", path = "/c" },
            },
            { { node_a }, { node_b }, { node_c } }
        )

        assert.is_false(yielded[1].last)  -- /a: not last
        assert.is_false(yielded[2].last)  -- /b: not last
        assert.is_true(yielded[3].last)   -- /c: last root
    end)

    it("sets last correctly within a root subtree", function()
        local virtual_root = { path = "" }
        local root_node   = make_node("/r", { dir = true, parent = virtual_root })
        local child_1     = make_node("/r/x", { dir = false, parent = root_node })
        local child_2     = make_node("/r/y", { dir = false, parent = root_node })

        run_finder(
            { { name = "r", path = "/r" } },
            { { root_node, child_1, child_2 } }
        )

        -- root is last (only root)
        assert.is_true(yielded[1].last)
        -- child_1 is not last (child_2 follows)
        assert.is_false(yielded[2].last)
        -- child_2 is last child of root_node
        assert.is_true(yielded[3].last)
    end)

    it("sets parent to nil for root nodes", function()
        local virtual_root = { path = "" }
        local node_a = make_node("/a", { dir = true, parent = virtual_root })

        run_finder(
            { { name = "a", path = "/a" } },
            { { node_a } }
        )

        -- root nodes have parent = nil (virtual_root has path "", items[""] is nil)
        assert.is_nil(yielded[1].parent)
    end)

    it("sets parent correctly for children", function()
        local virtual_root = { path = "" }
        local root_node    = make_node("/r", { dir = true, parent = virtual_root })
        local child        = make_node("/r/x", { parent = root_node })

        run_finder(
            { { name = "r", path = "/r" } },
            { { root_node, child } }
        )

        -- child's parent item is the root item
        assert.equals(yielded[1], yielded[2].parent)
    end)

    it("root nodes are never hidden or ignored", function()
        local virtual_root = { path = "" }
        local node = make_node("/a", { dir = true, parent = virtual_root, hidden = true, ignored = true })

        run_finder(
            { { name = "a", path = "/a" } },
            { { node } }
        )

        assert.is_false(yielded[1].hidden)
        assert.is_false(yielded[1].ignored)
    end)

    it("yields nothing when roots is empty", function()
        run_finder({}, {})
        assert.equals(0, #yielded)
    end)
end)
```

- [ ] **Step 2: Run new tests to verify they fail**

```
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/snacks_spec.lua"
```

Expected: the `integrations/snacks/init` tests still PASS; the new `integrations/snacks/source` tests FAIL (stub finder yields nothing).

- [ ] **Step 3: Implement the full finder in `source.lua`**

Replace the entire contents of `lua/code-workspace/integrations/snacks/source.lua`:

```lua
local Tree    = require("snacks.explorer.tree")
local Actions = require("snacks.explorer.actions")

local M = {}
local _state = setmetatable({}, { __mode = "k" })

---@class snacks.workspace.State
local State = {}
State.__index = State

---@param picker table
---@param opts table
function State.new(picker, opts)
    local self = setmetatable({}, State)
    return self
end

---@param opts {roots: {name:string, path:string}[], hidden?:boolean, ignored?:boolean, exclude?:string[], include?:string[], git_status_open?:boolean, diagnostics_open?:boolean}
---@param ctx table
function M.finder(opts, ctx)
    local roots = opts.roots or {}
    local filter_opts = {
        hidden  = opts.hidden,
        ignored = opts.ignored,
        exclude = opts.exclude,
        include = opts.include,
    }

    if ctx and ctx.picker and not _state[ctx.picker] then
        _state[ctx.picker] = State.new(ctx.picker, opts)
    end

    return function(cb)
        local items        = {}  -- path → picker item, for parent references
        local last_tracker = {}  -- Tree node → last picker item that is its child

        for _, folder in ipairs(roots) do
            Tree:refresh(folder.path)
            Tree:get(folder.path, function(node)
                local parent_item = node.parent and items[node.parent.path] or nil
                local status = node.status
                if not status and parent_item and parent_item.dir_status then
                    status = parent_item.dir_status
                end

                local item = {
                    file       = node.path,
                    dir        = node.dir,
                    open       = node.open,
                    dir_status = node.dir_status or (parent_item and parent_item.dir_status),
                    text       = node.path,
                    parent     = parent_item,
                    hidden     = node.hidden,
                    ignored    = node.ignored,
                    status     = (not node.dir or not node.open or opts.git_status_open) and status or nil,
                    last       = true,
                    type       = node.type,
                    severity   = (not node.dir or not node.open or opts.diagnostics_open) and node.severity or nil,
                }

                -- track last child per parent node (shared across roots handles inter-root boundary)
                if last_tracker[node.parent] then
                    last_tracker[node.parent].last = false
                end
                last_tracker[node.parent] = item

                -- root node: always visible regardless of hidden/ignored filters
                if node.path == folder.path then
                    item.hidden  = false
                    item.ignored = false
                end

                items[node.path] = item
                cb(item)
            end, filter_opts)
        end
    end
end

return M
```

- [ ] **Step 4: Run source tests to verify they pass**

```
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/snacks_spec.lua"
```

Expected: all tests in both `integrations/snacks/init` and `integrations/snacks/source` PASS.

- [ ] **Step 5: Run full suite**

```
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}"
```

Expected: all tests PASS (same counts as before).

- [ ] **Step 6: Commit**

```bash
git add lua/code-workspace/integrations/snacks/source.lua tests/snacks_spec.lua
git commit -m "feat: implement multi-root finder for workspace_explorer source"
```

---

### Task 4: Add State class for git, diagnostics, watch, and follow-file

**Files:**
- Modify: `lua/code-workspace/integrations/snacks/source.lua`

- [ ] **Step 1: Replace the stub State class with the full implementation**

In `lua/code-workspace/integrations/snacks/source.lua`, replace the stub State class:

```lua
---@class snacks.workspace.State
local State = {}
State.__index = State

---@param picker table
---@param opts table
function State.new(picker, opts)
    local self = setmetatable({}, State)
    return self
end
```

With the full State class:

```lua
---@class snacks.workspace.State
---@field on_find? fun()
local State = {}
State.__index = State

---@param picker table
---@param opts {roots:{name:string,path:string}[], git_status?:boolean, git_untracked?:boolean, diagnostics?:boolean, watch?:boolean, follow_file?:boolean}
function State.new(picker, opts)
    local self = setmetatable({}, State)
    local roots = opts.roots or {}

    local function ref()
        return not picker.closed and picker or nil
    end

    local function re_find()
        local p = ref()
        if p then
            p.list:set_target()
            p:find()
        end
    end

    -- Git status: one watcher per root
    if opts.git_status then
        for _, folder in ipairs(roots) do
            require("snacks.explorer.git").update(folder.path, {
                untracked = opts.git_untracked,
                on_update = re_find,
            })
        end
    end

    -- Diagnostics: global DiagnosticChanged, debounced, update all roots
    if opts.diagnostics then
        local dirty = false
        local diag_update = Snacks.util.debounce(function()
            dirty = false
            local p = ref()
            if p then
                local changed = false
                for _, folder in ipairs(roots) do
                    if require("snacks.explorer.diagnostics").update(folder.path) then
                        changed = true
                    end
                end
                if changed then
                    re_find()
                end
            end
        end, { ms = 200 })

        picker.list.win:on({ "InsertLeave", "DiagnosticChanged" }, function(_, ev)
            dirty = dirty or ev.event == "DiagnosticChanged"
            if vim.fn.mode() == "n" and dirty then
                diag_update()
            end
        end)
    end

    -- File watch: global watcher, refresh tree on write
    if opts.watch then
        require("snacks.explorer.watch").watch()
        picker.list.win:on("BufWritePost", function(_, ev)
            local p = ref()
            if p then
                Tree:refresh(ev.file)
                Actions.update(p)
            end
        end)
    end

    -- Follow file: on BufEnter, check all roots and scroll list to current file
    if opts.follow_file then
        local buf_file = vim.fs.normalize(
            vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(picker.main))
        )

        picker.list.win:on({ "WinEnter", "BufEnter" }, function(_, ev)
            vim.schedule(function()
                if ev.buf ~= vim.api.nvim_get_current_buf() then
                    return
                end
                local p = ref()
                if not p or p:is_focused() or not p:on_current_tab() or p.closed then
                    return
                end
                local win = vim.api.nvim_get_current_win()
                if vim.api.nvim_win_get_config(win).relative ~= "" then
                    return
                end
                local file = vim.fs.normalize(vim.api.nvim_buf_get_name(ev.buf))
                local item = p:current()
                if item and item.file == file then
                    return
                end
                for _, folder in ipairs(roots) do
                    if Tree:in_cwd(folder.path, file) then
                        Actions.update(p, { target = file })
                        return
                    end
                end
            end)
        end)

        if buf_file ~= "" then
            self.on_find = function()
                local p = ref()
                if p then
                    Actions.update(p, { target = buf_file })
                end
            end
        end
    end

    return self
end
```

- [ ] **Step 2: Run the full test suite**

```
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}"
```

Expected: all tests PASS. The State class is not directly tested in the unit suite (it depends on a live snacks picker with window objects); manual integration testing is required for git/diagnostics/watch/follow-file.

- [ ] **Step 3: Commit**

```bash
git add lua/code-workspace/integrations/snacks/source.lua
git commit -m "feat: add State class for git, diagnostics, watch and follow-file"
```
