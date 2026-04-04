local M = {}

--- Parse a .code-workspace file.
--- Returns a workspace table on success, or nil + error string on failure.
---@param filepath string Absolute path to the .code-workspace file
---@return table|nil workspace
---@return string|nil error
function M.parse(filepath)
    local f = io.open(filepath, "r")
    if not f then
        return nil, "cannot open file: " .. filepath
    end
    local content = f:read("*a")
    f:close()

    local ok, data = pcall(vim.fn.json_decode, content)
    if not ok or type(data) ~= "table" then
        return nil, "invalid JSON in " .. filepath
    end

    if not data.folders or #data.folders == 0 then
        return nil, "workspace has no folders: " .. filepath
    end

    local abs_file = vim.fn.fnamemodify(filepath, ":p")
    local workspace_dir = vim.fn.fnamemodify(abs_file, ":h")

    local folders = {}
    for _, folder in ipairs(data.folders) do
        local path = folder.path
        if vim.fn.isabsolutepath(path) == 0 then
            path = workspace_dir .. "/" .. path
        end
        path = vim.fn.fnamemodify(path, ":p"):gsub("[/\\]+$", "")
        if vim.fn.isdirectory(path) == 0 then
            vim.notify("[code-workspace] folder does not exist: " .. path, vim.log.levels.WARN)
        end
        table.insert(folders, {
            name = folder.name or vim.fn.fnamemodify(path, ":t"),
            path = path,
        })
    end

    return {
        file     = abs_file,
        name     = data.name or vim.fn.fnamemodify(abs_file, ":t:r"),
        folders  = folders,
        settings = data.settings or {},
    }
end

return M
