handler = require("event_handler")
names = require("shared")
util = require("script/script_util")
require("script/command_processor")
require("script/drone_manager")
require("script/utils")
require("script/globals")

handler.add_lib(require("script/event_processor"))  -- Registers event handlers and mod lifecycle functions
handler.add_lib(require("script/freeplay_interface"))  -- Registers on_init for freeplay starting items