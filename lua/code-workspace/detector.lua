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

--- Recursively find all *.code-workspace files anywhere under a project
--- root (detected via .git, falling back to dir itself). Used by
--- ":Workspace open" as a last resort when M._scan (cwd + N parents) finds
--- nothing -- e.g. a workspace file living in a subdirectory like
--- apps/Apps.code-workspace rather than the repo root.
---@param dir string Starting directory
---@return string[] List of absolute file paths found
function M._scan_recursive(dir)
    local root = vim.fs.root(dir, ".git") or dir
    return vim.fn.glob(root .. "/**/*.code-workspace", false, true)
end

--- After the .code-workspace buffer is wiped, surface the loaded workspace like
--- VS Code does when opening a workspace: a start page in the main window (its
--- Welcome tab) plus the explorer sidebar showing all roots.
---
--- The dashboard is opened into the current window (win = 0), NOT via a plain
--- Snacks.dashboard.open(): called mid-session that spawns a full-screen
--- floating dashboard + backdrop that never closes, so files open into the
--- float and the real window layout is corrupted. Opened before the explorer so
--- win = 0 lands on the main window rather than the picker.
local function show_landing()
    local ok, snacks = pcall(require, "snacks")
    if ok and snacks.dashboard then
        snacks.dashboard.open({ win = 0 })
    end
    require("code-workspace").explorer()
end

local function wipe_buf(filepath)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_get_name(buf) == filepath then
            vim.schedule(function()
                -- Landing first so the window moves off the .code-workspace
                -- buffer; deleting it after (while no window shows it) avoids
                -- nvim spawning a replacement empty [No Name] buffer.
                show_landing()
                if vim.api.nvim_buf_is_valid(buf) then
                    vim.api.nvim_buf_delete(buf, { force = true })
                end
            end)
            return
        end
    end
end

local function on_startup(cfg)
    -- Always check if a .code-workspace file was passed as a command-line argument.
    -- BufRead fires before VimEnter so detect_on_buf_read cannot catch this case.
    for i = 0, vim.fn.argc() - 1 do
        local arg = vim.fn.fnamemodify(vim.fn.argv(i) --[[@as string]], ":p")
        if arg:match("%.code%-workspace$") and vim.fn.filereadable(arg) == 1 then
            load_file(arg)
            wipe_buf(arg)
            return
        end
    end

    -- CWD scan is opt-in via detect_on_startup.
    if not cfg.detect_on_startup then
        return
    end

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
    -- on_startup always runs: it checks argv unconditionally, then optionally
    -- scans cwd based on cfg.detect_on_startup.
    if vim.v.vim_did_enter == 1 then
        on_startup(cfg)
    else
        vim.api.nvim_create_autocmd("VimEnter", {
            once = true,
            callback = function()
                on_startup(cfg)
            end,
        })
    end

    if cfg.detect_on_buf_read then
        vim.api.nvim_create_autocmd("BufRead", {
            pattern = "*.code-workspace",
            callback = function(ev)
                local workspace, err = parser.parse(ev.file)
                if not workspace then
                    vim.notify("[code-workspace] " .. err, vim.log.levels.ERROR)
                    return
                end
                loader.load(workspace)
                vim.schedule(function()
                    -- See wipe_buf: landing first, then delete, to avoid a
                    -- leftover empty [No Name] buffer.
                    show_landing()
                    if vim.api.nvim_buf_is_valid(ev.buf) then
                        vim.api.nvim_buf_delete(ev.buf, { force = true })
                    end
                end)
            end,
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
                    -- Nothing found scanning cwd + parents: fall back to a
                    -- recursive scan of the whole project (e.g. a workspace
                    -- file living in a subdirectory, not the repo root).
                    files = M._scan_recursive(vim.fn.getcwd())
                end
                if #files == 0 then
                    vim.notify("[code-workspace] no .code-workspace files found", vim.log.levels.WARN)
                    return
                end
                if #files == 1 then
                    load_file(files[1])
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
        nargs = "*",
        complete = function()
            return { "open", "close", "status" }
        end,
    })
end

return M
