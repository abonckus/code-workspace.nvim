local M = {}

local parser = require("code-workspace.parser")
local loader = require("code-workspace.loader")

local function load_file(filepath)
    local workspace, err = parser.parse(filepath)
    if not workspace then
        vim.notify("[code-workspace] " .. err, vim.log.levels.ERROR)
        return
    end
    loader.load(workspace)
end

--- Scan dir (and parents up to depth) for *.code-workspace files.
---@param dir string Starting directory
---@param depth number How many levels up to scan (0 = cwd only)
---@return string[] List of absolute file paths found
function M._scan(dir, depth)
    local files = vim.fn.glob(dir .. "/*.code-workspace", false, true)
    if #files > 0 then
        return files
    end
    if depth > 0 then
        local parent = vim.fn.fnamemodify(dir, ":h")
        if parent ~= dir then
            return M._scan(parent, depth - 1)
        end
    end
    return {}
end

local function on_startup(cfg)
    local files = M._scan(vim.fn.getcwd(), cfg.scan_depth)
    if #files == 0 then
        return
    end
    if #files == 1 then
        load_file(files[1])
    else
        vim.ui.select(files, { prompt = "Select workspace:" }, function(choice)
            if choice then
                load_file(choice)
            end
        end)
    end
end

function M.setup(cfg)
    if cfg.detect_on_startup then
        vim.api.nvim_create_autocmd("VimEnter", {
            once     = true,
            callback = function() on_startup(cfg) end,
        })
    end

    if cfg.detect_on_buf_read then
        vim.api.nvim_create_autocmd("BufRead", {
            pattern  = "*.code-workspace",
            callback = function(ev) load_file(ev.file) end,
        })
    end

    vim.api.nvim_create_user_command("Workspace", function(opts)
        local subcmd = opts.fargs[1]
        if subcmd == "open" then
            if opts.fargs[2] then
                load_file(opts.fargs[2])
            else
                local files = M._scan(vim.fn.getcwd(), cfg.scan_depth)
                if #files == 0 then
                    vim.notify("[code-workspace] no .code-workspace files found", vim.log.levels.WARN)
                    return
                end
                vim.ui.select(files, { prompt = "Select workspace:" }, function(choice)
                    if choice then
                        load_file(choice)
                    end
                end)
            end
        elseif subcmd == "close" then
            loader.close()
        elseif subcmd == "status" then
            local active = loader.active()
            if active then
                vim.notify(("[code-workspace] active: %s (%d folders)"):format(active.name, #active.folders))
            else
                vim.notify("[code-workspace] no workspace active")
            end
        else
            vim.notify("[code-workspace] unknown subcommand: " .. (subcmd or ""), vim.log.levels.ERROR)
        end
    end, {
        nargs    = "*",
        complete = function() return { "open", "close", "status" } end,
    })
end

return M
