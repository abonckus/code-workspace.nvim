local M = {}

function M.setup(opts)
    vim.g.code_workspace_setup_called = true

    local cfg      = require("code-workspace.config").resolve(opts)
    local loader   = require("code-workspace.loader")
    local detector = require("code-workspace.detector")

    -- Notify late-attaching LSP clients about current workspace folders
    vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(ev)
            local active = loader.active()
            if not active then
                return
            end
            local client = vim.lsp.get_client_by_id(ev.data.client_id)
            if not client then
                return
            end
            local uris = vim.tbl_map(function(f)
                return { uri = vim.uri_from_fname(f.path), name = f.name }
            end, active.folders)
            client.notify("workspace/didChangeWorkspaceFolders", {
                event = { added = uris, removed = {} },
            })
        end,
    })

    -- Neo-tree integration
    local neo_tree_enabled = cfg.integrations.neo_tree
    if neo_tree_enabled == nil then
        neo_tree_enabled = pcall(require, "neo-tree")
    end
    if neo_tree_enabled then
        local ok, integration = pcall(require, "code-workspace.integrations.neo-tree")
        if ok then
            integration.setup()
        end
    end

    -- User hooks
    if cfg.on_load then
        vim.api.nvim_create_autocmd("User", {
            pattern  = "WorkspaceLoaded",
            callback = function(ev) cfg.on_load(ev.data) end,
        })
    end
    if cfg.on_close then
        vim.api.nvim_create_autocmd("User", {
            pattern  = "WorkspaceClosed",
            callback = function(ev) cfg.on_close(ev.data) end,
        })
    end

    detector.setup(cfg)
end

function M.load(filepath)
    local parser  = require("code-workspace.parser")
    local loader  = require("code-workspace.loader")
    local ws, err = parser.parse(filepath)
    if not ws then
        vim.notify("[code-workspace] " .. err, vim.log.levels.ERROR)
        return
    end
    loader.load(ws)
end

function M.close()
    require("code-workspace.loader").close()
end

function M.active()
    return require("code-workspace.loader").active()
end

return M
