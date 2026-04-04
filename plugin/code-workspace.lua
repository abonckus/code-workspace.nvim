-- Guard: only run once
if vim.g.loaded_code_workspace then
    return
end
vim.g.loaded_code_workspace = true

-- Allow users to call setup() themselves; if they don't, run with defaults on VimEnter
vim.api.nvim_create_autocmd("VimEnter", {
    once     = true,
    callback = function()
        if not vim.g.code_workspace_setup_called then
            require("code-workspace").setup()
        end
    end,
})
