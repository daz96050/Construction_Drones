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

get_drone_stack_capacity = function()
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

