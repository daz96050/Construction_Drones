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
    local available_items
    --game.print("Searching for stack of " ..stack.name .. " with count " .. stack.count)
    if stack.quality then
        available_items = source_entity.get_item_count({ name = stack.name, quality = stack.quality})
        --game.print("Quality level: " .. stack.quality.level)
    else
        available_items = source_entity.get_item_count(stack.name)
    end
    stack.count = math.min(8, available_items) -- max number of items available for transfer
    if stack.count == 0 then
        return 0
    end
    local transferred = 0
    local insert = destination.insert
    local can_insert = destination.can_insert
    for _, inventory in pairs(inventories(source_entity)) do
        while stack.count > 0 do
            -- Find stack in inventory
            local source_stack = inventory.find_item_stack({ name = stack.name, quality = stack.quality })
            if source_stack and source_stack.valid and source_stack.valid_for_read then
                -- Only transfer up to the remaining count
                local transfer_count = math.min(stack.count, source_stack.count)
                local to_transfer = { name = source_stack.name, count = transfer_count, quality = source_stack.quality }

                if can_insert(to_transfer) then
                    -- Insert into destination inventory
                    local inserted = insert(to_transfer)
                    transferred = transferred + inserted
                    stack.count = stack.count - inserted

                    -- Remove items from the source inventory
                    inventory.remove({ name = source_stack.name, count = inserted, quality = source_stack.quality })
                else break end
            else break end
            if stack.count <= 0 then
                --game.print("Transferred total: " .. transferred)
                return transferred
            end
        end
    end

    --game.print("Transferred end: "..transferred)
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

take_entity_stack = function(inventory, entity)
    local insert = inventory.insert
    local to_spill = {}
    local stack = stack_from_product(entity)
    if stack then
        local leftover = stack.count - insert(stack)
        if leftover > 0 then
            to_spill[stack.name] = (to_spill[stack.name] or 0) + leftover
        end
    end
end

get_drone_stack_capacity = function()
    if drone_stack_capacity then
        return drone_stack_capacity
    end
    drone_stack_capacity = prototypes.entity[proxy_name].get_inventory_size(defines.inventory.chest)
    return drone_stack_capacity
end

get_build_item = function(entity, player)
    local items
    local quality

    if entity.type == "entity-ghost" or entity.type == "tile-ghost"
    then
        items = entity.ghost_prototype.items_to_place_this
        quality = entity.quality
    else
        items = entity.get_upgrade_target().items_to_place_this
        _, quality = entity.get_upgrade_target()
    end

    for _, item in pairs(items) do
        if player.cheat_mode or player.get_item_count({ name = item.name, quality = quality }) >= item.count
        then
            return item
        end
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

stack_from_product = function(entity)
    local stack = { name = entity.name, count = 1, quality = entity.quality }
    return stack
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

search_drone_inventory = function(drone_inventory, item)
    return drone_inventory.get_item_count({name = item.name, quality = item.quality})
end

remove_from_inventory = function(inventory, item, count)
    if count then inventory.remove{ name = item.name, quality = item.quality, count = count}
    else inventory.remove{name = item.name, quality = item.quality}
    end
end