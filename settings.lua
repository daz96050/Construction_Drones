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
        order = "a",
    },
    {
        type = "bool-setting",
        name = "drone_process_other_player_upgrade",
        setting_type = "runtime-per-user",
        default_value = false,
        order = "a",
    },
    {
        type = "bool-setting",
        name = "drone_process_other_player_proxies",
        setting_type = "runtime-per-user",
        default_value = false,
        order = "a",
    },
})
