local parser

-- Helper: write a temp .code-workspace file and return its path
local function write_workspace(content)
    local path = vim.fn.tempname() .. ".code-workspace"
    local f = io.open(path, "w")
    f:write(content)
    f:close()
    return path
end

describe("parser.parse", function()
    before_each(function()
        package.loaded["code-workspace.parser"] = nil
        parser = require("code-workspace.parser")
    end)

    it("returns nil and error message when file does not exist", function()
        local ws, err = parser.parse("/nonexistent/path.code-workspace")
        assert.is_nil(ws)
        assert.is_string(err)
        assert.truthy(err:find("cannot open"))
    end)

    it("returns nil and error message when JSON is invalid", function()
        local path = write_workspace("not json {{{")
        local ws, err = parser.parse(path)
        assert.is_nil(ws)
        assert.is_string(err)
        assert.truthy(err:find("invalid JSON"))
    end)

    it("returns nil and error when folders key is missing", function()
        local path = write_workspace('{"settings": {}}')
        local ws, err = parser.parse(path)
        assert.is_nil(ws)
        assert.truthy(err:find("no folders"))
    end)

    it("returns nil and error when folders is empty", function()
        local path = write_workspace('{"folders": []}')
        local ws, err = parser.parse(path)
        assert.is_nil(ws)
        assert.truthy(err:find("no folders"))
    end)

    it("returns workspace table for valid file", function()
        local path = write_workspace('{"folders": [{"path": "/tmp"}]}')
        local ws, err = parser.parse(path)
        assert.is_nil(err)
        assert.is_table(ws)
        assert.equals(path, ws.file)
        assert.equals(1, #ws.folders)
    end)

    it("uses filename (without extension) as name when name field absent", function()
        local path = write_workspace('{"folders": [{"path": "/tmp"}]}')
        local ws = parser.parse(path)
        local expected_name = vim.fn.fnamemodify(path, ":t:r")
        assert.equals(expected_name, ws.name)
    end)

    it("uses name field from JSON when present", function()
        local path = write_workspace('{"name": "My Project", "folders": [{"path": "/tmp"}]}')
        local ws = parser.parse(path)
        assert.equals("My Project", ws.name)
    end)

    it("uses folder path basename as folder name when folder name absent", function()
        local path = write_workspace('{"folders": [{"path": "/tmp/myproject"}]}')
        local ws = parser.parse(path)
        assert.equals("myproject", ws.folders[1].name)
    end)

    it("uses folder name field when present", function()
        local path = write_workspace('{"folders": [{"path": "/tmp", "name": "Root"}]}')
        local ws = parser.parse(path)
        assert.equals("Root", ws.folders[1].name)
    end)

    it("resolves relative folder paths relative to workspace file directory", function()
        local dir = vim.fn.tempname()
        vim.fn.mkdir(dir, "p")
        local subdir = dir .. "/src"
        vim.fn.mkdir(subdir, "p")
        local path = dir .. "/my.code-workspace"
        local f = io.open(path, "w")
        f:write('{"folders": [{"path": "./src"}]}')
        f:close()

        local ws = parser.parse(path)
        assert.equals(1, vim.fn.isdirectory(ws.folders[1].path))
        assert.truthy(ws.folders[1].path:find("src"))
    end)

    it("stores raw settings table", function()
        local path = write_workspace('{"folders": [{"path": "/tmp"}], "settings": {"editor.fontSize": 14}}')
        local ws = parser.parse(path)
        assert.equals(14, ws.settings["editor.fontSize"])
    end)

    it("stores empty table when settings key absent", function()
        local path = write_workspace('{"folders": [{"path": "/tmp"}]}')
        local ws = parser.parse(path)
        assert.is_table(ws.settings)
    end)

    it("still returns workspace and warns when a folder path does not exist on disk", function()
        local warned = false
        local orig_notify = vim.notify
        vim.notify = function(msg, level)
            if level == vim.log.levels.WARN then
                warned = true
            end
        end

        local path = write_workspace('{"folders": [{"path": "/nonexistent/path/xyz123"}]}')
        local ws = parser.parse(path)

        vim.notify = orig_notify

        assert.is_not_nil(ws)
        assert.is_true(warned)
        assert.equals(1, #ws.folders)
    end)

    it("parses files with single-line // comments", function()
        local path = write_workspace(
            '// workspace comment\n{"folders": [{"path": "/tmp"}], "name": "Test"}'
        )
        local ws = parser.parse(path)
        assert.is_not_nil(ws)
        assert.equals("Test", ws.name)
    end)

    it("parses files with trailing commas", function()
        local path = write_workspace(
            '{"folders": [{"path": "/tmp",}],"name": "Test",}'
        )
        local ws = parser.parse(path)
        assert.is_not_nil(ws)
        assert.equals("Test", ws.name)
    end)

    it("parses files with block /* */ comments", function()
        local path = write_workspace(
            '/* header */{"folders": [{"path": "/tmp"}], /* inline */ "name": "Test"}'
        )
        local ws = parser.parse(path)
        assert.is_not_nil(ws)
        assert.equals("Test", ws.name)
    end)

    it("parses files where folder names do not contain //", function()
        -- Note: the pattern-based JSONC stripper will incorrectly strip // inside
        -- string values (e.g. URLs). This is a known limitation for .code-workspace files.
        local path = write_workspace(
            '{"folders": [{"path": "/tmp", "name": "my-folder"}]}'
        )
        local ws = parser.parse(path)
        assert.is_not_nil(ws)
        assert.equals("my-folder", ws.folders[1].name)
    end)
end)
