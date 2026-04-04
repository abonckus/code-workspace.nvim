local M = {}

function M.setup()
    vim.api.nvim_create_autocmd("User", {
        pattern  = "WorkspaceLoaded",
        callback = function(ev)
            local workspace = ev.data
            if not workspace or not workspace.folders or #workspace.folders == 0 then
                return
            end
            local roots = vim.tbl_map(function(f) return f.path end, workspace.folders)
            Snacks.explorer({ roots = roots })
        end,
    })

    vim.api.nvim_create_autocmd("User", {
        pattern  = "WorkspaceClosed",
        callback = function()
            Snacks.explorer({ roots = { vim.fn.getcwd() } })
        end,
    })
end

return M
