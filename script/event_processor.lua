local logs = require("logs")
local unit_data = require("shared")
local insert = table.insert

-- RPC
remote.add_interface("construction_drone", {
    debug = function(bool)
        data.debug = bool
        debug_enabled = bool
    end,
    dump = function()
         log(serpent.block(data))
    end,
    trace = function(bool)
        trace_enabled = bool
    end,
    console = function(bool)
        use_console = bool
    end
})

local function compute_search_offsets(div)
    local radius = settings.global["construction-drone-search-radius"].value or 60
    local r = radius / div
    local offsets = {}
    for y = -div, div - 1 do
        for x = -div, div - 1 do
            local area = { { x * r, y * r }, { (x + 1) * r, (y + 1) * r } }
            table.insert(offsets, area)
        end
    end
    -- Sort by distance for spiral search order
    table.sort(offsets, function(a, b)
        return distance(a[1], { 0, 0 }) < distance(b[1], { 0, 0 })
    end)
    return offsets
end

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

    local entities = player.physical_surface.find_entities_filtered { area = area, type = ignored_types, invert = true }

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

get_available_drones = function(player)
    local drone_count = 0
    if script.active_mods["quality"] then
        for quality, _ in pairs(unit_data.drone_quality) do
            drone_count = drone_count + player.get_item_count({name = names.units.construction_drone, quality = quality})
        end
    else
        drone_count = player.get_item_count({name = names.units.construction_drone})
    end
    return drone_count
end

can_player_spawn_drones = function(player)
    if not player.is_shortcut_toggled("construction-drone-toggle") then return end
    local current_item_count = get_available_drones(player)

    local count = current_item_count - (data.request_count[player.index] or 0)
    return count > 0
end

check_player_jobs = function(player)
    if not can_player_spawn_drones(player) then return end
    local queue = data.job_queue[player.index]
    if not queue then return end
    local count = math.min(5, get_available_drones(player) - (data.request_count[player.index] or 0))

    for _ = 1, count do
        local index, job = next(queue)
        if not index then return end
        check_job(player, job)
        queue[index] = nil
    end
end

setup_search_offsets = function(div)
    search_offsets = compute_search_offsets(div)
    search_refresh = math.max(#search_offsets, 1)
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
    local force_player_position = settings.global["force-player-position-search"].value
    local position
    if force_player_position then
        -- Use physical_position to clamp search area to player's character location, not remote view
        position = player.physical_position
    else
        -- Use position for remote view or default player position
        position = player.position
    end
    -- Define search area centered on the chosen position
    local search_area = {
        { area[1][1] + position.x, area[1][2] + position.y },
        { area[2][1] + position.x, area[2][2] + position.y },
    }
    -- Scan for jobs in the defined search area
    scan_for_nearby_jobs(player, search_area)
end

schedule_new_searches = function(event_tick)
    local queue = data.search_queue
    if next(queue) then return end
    if search_refresh == nil then
        setup_search_offsets(settings.global["throttling"].value or 1)
    end
    if event_tick % search_refresh ~= 0 then return end

    for _, player in pairs(game.connected_players) do
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

    schedule_new_searches(event.tick)
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
    if not drone_data then return end
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
        logs.debug("Could not create drone")
        clear_target(drone_data)
        clear_extra_targets(drone_data)
        return
    end
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

on_runtime_mod_setting_changed = function(event)
    if event and (event.setting == "throttling" or event.setting == "construction-drone-search-radius" or event.setting == "force-player-position-search") then
        setup_search_offsets(settings.global["throttling"].value)
    end
end

on_player_left_game = function(event)
    local player = game.get_player(event.player_index)
    cancel_player_drone_orders(player)
    data.job_queue[event.player_index] = nil
end

prune_commands = function()
    for unit_number, drone_data in pairs(data.drone_commands) do
        if not (drone_data.entity and drone_data.entity.valid) then
            -- Decrement active drone count for this player
            if drone_data.player then
                data.active_drone_count[drone_data.player.index] = (data.active_drone_count[drone_data.player.index] or 1) - 1
            end
            data.drone_commands[unit_number] = nil
            local proxy_chest = data.proxy_chests[unit_number]
            if proxy_chest then
                proxy_chest.destroy()
                data.proxy_chests[unit_number] = nil
            end
        end
    end
end

on_research_finished = function(event)
    local research = event.research
    if not (research and research.valid and research.force) then return end
    local force = research.force
    -- If startup unlimited is enabled, ensure force bonus is infinite and invalidate caches
    storage.drone_force_bonus = storage.drone_force_bonus or {}
    local unlimited_startup = settings and settings.startup and settings.startup["construction-drone-unlimited"] and settings.startup["construction-drone-unlimited"].value
    if unlimited_startup then
        storage.drone_force_bonus[force.index] = math.huge
    else
        if force.technologies["construction_drone_count_unlimited"] and force.technologies["construction_drone_count_unlimited"].researched then
            storage.drone_force_bonus[force.index] = math.huge
        else
            local bonus = 0
            for i = 1, 9 do
                if force.technologies["construction_drone_count_"..i] and force.technologies["construction_drone_count_"..i].researched then
                    bonus = bonus + 2
                end
            end
            storage.drone_force_bonus[force.index] = bonus
        end
    end

    -- Invalidate per-player caches for players on this force
    for _, player in pairs(game.players) do
        if player.force == force then
            invalidate_drone_count_cache(player)
        end
    end
end

setup_drone_force_bonus = function() 
    -- Initialize force-level drone bonuses from existing research or startup setting
    storage.drone_force_bonus = storage.drone_force_bonus or {}
    local unlimited_startup = settings and settings.startup and settings.startup["construction-drone-unlimited"] and settings.startup["construction-drone-unlimited"].value
    for _, force in pairs(game.forces) do
        if unlimited_startup then
            storage.drone_force_bonus[force.index] = math.huge
        else
            if force.technologies then
                if force.technologies["construction_drone_count_unlimited"] and force.technologies["construction_drone_count_unlimited"].researched then
                    storage.drone_force_bonus[force.index] = math.huge
                else
                    local bonus = 0
                    for i = 1, 9 do
                        if force.technologies["construction_drone_count_"..i] and force.technologies["construction_drone_count_"..i].researched then
                            bonus = bonus + 2
                        end
                    end
                    storage.drone_force_bonus[force.index] = bonus
                end
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
    
    [defines.events.on_research_finished] = on_research_finished,

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
    setup_search_offsets(settings.global["throttling"].value or 1)
    setup_drone_force_bonus()
end

lib.on_configuration_changed = function()
    game.map_settings.path_finder.use_path_cache = false
    data.path_requests = data.path_requests or {}
    data.request_count = data.request_count or {}
    prune_commands()

    if not data.set_default_shortcut then
        data.set_default_shortcut = true
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
    end

    data.search_queue = data.search_queue or {}
    data.job_queue = data.job_queue or {}
    data.already_targeted = data.already_targeted or {}
    setup_search_offsets(settings.global["throttling"].value or 1)  -- Recompute offsets with global settings
end

return lib