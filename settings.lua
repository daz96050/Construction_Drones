data:extend({
    {
        type = "int-setting",
        name = "throttling",
        setting_type = "runtime-global",
        default_value = 5,
        minimum_value = 1,
        maximum_value = 10,
    },
    {
        type = "bool-setting",
        name = "drone_process_other_player_deconstruction",
        setting_type = "runtime-per-user",
        default_value = false,
        order = "a",
    },
    {
        type = "bool-setting",
        name = "drone_process_other_player_construction",
        setting_type = "runtime-per-user",
        default_value = false,
        order = "b",
    },
    {
        type = "bool-setting",
        name = "drone_process_other_player_upgrade",
        setting_type = "runtime-per-user",
        default_value = false,
        order = "c",
    },
    {
        type = "bool-setting",
        name = "drone_process_other_player_proxies",
        setting_type = "runtime-per-user",
        default_value = false,
        order = "d",
    },
    {
        type = "int-setting",
        name = "construction-drone-search-radius",
        setting_type = "runtime-global",  -- Global setting for search radius
        default_value = 60,
        minimum_value = 10,
        maximum_value = 200,
        order = "a"
    },
    {
            type = "bool-setting",
            name = "remote-view-spawn",
            setting_type = "runtime-global",
            default_value = false,
            order = "b"
    },
    {
        type = "bool-setting",
        name = "force-player-position-search",
        setting_type = "runtime-global",
        default_value = true,
        order = "c"
    }
    ,
    {
        type = "bool-setting",
        name = "construction-drone-unlimited",
        setting_type = "startup",
        default_value = false,
        order = "z",
        description = "Allow unlimited construction drones by default and hide related technologies"
    }
})
