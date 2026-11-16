-- Plain-Lua test runner for the mod's pure modules. Run from the repo root: lua tests/run.lua
package.path = "./?.lua;" .. package.path

local files = {
    "tests/test_stats.lua",
    "tests/test_batch_planner.lua",
    "tests/test_quality_variants.lua",
}

local failed = false
for _, file in ipairs(files) do
    local f = io.open(file, "r")
    if f then
        f:close()
        local ok, err = pcall(dofile, file)
        if ok then
            print("PASS " .. file)
        else
            print("FAIL " .. file .. ": " .. tostring(err))
            failed = true
        end
    end
end
if failed then os.exit(1) end
