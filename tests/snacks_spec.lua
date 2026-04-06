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

        pick_calls     = {}
        explorer_calls = {}
        mock_picker    = { closed = false, close = function(self) self.closed = true end }
        get_result     = {}

        _G.Snacks = {
            picker = {
                sources = {
                    explorer = {
                        layout     = { preset = "sidebar" },
                        tree       = true,
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

    describe("open()", function()
        it("calls Snacks.picker.pick with source workspace_explorer", function()
            integration.open({ folders = { { name = "app", path = "/srv/app" } } })

            assert.equals(1, #pick_calls)
            assert.equals("workspace_explorer", pick_calls[1].source)
        end)

        it("passes workspace folders as roots", function()
            local folders = {
                { name = "app", path = "/srv/app" },
                { name = "lib", path = "/srv/lib" },
            }
            integration.open({ folders = folders })

            assert.same(folders, pick_calls[1].roots)
        end)

        it("inherits standard explorer config as base", function()
            integration.open({ folders = { { name = "app", path = "/srv/app" } } })

            -- layout from Snacks.picker.sources.explorer is present
            assert.same({ preset = "sidebar" }, pick_calls[1].layout)
            assert.is_true(pick_calls[1].tree)
        end)

        it("does not mutate Snacks.picker.sources.explorer", function()
            integration.open({ folders = { { name = "app", path = "/srv/app" } } })

            -- source field must not leak into the original table
            assert.is_nil(Snacks.picker.sources.explorer.source)
        end)

        it("does nothing when folders list is empty", function()
            integration.open({ folders = {} })
            assert.equals(0, #pick_calls)
        end)

        it("does nothing when workspace is nil", function()
            integration.open(nil)
            assert.equals(0, #pick_calls)
        end)

        it("WorkspaceLoaded does not auto-open the picker", function()
            fire("WorkspaceLoaded", { folders = { { name = "app", path = "/srv/app" } } })
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

describe("integrations/snacks/source", function()
    local source
    local tree_calls   -- { refresh = [...], get = [...] }
    local yielded      -- items collected by calling the finder's return function

    local function make_node(path, opts)
        opts = opts or {}
        return {
            path       = path,
            name       = vim.fs.basename(path),
            dir        = opts.dir,
            open       = opts.open,
            hidden     = opts.hidden or false,
            ignored    = opts.ignored or false,
            status     = opts.status,
            dir_status = opts.dir_status,
            type       = opts.dir and "directory" or "file",
            severity   = opts.severity,
            parent     = opts.parent,
        }
    end

    local mock_find_nodes  -- path → node, controls what Tree:find returns

    before_each(function()
        package.loaded["code-workspace.integrations.snacks.source"] = nil
        tree_calls      = { refresh = {}, get = {} }
        yielded         = {}
        mock_find_nodes = {}

        -- Mock Tree singleton
        -- shared_virtual_root ensures default Tree:find nodes share one parent
        -- reference, so last_tracker works correctly across roots in tests.
        local shared_virtual_root = { path = "" }
        package.loaded["snacks.explorer.tree"] = {
            refresh = function(self, path)
                table.insert(tree_calls.refresh, path)
            end,
            find = function(self, path)
                if not mock_find_nodes[path] then
                    mock_find_nodes[path] = {
                        path   = path,
                        open   = nil,
                        dir    = true,
                        type   = "directory",
                        hidden = false,
                        parent = shared_virtual_root,
                    }
                end
                return mock_find_nodes[path]
            end,
            get = function(self, cwd, cb, filter_opts)
                table.insert(tree_calls.get, { cwd = cwd, filter_opts = filter_opts })
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

        -- Mark /b and /c open=true so non-first-root default-collapse is overridden.
        mock_find_nodes["/b"] = make_node("/b", { dir = true, open = true, parent = virtual_root })
        mock_find_nodes["/c"] = make_node("/c", { dir = true, open = true, parent = virtual_root })

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
        local root_node = make_node("/r", { dir = true, parent = virtual_root })
        local child_1   = make_node("/r/x", { dir = false, parent = root_node })
        local child_2   = make_node("/r/y", { dir = false, parent = root_node })

        run_finder(
            { { name = "r", path = "/r" } },
            { { root_node, child_1, child_2 } }
        )

        assert.is_true(yielded[1].last)   -- root is last (only root)
        assert.is_false(yielded[2].last)  -- child_1 not last (child_2 follows)
        assert.is_true(yielded[3].last)   -- child_2 is last child of root_node
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
        local root_node = make_node("/r", { dir = true, parent = virtual_root })
        local child     = make_node("/r/x", { parent = root_node })

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

    describe("collapsed roots", function()
        it("collapses non-first roots by default (open=nil)", function()
            local get_called_for = {}
            package.loaded["snacks.explorer.tree"].get = function(self, cwd, cb)
                table.insert(get_called_for, cwd)
            end

            local ctx = { picker = {} }
            local gen = source.finder({
                roots = {
                    { name = "a", path = "/a" },
                    { name = "b", path = "/b" },
                    { name = "c", path = "/c" },
                },
            }, ctx)
            gen(function(item) table.insert(yielded, item) end)

            -- Only /a (first root) should trigger Tree:get; /b and /c collapsed by default
            assert.equals(1, #get_called_for)
            assert.equals("/a", get_called_for[1])
            -- /b and /c yielded as collapsed root items
            assert.equals("/b", yielded[1].file)
            assert.equals("/c", yielded[2].file)
        end)

        it("expands non-first root when user has explicitly opened it (open=true)", function()
            local virtual_root = { path = "" }
            mock_find_nodes["/b"] = make_node("/b", { dir = true, open = true, parent = virtual_root })

            local get_called_for = {}
            local node_b = make_node("/b", { dir = true, parent = virtual_root })
            package.loaded["snacks.explorer.tree"].get = function(self, cwd, cb)
                table.insert(get_called_for, cwd)
                if cwd == "/b" then cb(node_b) end
            end

            local ctx = { picker = {} }
            local gen = source.finder({
                roots = { { name = "a", path = "/a" }, { name = "b", path = "/b" } },
            }, ctx)
            gen(function(item) table.insert(yielded, item) end)

            -- /b explicitly open=true → Tree:get called for both /a and /b
            assert.equals(2, #get_called_for)
        end)

        it("yields only root item when root open=false, skips Tree:get", function()
            local virtual_root = { path = "" }
            mock_find_nodes["/a"] = make_node("/a", {
                dir    = true,
                open   = false,
                parent = virtual_root,
            })
            local get_called = false
            package.loaded["snacks.explorer.tree"].get = function()
                get_called = true
            end

            local ctx = { picker = {} }
            local gen = source.finder({ roots = { { name = "a", path = "/a" } } }, ctx)
            gen(function(item) table.insert(yielded, item) end)

            assert.is_false(get_called)
            assert.equals(1, #yielded)
            assert.equals("/a", yielded[1].file)
            assert.is_false(yielded[1].open)
        end)

        it("calls Tree:get when root open=nil (first visit)", function()
            local get_called = false
            package.loaded["snacks.explorer.tree"].get = function(self, cwd, cb)
                get_called = true
            end

            local ctx = { picker = {} }
            local gen = source.finder({ roots = { { name = "a", path = "/a" } } }, ctx)
            gen(function(item) table.insert(yielded, item) end)

            assert.is_true(get_called)
        end)

        it("calls Tree:get when root open=true", function()
            local virtual_root = { path = "" }
            mock_find_nodes["/a"] = make_node("/a", {
                dir    = true,
                open   = true,
                parent = virtual_root,
            })
            local get_called = false
            package.loaded["snacks.explorer.tree"].get = function(self, cwd, cb)
                get_called = true
            end

            local ctx = { picker = {} }
            local gen = source.finder({ roots = { { name = "a", path = "/a" } } }, ctx)
            gen(function(item) table.insert(yielded, item) end)

            assert.is_true(get_called)
        end)

        it("collapsed root has correct last flags alongside open roots", function()
            local virtual_root = { path = "" }
            -- /a is collapsed, /b is explicitly open
            mock_find_nodes["/a"] = make_node("/a", { dir = true, open = false, parent = virtual_root })
            -- /b must be open=true so it isn't treated as a default-collapsed non-first root
            mock_find_nodes["/b"] = make_node("/b", { dir = true, open = true, parent = virtual_root })

            local call_index = 0
            local node_b = make_node("/b", { dir = true, parent = virtual_root })
            package.loaded["snacks.explorer.tree"].get = function(self, cwd, cb)
                call_index = call_index + 1
                if cwd == "/b" then cb(node_b) end
            end

            local ctx = { picker = {} }
            local gen = source.finder({
                roots = { { name = "a", path = "/a" }, { name = "b", path = "/b" } },
            }, ctx)
            gen(function(item) table.insert(yielded, item) end)

            assert.equals(2, #yielded)
            assert.equals("/a", yielded[1].file)
            assert.is_false(yielded[1].last)  -- /a not last, /b follows
            assert.equals("/b", yielded[2].file)
            assert.is_true(yielded[2].last)   -- /b is last root
        end)
    end)
end)
