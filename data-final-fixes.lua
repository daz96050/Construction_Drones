util = require "data/tf_util/tf_util"
local collision_mask_util = require("collision-mask-util")

-- We want the drones to have a unique set of collisions, which is not already accommodated for in the default collision
-- layers. So we need to add a completely new layer.

local drone_collision_mask = "construction_drone"
data:extend({ { type = "collision-layer", name = "construction_drone" } })
for unit_name, _ in pairs(data.raw.unit) do
    if string.find(unit_name, "-Construction_Drone") then
        data.raw.unit[unit_name].collision_mask = { not_colliding_with_itself = true, consider_tile_transitions = true, layers = {} }
        data.raw.unit[unit_name].collision_mask.layers[drone_collision_mask] = true
    end
end

-- Add the new collision layer to all buildings and cliffs, along with all deep water tiles. We use the fact that they
-- have collisions with player and item here as a proxy to identify them. If this ever changes in the future, this might
-- break :^)

local prototype_ignore_list = {
    ["kr-electric-mining-drill-mk2"] = true,
    ["kr-electric-mining-drill-mk3"] = true,
    ["electric-mining-drill"] = true,
    ["mining-drill"] = true,
    ["bob-mining-drill-1"] = true,
    ["bob-mining-drill-2"] = true,
    ["bob-mining-drill-3"] = true,
    ["bob-mining-drill-4"] = true,
    ["bob-area-mining-drill-1"] = true,
    ["bob-area-mining-drill-2"] = true,
    ["bob-area-mining-drill-3"] = true,
    ["bob-area-mining-drill-4"] = true,
}

for _, prototype in pairs(collision_mask_util.collect_prototypes_with_layer("player")) do
    local mask = collision_mask_util.get_mask(prototype)
    if (mask.layers and mask.layers["item"]) then
        if prototype_ignore_list[prototype.name] then
            log("Ignoring " .. prototype.name .. " for drone collision mask addition")
            goto continue
        end
        mask.layers[drone_collision_mask] = true
        prototype.collision_mask = mask
        log("Added drone collision layer to " .. prototype.name)
        log("prototype mask " .. serpent.block(prototype.collision_mask))
        ::continue::
    end
end