get_proxy_chest = function(drone)
    local index = drone.unit_number
    local proxy_chest = data.proxy_chests[index]
    if proxy_chest and proxy_chest.valid then
        return proxy_chest
    end
    local quality_name = drone.quality and drone.quality.name or "normal"
    local chest_name = proxy_name .. "_" .. quality_name
    local new = drone.surface.create_entity { name = chest_name, position = proxy_position, force = drone.force }
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
    local available_items = source_entity.get_item_count({ name = stack.name, quality = stack.quality })
    -- Respect the requested stack count, but cap at available items
    logs.trace("Available Items: " ..serpent.block(available_items))
    stack.count = math.min(stack.count, available_items)
    if stack.count == 0 then
        return 0
    end
    local transferred = 0
    local insert = destination.insert
    local can_insert = destination.can_insert
    for _, inventory in pairs(inventories(source_entity)) do
        while stack.count > 0 do
            local source_stack = inventory.find_item_stack({ name = stack.name, quality = stack.quality })
            logs.trace("source stack: " .. serpent.block(source_stack))
            if source_stack and source_stack.valid and source_stack.valid_for_read then
                local transfer_count = math.min(stack.count, source_stack.count)
                local to_transfer = { name = source_stack.name, count = transfer_count, quality = source_stack.quality }
                logs.trace("to transfer: " .. serpent.block(to_transfer))
                if can_insert(to_transfer) then
                    local inserted = insert(to_transfer)
                    logs.trace("inserted " .. inserted .. " of " .. source_stack.name .. " into inventory")
                    transferred = transferred + inserted
                    stack.count = stack.count - inserted
                    inventory.remove({ name = source_stack.name, count = inserted, quality = source_stack.quality })
                    logs.trace("removed " .. inserted .. " from source")
                else break end
            else break end
        end
    end
    logs.debug("Transferred: " ..transferred.." items to destination")
    return transferred
end

transfer_inventory = function(source, destination)
    for k = 1, #source do
        local stack = source[k]
        if stack and stack.valid and stack.valid_for_read and destination and destination.can_insert(stack) then
            local remove_stack = { name = stack.name, count = destination.insert(stack), quality = stack.quality }
            if remove_stack.count > 0 then
                source.remove(remove_stack)
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

-- Inventory slots of a drone of the given quality (same formula the data stage uses for its proxy chest).
get_drone_capacity = function(quality_name)
    local quality = prototypes.quality[quality_name]
    return shared.drone_stats(quality and quality.level or 0).inventory_size
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
            item.quality = quality
            logs.trace("found build item: " ..serpent.block(item))
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

-- Every item that mining `entity` would hand over: its own mining products plus everything
-- it holds (inventories, belt contents, an inserter's held stack, the ingredients of an
-- in-progress craft). Quality-aware, unlike `contents`.
mining_yield = function(entity)
    local yield = {}
    local item_prototypes = prototypes.item
    local function add(name, count, quality)
        if count and count > 0 and item_prototypes[name] then
            yield[#yield + 1] = { name = name, count = math.ceil(count), quality = quality or "normal" }
        end
    end
    local function add_all(list)
        for _, item in pairs(list) do
            add(item.name, item.count, item.quality)
        end
    end

    local entity_quality = entity.quality and entity.quality.name or "normal"
    local mineable = entity.prototype.mineable_properties
    if mineable and mineable.products then
        for _, product in pairs(mineable.products) do
            if product.type == "item" then
                add(product.name, product.amount or product.amount_max, entity_quality)
            end
        end
    end

    for k = 1, entity.get_max_inventory_index() do
        local inventory = entity.get_inventory(k)
        if inventory and not inventory.is_empty() then
            add_all(inventory.get_contents())
        end
    end

    local max_line_index = belt_connectible_type[entity.type]
    if max_line_index then
        for k = 1, max_line_index do
            local transport_line = entity.get_transport_line(k)
            if not transport_line then break end
            add_all(transport_line.get_contents())
        end
    end

    local entity_type = entity.type
    if entity_type == "inserter" then
        local held = entity.held_stack
        if held and held.valid_for_read then
            add(held.name, held.count, held.quality.name)
        end
    elseif (entity_type == "assembling-machine" or entity_type == "furnace") and entity.is_crafting() then
        local recipe, recipe_quality = entity.get_recipe()
        if recipe then
            local quality_name = recipe_quality and recipe_quality.name or "normal"
            for _, ingredient in pairs(recipe.ingredients) do
                if ingredient.type == "item" then
                    add(ingredient.name, ingredient.amount, quality_name)
                end
            end
        end
    end

    return yield
end

-- Whether `inventory` has room for everything mining `entity` would produce. LuaEntity.mine
-- with force = false only refuses when the entity's *contents* don't fit; once they do, any
-- product that no longer fits (usually the building item itself) is spilled on the ground.
-- Simulates the insert on a scratch copy so the real inventory is untouched.
can_hold_mining_yield = function(inventory, entity)
    local yield = mining_yield(entity)
    if #yield == 0 then return true end
    return inventory_can_swap(inventory, nil, yield)
end

-- Whether `inventory` could take every item in `insertions` after first giving up every item
-- in `removals`, simulated on a scratch copy so the real inventory is untouched. Items are
-- inserted as given, so a `health` field is honoured (damaged items don't stack with whole ones).
inventory_can_swap = function(inventory, removals, insertions)
    local scratch = game.create_inventory(#inventory)
    for k = 1, #inventory do
        local stack = inventory[k]
        if stack.valid_for_read then
            scratch[k].set_stack(stack)
        end
    end

    for _, item in ipairs(removals or {}) do
        scratch.remove(item)
    end

    local fits = true
    for _, item in ipairs(insertions) do
        if scratch.insert(item) < (item.count or 1) then
            fits = false
            break
        end
    end
    scratch.destroy()
    return fits
end

-- Moves as much of `entity`'s inventory contents into `destination` as fits, leaving the
-- entity itself in place. Lets a drone make progress on a container larger than it can carry.
pull_entity_inventories = function(entity, destination)
    for k = 1, entity.get_max_inventory_index() do
        local inventory = entity.get_inventory(k)
        if inventory and not inventory.is_empty() then
            for i = 1, #inventory do
                local stack = inventory[i]
                if stack.valid_for_read then
                    local inserted = destination.insert(stack)
                    if inserted >= stack.count then
                        stack.clear()
                    elseif inserted > 0 then
                        stack.count = stack.count - inserted
                    end
                end
            end
        end
    end
end

search_drone_inventory = function(drone_inventory, item)
    return drone_inventory.get_item_count({name = item.name, quality = item.quality})
end

remove_from_inventory = function(inventory, item, count)
    if count then inventory.remove{ name = item.name, quality = item.quality, count = count}
    else inventory.remove{name = item.name, quality = item.quality}
    end
end