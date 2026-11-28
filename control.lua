handler = require("event_handler")
shared = require("shared")
util = require("util")
script_util = require("script/script_util")
logs = require("script/logs")
batch_planner = require("script/batch_planner")
require("script/inventory_manager")
require("script/command_processor")
require("script/drone_manager")
require("script/globals")

handler.add_lib(require("script/event_processor"))  -- Registers event handlers and mod lifecycle functions
handler.add_lib(require("script/freeplay_interface"))  -- Registers on_init for freeplay starting items
