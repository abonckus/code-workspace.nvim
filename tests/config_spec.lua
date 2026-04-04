local config

describe("config.resolve", function()
    before_each(function()
        package.loaded["code-workspace.config"] = nil
        config = require("code-workspace.config")
    end)

    it("returns all defaults when called with no arguments", function()
        local c = config.resolve()
        assert.is_true(c.detect_on_startup)
        assert.is_true(c.detect_on_buf_read)
        assert.equals(1, c.scan_depth)
        assert.is_nil(c.integrations.neo_tree)
        assert.is_nil(c.on_load)
        assert.is_nil(c.on_close)
    end)

    it("merges user options over defaults", function()
        local c = config.resolve({ detect_on_startup = false, scan_depth = 3 })
        assert.is_false(c.detect_on_startup)
        assert.is_true(c.detect_on_buf_read)
        assert.equals(3, c.scan_depth)
    end)

    it("merges nested integrations table", function()
        local c = config.resolve({ integrations = { neo_tree = true } })
        assert.is_true(c.integrations.neo_tree)
    end)

    it("does not mutate defaults when user options provided", function()
        config.resolve({ detect_on_startup = false })
        local c2 = config.resolve()
        assert.is_true(c2.detect_on_startup)
    end)
end)
