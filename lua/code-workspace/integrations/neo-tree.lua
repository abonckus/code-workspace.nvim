local M = {}

function M.setup()
    vim.api.nvim_create_autocmd("User", {
        pattern  = "WorkspaceLoaded",
        callback = function(ev)
            local workspace = ev.data
            if not workspace or not workspace.folders or #workspace.folders == 0 then
                return
            end
            -- Primary root: first folder
            vim.cmd("Neotree dir=" .. vim.fn.fnameescape(workspace.folders[1].path))
            -- Additional folders as right-side splits
            for i = 2, #workspace.folders do
                vim.cmd(
                    "Neotree dir="
                        .. vim.fn.fnameescape(workspace.folders[i].path)
                        .. " position=right"
                )
            end
        end,
    })
end

return M
