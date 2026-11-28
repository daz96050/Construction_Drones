-- Fakes just enough of the data stage to run quality_variants.lua.
local function deepcopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = deepcopy(v) end
    return c
end
table.deepcopy = table.deepcopy or deepcopy
shared = require("shared")

data = {
    raw = {
        quality = { normal = { level = 0 }, legendary = { level = 5 }, ["quality-unknown"] = { level = 0 } },
        unit = {},
        container = {},
    },
}
function data:extend(list)
    for _, p in ipairs(list) do
        local kind = p.type
        self.raw[kind] = self.raw[kind] or {}
        self.raw[kind][p.name] = p
    end
end

local make = dofile("data/units/construction_drone/quality_variants.lua")
local unit_template = { type = "unit", name = "Construction_Drone" }
local chest_template = { type = "container", name = "Construction_Drone_Proxy_Chest", inventory_size = 4 }

-- variants_for_existing_qualities
make(unit_template, chest_template)
assert(data.raw.unit["legendary-Construction_Drone"].max_health == 112, "variants_for_existing_qualities: unit")
assert(data.raw.unit["legendary-Construction_Drone_spectral"], "variants_for_existing_qualities: spectral")
assert(data.raw.container["Construction_Drone_Proxy_Chest_legendary"].inventory_size == 14, "variants_for_existing_qualities: chest")
assert(not data.raw.unit["quality-unknown-Construction_Drone"], "variants_for_existing_qualities: skips quality-unknown")

-- late_quality_added_on_second_pass
data.raw.quality.mythic = { level = 7 }
local before = data.raw.unit["legendary-Construction_Drone"]
before.marker = true
make(data.raw.unit["normal-Construction_Drone"], chest_template)
assert(data.raw.unit["mythic-Construction_Drone"] and data.raw.container["Construction_Drone_Proxy_Chest_mythic"].inventory_size == 18, "late_quality_added_on_second_pass")
assert(data.raw.unit["legendary-Construction_Drone"].marker, "late_quality_added_on_second_pass: existing variants untouched")
