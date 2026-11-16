-- Decides how many targets each free drone takes. Pure Lua: no Factorio globals, so it can be
-- unit-tested outside the game (tests/test_batch_planner.lua).
--
-- Rules:
--   * Use the best min(free drones, targets) drones, so spare targets never leave good drones idle.
--   * Spread targets evenly; when drones can't hold an even share, the higher-capacity drones
--     absorb the overflow (filled worst-first so each drone takes min(capacity, ceil(remaining / left))).
--   * Targets beyond the total capacity are not planned; the caller leaves them for a later scan.
local planner = {}

-- target_count: integer
-- free: array of { quality = string, count = integer, capacity = integer }, any order
-- returns: array of { quality = string, size = integer }, best capacity first
function planner.plan(target_count, free)
    local groups = {}
    for _, group in ipairs(free) do
        if group.count > 0 and group.capacity > 0 then
            groups[#groups + 1] = group
        end
    end
    table.sort(groups, function(a, b)
        if a.capacity ~= b.capacity then return a.capacity > b.capacity end
        return a.quality < b.quality
    end)

    -- The best drones, one entry per drone, at most one per target.
    local drones = {}
    for _, group in ipairs(groups) do
        for _ = 1, group.count do
            if #drones >= target_count then break end
            drones[#drones + 1] = group
        end
    end

    local sizes = {}
    local remaining = target_count
    for i = #drones, 1, -1 do
        local size = math.min(drones[i].capacity, math.ceil(remaining / i))
        sizes[i] = size
        remaining = remaining - size
    end

    local batches = {}
    for i, drone in ipairs(drones) do
        batches[i] = { quality = drone.quality, size = sizes[i] }
    end
    return batches
end

-- How many targets the player can actually supply: held items / items per placement.
-- held = nil means unlimited (cheat mode).
function planner.affordable_targets(target_count, held, per_target)
    if held == nil then return target_count end
    return math.min(target_count, math.floor(held / math.max(per_target, 1)))
end

-- Hands out targets (already sorted by distance) to batches in order.
-- returns: chunks { quality = string, targets = target[] }[], leftover target[] that no batch took
function planner.split(targets, batches)
    local chunks = {}
    local next_index = 1
    for _, batch in ipairs(batches) do
        local chunk = {}
        for i = next_index, math.min(next_index + batch.size - 1, #targets) do
            chunk[#chunk + 1] = targets[i]
        end
        next_index = next_index + #chunk
        if #chunk > 0 then
            chunks[#chunks + 1] = { quality = batch.quality, targets = chunk }
        end
    end
    local leftover = {}
    for i = next_index, #targets do
        leftover[#leftover + 1] = targets[i]
    end
    return chunks, leftover
end

local function by_capacity(capacities, ascending)
    return function(a, b)
        local ca, cb = capacities[a] or 0, capacities[b] or 0
        if ca ~= cb then
            if ascending then return ca < cb end
            return ca > cb
        end
        return a < b
    end
end

local function sorted_qualities(map, capacities, ascending)
    local names = {}
    for name in pairs(map) do names[#names + 1] = name end
    table.sort(names, by_capacity(capacities, ascending))
    return names
end

-- Drones a player can still hand to a new batch.
-- counts:     { [quality] = drones held }
-- reserved:   { [quality] = drones promised to in-flight batched path requests }
-- capacities: { [quality] = inventory slots }
-- allowed:    drones not taken by any in-flight request (held - request_count); unbatched requests
--             hold an unspecified drone, so the total is trimmed to this, lowest capacity first.
-- returns:    FreeDrone[] best capacity first, zero counts omitted
function planner.free_drones(counts, reserved, capacities, allowed)
    local result = {}
    local left = math.max(allowed or 0, 0)
    for _, quality in ipairs(sorted_qualities(counts, capacities, false)) do
        local count = math.min(math.max(counts[quality] - (reserved[quality] or 0), 0), left)
        if count > 0 then
            result[#result + 1] = { quality = quality, count = count, capacity = capacities[quality] or 0 }
            left = left - count
        end
    end
    return result
end

-- Which quality of drone to spawn for a request.
-- preferred: the quality the request reserved (nil for unbatched requests). Used while the player holds one.
-- Otherwise the lowest-capacity drone, preferring one no batch has reserved, so the best drones
-- stay free for batches.
function planner.pick_quality(counts, reserved, preferred, capacities)
    if preferred and (counts[preferred] or 0) > 0 then return preferred end
    local held = {}
    for quality, count in pairs(counts) do
        if count > 0 then held[quality] = count end
    end
    local ordered = sorted_qualities(held, capacities, true)
    for _, quality in ipairs(ordered) do
        if held[quality] > (reserved[quality] or 0) then return quality end
    end
    return ordered[1]
end

return planner
