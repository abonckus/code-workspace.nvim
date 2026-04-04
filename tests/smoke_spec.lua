describe("smoke", function()
    it("loads code-workspace without error", function()
        assert.has_no.errors(function()
            require("code-workspace")
        end)
    end)

    it("exposes setup, load, close, active, explorer", function()
        local m = require("code-workspace")
        assert.is_function(m.setup)
        assert.is_function(m.load)
        assert.is_function(m.close)
        assert.is_function(m.active)
        assert.is_function(m.explorer)
    end)

    it("active() returns nil before any workspace is loaded", function()
        package.loaded["code-workspace.loader"] = nil
        package.loaded["code-workspace"] = nil
        local m = require("code-workspace")
        assert.is_nil(m.active())
    end)
end)
