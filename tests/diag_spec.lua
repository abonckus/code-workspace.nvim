describe("diag", function()
    it("strip_jsonc direct call", function()
        package.loaded["code-workspace.parser"] = nil
        local p = require("code-workspace.parser")
        local input = '{"folders":[{"path":"/tmp"}]}'
        local out = p._strip_jsonc(input)
        print("\nstrip input=[" .. input .. "] len=" .. #input)
        print("strip output=[" .. tostring(out) .. "] len=" .. tostring(out and #out or "nil"))
        local ok, d = pcall(vim.fn.json_decode, out)
        print("decode ok=" .. tostring(ok))
        assert.equals(input, out)
    end)

    it("parses valid json file", function()
        package.loaded["code-workspace.parser"] = nil
        local p = require("code-workspace.parser")
        local tmp = vim.fn.tempname() .. ".json"
        local f = io.open(tmp, "w")
        f:write('{"folders":[{"path":"/tmp"}]}')
        f:close()
        local f2 = io.open(tmp, "r")
        local raw = f2:read("*a")
        f2:close()
        print("\nraw=[" .. raw .. "] len=" .. #raw)
        local ok, data = pcall(vim.fn.json_decode, raw)
        print("json_decode direct: ok=" .. tostring(ok))
        -- Replicate strip_jsonc manually to see what it produces
        local result = {}
        local ii = 1
        local nn = #raw
        local ins = false
        while ii <= nn do
            local c = raw:sub(ii, ii)
            if ins then
                if c == "\\" then result[#result+1] = raw:sub(ii,ii+1); ii=ii+2
                elseif c == '"' then ins=false; result[#result+1]=c; ii=ii+1
                else result[#result+1]=c; ii=ii+1 end
            else
                if c == '"' then ins=true; result[#result+1]=c; ii=ii+1
                elseif c=="/" and raw:sub(ii+1,ii+1)=="/" then
                    while ii<=nn and raw:sub(ii,ii)~="\n" do ii=ii+1 end
                elseif c=="/" and raw:sub(ii+1,ii+1)=="*" then
                    ii=ii+2; while ii<nn do if raw:sub(ii,ii+1)=="*/" then ii=ii+2; break end; ii=ii+1 end
                else result[#result+1]=c; ii=ii+1 end
            end
        end
        local stripped = table.concat(result):gsub(",%s*([%]%}])", "%1")
        print("stripped=[" .. stripped .. "] len=" .. #stripped)
        local ok2, d2 = pcall(vim.fn.json_decode, stripped)
        print("after strip decode: ok=" .. tostring(ok2))
        local ws, err = p.parse(tmp)
        print("parse result: ws=" .. tostring(ws) .. " err=" .. tostring(err))
        assert.is_not_nil(ws)
    end)
end)
