-- Small JSON codec for statistics snapshots. Decoding never executes Lua code.
local Json = {null = {}}
local escapes = {['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'}
local function quote(value)
    return '"' .. value:gsub('[%z\1-\31\\"]', function(c) return escapes[c] or string.format("\\u%04x", c:byte()) end) .. '"'
end
function Json.encode(value)
    local active = {}
    local function encode(v)
        local kind = type(v)
        if v == Json.null then return "null"
        elseif kind == "string" then return quote(v)
        elseif kind == "boolean" then return v and "true" or "false"
        elseif kind == "number" then
            assert(v == v and math.abs(v) < math.huge, "JSON numbers must be finite")
            return string.format("%.17g", v)
        elseif kind ~= "table" then error("unsupported JSON value: " .. kind) end
        assert(not active[v], "cyclic JSON value")
        active[v] = true
        local count, array = 0, true
        for k in pairs(v) do
            count = count + 1
            if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then array = false end
        end
        array = array and count > 0 and #v == count
        local parts = {}
        if array then
            for i = 1, count do parts[i] = encode(v[i]) end
        else
            local keys = {}
            for k in pairs(v) do assert(type(k) == "string", "JSON object keys must be strings"); keys[#keys + 1] = k end
            table.sort(keys)
            for i, k in ipairs(keys) do parts[i] = quote(k) .. ":" .. encode(v[k]) end
        end
        active[v] = nil
        return (array and "[" or "{") .. table.concat(parts, ",") .. (array and "]" or "}")
    end
    return encode(value)
end
function Json.decode(text)
    assert(type(text) == "string", "JSON text required")
    local pos, length = 1, #text
    local function fail(message) error("invalid JSON at byte " .. pos .. ": " .. message, 0) end
    local function whitespace()
        while text:sub(pos, pos):match("[ \t\r\n]") do pos = pos + 1 end
    end
    local function hex4()
        local value = text:sub(pos, pos + 3)
        if #value ~= 4 or not value:match("^%x%x%x%x$") then fail("invalid Unicode escape") end
        pos = pos + 4
        return tonumber(value, 16)
    end
    local function stringValue()
        pos = pos + 1
        local result, start = {}, pos
        while pos <= length do
            local c = text:sub(pos, pos)
            if c == '"' then result[#result + 1] = text:sub(start, pos - 1); pos = pos + 1; return table.concat(result)
            elseif c == "\\" then
                result[#result + 1] = text:sub(start, pos - 1)
                pos = pos + 1
                local escaped = text:sub(pos, pos)
                pos = pos + 1
                local values = {['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t'}
                if escaped == "u" then
                    local code = hex4()
                    if code >= 0xD800 and code <= 0xDBFF then
                        if text:sub(pos, pos + 1) ~= "\\u" then fail("missing low surrogate") end
                        pos = pos + 2
                        local low = hex4()
                        if low < 0xDC00 or low > 0xDFFF then fail("invalid low surrogate") end
                        code = 0x10000 + (code - 0xD800) * 0x400 + low - 0xDC00
                    elseif code >= 0xDC00 and code <= 0xDFFF then fail("unexpected low surrogate") end
                    result[#result + 1] = utf8.char(code)
                elseif values[escaped] then result[#result + 1] = values[escaped]
                else fail("invalid string escape") end
                start = pos
            elseif c:byte() < 32 then fail("unescaped control character")
            else pos = pos + 1 end
        end
        fail("unterminated string")
    end
    local function numberValue()
        local start = pos
        if text:sub(pos, pos) == "-" then pos = pos + 1 end
        if text:sub(pos, pos) == "0" then pos = pos + 1
        elseif text:sub(pos, pos):match("[1-9]") then repeat pos = pos + 1 until not text:sub(pos, pos):match("%d")
        else fail("number requires an integer") end
        if text:sub(pos, pos) == "." then
            pos = pos + 1
            if not text:sub(pos, pos):match("%d") then fail("fraction requires digits") end
            repeat pos = pos + 1 until not text:sub(pos, pos):match("%d")
        end
        if text:sub(pos, pos):match("[eE]") then
            pos = pos + 1
            if text:sub(pos, pos):match("[+-]") then pos = pos + 1 end
            if not text:sub(pos, pos):match("%d") then fail("exponent requires digits") end
            repeat pos = pos + 1 until not text:sub(pos, pos):match("%d")
        end
        local result = tonumber(text:sub(start, pos - 1))
        if not result or math.abs(result) == math.huge then fail("invalid finite number") end
        return result
    end
    local value
    value = function()
        whitespace()
        local c = text:sub(pos, pos)
        if c == '"' then return stringValue()
        elseif c == "{" then
            local result = {}; pos = pos + 1; whitespace()
            if text:sub(pos, pos) == "}" then pos = pos + 1; return result end
            while true do
                if text:sub(pos, pos) ~= '"' then fail("object key required") end
                local key = stringValue(); whitespace()
                if text:sub(pos, pos) ~= ":" then fail("colon required") end
                pos = pos + 1
                if result[key] ~= nil then fail("duplicate object key") end
                result[key] = value(); whitespace()
                local separator = text:sub(pos, pos); pos = pos + 1
                if separator == "}" then return result end
                if separator ~= "," then fail("object separator required") end
                whitespace()
            end
        elseif c == "[" then
            local result = {}; pos = pos + 1; whitespace()
            if text:sub(pos, pos) == "]" then pos = pos + 1; return result end
            while true do
                result[#result + 1] = value(); whitespace()
                local separator = text:sub(pos, pos); pos = pos + 1
                if separator == "]" then return result end
                if separator ~= "," then fail("array separator required") end
            end
        elseif c == "-" or c:match("%d") then return numberValue() end
        for literal, result in pairs({["true"] = true, ["false"] = false, ["null"] = Json.null}) do
            if text:sub(pos, pos + #literal - 1) == literal then pos = pos + #literal; return result end
        end
        fail("value required")
    end
    local result = value(); whitespace()
    if pos <= length then fail("trailing text") end
    return result
end
return Json
