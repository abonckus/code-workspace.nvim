local M = {}

function M.setup()
    vim.api.nvim_create_autocmd("User", {
        pattern = "WorkspaceClosed",
        callback = function()
            local pickers = Snacks.picker.get({ source = "workspace_explorer" })
            if pickers[1] then
                pickers[1]:close()
            end
            Snacks.explorer({ cwd = vim.fn.getcwd() })
        end,
    })
end

function M.open(workspace)
    if not workspace or not workspace.folders or #workspace.folders == 0 then
        return
    end
    local base = vim.deepcopy(Snacks.picker.sources.explorer)
    local config = vim.tbl_deep_extend("force", base, {
        source = "workspace_explorer",
        finder = require("code-workspace.integrations.snacks.source").finder,
        roots = workspace.folders,
    })
    Snacks.picker.pick(config)
end

return M
