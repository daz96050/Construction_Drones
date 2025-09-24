local path = util.path("data/units/construction_drone/")

local icon = {
    filename = path .. "construction_drone_icon.png",
    priority = "extra-high-no-scale",
    scale = 1,
    flags = { "icon" },
}

data:extend({
    {
        type = "shortcut",
        name = "construction-drone-toggle",
        order = "a[construction-drones]",
        action = "lua",
        associated_control_input = "construction-drone-toggle",
        localised_name = "Toggle Construction drones",
        icon_size = 64,
        small_icon_size = 64,
        style = "default",
        icon = path .. "construction_drone_icon.png",
        small_icon = path .. "construction_drone_icon.png",
        disabled_small_icon = path .. "construction_drone_icon.png",
        toggleable = true,
    },
    {
        type = "shortcut",
        name = "drone-repair-toggle",
        order = "a[construction-drones]",
        action = "lua",
        associated_control_input = "drone-repair-toggle",
        localised_name = "Toggle Construction Drone Repairs",
        icon_size = 64,
        small_icon_size = 64,
        style = "default",
        icon = path .. "repair-pack.png",
        small_icon = path .. "repair-pack.png",
        disabled_small_icon = path .. "repair-pack.png",
        toggleable = true,
    },
})