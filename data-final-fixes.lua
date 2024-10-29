util = require "data/tf_util/tf_util"
names = require("shared")
local collision_mask_util = require("collision-mask-util")

local drone_collision_mask = "construction_drone"
data:extend({ { type = "collision-layer", name = drone_collision_mask } })


local name = names.units.construction_drone
data.raw.unit[name].collision_mask = { not_colliding_with_itself = true, consider_tile_transitions = true, layers = {} }
data.raw.unit[name].collision_mask.layers[drone_collision_mask] = true

-- Add collision to all buildings and cliffs. We use the fact that they have collisions with player and item here as a
-- proxy to identify them. If this ever changes in the future, this might break :^)
for _, prototype in pairs(collision_mask_util.collect_prototypes_with_layer("player")) do
    local mask = collision_mask_util.get_mask(prototype)
    if mask.layers and mask.layers["item"] then
        mask.layers[drone_collision_mask] = true
        print("proto " .. prototype.name)
        print("proto " .. serpent.block(mask.layers))
    end
    prototype.collision_mask = mask
end

-- Add collision to all water tiles
local tiles = {
    -- From data/base/prototypes/tile/tiles.lua
    "water",
    "deepwater",
    "water-green",
    "deepwater-green",
    -- "water-shallow", -- A little amphibious never hurts :^)
    -- "water-mud", -- A little amphibious never hurts :^)
    "water-wube",

    -- From data/space-age/prototypes/tile/tiles-aquilo.lua
    "ammoniacal-ocean",
    "ammoniacal-ocean-2",
    "brash-ice",

    -- From data/space-age/prototypes/tile/tiles-vulcanus.lua
    "lava",
    "lava-hot",

    -- From data/space-age/prototypes/tile/tiles-fulgora.lua
    -- "oil-ocean-deep",

    -- From data/space-age/prototypes/tile/tiles-gleba.lua
    "gleba-deep-lake",
}

for _, tile in pairs(tiles) do
    if data.raw["tile"][tile] then
        data.raw["tile"][tile].collision_mask.layers[drone_collision_mask] = true
        print("proto " .. data.raw["tile"][tile].name)
        print("proto " .. serpent.block(data.raw["tile"][tile].collision_mask.layers))
    end
end
