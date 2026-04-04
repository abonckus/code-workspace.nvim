local loader

local function make_workspace(overrides)
    local ws = {
        file     = "/tmp/test.code-workspace",
        name     = "Test",
        folders  = { { name = "root", path = "/tmp" } },
        settings = {},
    }
    if overrides then
        for k, v in pairs(overrides) do ws[k] = v end
    end
    return ws
end

describe("loader", function()
    before_each(function()
        package.loaded["code-workspace.loader"] = nil
        loader = require("code-workspace.loader")
    end)

    describe("active", function()
        it("returns nil when no workspace is loaded", function()
            assert.is_nil(loader.active())
        end)
    end)

    describe("load", function()
        it("sets active workspace", function()
            local ws = make_workspace()
            loader.load(ws)
            assert.equals(ws, loader.active())
            loader.close()
        end)

        it("changes cwd to workspace file directory", function()
            local original_cwd = vim.fn.getcwd()
            local ws = make_workspace({ file = "/tmp/test.code-workspace" })
            loader.load(ws)
            assert.equals(vim.fn.fnamemodify("/tmp", ":p"):gsub("[/\\]+$", ""), vim.fn.getcwd())
            loader.close()
            vim.fn.chdir(original_cwd)
        end)

        it("fires WorkspaceLoaded autocmd", function()
            local fired = false
            local received_data = nil
            local id = vim.api.nvim_create_autocmd("User", {
                pattern  = "WorkspaceLoaded",
                callback = function(ev)
                    fired = true
                    received_data = ev.data
                end,
            })
            local ws = make_workspace()
            loader.load(ws)
            assert.is_true(fired)
            assert.same(ws, received_data)
            vim.api.nvim_del_autocmd(id)
            loader.close()
        end)

        it("closes previous workspace before loading a new one", function()
            local closed = false
            local id = vim.api.nvim_create_autocmd("User", {
                pattern  = "WorkspaceClosed",
                callback = function() closed = true end,
            })
            loader.load(make_workspace({ name = "First" }))
            loader.load(make_workspace({ name = "Second" }))
            assert.is_true(closed)
            assert.equals("Second", loader.active().name)
            vim.api.nvim_del_autocmd(id)
            loader.close()
        end)
    end)

    describe("close", function()
        it("clears active workspace", function()
            loader.load(make_workspace())
            loader.close()
            assert.is_nil(loader.active())
        end)

        it("fires WorkspaceClosed autocmd", function()
            local fired = false
            local received_data = nil
            loader.load(make_workspace())
            local id = vim.api.nvim_create_autocmd("User", {
                pattern  = "WorkspaceClosed",
                callback = function(ev)
                    fired = true
                    received_data = ev.data
                end,
            })
            loader.close()
            assert.is_true(fired)
            assert.is_string(received_data.file)
            vim.api.nvim_del_autocmd(id)
        end)

        it("restores previous cwd", function()
            local original_cwd = vim.fn.getcwd()
            loader.load(make_workspace({ file = "/tmp/test.code-workspace" }))
            loader.close()
            assert.equals(original_cwd, vim.fn.getcwd())
        end)

        it("is a no-op when no workspace is active", function()
            assert.has_no.errors(function()
                loader.close()
            end)
        end)

        it("sends workspace/didChangeWorkspaceFolders to LSP clients with removed folders", function()
            local notified = {}
            local mock_client = {
                server_capabilities = {
                    workspace = {
                        workspaceFolders = { changeNotifications = true },
                    },
                },
                notify = function(method, params)
                    table.insert(notified, { method = method, params = params })
                end,
            }
            local orig = vim.lsp.get_clients
            vim.lsp.get_clients = function() return { mock_client } end

            local ws = make_workspace()
            loader.load(ws)
            loader.close()

            vim.lsp.get_clients = orig

            local removed_call = nil
            for _, call in ipairs(notified) do
                if #call.params.event.removed > 0 then
                    removed_call = call
                end
            end
            assert.is_not_nil(removed_call)
            assert.equals("workspace/didChangeWorkspaceFolders", removed_call.method)
            assert.equals(1, #removed_call.params.event.removed)
        end)
    end)
end)
