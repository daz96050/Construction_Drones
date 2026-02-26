-- Shared data interface between data and script, notably prototype names.
local data = {}
data.drones = {}

data.drone_quality = {
    ["normal"] = {
        max_health = 45,
        movement_speed = 0.16
    },
    ["uncommon"] = {
        max_health = 60,
        movement_speed = 0.3
    },
    ["rare"] = {
        max_health = 75,
        movement_speed = 0.6
    },
    ["epic"] = {
        max_health = 120,
        movement_speed = 0.8
    },
    ["legendary"] = {
        max_health = 240,
        movement_speed = 1.2
    }
}
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
    logistic_beacon = "Logistic_Beacon",
    simple_storage_chest = "Simple_Storage_Chest",
    simple_provider_chest = "Simple_Provider_Chest",
    construction_drone_proxy_chest = "Construction_Drone_Proxy_Chest",
}

data.equipment = { drone_port = "Personal Drone Port" }

data.beams = {
    build = "Build_beam",
    deconstruction = "Deconstruct_Beam",
    pickup = "Pickup_Beam",
    dropoff = "Dropoff_Beam",
    attack = "Attack_Beam",
}

return data
