local util = require("util")

local is_sprite_def = function(array)
    return array.width and array.height and (array.filename or array.stripes or array.filenames)
end


util.is_sprite_def = is_sprite_def

util.recursive_hack_tint = function(array, tint)
    for _, v in pairs(array) do
        if type(v) == "table" then
            if is_sprite_def(v) then
                v.tint = tint
            end
            util.recursive_hack_tint(v, tint)
        end
    end
end

util.path = function(str)
    return "__Construction_Drones_Forked__/" .. str
end

util.damage_type = function(name)
    if not data.raw["damage-type"][name] then
        data:extend { { type = "damage-type", name = name, localised_name = name } }
    end
    return name
end

util.remove_from_list = function(list, name)
    local remove = table.remove
    for i = #list, 1, -1 do
        if list[i] == name then
            remove(list, i)
        end
    end
end


util.copy = util.table.deepcopy


util.projectile_collision_mask = function()
    return { "layer-15", "player-layer", "train-layer" }
end


util.shift_box = function(box, shift)
    local left_top = box[1]
    local right_bottom = box[2]
    left_top[1] = left_top[1] + shift[1]
    left_top[2] = left_top[2] + shift[2]
    right_bottom[1] = right_bottom[1] + shift[1]
    right_bottom[2] = right_bottom[2] + shift[2]
    return box
end


util.shift_layer = function(layer, shift)
    layer.shift = layer.shift or { 0, 0 }
    layer.shift[1] = layer.shift[1] + shift[1]
    layer.shift[2] = layer.shift[2] + shift[2]
    return layer
end


return util
