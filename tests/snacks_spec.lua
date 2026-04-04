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
