util = require "data/tf_util/tf_util"
names = require("shared")
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
local drone_icon_location = "__Construction_Drones_Forked__/data/units/construction_drone/construction_drone_icon.png"
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

local tech_data = {
    [0] = {ingredients = {"automation-science-pack", 1}},
    [1] = {prereq = {"logistic-science-pack"}, ingredients = {{"automation-science-pack", 1}, {"logistic-science-pack"}}, count = 100},
    [2] = {prereq = {"logistic-science-pack"}, ingredients = {{"automation-science-pack", 1}, {"logistic-science-pack"}}, count = 100},
    [3] = {prereq = {"logistic-science-pack"}, ingredients = {{"automation-science-pack", 1}, {"logistic-science-pack"}}, count = 100},
    [4] = {prereq = {"chemical-science-pack"}, ingredients = {{"automation-science-pack", 1}, {"chemical-science-pack", 1}}, count = 200},
    [5] = {prereq = {"chemical-science-pack"}, ingredients = {{"automation-science-pack", 1}, {"chemical-science-pack", 1}}, count = 200},
    [6] = {prereq = {"chemical-science-pack"}, ingredients = {{"automation-science-pack", 1}, {"chemical-science-pack", 1}}, count = 200},
    [7] = {prereq = {"space-science-pack"}, ingredients = {{"automation-science-pack", 1}, {"space-science-pack", 1}}, count = 400},
    [8] = {prereq = {"space-science-pack"}, ingredients = {{"automation-science-pack", 1}, {"space-science-pack", 1}}, count = 400},
    [9] = {prereq = {"space-science-pack"}, ingredients = {{"automation-science-pack", 1}, {"space-science-pack", 1}}, count = 400},
}

local drone_tech = {
    type = "technology",
    name = "construction_drone_",
    icon = drone_icon_location,
    icon_size = 128,
    effects = {},
    prerequisites = {},  -- Adjust prerequisites as needed (e.g., based on your mod's tech tree)
    unit = {
        count = 100,  -- Research cost in science packs
        ingredients = { },
        time = 60  -- Time in seconds
    },
    order = "c-k-a"
}

for i = 1, 10 do
    drone_tech.name = drone_tech.name .."count_"..i
    drone_tech.prerequisites = tech_data[i].prereq
    drone_tech.unit.ingredients = tech_data[i].ingredients
    drone_tech.unit.count = tech_data[i].count
    
    data:extend({drone_tech})
end

drone_tech.name = drone_tech.name .. "unlocked"
drone_tech.prerequisites = {"electronics"}
drone_tech.unit.ingredients = {{"automation-science-pack", 1}}
data:extend({drone_tech})
