local logs = {}

logs.trace = function(string)
    if trace_enabled then
        if use_console then
            game.print(string)
        end
        log(string)
    end
end

logs.debug = function(string)
    if debug_enabled then
        if use_console then
            game.print(string)
        end
        log(string)
    end
end

logs.info = function(string)
    if use_console then
        game.print(string)
    end
    log(string)
end

return logs;