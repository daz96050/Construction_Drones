util = require "data/tf_util/tf_util"
names = require("shared")
local collision_mask_util = require("collision-mask-util")

local drone_collision_mask = collision_mask_util.get_first_unused_layer()

for _, prototype in pairs(collision_mask_util.collect_prototypes_with_layer(
                              "player-layer")) do
    local mask = collision_mask_util.get_mask(prototype)
    if collision_mask_util.mask_contains_layer(mask, "item-layer") then
        collision_mask_util.add_layer(mask, drone_collision_mask)
    end
    prototype.collision_mask = mask
end

collision_mask_util.add_layer(data.raw["tile"]["deepwater"].collision_mask,
                              drone_collision_mask)
collision_mask_util.add_layer(
    data.raw["tile"]["deepwater-green"].collision_mask, drone_collision_mask)
collision_mask_util.add_layer(data.raw["tile"]["water"].collision_mask,
                              drone_collision_mask)
collision_mask_util.add_layer(data.raw["tile"]["water-green"].collision_mask,
                              drone_collision_mask)
collision_mask_util.add_layer(data.raw["tile"]["water-mud"].collision_mask,
                              drone_collision_mask)
collision_mask_util.add_layer(data.raw["tile"]["water-shallow"].collision_mask,
                              drone_collision_mask)
collision_mask_util.add_layer(data.raw["tile"]["water-wube"].collision_mask,
                              drone_collision_mask)

-- print("proto " .. serpent.block(data.raw["tile"]["water"].collision_mask))

local name = names.units.construction_drone
data.raw.unit[name].collision_mask = {
    "not-colliding-with-itself", drone_collision_mask,
    "consider-tile-transitions"
}
