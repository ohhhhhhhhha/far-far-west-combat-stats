local T = { count = 0, failed = 0 }
function T.eq(actual, expected, label)
    if actual ~= expected then
        error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end
function T.near(actual, expected, label)
    if type(actual) ~= "number" or math.abs(actual - expected) > 0.0000001 then
        error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end
function T.test(name, run)
    T.count = T.count + 1
    local ok, err = pcall(run)
    if ok then print("PASS " .. name) else T.failed = T.failed + 1; print("FAIL " .. name .. "\n  " .. tostring(err)) end
end
function T.finish()
    print(string.format("%d tests, %d failures", T.count, T.failed))
    if T.failed > 0 then os.exit(1) end
end
return T
