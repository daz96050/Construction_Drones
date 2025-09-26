local sin, cos = math.sin, math.cos
local angle = util.angle
local floor = math.floor
local random = math.random

unique_index = function(entity)
    if entity.unit_number then
        return entity.unit_number
    end
    return entity.surface.index .. entity.name .. entity.position.x .. entity.position.y
end

is_commandable = function(string)
    return drone_prototypes[string] ~= nil
end

get_prototype = function(name)
    if prototype_cache[name] then
        return prototype_cache[name]
    end
    local prototype = prototypes.entity[name]
    prototype_cache[name] = prototype
    return prototype
end

player_physical_position = function(player)
    if player.controller_type == 7 then -- remote map view
        return player.physical_position
    else
        return player.position
    end
end

get_beam_orientation = function(source_position, target_position)
    -- Angle in rads
    local angle = angle(target_position, source_position)

    -- Convert to orientation
    local orientation = (angle / (2 * math.pi)) - 0.25
    if orientation < 0 then
        orientation = orientation + 1
    end

    local x, y = 0, 0.5

    --[[x = x cos θ − y sin θ
    y = x sin θ + y cos θ]]
    angle = angle + (math.pi / 2)
    local x1 = (x * cos(angle)) - (y * sin(angle))
    local y1 = (x * sin(angle)) + (y * cos(angle))

    return orientation, { x1, y1 - 0.5 }
end

should_process_entity = function(entity, player, order_type)
    if not (entity and entity.valid and player and player.valid) then
        return false
    end

    -- Map drone order type to the corresponding setting
    local setting_name
    if order_type == drone_orders.construct then
        setting_name = "drone_process_other_player_construction"
    elseif order_type == drone_orders.deconstruct then
        setting_name = "drone_process_other_player_deconstruction"
    elseif order_type == drone_orders.upgrade then
        setting_name = "drone_process_other_player_upgrade"
    elseif order_type == drone_orders.request_proxy then
        setting_name = "drone_process_other_player_proxies"
    else
        return true  -- For unsupported types (repair, cliff_deconstruct), process as original
    end

    -- Check the player's runtime setting
    local process_others = settings.get_player_settings(player)[setting_name].value
    if process_others then
        return true  -- Setting enabled: process any valid entity, including other players'
    else
        -- Setting disabled: only process if last_user matches the player or is nil (for neutral entities)
        return entity.last_user == nil or entity.last_user == player
    end
end

get_radius_map = function()
    -- Caching radius map, deliberately not local or data
    if radius_map then
        return radius_map
    end
    radius_map = {}
    for k, entity in pairs(prototypes.entity) do
        radius_map[k] = entity.radius
    end
    return radius_map
end

get_radius = function(entity, range, goto_entity)
    -- Handle non-entity targets (e.g., plain positions) by returning 0 to avoid errors in radius lookups
    if not entity.name then
        return 0
    end
    local radius
    local type = entity.type
    if type == ghost_type then
        radius = get_radius_map()[entity.ghost_name]
    elseif type == cliff_type then
        radius = entity.get_radius() * 2
    elseif is_commandable(entity.name) then
        if range == ranges.interact then
            radius = get_radius_map()[entity.name] + drone_prototypes[entity.name].interact_range
        elseif range == ranges.return_to_character then
            radius = get_radius_map()[entity.name] + drone_prototypes[entity.name].return_to_character_range
        else
            radius = get_radius_map()[entity.name]
        end
    elseif goto_entity then
        return 0
    else
        radius = get_radius_map()[entity.name]
    end

    if radius < oofah then
        return oofah
    end
    return radius
end

distance = function(position_1, position_2)
    local x1 = position_1[1] or position_1.x
    local y1 = position_1[2] or position_1.y
    local x2 = position_2[1] or position_2.x
    local y2 = position_2[2] or position_2.y
    return (((x2 - x1) * (x2 - x1)) + ((y2 - y1) * (y2 - y1))) ^ 0.5
end

in_construction_range = function(drone, target)
    local distance = distance(drone.position, target.position) - 2
    return distance <= ((get_radius(drone, ranges.interact) + (get_radius(target))))
end

stack_from_product = function(product)
    local count = floor(product.amount or (random() * (product.amount_max - product.amount_min) + product.amount_min))
    if count < 1 then
        return
    end
    local stack = { name = product.name, count = count }
    -- print(serpent.line(stack))
    return stack
end

inventories = function(entity)
    local get = entity.get_inventory
    local inventories = {}
    for k = 1, 10 do
        inventories[k] = get(k)
    end
    return inventories
end

rip_inventory = function(inventory, list)
    if inventory.is_empty() then
        return
    end
    for _, item in pairs(inventory.get_contents()) do
        list[item.name] = (list[item.name] or 0) + item.count
    end
end

contents = function(entity)
    local contents = {}
    local get_inventory = entity.get_inventory

    for k = 1, 10 do
        local inventory = get_inventory(k)
        if inventory then
            rip_inventory(inventory, contents)
        else
            break
        end
    end

    local max_line_index = belt_connectible_type[entity.type]

    if max_line_index then
        local get_transport_line = entity.get_transport_line
        for k = 1, max_line_index do
            local transport_line = get_transport_line(k)
            if transport_line then
                for _, item in pairs(transport_line.get_contents()) do
                    contents[item.name] = (contents[item.name] or 0) + item.count
                end
            else
                break
            end
        end
    end

    return contents
end

validate = function(entities)
    for k, entity in pairs(entities) do
        if not entity.valid then
            entities[k] = nil
        end
    end
    return entities
end

get_build_time = function()
    return random(15, 25)
end

unit_clear_target = function(unit, target)
    local r = get_radius(unit) + get_radius(target) + 1
    local position = { x = true, y = true }
    if unit.position.x > target.position.x then
        position.x = unit.position.x + r
    else
        position.x = unit.position.x - r
    end
    if unit.position.y > target.position.y then
        position.y = unit.position.y + r
    else
        position.y = unit.position.y - r
    end
    unit.speed = unit.prototype.speed
    unit.commandable.set_command { type = defines.command.go_to_location, destination = position, radius = 1 }
end

get_extra_target = function(drone_data)
    if not drone_data.extra_targets then
        return
    end
    drone_data.extra_targets = validate(drone_data.extra_targets)

    local any = next(drone_data.extra_targets)
    if not any then
        drone_data.extra_targets = nil
        return
    end

    local next_target = drone_data.entity.surface.get_closest(drone_data.entity.position, drone_data.extra_targets)
    if next_target then
        drone_data.target = next_target
        drone_data.extra_targets[unique_index(next_target)] = nil
        return next_target
    end
end