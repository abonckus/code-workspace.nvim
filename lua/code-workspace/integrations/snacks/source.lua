local Tree    = require("snacks.explorer.tree")
local Actions = require("snacks.explorer.actions")

local M = {}
local _state = setmetatable({}, { __mode = "k" })

---@class snacks.workspace.State
local State = {}
State.__index = State

---@param picker table
---@param opts table
function State.new(picker, opts)
    local self = setmetatable({}, State)
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
