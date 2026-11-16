local shared = require("shared")
local s = shared.drone_stats

-- stats_for_vanilla_levels
assert(s(0).max_health == 45 and s(0).movement_speed == 0.2 and s(0).inventory_size == 4, "stats_for_vanilla_levels: normal")
assert(s(5).max_health == 112 and math.abs(s(5).movement_speed - 0.3) < 1e-9 and s(5).inventory_size == 14, "stats_for_vanilla_levels: legendary")

-- stats_for_unlisted_levels
assert(s(4).inventory_size == 12 and s(10).inventory_size == 24, "stats_for_unlisted_levels")

-- stats_clamp_bad_levels
assert(s(nil).inventory_size == 4 and s(-1).inventory_size == 4, "stats_clamp_bad_levels")
