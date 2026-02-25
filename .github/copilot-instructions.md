Project: Construction_Drones_Forked — Copilot instructions

Purpose
- Help AI coding agents become productive quickly in this Factorio mod codebase.

Quick architecture summary
- The mod is split across two Factorio stages: data (prototypes) and control (runtime).
  - Data stage: `data.lua` and `data/units/*` define prototypes via `data:extend` (see [data.lua](data.lua#L1-L40)).
  - Runtime stage (control): `control.lua` wires event libraries; most logic lives in `script/*.lua` (see [control.lua](control.lua#L1-L10)).
- Shared constants and prototype names live in [shared.lua](shared.lua#L1-L40) and are referenced across data & runtime.

Key components & integration points
- `control.lua` registers libraries via `handler.add_lib(require(...))`. New event modules must export a `lib` table with `events` and/or lifecycle hooks (`on_init`, `on_load`, `on_configuration_changed`) — example: [script/event_processor.lua](script/event_processor.lua#L300-L320).
- Persistence: runtime state is stored on `storage`, e.g. `storage.construction_drone` is used in `on_load`/`on_init` patterns (see [script/event_processor.lua](script/event_processor.lua#L320-L340)).
- Prototype/name sharing: use values from [shared.lua](shared.lua#L1-L40) (e.g., `names.units.construction_drone`) instead of hardcoding strings.

Project-specific conventions
- Module requires: uses relative require paths like `require("script/utils")` and `require("data/tf_util/tf_util")` — maintain this layout.
- Event modules export a `lib` table and list events in `lib.events` keyed by `defines.events` or custom shortcut names. Do not mutate the event handler registration pattern.
- Use `data:extend` only in data-stage files and avoid runtime require of data-only code.
- Settings keys to be aware of: `construction-drone-search-radius`, `throttling`, `force-player-position-search`, `remote-view-spawn` (referenced in [script/event_processor.lua](script/event_processor.lua#L1-L40) and [script/drone_manager.lua](script/drone_manager.lua#L1-L40)).

Build / run / debug
- Packaging / deployment: project contains `deploy.ps1` in the repo root. Run the script on Windows PowerShell to build/deploy the mod: `./deploy.ps1`.

Patterns & examples agents should follow
- When adding new event handlers, follow the `lib.events` pattern and return `lib` (example: [script/event_processor.lua](script/event_processor.lua#L300-L330)).
- Use `storage` namespaced entries (e.g., `storage.construction_drone`) for persistent tables to survive saves/loads (see [script/event_processor.lua](script/event_processor.lua#L320-L340)).
- Data/prototype changes belong in `data.lua` or `data/` subfolders and must reference shared names in [shared.lua](shared.lua#L1-L20).
- Prefer small, focused patches. Avoid refactors that touch many unrelated files.

File references for common tasks
- Add new prototype: modify `data.lua` or add a file under `data/units/` and reference names from [shared.lua](shared.lua#L1-L20).
- Add runtime behavior: create a module under `script/` that exports `lib` and `events`, then register it from `control.lua`.
- Debugging: use `remote.add_interface` hooks and logging via the `logs` module used across `script/`.

Agent behavior rules
- Do not add or change licensing headers. Keep modifications minimal and logically scoped.
- Preserve existing public APIs: `storage` keys, remote interface names, and prototype names in `shared.lua`.
- Use the project's require/import conventions and folder layout. Keep data-stage code separated from runtime.
- For information about the Factorio modding API, refer to the official documentation: https://lua-api.factorio.com/latest.
- For information about factorio's existing data, refer to the github repo: https://github.com/wube/factorio-data/blob/master
