check_ghost = function(entity, player)
    if not (entity and entity.valid) then return end
    if not should_process_entity(entity, player, drone_orders.construct) then return end
    if data.already_targeted[entity.unit_number] then return end

    local item = get_build_item(entity, player)

    if not item then return end -- if the player doesn't have the required item, we can't continue

    local surface = entity.surface
    local position = entity.position

    local count = 0
    local extra_targets = {}
    local extra
    if entity.name == "tile-ghost" then extra = surface.find_entities_filtered { type = tile_ghost_type, position = position, radius = 3 }
    else extra = surface.find_entities_filtered { ghost_name = entity.ghost_name, position = position, quality = entity.quality.name, radius = 5 }
    end
    for _, ghost in pairs(extra) do
        if count >= 8 then
            break
        end
        local unit_number = ghost.unit_number
        local should_check = not data.already_targeted[unit_number]
        if should_check and should_process_entity(entity, player, drone_orders.construct) then
            if ghost.ghost_name == entity.ghost_name and ghost.quality == entity.quality then
                data.already_targeted[unit_number] = true
                extra_targets[unit_number] = ghost
                count = count + 1
            end
        end
    end

    local origCount = item.count
    item.count = item.count * count

    local target = surface.get_closest(player.position, extra_targets)
    extra_targets[target.unit_number] = nil

    local drone_data = {
        player = player,
        order = drone_orders.construct,
        pickup = { stack = item },
        target = target,
        entity_ghost_name = entity.ghost_name,
        item_to_place = item,
        item_place_count = origCount,
        extra_targets = extra_targets,
    }

    make_path_request(drone_data, player, target)
end

check_upgrade = function(entity, player)
    if not (entity and entity.valid) then return end
    if not should_process_entity(entity, player, drone_orders.upgrade) then return end
    if not entity.to_be_upgraded() then return end

    local index = unique_index(entity)
    if data.already_targeted[index] then return end

    local upgrade_prototype, upgrade_quality = entity.get_upgrade_target()
    if not upgrade_prototype then return end

    local surface = entity.surface

    local item = get_build_item(entity, player)
    if not item then game.print("no build item found") return end

    local count = 0

    local extra_targets = {}
    for _, nearby in pairs(surface.find_entities_filtered {
        name = entity.name,
        position = entity.position,
        radius = 8,
        to_be_upgraded = true,
    }) do
        if count >= 6 then
            break
        end
        local nearby_index = nearby.unit_number
        local should_check = not data.already_targeted[nearby_index]
        if should_check and should_process_entity(entity, player, drone_orders.upgrade) then
            data.already_targeted[nearby_index] = true
            extra_targets[nearby_index] = nearby
            count = count + 1
        end
    end

    local target = surface.get_closest(player.position, extra_targets)
    extra_targets[target.unit_number] = nil
    game.print("Adding " .. count .. " to stack "..item.name .." with quality " .. upgrade_quality.level)
    local drone_data = {
        player = player,
        order = drone_orders.upgrade,
        pickup = { stack = { name = item.name, count = count, quality = upgrade_quality } },
        target = target,
        extra_targets = extra_targets,
        upgrade_prototype = upgrade_prototype,
        item_to_place = item,
    }
    game.print("dispatching drone")
    make_path_request(drone_data, player, target)
end

check_proxy = function(entity, player)
    if not (entity and entity.valid) then
        return
    end

    if not should_process_entity(entity, player, drone_orders.request_proxy) then
        return
    end

    local target = entity.proxy_target
    if not (target and target.valid) then
        return
    end

    if data.already_targeted[unique_index(entity)] then
        return
    end

    local items = entity.item_requests

    for _, item in pairs(items) do
        if player.get_item_count(item.name) > 0 or player.cheat_mode then
            local drone_data = {
                player = player,
                order = drone_orders.request_proxy,
                pickup = { stack = { item } },
                target = entity,
            }
            make_path_request(drone_data, player, entity)
        end
    end

    data.already_targeted[unique_index(entity)] = true
end

check_cliff_deconstruction = function(entity, player)
    local cliff_destroying_item = entity.prototype.cliff_explosive_prototype
    if not cliff_destroying_item then
        return
    end

    if (not player.cheat_mode) and player.get_item_count(cliff_destroying_item) == 0  then
        return
    end

    local drone_data = {
        player = player,
        order = drone_orders.cliff_deconstruct,
        target = entity,
        pickup = { stack = { name = cliff_destroying_item, count = 1 } },
    }
    make_path_request(drone_data, player, entity)

    data.already_targeted[unique_index(entity)] = true
end

check_deconstruction = function(entity, player)
    if not (entity and entity.valid) then
        return
    end

    if not should_process_entity(entity, player, drone_orders.deconstruct) then
        return
    end

    if not entity.to_be_deconstructed() then
        return
    end

    local index = unique_index(entity)
    if data.already_targeted[index] then
        return
    end

    local force = player.force

    if not (entity.force == force or entity.force.name == "neutral" or entity.force.get_friend(force)) then
        return
    end

    if entity.type == cliff_type then
        return check_cliff_deconstruction(entity, player)
    end

    local surface = entity.surface

    local sent = data.sent_deconstruction[index] or 0

    local capacity = get_drone_stack_capacity()
    local total_contents = contents(entity)
    local stack_sum = 0
    local items = prototypes.item
    for name, count in pairs(total_contents) do
        stack_sum = stack_sum + (count / items[name].stack_size)
    end
    local needed = math.ceil((stack_sum + 1) / capacity)
    needed = needed - sent

    if needed <= 1 then
        local extra_targets = {}
        local count = 10

        for _, nearby in pairs(surface.find_entities_filtered {
            name = entity.name,
            position = entity.position,
            radius = 8,
            to_be_deconstructed = true,
        }) do
            if count <= 0 then
                break
            end
            local nearby_index = unique_index(nearby)
            local should_check = not data.already_targeted[nearby_index]
            if should_check and should_process_entity(entity, player, drone_orders.deconstruct) then
                data.already_targeted[nearby_index] = true
                data.sent_deconstruction[nearby_index] = (data.sent_deconstruction[nearby_index] or 0) + 1
                extra_targets[nearby_index] = nearby
                count = count - 1
            end
        end

        local target = surface.get_closest(player.position, extra_targets)
        if not target then
            return
        end

        extra_targets[unique_index(target)] = nil

        local drone_data = {
            player = player,
            order = drone_orders.deconstruct,
            target = target,
            extra_targets = extra_targets,
        }

        make_path_request(drone_data, player, target)
        return
    end

    for _ = 1, math.min(needed, 10, player.get_item_count(names.units.construction_drone)) do
        if not (entity and entity.valid) then
            break
        end
        local drone_data = { player = player, order = drone_orders.deconstruct, target = entity }
        make_path_request(drone_data, player, entity)
        sent = sent + 1
    end

    data.sent_deconstruction[index] = sent

    if sent >= needed then
        data.already_targeted[index] = true
    end
end

check_repair = function(entity, player)
    if not (entity and entity.valid) then
        return true
    end

    -- Respect player's allow_bot_repair setting
    if not player.is_shortcut_toggled("drone-repair-toggle") then
        return true -- Repairing disabled; skip
    end


    if entity.has_flag("not-repairable") then
        return
    end

    local health = entity.get_health_ratio()
    if not (health and health < 1) then
        return true
    end

    local index = unique_index(entity)
    if data.already_targeted[index] then
        return
    end

    local force = entity.force
    if not (force == player.force or player.force.get_friend(force)) then
        return
    end

    local repair_item
    local repair_items = get_repair_items()
    for name, item in pairs(repair_items) do
        if player.get_item_count(name) > 0 or player.cheat_mode then
            repair_item = item
            break
        end
    end

    if not repair_item then
        return
    end

    local drone_data = {
        player = player,
        order = drone_orders.repair,
        pickup = { stack = { name = repair_item.name, count = 1 } },
        target = entity,
    }

    make_path_request(drone_data, player, entity)

    data.already_targeted[index] = true
end

check_job = function(player, job)
    if job.type == drone_orders.construct then
        check_ghost(job.entity, player)
        return
    end

    if job.type == drone_orders.deconstruct then
        check_deconstruction(job.entity, player)
        return
    end

    if job.type == drone_orders.upgrade then
        check_upgrade(job.entity, player)
        return
    end

    if job.type == drone_orders.request_proxy then
        check_proxy(job.entity, player)
        return
    end

    if job.type == drone_orders.repair then
        check_repair(job.entity, player)
        return
    end
end

process_pickup_command = function(drone_data)
    -- print("Procesing pickup command")

    local player = drone_data.player
    if not (player and player.valid) then
        -- print("Character for pickup was not valid")
        return cancel_drone_order(drone_data)
    end

    if not move_to_player(drone_data, player) then
        return
    end

    -- print("Pickup chest in range, picking up item")

    local stack = drone_data.pickup.stack
    local drone_inventory = get_drone_inventory(drone_data)

    transfer_stack(drone_inventory, player, stack)

    update_drone_sticker(drone_data)

    drone_data.pickup = nil

    return process_drone_command(drone_data)
end

process_dropoff_command = function(drone_data)
    -- print("Procesing dropoff command. "..drone.unit_number)

    if drone_data.player then
        return process_return_to_player_command(drone_data)
    end

    find_a_player(drone_data)
end

process_construct_command = function(drone_data)
    -- print("Processing construct command")
    local target = drone_data.target
    local item = drone_data.item_to_place
    if not (target and target.valid and drone_data.item_place_count) then
        return cancel_drone_order(drone_data)
    end

    local drone_inventory = get_drone_inventory(drone_data)
    if search_drone_inventory(drone_inventory, item) < drone_data.item_place_count then
        return cancel_drone_order(drone_data)
    end

    if target.ghost_name ~= drone_data.entity_ghost_name and target.quality ~= item.quality then
        return cancel_drone_order(drone_data) -- entity got upgraded?
    end

    if not move_to_order_target(drone_data, target) then
        return
    end

    local drone = drone_data.entity
    local position = target.position
    local force = target.force
    local surface = target.surface

    local index = unique_index(target)
    local colliding_items, entity, _ = target.revive(revive_param)
    if not colliding_items then
        if target.valid then
            drone_wait(drone_data, 30)
            -- print("Some idiot might be in the way too ("..drone.unit_number.." - "..game.tick..")")
            local radius = get_radius(target)
            for _, unit in pairs(target.surface.find_entities_filtered {
                type = "unit",
                position = position,
                radius = radius,
            }) do
                -- print("Telling idiot to MOVE IT ("..drone.unit_number.." - "..game.tick..")")
                unit_clear_target(unit, target)
            end
        end
        return
    end
    data.already_targeted[index] = nil

    for _, item in pairs(colliding_items) do
        local inserted = drone_inventory.insert { name = item.name, count = item.count, quality = item.quality }

        if inserted < item.count then
            surface.spill_item_stack({
                position = position,
                stack = { name = item.name, count = item.count - inserted, quality = item.quality },
                enable_looted = false,
                force = force
            })
        end
    end
    remove_from_inventory(drone_inventory, drone_data.item_to_place, drone_data.item_place_count)
    update_drone_sticker(drone_data)

    drone_data.target = get_extra_target(drone_data)

    local build_time = get_build_time()
    local orientation, offset = get_beam_orientation(drone.position, position)
    drone.orientation = orientation
    drone.surface.create_entity {
        name = beams.build,
        source = drone,
        target = entity and entity.valid and entity,
        target_position = position,
        position = position,
        force = drone.force,
        duration = build_time - 5,
        source_offset = offset,
    }
    return drone_wait(drone_data, build_time)
end

process_failed_command = function(drone_data)
    local drone = drone_data.entity

    local modifier = drone.ai_settings.path_resolution_modifier

    if modifier <= 2 then
        drone.ai_settings.path_resolution_modifier = modifier + 1
        return drone_wait(drone_data, 107)
    end

    drone.ai_settings.path_resolution_modifier = 0
    cancel_drone_order(drone_data, true)
    process_return_to_player_command(drone_data, true)
end

process_deconstruct_command = function(drone_data)
    -- print("Processing deconstruct command")
    local target = drone_data.target
    if not (target and target.valid) then
        return cancel_drone_order(drone_data)
    end

    if not target.to_be_deconstructed() then
        return cancel_drone_order(drone_data)
    end

    if not move_to_order_target(drone_data, target) then
        return
    end

    local drone_inventory = get_drone_inventory(drone_data)

    local index = unique_index(target)

    local drone = drone_data.entity
    if not drone_data.beam then
        local build_time = get_build_time()
        local orientation, offset = get_beam_orientation(drone.position, target.position)
        drone.orientation = orientation
        drone_data.beam = drone.surface.create_entity {
            name = beams.deconstruction,
            source = drone,
            target_position = target.position,
            position = drone.position,
            force = drone.force,
            duration = build_time - 5,
            source_offset = offset,
        }
        return drone_wait(drone_data, build_time)
    else
        drone_data.beam = nil
    end

    local tiles
    if target.type == tile_deconstruction_proxy then
        tiles = { { name = target.surface.get_hidden_tile(target.position) or "grass-1", position = target.position } }
    end

    local mined = target.mine { inventory = drone_inventory, force = false, raise_destroyed = true }
    data.already_targeted[index] = nil

    if mined then
        data.sent_deconstruction[index] = nil
    else
        update_drone_sticker(drone_data)
        if drone_inventory.is_empty() then
            return drone_wait(drone_data, 300)
        end
        cancel_drone_order(drone_data)
        return
    end

    if tiles then
        drone.surface.set_tiles(tiles, true, false, false, true)
    end

    local extra_target = get_extra_target(drone_data)
    if extra_target then
        drone_data.target = extra_target
    else
        drone_data.dropoff = {}
    end

    update_drone_sticker(drone_data)
    return process_drone_command(drone_data)
end

process_repair_command = function(drone_data)
    -- print("Processing repair command")
    local target = drone_data.target

    if not (target and target.valid) then
        return cancel_drone_order(drone_data)
    end

    if target.get_health_ratio() == 1 then
        -- print("Target is fine... give up on healing him")
        return cancel_drone_order(drone_data)
    end

    if not move_to_order_target(drone_data, target) then
        return
    end

    local drone = drone_data.entity
    local drone_inventory = get_drone_inventory(drone_data)
    local stack
    for name, _ in pairs(get_repair_items()) do
        stack = drone_inventory.find_item_stack(name)
        if stack then
            break
        end
    end

    if not stack then
        -- print("I don't have a repair item... get someone else to do it")
        return cancel_drone_order(drone_data)
    end

    local repair_speed = prototypes.item[stack.name].speed
    if not repair_speed then
        -- print("WTF, maybe some migration?")
        return cancel_drone_order(drone_data)
    end

    local ticks_to_repair = random(20, 30)
    local repair_cycles_left = math.ceil((target.max_health - target.health) / repair_speed)
    local max_left = math.ceil(stack.durability / repair_speed)
    ticks_to_repair = math.min(ticks_to_repair, repair_cycles_left)
    ticks_to_repair = math.min(ticks_to_repair, max_left)

    local repair_amount = (repair_speed * ticks_to_repair)

    target.health = target.health + repair_amount
    stack.drain_durability(repair_amount)

    if not stack.valid_for_read then
        -- print("Stack expired, someone else will take over")
        return cancel_drone_order(drone_data)
    end

    local orientation, offset = get_beam_orientation(drone.position, target.position)
    drone.orientation = orientation
    drone.surface.create_entity {
        name = beams.build,
        source = drone,
        target = target,
        position = drone.position,
        force = drone.force,
        duration = ticks_to_repair,
        source_offset = offset,
    }

    return drone_wait(drone_data, ticks_to_repair)
end

process_upgrade_command = function(drone_data)
    -- print("Processing upgrade command")

    local target = drone_data.target
    if not (target and target.valid and target.to_be_upgraded()) then
        return cancel_drone_order(drone_data)
    end

    local drone_inventory = get_drone_inventory(drone_data)
    if search_drone_inventory(drone_inventory, drone_data.item_to_place) == 0 then
        return cancel_drone_order(drone_data)
    end

    local drone = drone_data.entity

    if not move_to_order_target(drone_data, target) then
        return
    end

    local surface = drone.surface
    local prototype = drone_data.upgrade_prototype
    local direction = target.direction
    local original_name = target.name
    local entity_type = target.type
    local index = unique_index(target)
    local neighbour = entity_type == "underground-belt" and target.neighbours
    local type = entity_type == "underground-belt" and target.belt_to_ground_type or
            (entity_type == "loader" or entity_type == "loader-1x1") and target.loader_type
    local position = target.position

    surface.create_entity {
        name = prototype.name,
        position = position,
        direction = direction,
        fast_replace = true,
        force = target.force,
        spill = false,
        type = type or nil,
        raise_built = true,
    }

    data.already_targeted[index] = nil
    remove_from_inventory(drone_inventory, drone_data.item_to_place)

    local inv = get_drone_inventory(drone_data)
    local products = get_prototype(original_name).mineable_properties.products

    take_product_stacks(inv, products)
    if neighbour and neighbour.valid and search_drone_inventory(inv, drone_data.item_to_place) > 0 then
        -- print("Upgrading neighbour")
        local type = neighbour.type == "underground-belt" and neighbour.belt_to_ground_type
        local neighbour_index = unique_index(neighbour)
        surface.create_entity {
            name = prototype.name,
            position = neighbour.position,
            direction = neighbour.direction,
            fast_replace = true,
            force = neighbour.force,
            spill = false,
            type = type or nil,
            raise_built = true,
        }
        data.already_targeted[neighbour_index] = nil
        take_product_stacks(drone_inventory, products)
        remove_from_inventory(drone_inventory, drone_data.item_to_place)
    end

    local extra_target = get_extra_target(drone_data)
    if extra_target then
        drone_data.target = extra_target
    else
        drone_data.dropoff = {}
    end

    update_drone_sticker(drone_data)
    local working_drone = drone_data.entity
    local build_time = get_build_time()
    local orientation, offset = get_beam_orientation(working_drone.position, position)
    working_drone.orientation = orientation
    working_drone.surface.create_entity {
        name = beams.build,
        source = drone,
        target_position = position,
        position = drone.position,
        force = drone.force,
        duration = build_time - 5,
        source_offset = offset,
    }
    return drone_wait(drone_data, build_time)
end

process_request_proxy_command = function(drone_data)
    -- print("Processing request proxy command")

    local target = drone_data.target
    if not (target and target.valid) then
        return cancel_drone_order(drone_data)
    end

    local proxy_target = target.proxy_target
    if not (proxy_target and proxy_target.valid) then
        return cancel_drone_order(drone_data)
    end

    local drone = drone_data.entity

    local drone_inventory = get_drone_inventory(drone_data)
    local find_item_stack = drone_inventory.find_item_stack
    local requests = target.item_requests

    local stack
    local requests_index
    for k, item in pairs(requests) do
        stack = find_item_stack(item.name)
        requests_index = k
        if stack then
            break
        end
    end

    if not stack then
        -- print("We don't have anything to offer, abort")
        return cancel_drone_order(drone_data)
    end

    if not move_to_order_target(drone_data, proxy_target) then
        return
    end

    -- print("We are in range, and we have what he wants")

    local stack_name = stack.name
    local position = target.position
    local inserted = 0
    local moduleInv = proxy_target.get_module_inventory()

    if moduleInv then
        inserted = moduleInv.insert(stack)
    end

    if not moduleInv or inserted == 0 then
        inserted = proxy_target.insert(stack)
    end

    if inserted == 0 then
        -- print("Can't insert anything anyway, kill the proxy")
        target.destroy()
        return cancel_drone_order(drone_data)
    end
    drone_inventory.remove({ name = stack_name, count = inserted })
    requests[requests_index].count = requests[requests_index].count - inserted
    if requests[requests_index].count <= 0 then
        requests[requests_index] = nil
    end

    -- If we fulfilled all the requests, we can safely destroy the proxy chest
    if not next(requests) then
        target.destroy()
    end

    local build_time = get_build_time()
    local orientation, offset = get_beam_orientation(drone.position, position)
    drone.orientation = orientation
    drone.surface.create_entity {
        name = beams.build,
        source = drone,
        target_position = position,
        position = drone.position,
        force = drone.force,
        duration = build_time - 5,
        source_offset = offset,
    }

    update_drone_sticker(drone_data)

    return drone_wait(drone_data, build_time)
end

process_deconstruct_cliff_command = function(drone_data)
    -- print("Processing deconstruct cliff command")
    local target = drone_data.target

    if not (target and target.valid) then
        -- print("Target cliff was not valid. ")
        return cancel_drone_order(drone_data)
    end

    local drone = drone_data.entity

    if not move_to_order_target(drone_data, target) then
        return
    end

    if not drone_data.beam then
        local drone = drone_data.entity
        local build_time = get_build_time()
        local orientation, offset = get_beam_orientation(drone.position, target.position)
        drone.orientation = orientation
        drone.surface.create_entity {
            name = beams.deconstruction,
            source = drone,
            target_position = target.position,
            position = drone.position,
            force = drone.force,
            duration = build_time,
            source_offset = offset,
        }
        drone_data.beam = true
        return drone_wait(drone_data, build_time)
    else
        drone_data.beam = nil
    end
    local index = unique_index(target)
    get_drone_inventory(drone_data).remove { name = target.prototype.cliff_explosive_prototype, count = 1 }
    target.surface.create_entity { name = "ground-explosion", position = util.center(target.bounding_box) }
    target.destroy({ do_cliff_correction = true })
    data.already_targeted[index] = nil
    -- print("Cliff destroyed, heading home bois. ")
    update_drone_sticker(drone_data)

    return set_drone_idle(drone)
end

process_return_to_player_command = function(drone_data, force)
    local player = drone_data.player
    if not (player and player.valid) then
        return cancel_drone_order(drone_data)
    end

    if not (force or move_to_player(drone_data, player)) then return end

    local inventory = get_drone_inventory(drone_data)
    transfer_inventory(inventory, player)

    if not inventory.is_empty() then
        drone_wait(drone_data, random(18, 24))
        return
    end

    if player.insert({ name = names.units.construction_drone, count = 1 }) == 0 then
        drone_wait(drone_data, random(18, 24)) --If the drone didn't get inserted into the players inventory, wait & follow the player until it does
        return
    end

    cancel_drone_order(drone_data, true)

    local unit_number = drone_data.entity.unit_number

    local proxy_chest = data.proxy_chests[unit_number]
    if proxy_chest then
        proxy_chest.destroy()
        data.proxy_chests[unit_number] = nil
    end
    data.drone_commands[unit_number] = nil

    drone_data.entity.destroy()
end

local max = math.max
process_drone_command = function(drone_data, result)
    local drone = drone_data.entity
    if not (drone and drone.valid) then
        return
    end

    if drone_data.player and drone_data.player.valid and drone_data.player.character then
        drone.speed = max(drone_data.player.character_running_speed * 1.2, 0.2)
    else
        drone.speed = 0.2
    end

    if (result == defines.behavior_result.fail) then
        -- print("Fail")
        return process_failed_command(drone_data)
    end

    if drone_data.pickup then
        -- print("Pickup")
        return process_pickup_command(drone_data)
    end

    if drone_data.dropoff then
        -- print("Dropoff")
        return process_dropoff_command(drone_data)
    end

    if drone_data.order == drone_orders.construct then
        -- print("Construct")
        return process_construct_command(drone_data)
    end

    if drone_data.order == drone_orders.deconstruct then
        -- print("Deconstruct")
        return process_deconstruct_command(drone_data)
    end

    if drone_data.order == drone_orders.repair then
        -- print("Repair")
        return process_repair_command(drone_data)
    end

    if drone_data.order == drone_orders.upgrade then
        -- print("Upgrade")
        return process_upgrade_command(drone_data)
    end

    if drone_data.order == drone_orders.request_proxy then
        -- print("Request proxy")
        return process_request_proxy_command(drone_data)
    end

    if drone_data.order == drone_orders.cliff_deconstruct then
        -- print("Cliff Deconstruct")
        return process_deconstruct_cliff_command(drone_data)
    end

    find_a_player(drone_data)

    if drone_data.player then
        return process_return_to_player_command(drone_data)
    end

    -- game.print("Nothin")
    return set_drone_idle(drone)
end