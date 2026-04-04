local M = {}

local _active   = nil
local _prev_cwd = nil

local function lsp_folder_uris(folders)
    return vim.tbl_map(function(f)
        return { uri = vim.uri_from_fname(f.path), name = f.name }
    end, folders)
end

local function notify_lsp(folders, action)
    local added   = action == "added"   and lsp_folder_uris(folders) or {}
    local removed = action == "removed" and lsp_folder_uris(folders) or {}

    local params = { event = { added = added, removed = removed } }

    for _, client in ipairs(vim.lsp.get_clients()) do
        local caps = client.server_capabilities
        if caps
            and caps.workspace
            and caps.workspace.workspaceFolders
            and caps.workspace.workspaceFolders.changeNotifications
        then
            client.notify("workspace/didChangeWorkspaceFolders", params)
        end
    end
end

function M.load(workspace)
    if _active then
        M.close()
    end

    _prev_cwd = vim.fn.getcwd()
    _active   = workspace

    vim.fn.chdir(vim.fn.fnamemodify(workspace.file, ":p:h"))
    notify_lsp(workspace.folders, "added")

    vim.api.nvim_exec_autocmds("User", {
        pattern = "WorkspaceLoaded",
        data    = workspace,
    })
end

function M.close()
    if not _active then
        return
    end

    notify_lsp(_active.folders, "removed")

    vim.api.nvim_exec_autocmds("User", {
        pattern = "WorkspaceClosed",
        data    = { file = _active.file },
    })

    if _prev_cwd then
        vim.fn.chdir(_prev_cwd)
        _prev_cwd = nil
    end

    _active = nil
end

function M.active()
    return _active
end

return M
