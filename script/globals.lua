beams = names.beams
proxy_name = names.entities.construction_drone_proxy_chest

drone_prototypes = { [names.units.construction_drone] = { interact_range = 5, return_to_character_range = -1 } }

ghost_type = "entity-ghost"
tile_ghost_type = "tile-ghost"
tile_deconstruction_proxy = "deconstructible-tile-proxy"
cliff_type = "cliff"

oofah = (2 ^ 0.5) / 2
ranges = { interact = 1, return_to_character = 3 }
proxy_position = { 1000000, 1000000 }

belt_connectible_type = {
    ["transport-belt"] = 2,
    ["underground-belt"] = 4,
    ["splitter"] = 8,
    ["loader"] = 2,
    ["loader-1x1"] = 2,
}

drone_pathfind_flags = {
    allow_destroy_friendly_entities = false,
    cache = false,
    low_priority = false,
    prefer_straight_paths = true,
    no_break = true,
}

drone_orders = {
    construct = 1,
    deconstruct = 2,
    repair = 3,
    upgrade = 4,
    request_proxy = 5,
    cliff_deconstruct = 8,
    return_to_character = 10,
}

data = {
    drone_commands = {},
    targets = {},
    sent_deconstruction = {},
    debug = false,
    proxy_chests = {},
    migrate_deconstructs = true,
    migrate_characters = true,
    path_requests = {},
    request_count = {},
    set_default_shortcut = true,
    job_queue = {},
    already_targeted = {},
    search_queue = {},
}

prototype_cache = {}
radius_map = nil
drone_stack_capacity = nil
repair_items = nil
ignored_types = {
    "resource",
    "corpse",
    "beam",
    "flying-text",
    "explosion",
    "smoke-with-trigger",
    "stream",
    "fire-flame",
    "particle-source",
    "projectile",
    "sticker",
    "speech-bubble",
}
search_offsets = {}
search_refresh = nil
offsets = { { 0, 0 }, { 0.25, 0 }, { 0, 0.25 }, { 0.25, 0.25 } }
revive_param = { return_item_request_proxy = true, raise_revive = true }
directions = {
    [defines.direction.north] = { 0, -1 },
    [defines.direction.northeast] = { 1, -1 },
    [defines.direction.east] = { 1, 0 },
    [defines.direction.southeast] = { 1, 1 },
    [defines.direction.south] = { 0, 1 },
    [defines.direction.southwest] = { -1, 1 },
    [defines.direction.west] = { -1, 0 },
    [defines.direction.northwest] = { -1, -1 },
}