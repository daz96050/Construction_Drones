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
            count = 1000,  -- Research cost in science packs
            ingredients = ingredients,
            time = 60  -- Time in seconds
        },
        order = "c-k-a"
    }
})

local tech_data = {
    [1] = {prereq = {"logistic-science-pack"}, ingredients = {{"automation-science-pack", 1}, {"logistic-science-pack", 1}}, count = 100},
    [2] = {prereq = {"construction_drone_count_1"}, ingredients = {{"automation-science-pack", 1}, {"logistic-science-pack", 1}}, count = 200},
    [3] = {prereq = {"construction_drone_count_2"}, ingredients = {{"automation-science-pack", 1}, {"logistic-science-pack", 1}}, count = 400},
    [4] = {prereq = {"chemical-science-pack"}, ingredients = {{"automation-science-pack", 1}, {"logistic-science-pack", 1}, {"chemical-science-pack", 1}}, count = 200},
    [5] = {prereq = {"construction_drone_count_4"}, ingredients = {{"automation-science-pack", 1}, {"logistic-science-pack", 1}, {"chemical-science-pack", 1}}, count = 400},
    [6] = {prereq = {"utility-science-pack"}, ingredients = {{"automation-science-pack", 1}, {"logistic-science-pack", 1}, {"chemical-science-pack", 1}, {"utility-science-pack", 1}}, count = 200},
    [7] = {prereq = {"space-science-pack"}, ingredients = {{"automation-science-pack", 1}, {"logistic-science-pack", 1}, {"chemical-science-pack", 1}, {"utility-science-pack", 1}, {"space-science-pack", 1}}, count = 400},
    [8] = {prereq = {"construction_drone_count_7"}, ingredients = {{"automation-science-pack", 1}, {"logistic-science-pack", 1}, {"chemical-science-pack", 1}, {"utility-science-pack", 1}, {"space-science-pack", 1}}, count = 600},
    [9] = {prereq = {"construction_drone_count_8"}, ingredients = {{"automation-science-pack", 1}, {"logistic-science-pack", 1}, {"chemical-science-pack", 1}, {"utility-science-pack", 1}, {"space-science-pack", 1}}, count = 800},
}

local drone_tech = {
    type = "technology",
    name = "construction_drone_",
    icon = drone_icon_location,
    icon_size = 128,
    effects = {},
    prerequisites = {},
    unit = {
        count = 100,
        ingredients = { },
        time = 60
    },
    order = "c-k-a"
}

for i = 1, 9 do
    tech = table.deepcopy(drone_tech)
    tech.name = tech.name .."count_"..i
    tech.prerequisites = tech_data[i].prereq
    tech.unit.ingredients = tech_data[i].ingredients
    tech.unit.count = tech_data[i].count
    
    data:extend({tech})
end

drone_tech.name = drone_tech.name .. "unlocked"
drone_tech.prerequisites = {"electronics"}
drone_tech.unit.ingredients = {{"automation-science-pack", 1}}
data:extend({drone_tech})
