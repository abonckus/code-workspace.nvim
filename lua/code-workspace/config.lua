local M = {}

M.defaults = {
    detect_on_startup  = true,
    detect_on_buf_read = true,
    scan_depth         = 1,
    integrations       = {
        neo_tree = nil,
    },
    on_load  = nil,
    on_close = nil,
}

function M.resolve(user_opts)
    return vim.tbl_deep_extend("force", M.defaults, user_opts or {})
end

return M
