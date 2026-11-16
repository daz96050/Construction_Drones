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

local planner = require("script/batch_planner")
local caps = { normal = 4, rare = 8, legendary = 14 }
local function groups(list)
    local t = {}
    for i, g in ipairs(list) do t[i] = g.quality .. "x" .. g.count .. "@" .. g.capacity end
    return table.concat(t, ",")
end

-- free_drones_subtracts_reservations
got = groups(planner.free_drones({ normal = 3, legendary = 1 }, { legendary = 1 }, caps, 10))
assert(got == "normalx3@4", "free_drones_subtracts_reservations: " .. got)

-- free_drones_trims_worst_first
got = groups(planner.free_drones({ normal = 3, legendary = 1 }, {}, caps, 2))
assert(got == "legendaryx1@14,normalx1@4", "free_drones_trims_worst_first: " .. got)

-- free_drones_over_reserved_clamps_to_zero
got = groups(planner.free_drones({ normal = 1 }, { normal = 3 }, caps, 5))
assert(got == "", "free_drones_over_reserved_clamps_to_zero: " .. got)

-- free_drones_nothing_allowed
assert(#planner.free_drones({ normal = 3 }, {}, caps, 0) == 0, "free_drones_nothing_allowed")

-- pick_quality_uses_preferred
assert(planner.pick_quality({ normal = 2, legendary = 1 }, {}, "legendary", caps) == "legendary", "pick_quality_uses_preferred")

-- pick_quality_preferred_gone_falls_back_to_worst
assert(planner.pick_quality({ normal = 2, rare = 1 }, {}, "legendary", caps) == "normal", "pick_quality_preferred_gone_falls_back_to_worst")

-- pick_quality_unbatched_avoids_reserved
assert(planner.pick_quality({ normal = 1, rare = 1 }, { normal = 1 }, nil, caps) == "rare", "pick_quality_unbatched_avoids_reserved")

-- pick_quality_all_reserved_still_spawns
assert(planner.pick_quality({ normal = 1 }, { normal = 1 }, nil, caps) == "normal", "pick_quality_all_reserved_still_spawns")

-- pick_quality_none_held
assert(planner.pick_quality({}, {}, nil, caps) == nil, "pick_quality_none_held")
