describe("integrations/snacks", function()
    local integration
    local explorer_calls

    before_each(function()
        package.loaded["code-workspace.integrations.snacks"] = nil
        explorer_calls = {}
        _G.Snacks = {
            explorer = function(opts)
                table.insert(explorer_calls, opts)
            end,
        }
        integration = require("code-workspace.integrations.snacks")
        integration.setup()
    end)

    after_each(function()
        _G.Snacks = nil
        -- Clean up autocmds created by setup()
        vim.api.nvim_clear_autocmds({ event = "User", pattern = "WorkspaceLoaded" })
        vim.api.nvim_clear_autocmds({ event = "User", pattern = "WorkspaceClosed" })
    end)

    describe("WorkspaceLoaded", function()
        it("calls Snacks.explorer with all folder paths as roots", function()
            vim.api.nvim_exec_autocmds("User", {
                pattern = "WorkspaceLoaded",
                data = {
                    folders = {
                        { name = "app", path = "/srv/app" },
                        { name = "lib", path = "/srv/lib" },
                    },
                },
            })

            assert.equals(1, #explorer_calls)
            assert.same({ "/srv/app", "/srv/lib" }, explorer_calls[1].roots)
        end)

        it("calls Snacks.explorer with a single folder", function()
            vim.api.nvim_exec_autocmds("User", {
                pattern = "WorkspaceLoaded",
                data = {
                    folders = { { name = "root", path = "/tmp/proj" } },
                },
            })

            assert.equals(1, #explorer_calls)
            assert.same({ "/tmp/proj" }, explorer_calls[1].roots)
        end)

        it("does nothing when folders list is empty", function()
            vim.api.nvim_exec_autocmds("User", {
                pattern = "WorkspaceLoaded",
                data = { folders = {} },
            })

            assert.equals(0, #explorer_calls)
        end)

        it("does nothing when workspace data is nil", function()
            vim.api.nvim_exec_autocmds("User", {
                pattern = "WorkspaceLoaded",
                data = nil,
            })

            assert.equals(0, #explorer_calls)
        end)
    end)

    describe("WorkspaceClosed", function()
        it("calls Snacks.explorer with cwd as single root", function()
            local cwd = vim.fn.getcwd()
            vim.api.nvim_exec_autocmds("User", {
                pattern = "WorkspaceClosed",
                data = { file = "/tmp/test.code-workspace" },
            })

            assert.equals(1, #explorer_calls)
            assert.same({ cwd }, explorer_calls[1].roots)
        end)
    end)
end)
