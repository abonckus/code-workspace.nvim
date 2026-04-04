-- Add the plugin root to runtimepath so tests can require("code-workspace.*")
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h"))

-- Add plenary from the lazy.nvim cache
local plenary_path = vim.fn.stdpath("data") .. "/lazy/plenary.nvim"
if vim.fn.isdirectory(plenary_path) == 1 then
    vim.opt.runtimepath:append(plenary_path)
end
