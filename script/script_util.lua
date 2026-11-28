local script_util = {}

script_util.center = function(area)
    return { x = (area.left_top.x + area.right_bottom.x) / 2, y = (area.left_top.y + area.right_bottom.y) / 2 }
end

script_util.angle = function(position_1, position_2)
    local d_x = (position_2[1] or position_2.x) - (position_1[1] or position_1.x)
    local d_y = (position_2[2] or position_2.y) - (position_1[2] or position_1.y)
    return math.atan(d_y, d_x)
end

return script_util
