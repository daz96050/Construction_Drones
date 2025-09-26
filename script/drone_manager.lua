get_proxy_chest = function(drone)
    local index = drone.unit_number
    local proxy_chest = data.proxy_chests[index]
    if proxy_chest and proxy_chest.valid then
        return proxy_chest
    end
    local new = drone.surface.create_entity { name = proxy_name, position = proxy_position, force = drone.force }
    data.proxy_chests[index] = new
    return new
end

get_drone_inventory = function(drone_data)
    local inventory = drone_data.inventory
    if inventory and inventory.valid then
        inventory.sort_and_merge()
        return inventory
    end
    local drone = drone_data.entity
    local proxy_chest = get_proxy_chest(drone)
    drone_data.inventory = proxy_chest.get_inventory(defines.inventory.chest)
    return drone_data.inventory
end

get_drone_first_stack = function(drone_data)
    local inventory = get_drone_inventory(drone_data)
    if inventory.is_empty() then
        return
    end
    inventory.sort_and_merge()
    local stack = inventory[1]
    if stack and stack.valid and stack.valid_for_read then
        return stack
    end
end

transfer_stack = function(destination, source_entity, stack)
    if source_entity.is_player() and source_entity.cheat_mode then
        destination.insert(stack)
        return stack.count
    end

    stack.count = math.min(stack.count, source_entity.get_item_count(stack.name))
    if stack.count == 0 then
        return 0
    end
    local transferred = 0
    local insert = destination.insert
    local can_insert = destination.can_insert
    for k, inventory in pairs(inventories(source_entity)) do
        while true do
            local source_stack = inventory.find_item_stack(stack.name)
            if source_stack and source_stack.valid and source_stack.valid_for_read and can_insert(source_stack) then
                local inserted = insert(stack)
                transferred = transferred + inserted
                -- count should always be greater than 0, otherwise can_insert would fail
                inventory.remove(stack)
            else
                break
            end
            if transferred >= stack.count then
                -- print("Transferred: "..transferred)
                return transferred
            end
        end
    end
    -- print("Transferred end: "..transferred)
    return transferred
end

transfer_inventory = function(source, destination)
    local insert = destination.insert
    local remove = source.remove
    local can_insert = destination.can_insert
    for k = 1, #source do
        local stack = source[k]
        if stack and stack.valid and stack.valid_for_read and can_insert(stack) then
            local remove_stack = { name = stack.name, count = insert(stack), quality = stack.quality }
            if remove_stack.count > 0 then
                remove(remove_stack)
            end
        end
    end
end

take_product_stacks = function(inventory, products)
    local insert = inventory.insert
    local to_spill = {}

    if products then
        for _, product in pairs(products) do
            local stack = stack_from_product(product)
            if stack then
                local leftover = stack.count - insert(stack)
                if leftover > 0 then
                    to_spill[stack.name] = (to_spill[stack.name] or 0) + leftover
                end
            end
        end
    end
end

make_path_request = function(drone_data, player, target)
    local prototype = get_prototype(names.units.construction_drone)

    local path_id = player.surface.request_path {
        bounding_box = prototype.collision_box,
        collision_mask = prototype.collision_mask,
        start = player_physical_position(player),
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

get_drone_stack_capacity = function(force)
    if drone_stack_capacity then
        return drone_stack_capacity
    end
    drone_stack_capacity = prototypes.entity[proxy_name].get_inventory_size(defines.inventory.chest)
    return drone_stack_capacity
end

get_build_item = function(prototype, player)
    local items = prototype.items_to_place_this
    for _, item in pairs(items) do
        if player.get_item_count(item.name) >= item.count or player.cheat_mode then
            return item
        end
    end
end

make_player_drone = function(player)
    -- Find a spawn position close to the player.
    local position = player.surface.find_non_colliding_position(
            names.units.construction_drone,
            player_physical_position(player),
            5,
            0.5,
            false
    )

    if not position then
        return
    end

    -- Remove a drone from the player's inventory.
    local removed = player.remove_item({ name = names.units.construction_drone, count = 1 })
    if removed == 0 then
        return
    end

    -- Create the drone entity.
    local drone = player.surface.create_entity {
        name = names.units.construction_drone,
        position = position,
        force = player.force,
    }

    -- Attach the player to the drone data entry.
    local drone_data = {
        entity = drone,
        player = player, -- Associate the spawning player with the drone.
    }

    -- Register the drone for tracking.
    script.register_on_object_destroyed(drone)
    data.drone_commands = data.drone_commands or {}
    data.drone_commands[drone.unit_number] = drone_data

    return drone

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
    if not (drone and drone.valid) then
        return
    end

    -- Ensure the drone always targets the player who spawned it.
    local original_player = drone_data.player
    if original_player and original_player.valid and original_player.surface == drone.surface then
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

    for k, entity in pairs(targets) do
        data.already_targeted[unique_index(entity)] = nil
    end

    if order == drone_orders.deconstruct or order == drone_orders.cliff_deconstruct then
        for index, entity in pairs(targets) do
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
    local drone = drone_data.entity

    if drone.surface ~= target.surface then
        cancel_drone_order(drone_data)
        return
    end

    if in_construction_range(drone, target) then
        return true
    end

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

    if drone.surface ~= player.surface then
        cancel_drone_order(drone_data)
        return
    end

    if distance(drone.position, player.position) < 2 then
        return true
    end

    drone.commandable.set_command {
        type = defines.command.go_to_location,
        destination_entity = player.character or nil,
        destination = (not player.character and player.position) or nil,
        radius = 0,
        distraction = defines.distraction.none,
        pathfind_flags = drone_pathfind_flags,
    }
end

local insert = table.insert

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

    if not next(contents) then
        return
    end

    local number = table_size(contents)

    local drone = drone_data.entity
    local surface = drone.surface
    local forces = { drone.force }

    local renderings = {}
    drone_data.renderings = renderings

    insert(renderings, rendering.draw_sprite {
        sprite = "utility/entity_info_dark_background",
        target = drone,
        surface = surface,
        forces = forces,
        only_in_alt_mode = true,
        target_offset = { 0, -0.5 },
        x_scale = 0.5,
        y_scale = 0.5,
    })

    if number == 1 then
        local attemptor = rendering.draw_sprite {
            sprite = "item/" .. contents[1].name,
            target = drone,
            surface = surface,
            forces = forces,
            only_in_alt_mode = true,
            target_offset = { 0, -0.5 },
            x_scale = 0.5,
            y_scale = 0.5,
        }
        insert(renderings, attemptor)
        return
    end

    local offset_index = 1

    for _, item in pairs(contents) do
        local offset = offsets[offset_index]
        insert(renderings, rendering.draw_sprite {
            sprite = "item/" .. item.name,
            target = drone,
            surface = surface,
            forces = forces,
            only_in_alt_mode = true,
            target_offset = { -0.125 + offset[1], -0.5 + offset[2] },
            x_scale = 0.25,
            y_scale = 0.25,
        })
        offset_index = offset_index + 1
    end
end

get_repair_items = function()
    if repair_items then
        return repair_items
    end
    -- Deliberately not 'local'
    repair_items = {}
    for name, item in pairs(prototypes.item) do
        if item.type == "repair-tool" then
            repair_items[name] = item
        end
    end
    return repair_items
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