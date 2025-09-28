local insert = table.insert

-- RPC
remote.add_interface("construction_drone", {
    set_debug = function(bool)
        data.debug = bool
    end,
    dump = function()
        -- print(serpent.block(data))
    end,
})

scan_for_nearby_jobs = function(player, area)
    local job_queue = data.job_queue
    local player_index = player.index
    if not player.connected then
        job_queue[player_index] = nil
        return
    end

    if not player.is_shortcut_toggled("construction-drone-toggle") then
        job_queue[player_index] = nil
        return
    end
    local player_queue = job_queue[player_index]
    if not player_queue then
        player_queue = {}
        job_queue[player_index] = player_queue
    end
    local already_targeted = data.already_targeted

    local entities = player.surface.find_entities_filtered { area = area, type = ignored_types, invert = true }

    local unique_index = unique_index
    local check_entity = function(entity)
        local index = unique_index(entity)
        if already_targeted[index] then return end
        local name = entity.name
        if name == "entity-ghost" or name == "tile-ghost" then
            player_queue[index] = { type = drone_orders.construct, entity = entity }
            return true
        end

        if name == "item-request-proxy" then
            player_queue[index] = { type = drone_orders.request_proxy, entity = entity }
            return true
        end

        if entity.to_be_deconstructed() then
            player_queue[index] = { type = drone_orders.deconstruct, entity = entity }
            return true
        end

        if (entity.get_health_ratio() or 1) < 1 then
            player_queue[index] = { type = drone_orders.repair, entity = entity }
            return true
        end

        if entity.to_be_upgraded() then
            player_queue[index] = { type = drone_orders.upgrade, entity = entity }
            return true
        end
    end

    for _, entity in pairs(entities) do
        check_entity(entity)
    end
end

can_player_spawn_drones = function(player)
    if not player.is_shortcut_toggled("construction-drone-toggle") then
        return
    end

    local count = player.get_item_count(names.units.construction_drone) - (data.request_count[player.index] or 0)
    return count > 0
end

check_player_jobs = function(player)
    if not can_player_spawn_drones(player) then return end
    local queue = data.job_queue[player.index]
    if not queue then return end
    local count = math.min(
            5,
            player.get_item_count(names.units.construction_drone) - (data.request_count[player.index] or 0)
    )

    for _ = 1, count do
        local index, job = next(queue)
        if not index then return end
        check_job(player, job)
        queue[index] = nil
    end
end

setup_search_offsets = function(div)
    local r = 60 / div

    search_offsets = {}

    for y = -div, div - 1 do
        for x = -div, div - 1 do
            local area = { { x * r, y * r }, { (x + 1) * r, (y + 1) * r } }
            table.insert(search_offsets, area)
        end
    end

    -- Use distance instead of global distance
    table.sort(search_offsets, function(a, b)
        return distance(a[1], { 0, 0 }) < distance(b[1], { 0, 0 })
    end)
    search_refresh = #search_offsets
end

check_search_queue = function()
    local index, search_data = next(data.search_queue)
    if not index then return end
    data.search_queue[index] = nil
    local player_index = search_data.player_index
    local player = game.get_player(player_index)
    if not player then return end
    local area_index = search_data.area_index
    local area = search_offsets[area_index]
    if not area then return end
    local position = player.position
    local search_area = {
        { area[1][1] + position.x, area[1][2] + position.y },
        { area[2][1] + position.x, area[2][2] + position.y },
    }
    scan_for_nearby_jobs(player, search_area)
end

schedule_new_searches = function()
    local queue = data.search_queue
    if next(queue) then
        return
    end

    for k, player in pairs(game.connected_players) do
        local index = player.index
        if can_player_spawn_drones(player) and not next(data.job_queue[index] or {}) then
            for i, _ in pairs(search_offsets) do
                insert(queue, { player_index = index, area_index = i })
            end
        end
    end
end

on_tick = function(event)
    check_search_queue()

    for _, player in pairs(game.connected_players) do
        check_player_jobs(player)
    end

    if event.tick % search_refresh == 0 then
        schedule_new_searches()
    end
end

on_ai_command_completed = function(event)
    local drone_data = data.drone_commands[event.unit_number]
    if drone_data then
        return process_drone_command(drone_data, event.result)
    end
end

on_entity_removed = function(event)
    local unit_number
    local entity = event.entity
    if entity and entity.valid then
        unit_number = entity.unit_number
    else
        unit_number = event.unit_number
    end

    if not unit_number then
        return
    end

    local drone_data = data.drone_commands[unit_number]
    if drone_data then
        cancel_drone_order(drone_data, true)
    end

    local proxy_chest = data.proxy_chests[unit_number]
    if proxy_chest and proxy_chest.valid then
        -- print("Giving inventory buffer from proxy")
        local buffer = event.buffer
        if buffer and buffer.valid then
            local inventory = proxy_chest.get_inventory(defines.inventory.chest)
            if inventory and inventory.valid then
                for _, item in pairs(inventory.get_contents()) do
                    buffer.insert { name = item.name, count = item.count, quality = item.quality }
                end
            end
        end
        proxy_chest.destroy()
    end
end

on_player_created = function(event)
    local player = game.get_player(event.player_index)
    player.set_shortcut_toggled("construction-drone-toggle", true)
end

on_entity_cloned = function(event)
    local destination = event.destination
    if not (destination and destination.valid) then
        return
    end

    local source = event.source
    if not (source and source.valid) then
        return
    end

    if destination.type == "unit" then
        local unit_number = source.unit_number
        if not unit_number then
            return
        end

        local drone_data = data.drone_commands[unit_number]
        if not drone_data then
            return
        end

        local new_data = util.copy(drone_data)
        set_drone_order(destination, new_data)
        return
    end
end

on_script_path_request_finished = function(event)
    local drone_data = data.path_requests[event.id]
    if not drone_data then
        return
    end
    data.path_requests[event.id] = nil

    local player = drone_data.player
    if not (player and player.valid) then
        clear_target(drone_data)
        clear_extra_targets(drone_data)
        return
    end

    local index = player.index
    data.request_count[index] = (data.request_count[index] or 0) - 1

    if not event.path then
        clear_target(drone_data)
        clear_extra_targets(drone_data)
        return
    end

    local drone = make_player_drone(player)
    if not drone then
        --game.print("Could not create drone")
        clear_target(drone_data)
        clear_extra_targets(drone_data)
        return
    end
    --game.print("setting drone order")
    set_drone_order(drone, drone_data)
end

on_construction_drone_toggle = function(event)
    local player = game.players[event.player_index]
    local enabled = not player.is_shortcut_toggled("construction-drone-toggle")
    player.set_shortcut_toggled("construction-drone-toggle", enabled)
    if not enabled then
        cancel_player_drone_orders(player)
        data.job_queue[event.player_index] = nil
    end
end

on_drone_repair_toggle = function(event)
    local player = game.players[event.player_index]
    local enabled = not player.is_shortcut_toggled("drone-repair-toggle")
    player.set_shortcut_toggled("drone-repair-toggle", enabled)
    if not enabled then
        data.job_queue[event.player_index] = nil
    end
end

on_lua_shortcut = function(event)
    if event.prototype_name == "construction-drone-toggle" then
        on_construction_drone_toggle(event)
    end
    if event.prototype_name == "drone-repair-toggle" then
        on_drone_repair_toggle(event)
    end
end

on_runtime_mod_setting_changed = function()
    setup_search_offsets(settings.global["throttling"].value)
end

on_player_left_game = function(event)
    local player = game.get_player(event.player_index)
    cancel_player_drone_orders(player)
    data.job_queue[event.player_index] = nil
end

prune_commands = function()
    for unit_number, drone_data in pairs(data.drone_commands) do
        if not (drone_data.entity and drone_data.entity.valid) then
            data.drone_commands[unit_number] = nil
            local proxy_chest = data.proxy_chests[unit_number]
            if proxy_chest then
                proxy_chest.destroy()
                data.proxy_chests[unit_number] = nil
            end
        end
    end
end

local lib = {}

lib.events = {
    [defines.events.on_tick] = on_tick,

    [defines.events.on_entity_died] = on_entity_removed,
    [defines.events.on_robot_mined_entity] = on_entity_removed,
    [defines.events.on_player_mined_entity] = on_entity_removed,
    [defines.events.on_pre_ghost_deconstructed] = on_entity_removed,
    [defines.events.on_entity_died] = on_entity_removed,

    [defines.events.on_player_created] = on_player_created,
    [defines.events.on_player_left_game] = on_player_left_game,
    [defines.events.on_player_banned] = on_player_left_game,
    [defines.events.on_player_kicked] = on_player_left_game,
    [defines.events.on_pre_player_removed] = on_player_left_game,

    [defines.events.on_ai_command_completed] = on_ai_command_completed,
    [defines.events.on_entity_cloned] = on_entity_cloned,

    [defines.events.on_script_path_request_finished] = on_script_path_request_finished,
    [defines.events.on_lua_shortcut] = on_lua_shortcut,
    ["construction-drone-toggle"] = on_construction_drone_toggle,
    ["drone-repair-toggle"] = on_drone_repair_toggle,

    [defines.events.on_runtime_mod_setting_changed] = on_runtime_mod_setting_changed,
}

lib.on_load = function()
    data = storage.construction_drone or data
    storage.construction_drone = data

    on_runtime_mod_setting_changed()
end

lib.on_init = function()
    game.map_settings.steering.default.force_unit_fuzzy_goto_behavior = false
    game.map_settings.steering.moving.force_unit_fuzzy_goto_behavior = false
    game.map_settings.path_finder.use_path_cache = false
    storage.construction_drone = storage.construction_drone or data

    for _, player in pairs(game.players) do
        player.set_shortcut_toggled("construction-drone-toggle", true)
        local player_settings = settings.get_player_settings(player)
        if not player_settings["drone_process_other_player_construction"] then
            player_settings["drone_process_other_player_construction"] = { value = false }
        end
        if not player_settings["drone_process_other_player_deconstruction"] then
            player_settings["drone_process_other_player_deconstruction"] = { value = false }
        end
        if not player_settings["drone_process_other_player_upgrade"] then
            player_settings["drone_process_other_player_upgrade"] = { value = false }
        end
        if not player_settings["drone_process_other_player_proxies"] then
            player_settings["drone_process_other_player_proxies"] = { value = false }
        end
    end

    on_runtime_mod_setting_changed()
end

lib.on_configuration_changed = function()
    game.map_settings.path_finder.use_path_cache = false
    data.path_requests = data.path_requests or {}
    data.request_count = data.request_count or {}
    prune_commands()

    if not data.set_default_shortcut then
        data.set_default_shortcut = true
        for k, player in pairs(game.players) do
            player.set_shortcut_toggled("construction-drone-toggle", true)
            local player_settings = settings.get_player_settings(player)
            if not player_settings["drone_process_other_player_construction"] then
                player_settings["drone_process_other_player_construction"] = { value = false }
            end
            if not player_settings["drone_process_other_player_deconstruction"] then
                player_settings["drone_process_other_player_deconstruction"] = { value = false }
            end
            if not player_settings["drone_process_other_player_upgrade"] then
                player_settings["drone_process_other_player_upgrade"] = { value = false }
            end
            if not player_settings["drone_process_other_player_proxies"] then
                player_settings["drone_process_other_player_proxies"] = { value = false }
            end
        end
    end

    data.search_queue = data.search_queue or {}
    data.job_queue = data.job_queue or {}
    data.already_targeted = data.already_targeted or {}
end

return lib