local M = {}

--- Strip JSONC extensions (// comments, /* */ comments, trailing commas) from a string.
--- String-aware: tracks whether each character is inside a JSON string literal
--- (respecting backslash escapes) so that //, /* or a trailing comma pattern
--- occurring inside string values (e.g. URLs in settings) is left untouched.
---@param text string Raw file content
---@return string Strict JSON
local function strip_jsonc(text)
    local out = {}
    local len = #text
    local i = 1
    local in_string = false
    -- Buffered whitespace following a comma seen outside a string, held back
    -- until we know whether the next non-whitespace char is ] or } (trailing
    -- comma, drop both) or something else (comma was real, flush it).
    local pending_comma_ws = nil

    local function flush_pending()
        if pending_comma_ws then
            out[#out + 1] = ","
            out[#out + 1] = pending_comma_ws
            pending_comma_ws = nil
        end
    end

    while i <= len do
        local c = text:sub(i, i)

        if in_string then
            flush_pending()
            out[#out + 1] = c
            if c == "\\" and i < len then
                -- Copy the escaped character verbatim so an escaped quote
                -- (\") doesn't end the string, and so we don't misparse the
                -- following character as its own escape sequence.
                out[#out + 1] = text:sub(i + 1, i + 1)
                i = i + 2
            else
                if c == '"' then
                    in_string = false
                end
                i = i + 1
            end
        elseif c == '"' then
            flush_pending()
            in_string = true
            out[#out + 1] = c
            i = i + 1
        elseif c == "/" and text:sub(i + 1, i + 1) == "/" then
            flush_pending()
            -- Line comment: skip to end of line, keep the newline itself.
            local nl = text:find("\n", i, true)
            i = nl or (len + 1)
        elseif c == "/" and text:sub(i + 1, i + 1) == "*" then
            flush_pending()
            -- Block comment: skip to closing */ (or EOF if unterminated).
            local close = text:find("*/", i + 2, true)
            i = close and (close + 2) or (len + 1)
        elseif c == "," and not pending_comma_ws then
            -- Start buffering: hold this comma back until we see what
            -- follows any whitespace/comments after it.
            pending_comma_ws = ""
            i = i + 1
        elseif pending_comma_ws and c:match("%s") then
            pending_comma_ws = pending_comma_ws .. c
            i = i + 1
        elseif pending_comma_ws and (c == "]" or c == "}") then
            -- Trailing comma: drop the buffered comma and whitespace.
            pending_comma_ws = nil
            out[#out + 1] = c
            i = i + 1
        else
            flush_pending()
            out[#out + 1] = c
            i = i + 1
        end
    end
    flush_pending()

    return table.concat(out)
end

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

    local ok, data = pcall(vim.fn.json_decode, strip_jsonc(content))
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
        file = abs_file,
        name = data.name or vim.fn.fnamemodify(abs_file, ":t:r"),
        folders = folders,
        settings = data.settings or {},
    }
end

return M
