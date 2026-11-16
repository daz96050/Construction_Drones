local plan = require("script/batch_planner").plan

local function sizes(batches)
    local t = {}
    for i, b in ipairs(batches) do t[i] = b.quality .. ":" .. b.size end
    return table.concat(t, ",")
end

-- more_drones_than_targets: one target each, best drones used
local got = sizes(plan(3, { { quality = "normal", count = 10, capacity = 4 }, { quality = "legendary", count = 2, capacity = 14 } }))
assert(got == "legendary:1,legendary:1,normal:1", "more_drones_than_targets: " .. got)

-- even_spread_within_capacity
got = sizes(plan(8, { { quality = "normal", count = 4, capacity = 4 } }))
assert(got == "normal:2,normal:2,normal:2,normal:2", "even_spread_within_capacity: " .. got)

-- best_drones_absorb_overflow
got = sizes(plan(20, { { quality = "normal", count = 2, capacity = 4 }, { quality = "legendary", count = 1, capacity = 14 } }))
assert(got == "legendary:12,normal:4,normal:4", "best_drones_absorb_overflow: " .. got)

-- one_drone_many_targets
got = sizes(plan(30, { { quality = "normal", count = 1, capacity = 4 } }))
assert(got == "normal:4", "one_drone_many_targets: " .. got)

-- nothing_free
assert(#plan(5, {}) == 0 and #plan(0, { { quality = "normal", count = 3, capacity = 4 } }) == 0, "nothing_free")

-- zero_count_entries_ignored
got = sizes(plan(2, { { quality = "legendary", count = 0, capacity = 14 }, { quality = "normal", count = 2, capacity = 4 } }))
assert(got == "normal:1,normal:1", "zero_count_entries_ignored: " .. got)
