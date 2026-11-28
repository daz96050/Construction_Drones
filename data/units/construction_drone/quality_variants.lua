-- Adds a drone unit, spectral unit and proxy chest for every quality that doesn't have them yet,
-- with stats derived from the quality's level (shared.drone_stats).
--
-- Called from data.lua (so `normal` always exists) and again from data-final-fixes.lua: quality
-- mods that load after this one add their qualities after our data.lua has run, and would
-- otherwise have drones with no unit to spawn.
local shared = require("shared")

return function(unit_template, proxy_template)
    local base_unit_name = shared.units.construction_drone
    for quality_name, quality in pairs(data.raw["quality"] or {}) do
        local unit_name = quality_name .. "-" .. base_unit_name
        if quality_name ~= "quality-unknown" and not data.raw.unit[unit_name] then
            local stats = shared.drone_stats(quality.level)

            local quality_unit = table.deepcopy(unit_template)
            quality_unit.name = unit_name
            quality_unit.collision_mask = shared.default_collision_mask
            quality_unit.movement_speed = stats.movement_speed
            quality_unit.max_health = stats.max_health

            local spectral_unit = table.deepcopy(quality_unit)
            spectral_unit.name = unit_name .. "_spectral"
            spectral_unit.collision_mask = shared.spectral_collision_mask

            local quality_proxy = table.deepcopy(proxy_template)
            quality_proxy.name = shared.entities.construction_drone_proxy_chest .. "_" .. quality_name
            quality_proxy.localised_name = quality_proxy.name
            quality_proxy.inventory_size = stats.inventory_size

            data:extend { quality_unit, spectral_unit, quality_proxy }
        end
    end
end
