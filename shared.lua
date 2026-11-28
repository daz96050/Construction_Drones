-- Shared data interface between data and script, notably prototype names.
local data = {}
data.drones = {}

-- Drone stats for a quality level (normal 0, uncommon 1, rare 2, epic 3, legendary 5 in vanilla).
-- Derived from the level rather than the quality's name so qualities added by other mods work.
-- Levels above 10 are treated as 10 so very high modded qualities don't get absurd stats.
data.max_drone_stat_level = 10
data.drone_stats = function(level)
    level = math.min(math.max(level or 0, 0), data.max_drone_stat_level)
    return {
        max_health = math.floor(45 * (1 + 0.3 * level)),
        movement_speed = 0.2 * (1 + 0.2 * level),
        inventory_size = 4 + 2 * level,
    }
end
data.units = { construction_drone = "Construction_Drone" }
data.bounding_box = { { -0.01, -0.01 }, { 0.01, 0.01 } }
data.default_collision_mask = { not_colliding_with_itself = true, consider_tile_transitions = true, layers = {
    construction_drone = true
}}
data.spectral_collision_mask = { not_colliding_with_itself = true, colliding_with_tiles_only = true, layers = {
    water_tile = true,
    lava_tile = true
}}

data.entities = {
    construction_drone_proxy_chest = "Construction_Drone_Proxy_Chest",
}

data.beams = {
    build = "Build_beam",
    deconstruction = "Deconstruct_Beam",
    pickup = "Pickup_Beam",
    dropoff = "Dropoff_Beam",
    attack = "Attack_Beam",
}

return data
