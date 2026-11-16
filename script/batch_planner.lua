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

return planner
