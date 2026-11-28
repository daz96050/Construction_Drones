Project: Construction_Drones_Forked — Copilot instructions

Purpose
- Help AI coding agents become productive quickly in this Factorio mod codebase.

Quick architecture summary
- The mod is split across two Factorio stages: data (prototypes) and control (runtime).
  - Data stage: `data.lua` and `data/units/*` define prototypes via `data:extend` (see [data.lua](data.lua#L1-L40)).
  - Runtime stage (control): `control.lua` wires event libraries; most logic lives in `script/*.lua` (see [control.lua](control.lua#L1-L10)).
- Shared constants and prototype names live in [shared.lua](shared.lua#L1-L50) and are referenced across data & runtime.

Key components & integration points
- `control.lua` registers libraries via `handler.add_lib(require(...))`. New event modules must export a `lib` table with `events` and/or lifecycle hooks (`on_init`, `on_load`, `on_configuration_changed`) — example: [script/event_processor.lua](script/event_processor.lua#L385-L412).
- Persistence: runtime state is stored on `storage`, e.g. `storage.construction_drone` is used in `on_load`/`on_init` patterns (see [script/event_processor.lua](script/event_processor.lua#L414-L425)).
- Prototype/name sharing: use values from [shared.lua](shared.lua#L1-L50) (e.g., `shared.units.construction_drone`) instead of hardcoding strings.

Runtime module structure
- All script modules use **global function declarations** (no `local` keyword) for cross-module access. Functions defined in one file are callable from any other file loaded afterward.
- Load order in `control.lua` matters: `shared` → `script_util` → `logs` → `inventory_manager` → `command_processor` → `drone_manager` → `utils` → `globals` → `event_processor` (via handler.add_lib).
- The `data` table in [script/globals.lua](script/globals.lua#L44-L58) holds all persistent runtime state. It is assigned to `storage.construction_drone` during `on_init`/`on_load`. When adding new persistent state, add a default value here **and** a migration (`data.new_field = data.new_field or {}`) in `on_load`.

Quality system
- Drones support any quality, including ones added by other mods. Quality means throughput: better drones carry bigger batches.
- Stats (health, speed, inventory size) come from `shared.drone_stats(level)` in [shared.lua](shared.lua), a formula on the quality's `level`, never its name. Both stages call it.
- **Data stage**: [data/units/construction_drone/quality_variants.lua](data/units/construction_drone/quality_variants.lua) adds a unit, a spectral unit and a proxy chest (`Construction_Drone_Proxy_Chest_<quality>`) for each quality that lacks them. It runs from `construction_drone.lua` and again from `data-final-fixes.lua`, so qualities from mods that load later are covered.
- **Batching**: [script/batch_planner.lua](script/batch_planner.lua) is pure Lua (tested by `lua tests/run.lua`). `plan` sizes batches from the free drones (spread targets across all free drones, best drones absorb overflow), `split` hands the distance-sorted targets out, and leftovers are un-targeted for a later scan.
- **Runtime**: `get_drone_counts(player)` counts held drones by quality; `get_free_drones(player)` subtracts in-flight requests. A batched request stores `drone_data.drone_quality`, reserved via `reserve_drone`/`release_drone` (`data.reserved_drones`); `make_player_drone(player, quality)` spawns that quality, or else the lowest-capacity unreserved drone (`batch_planner.pick_quality`).
- When adding quality-varying behavior, add the stat to `shared.drone_stats` and consume it in both data and runtime stages.

Drone lifecycle & state machine
- Drones are Factorio units managed via `data.drone_commands[unit_number]` — each entry (`drone_data`) tracks entity reference, player owner, current order, pickup/dropoff targets, etc.
- Command flow: `on_ai_command_completed` → `process_drone_command` → dispatches based on `drone_data.pickup`/`dropoff`/`order` → falls back to `find_a_player` → `process_return_to_player_command` or `set_drone_idle`.
- `drone_wait(drone_data, ticks)` issues a stop command; when it expires, `on_ai_command_completed` fires and the cycle re-evaluates.
- **Parked drones**: when a player disconnects, their drones are "parked" (`data.parked_drones[unit_number] = player_index`) with a max-duration stop command to avoid polling. They are unparked on `on_player_joined_game`. Parked drones skip all processing in `on_ai_command_completed`.
- **Job chaining**: After completing a deconstruction, drones check for nearby ghosts they can construct with items they already carry (`find_chain_construct_job` in [script/command_processor.lua](script/command_processor.lua#L459-L505)). This avoids a round-trip to the player for copy-paste and reorganization scenarios. The search radius is per-player configurable via `drone-chain-search-radius`.

Proxy chest system
- Drones (Factorio units) have no native inventory. Each drone gets a hidden `container` entity as its "backpack", placed off-map at `{1000000, 1000000}`.
- `get_proxy_chest(drone)` in [script/inventory_manager.lua](script/inventory_manager.lua#L1-L11) lazily creates the chest, selecting the quality-appropriate prototype.
- `get_drone_inventory(drone_data)` returns the proxy chest's inventory and caches it on `drone_data.inventory`.
- Cleanup: proxy chests are destroyed when a drone returns to player, dies, or is pruned.

Common pitfalls
- **`player.valid` vs `player.character`**: A `LuaPlayer` remains `.valid` even when disconnected or in spectator/remote view. Always check `player.character` before indexing it — it is `nil` when the player has no physical body.
- **`find_a_player` return value**: Returns `true`/`false` indicating whether the drone can reach its player. It does NOT modify `drone_data.player`. Always use the return value, not `drone_data.player`, to decide whether to proceed.
- **Unit commands**: `drone.commandable.set_command` replaces any current command. When a command finishes (including stop), `on_ai_command_completed` fires with `event.unit_number`.
- **Quality matching**: When matching items to ghosts or entities, always compare both item name AND quality. Use `entity.quality.name` for the quality string. See `find_chain_construct_job` for a pattern.

Settings reference
- `throttling` (global int, 1-10): Subdivides per-player search area. Higher = less CPU, lower = more responsive.
- `construction-drone-search-radius` (global int, 10-200): Radius in tiles for job scanning.
- `force-player-position-search` (global bool): Clamp search to player character position.
- `remote-view-spawn` (global bool): Allow drone spawn from remote view.
- `drone-chain-search-radius` (per-user int, 0-32): Radius for post-deconstruction ghost chaining. 0 disables.
- `drone_process_other_player_construction/deconstruction/upgrade/proxies` (per-user bool): Cross-player job processing.

Project-specific conventions
- Module requires: control-stage code uses relative require paths like `require("script/utils")` — maintain this layout (control stage is per-mod isolated, so no cross-mod collision). The data stage shares one Lua state and caches modules by the bare path string, so a bare relative require to a file whose name also exists in another mod collides in the shared cache and the alphabetically-first mod's copy wins for both. Any new data-stage lib file with a generic name MUST be required mod-qualified (`require("__Construction_Drones_Forked__/...")`). The mod no longer ships Klonan's `tf_util` (whose `util.path` hit exactly this collision with Teleporters); use vanilla `util` (`util.copy`, `util.by_pixel`, `util.recursive_tint`, `util.distance`) and build sprite paths from `shared.mod_path`. Control-stage helpers that vanilla lacks live in `script/script_util.lua` as the `script_util` global — don't add fields to the vanilla `util` table.
- Event modules export a `lib` table and list events in `lib.events` keyed by `defines.events` or custom shortcut names. Do not mutate the event handler registration pattern.
- Use `data:extend` only in data-stage files and avoid runtime require of data-only code.

Build / run / debug
- Packaging / deployment: project contains `deploy.ps1` in the repo root. Run the script on Windows PowerShell to build/deploy the mod: `./deploy.ps1`.

Patterns & examples agents should follow
- When adding new event handlers, follow the `lib.events` pattern and return `lib` (example: [script/event_processor.lua](script/event_processor.lua#L385-L412)).
- Use `storage` namespaced entries (e.g., `storage.construction_drone`) for persistent tables to survive saves/loads (see [script/event_processor.lua](script/event_processor.lua#L414-L425)).
- Data/prototype changes belong in `data.lua` or `data/` subfolders and must reference shared names in [shared.lua](shared.lua#L1-L50).
- Prefer small, focused patches. Avoid refactors that touch many unrelated files.
- When adding per-player settings, define in `settings.lua` as `runtime-per-user`, add locale in `locale/en/config.cfg`, and access at runtime via `settings.get_player_settings(player)["setting-name"].value`.

File references for common tasks
- Add new prototype: modify `data.lua` or add a file under `data/units/` and reference names from [shared.lua](shared.lua#L1-L50).
- Add runtime behavior: create a module under `script/` that exports `lib` and `events`, then register it from `control.lua`.
- Add a new setting: define in [settings.lua](settings.lua), add name and description in [locale/en/config.cfg](locale/en/config.cfg), then read at runtime.
- Debugging: use `remote.add_interface` hooks and logging via the `logs` module used across `script/`.

Agent behavior rules
- Do not add or change licensing headers. Keep modifications minimal and logically scoped.
- Preserve existing public APIs: `storage` keys, remote interface names, and prototype names in `shared.lua`.
- Use the project's require/import conventions and folder layout. Keep data-stage code separated from runtime.
- For information about the Factorio modding API, refer to the official documentation: https://lua-api.factorio.com/latest.

When changes are complete, run `deploy.ps1` using pwsh to deploy the changes.