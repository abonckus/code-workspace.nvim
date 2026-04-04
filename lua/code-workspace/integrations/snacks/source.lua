local Tree    = require("snacks.explorer.tree")
local Actions = require("snacks.explorer.actions")

local M = {}
local _state = setmetatable({}, { __mode = "k" })

---@class snacks.workspace.State
---@field on_find? fun()
local State = {}
State.__index = State

---@param picker table
---@param opts {roots:{name:string,path:string}[], git_status?:boolean, git_untracked?:boolean, diagnostics?:boolean, watch?:boolean, follow_file?:boolean}
function State.new(picker, opts)
    local self = setmetatable({}, State)
    local roots = opts.roots or {}

    local function ref()
        return not picker.closed and picker or nil
    end

    local function re_find()
        local p = ref()
        if p then
            p.list:set_target()
            p:find()
        end
    end

    -- Git status: one watcher per root
    if opts.git_status then
        for _, folder in ipairs(roots) do
            require("snacks.explorer.git").update(folder.path, {
                untracked = opts.git_untracked,
                on_update = re_find,
            })
        end
    end

    -- Diagnostics: global DiagnosticChanged, debounced, update all roots
    if opts.diagnostics then
        local dirty = false
        local diag_update = Snacks.util.debounce(function()
            dirty = false
            local p = ref()
            if p then
                local changed = false
                for _, folder in ipairs(roots) do
                    if require("snacks.explorer.diagnostics").update(folder.path) then
                        changed = true
                    end
                end
                if changed then
                    re_find()
                end
            end
        end, { ms = 200 })

        picker.list.win:on({ "InsertLeave", "DiagnosticChanged" }, function(_, ev)
            dirty = dirty or ev.event == "DiagnosticChanged"
            if vim.fn.mode() == "n" and dirty then
                diag_update()
            end
        end)
    end

    -- File watch: global watcher, refresh tree on write
    if opts.watch then
        require("snacks.explorer.watch").watch()
        picker.list.win:on("BufWritePost", function(_, ev)
            local p = ref()
            if p then
                Tree:refresh(ev.file)
                Actions.update(p)
            end
        end)
    end

    -- Follow file: on BufEnter, check all roots and scroll list to current file
    if opts.follow_file then
        local buf_file = vim.fs.normalize(
            vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(picker.main))
        )

        picker.list.win:on({ "WinEnter", "BufEnter" }, function(_, ev)
            vim.schedule(function()
                if ev.buf ~= vim.api.nvim_get_current_buf() then
                    return
                end
                local p = ref()
                if not p or p:is_focused() or not p:on_current_tab() or p.closed then
                    return
                end
                local win = vim.api.nvim_get_current_win()
                if vim.api.nvim_win_get_config(win).relative ~= "" then
                    return
                end
                local file = vim.fs.normalize(vim.api.nvim_buf_get_name(ev.buf))
                local item = p:current()
                if item and item.file == file then
                    return
                end
                for _, folder in ipairs(roots) do
                    if Tree:in_cwd(folder.path, file) then
                        Actions.update(p, { target = file })
                        return
                    end
                end
            end)
        end)

        if buf_file ~= "" then
            self.on_find = function()
                local p = ref()
                if p then
                    Actions.update(p, { target = buf_file })
                end
            end
        end
    end

    return self
end

---@param opts {roots: {name:string, path:string}[], hidden?:boolean, ignored?:boolean, exclude?:string[], include?:string[], git_status_open?:boolean, diagnostics_open?:boolean}
---@param ctx table
function M.finder(opts, ctx)
    local roots = opts.roots or {}
    local filter_opts = {
        hidden  = opts.hidden,
        ignored = opts.ignored,
        exclude = opts.exclude,
        include = opts.include,
    }

    if ctx and ctx.picker and not _state[ctx.picker] then
        _state[ctx.picker] = State.new(ctx.picker, opts)
    end

    return function(cb)
        local items        = {}  -- path → picker item, for parent references
        local last_tracker = {}  -- Tree node → last picker item that is its child

        for _, folder in ipairs(roots) do
            Tree:refresh(folder.path)
            Tree:get(folder.path, function(node)
                local parent_item = node.parent and items[node.parent.path] or nil
                local status = node.status
                if not status and parent_item and parent_item.dir_status then
                    status = parent_item.dir_status
                end

                local item = {
                    file       = node.path,
                    dir        = node.dir,
                    open       = node.open,
                    dir_status = node.dir_status or (parent_item and parent_item.dir_status),
                    text       = node.path,
                    parent     = parent_item,
                    hidden     = node.hidden,
                    ignored    = node.ignored,
                    status     = (not node.dir or not node.open or opts.git_status_open) and status or nil,
                    last       = true,
                    type       = node.type,
                    severity   = (not node.dir or not node.open or opts.diagnostics_open) and node.severity or nil,
                }

                -- track last child per parent node (shared across roots handles inter-root boundary)
                if last_tracker[node.parent] then
                    last_tracker[node.parent].last = false
                end
                last_tracker[node.parent] = item

                -- root node: always visible regardless of hidden/ignored filters
                if node.path == folder.path then
                    item.hidden  = false
                    item.ignored = false
                end

                items[node.path] = item
                cb(item)
            end, filter_opts)
        end
    end
end

return M
