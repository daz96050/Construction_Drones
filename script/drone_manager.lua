local logs = require("logs")
local random = math.random
local insert = table.insert
local shared = require("shared")

make_path_request = function(drone_data, player, target)
    local collision_mask_to_use = get_collision_mask(player)

    local path_id = player.physical_surface.request_path {
        bounding_box = shared.bounding_box,
        collision_mask = collision_mask_to_use,  -- Use the determined mask
        start = getPlayerPosition(player),
        goal = target.position,
        force = player.force,
        radius = target.get_radius() + 4,
        pathfind_flags = drone_pathfind_flags,
        can_open_gates = true,
        path_resolution_modifier = 0,
    }

    data.path_requests[path_id] = drone_data

    local index = player.index
    data.request_count[index] = (data.request_count[index] or 0) + 1
end

make_player_drone = function(player)
    local player_position
    if not settings.global["remote-view-spawn"].value and (player.controller_type == defines.controllers.remote) then
        -- Fallback to physical_position in remote view if remote-view-spawn is disabled
        logs.debug("returning physical location due to remote view")
        player_position = player.physical_position
    else
        -- Default to player.position (could be remote view)
        player_position = player.position
    end
    local player_surface = player.physical_surface

    local available_drones = get_quality_drones(player.character)
    if #available_drones == 0 then
        logs.debug("No available drones of any quality")
        return
    end

    -- Get a random available drone
    local drone_to_use = available_drones[math.random(#available_drones)]
    local prototype_name = drone_to_use.quality .. "-" .. drone_to_use.name

    -- Find a spawn position close to the player
    local position = player_surface.find_non_colliding_position(
            prototype_name,
            player_position,
            5,
            0.5,
            false
    )

    if not position then
        logs.debug("Could not find spawn position for drone")
        return
    end

    -- Remove a drone from the player's inventory
    local to_remove = { name = names.units.construction_drone, count = 1, quality = drone_to_use.quality }
    logs.debug("drone to remove from character: " .. serpent.block(to_remove))
    local removed = player.character.remove_item(to_remove)
    if removed == 0 then
        logs.debug("could not remove drone from player inventory")
        return
    end

    if use_spectral_drones(player) then
        prototype_name = prototype_name.."_spectral"
    end

    -- Create the drone entity
    local drone = player_surface.create_entity {
        name = prototype_name,
        position = position,
        force = player.force,
        quality = drone_to_use.quality
    }

    -- Attach the player to the drone data entry
    local drone_data = {
        entity = drone,
        player = player,
    }

    -- Register the drone for tracking
    script.register_on_object_destroyed(drone)
    data.drone_commands = data.drone_commands or {}
    data.drone_commands[drone.unit_number] = drone_data

    return drone
end


get_quality_drones = function(player)
    local available_drones = {}
    for _, inventory in pairs(inventories(player)) do
        for _, item in ipairs(inventory.get_contents()) do
            if string.find(item.name, "Construction_Drone") then
                table.insert(available_drones, item)
            end
        end
    end
    logs.debug("available drones: "..serpent.block(available_drones))
    return available_drones
end

set_drone_order = function(drone, drone_data)
    drone.ai_settings.path_resolution_modifier = 0
    drone.ai_settings.do_separation = true
    data.drone_commands[drone.unit_number] = drone_data
    drone_data.entity = drone
    return process_drone_command(drone_data)
end

find_a_player = function(drone_data)
    local drone = drone_data.entity
    if not (drone and drone.valid) then return end

    -- Ensure the drone always targets the player who spawned it.
    local original_player = drone_data.player
    if original_player and original_player.valid and original_player.physical_surface == drone.surface then
        return true
    end

    -- If the original player is disconnected or invalid, the drone does nothing.
    return false
end

drone_wait = function(drone_data, ticks)
    local drone = drone_data.entity
    if not (drone and drone.valid) then
        return
    end
    drone.commandable.set_command {
        type = defines.command.stop,
        ticks_to_wait = ticks,
        distraction = defines.distraction.none,
        radius = get_radius(drone),
    }
end

set_drone_idle = function(drone)
    if not (drone and drone.valid) then
        return
    end

    -- Retrieve the drone's data.
    local drone_data = data.drone_commands[drone.unit_number]

    if drone_data then
        -- Return to the original player or wait.
        if find_a_player(drone_data) then
            process_return_to_player_command(drone_data)
            return
        else
            -- Wait if the original player is unavailable.
            return drone_wait(drone_data, random(200, 400))
        end
    end

    -- Set the drone to idle if no data is present.
    set_drone_order(drone, {})
end

clear_extra_targets = function(drone_data)
    if not drone_data.extra_targets then
        return
    end

    local targets = validate(drone_data.extra_targets)
    local order = drone_data.order

    for _, entity in pairs(targets) do
        data.already_targeted[unique_index(entity)] = nil
    end

    if order == drone_orders.deconstruct or order == drone_orders.cliff_deconstruct then
        for _, entity in pairs(targets) do
            local index = unique_index(entity)
            data.sent_deconstruction[index] = (data.sent_deconstruction[index] or 1) - 1
        end
    end
end

clear_target = function(drone_data)
    local target = drone_data.target
    if not (target and target.valid) then
        return
    end

    local order = drone_data.order
    local index = unique_index(target)

    if order == drone_orders.deconstruct or order == drone_orders.cliff_deconstruct then
        data.sent_deconstruction[index] = (data.sent_deconstruction[index] or 1) - 1
    end

    data.already_targeted[index] = nil
end

cancel_drone_order = function(drone_data, on_removed)
    logs.debug("Cancelling drone order")
    local drone = drone_data.entity
    if not (drone and drone.valid) then
        return
    end

    -- local unit_number = drone.unit_number
    -- print("Drone command cancelled "..unit_number.." - "..game.tick)

    clear_target(drone_data)
    clear_extra_targets(drone_data)

    drone_data.pickup = nil
    drone_data.path = nil
    drone_data.dropoff = nil
    drone_data.order = nil
    drone_data.target = nil
    
    if not drone_data.player.connected then
        logs.debug("Player is disconnected, waiting indefinitely")
        return drone_wait(drone_data, math.huge)
    end

    if not find_a_player(drone_data) then
        return drone_wait(drone_data, random(30, 300))
    end

    local stack = get_drone_first_stack(drone_data)
    if stack then
        if not on_removed then
            -- print("Holding a stack, gotta go drop it off... "..unit_number)
            drone_data.dropoff = { stack = stack }
            return process_drone_command(drone_data)
        end
    end

    if not on_removed then
        set_drone_idle(drone)
    end
end

move_to_order_target = function(drone_data, target)
    logs.trace("attempting to move to target")
    local drone = drone_data.entity

    if drone.surface ~= target.surface then
        logs.trace("Drone is on a different surface, task cancelled")
        cancel_drone_order(drone_data)
        return
    end

    if in_construction_range(drone, target) then
        logs.trace("Drone is in construction range")
        return true
    end

    -- Track pathfinding attempts to prevent infinite loops
    drone_data.move_attempts = (drone_data.move_attempts or 0) + 1
    if drone_data.move_attempts > 3 then
        logs.trace("Max move attempts reached, cancelling order")
        cancel_drone_order(drone_data)
        return
    end

    -- Use position-based movement instead of destination_entity for reliability
    drone.commandable.set_command {
        type = defines.command.go_to_location,
        destination_entity = target,
        radius = ((target == drone_data.character and 0) or get_radius(drone, ranges.interact)) +
                get_radius(target, nil, true),
        distraction = defines.distraction.none,
        pathfind_flags = drone_pathfind_flags,
    }
end

move_to_player = function(drone_data, player)
    local drone = drone_data.entity
    logs.trace("attempting to move to player")

    if drone.surface ~= getPlayerSurface(player) then --if the player is on a different surface, stop trying to do anything
        cancel_drone_order(drone_data)
        logs.trace("Drone is on a different surface, cannot move to player")
        return -- tell the caller you can't get to the player
    end
    if distance(drone.position, player.physical_position) < 2 then
        logs.trace("drone distance is < 2 from player")
        return true -- tell the caller you're already at the player
    end

    logs.trace("Sending drone to player physical position")
    drone.commandable.set_command {
        type = defines.command.go_to_location,
        destination_entity = player.character or nil,
        destination = (not player.character and player.physical_position) or nil,
        radius = 0,
        distraction = defines.distraction.none,
        pathfind_flags = drone_pathfind_flags,
    }
    logs.trace(log_separator)
end

--Modify the alt-image of the item the drone is carrying on the drone
update_drone_sticker = function(drone_data)
    local sticker = drone_data.sticker
    if sticker and sticker.valid then
        sticker.destroy()
        -- Legacy
    end

    local renderings = drone_data.renderings
    if renderings then
        for _, v in pairs(renderings) do
            v.destroy()
        end
        drone_data.renderings = nil
    end

    local inventory = get_drone_inventory(drone_data)

    local contents = inventory.get_contents()

    if not next(contents) then return end

    local number = table_size(contents)

    local drone = drone_data.entity
    local surface = drone.surface
    local forces = { drone.force }

    local renderings = {}
    drone_data.renderings = renderings

    insert(renderings, rendering.draw_sprite {
        sprite = "utility/entity_info_dark_background",
        target = {entity = drone, offset = { 0, -0.5 }},
        surface = surface,
        forces = forces,
        only_in_alt_mode = true,
        x_scale = 0.5,
        y_scale = 0.5,
    })

    if number == 1 then
        local r = rendering.draw_sprite {
            sprite = "item/" .. contents[1].name,
            target = {entity = drone, offset = { 0, -0.5 }},
            surface = surface,
            forces = forces,
            only_in_alt_mode = true,
            x_scale = 0.5,
            y_scale = 0.5,
        }
        insert(renderings, r)
        draw_quality_sticker(drone_data, renderings, contents[1].quality)
        return
    end

    local offset_index = 1

    for _, item in pairs(contents) do
        local offset = offsets[offset_index]
        insert(renderings, rendering.draw_sprite {
            sprite = "item/" .. item.name,
            target = {entity = drone, offset = { -0.125 + offset[1], -0.5 + offset[2] }},
            surface = surface,
            forces = forces,
            only_in_alt_mode = true,
            x_scale = 0.25,
            y_scale = 0.25,
        })
        offset_index = offset_index + 1
    end
end

draw_quality_sticker = function(drone_data, renderings, quality)
    local drone = drone_data.entity
    local surface = drone.surface
    local forces = { drone.force }

    local r = rendering.draw_sprite {
        sprite = "quality/" .. quality,
        target = {entity = drone, offset = { -0.23, -0.3 }},
        surface = surface,
        forces = forces,
        only_in_alt_mode = true,
        x_scale = 0.25,
        y_scale = 0.25,
    }
    insert(renderings, r)
    return
end

cancel_player_drone_orders = function(player)
    -- Iterate through all drones commanded by this player
    for unit_number, drone_data in pairs(data.drone_commands) do
        if drone_data.player == player and drone_data.entity and drone_data.entity.valid then
            -- Cancel all current tasks and remove relevant targets
            clear_extra_targets(drone_data)
            clear_target(drone_data)

            -- Clean up any lingering tasks
            if data.job_queue[player.index] then
                data.job_queue[player.index][unit_number] = nil
            end

            -- Reset the drone's internal state
            drone_data.order = nil
            drone_data.target = nil

            -- Set the drone to idle and prevent it from reassuming old tasks
            set_drone_idle(drone_data.entity)
        end
    end

end