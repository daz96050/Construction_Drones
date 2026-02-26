util = require "data/tf_util/tf_util"
shared = require("shared")
require "data/units/units"
require "data/hotkeys"
require "data/shortcut"

local prereq = {"space-science-pack"}
local ingredients = {}
table.insert(ingredients, {"automation-science-pack", 1})
table.insert(ingredients, {"chemical-science-pack", 1})
table.insert(ingredients, {"logistic-science-pack", 1})
table.insert(ingredients, {"space-science-pack", 1})
if mods["space-exploration"] then
    table.insert(ingredients, {"se-rocket-science-pack", 1})
end
data:extend({
    {
        type = "technology",
        name = "spectral-drones",
        icon = "__Construction_Drones_Forked__/graphics/technology/spectral-drones-128.png",
        icon_size = 128,
        effects = {},
        prerequisites = prereq,  -- Adjust prerequisites as needed (e.g., based on your mod's tech tree)
        unit = {
            count = 100,  -- Research cost in science packs
            ingredients = ingredients,
            time = 60  -- Time in seconds
        },
        order = "c-k-a"
    }
})
