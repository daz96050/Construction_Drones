local shared = require("shared")
local s = shared.drone_stats
local function near(a, b) return math.abs(a - b) < 1e-9 end

-- stats_for_vanilla_levels
assert(s(0).max_health == 45 and near(s(0).movement_speed, 0.2) and s(0).inventory_size == 4, "stats_for_vanilla_levels: normal")
assert(s(5).max_health == 112 and near(s(5).movement_speed, 0.4) and s(5).inventory_size == 14, "stats_for_vanilla_levels: legendary")

-- stats_for_unlisted_levels
assert(s(4).inventory_size == 12 and s(10).inventory_size == 24, "stats_for_unlisted_levels")

-- stats_clamp_bad_levels
assert(s(nil).inventory_size == 4 and s(-1).inventory_size == 4, "stats_clamp_bad_levels")

-- stats_cap_at_level_10
local capped, top = s(50), s(10)
assert(capped.inventory_size == top.inventory_size and capped.max_health == top.max_health and near(capped.movement_speed, top.movement_speed) and near(top.movement_speed, 0.6), "stats_cap_at_level_10")
