# Drone Quality Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make drone quality mean "throughput": stats come from a formula on `quality.level` (so any quality mod works), and batch sizes adapt to how many drones are free, with the best drones taking the biggest batches.

**Architecture:** One pure stat function in `shared.lua` used by both the data stage and the runtime. One pure batch planner module (`script/batch_planner.lua`), unit-tested with plain Lua, decides how many targets each drone gets. The runtime reserves a drone quality per batch when the path request is made, and `make_player_drone` spawns that quality.

**Tech Stack:** Factorio 2.1 Lua mod API; Lua 5.4 (`C:\Users\Dakota\AppData\Local\Programs\Lua\bin\lua`) for the pure-function tests.

**Spec:** No separate spec file. The design was agreed in conversation on 2026-11-15 and is summarised under "Design" below.

## Design

- **Stats:** `shared.drone_stats(level)` returns
  - `max_health = math.floor(45 * (1 + 0.3 * level))`
  - `movement_speed = 0.2 * (1 + 0.1 * level)`
  - `inventory_size = 4 + 2 * level`

  A negative or nil level is treated as 0. With vanilla levels (normal 0, uncommon 1, rare 2, epic 3, legendary 5), legendary gets 112 health, speed 0.3 and 14 slots.
- **Adaptive batching:** with `F` free drones and `T` targets, use the best `min(F, T)` free drones. Spread the targets over those drones worst-first, giving each `min(capacity, ceil(remaining / drones_left))`. Targets that no drone can hold stay unclaimed so a later scan picks them up.
- **Drone choice:** a batched request reserves the quality the planner gave it. Unbatched requests (repair, upgrade, large deconstruction) take the **lowest-capacity** free drone, which keeps the best drones for batches. Nothing is random any more.

## Global Constraints

- Prototype names stay as they are: `<quality>-Construction_Drone`, `<quality>-Construction_Drone_spectral`, `<proxy_name>_<quality>`. Existing saves depend on them.
- Skip the `quality-unknown` quality in every loop over qualities.
- Do not commit `deploy.ps1`: it has the user's uncommitted changes. Task 5 edits one line in it and leaves it unstaged.
- Do not bump the version in `info.json`; `deploy.ps1` handles that.
- Pure test files live in `tests/` and run with `lua tests/run.lua` from the repo root.
- Commit messages end with the attribution lines from the session's system reminder.

## Review Focus

1. **A modded quality whose level the old table never knew about** (for example level 4 or 10). The mod must load and give it formula stats. *Task 1 test `stats_for_unlisted_levels`.*
2. **The quality mod is off**, so only `normal` (plus `quality-unknown`) exists. Drones spawn as normal. *Task 1 in-game check; Task 3 `get_drone_counts` reads by item quality, not a hard-coded list.*
3. **One free drone and 30 ghosts.** One batch of up to 4 targets goes out and the other targets are left unclaimed, not lost. *Task 2 test `one_drone_many_targets`; Task 4 unmark step.*
4. **A reserved quality runs out before the path finishes** (the player drops the drone or another request takes it). `make_player_drone` falls back to any free drone instead of failing. *Task 3 in-game check.*
5. **A path request fails, or the player becomes invalid.** The reservation is released, so drones aren't permanently counted as busy. *Task 3: `release_drone` sits beside every `request_count` decrement.*

---

### Task 1: Formula-based stats and data-stage prototypes

**Files:**
- Modify: `shared.lua:5-31` (replace the `drone_quality` table)
- Modify: `data/units/construction_drone/construction_drone.lua:3, 35-38, 133-135, 177-189, 304-321`
- Create: `tests/run.lua`, `tests/test_stats.lua`

**Interfaces:**
- Produces: `shared.drone_stats(level: number|nil) -> { max_health: integer, movement_speed: number, inventory_size: integer }`

- [ ] **Step 1: Write the failing tests**

`tests/run.lua` sets `package.path = "./?.lua;" .. package.path`, runs each `tests/test_*.lua` with `dofile`, prints `PASS <name>` per test, and calls `os.exit(1)` on the first failure. In `tests/test_stats.lua`:

```lua
local shared = require("shared")
local s = shared.drone_stats
-- stats_for_vanilla_levels
assert(s(0).max_health == 45 and s(0).movement_speed == 0.2 and s(0).inventory_size == 4)
assert(s(5).max_health == 112 and math.abs(s(5).movement_speed - 0.3) < 1e-9 and s(5).inventory_size == 14)
-- stats_for_unlisted_levels
assert(s(4).inventory_size == 12 and s(10).inventory_size == 24)
-- stats_clamp_bad_levels
assert(s(nil).inventory_size == 4 and s(-1).inventory_size == 4)
```

- [ ] **Step 2: Run `lua tests/run.lua`.** Expected: FAIL, `attempt to call a nil value (field 'drone_stats')`.

- [ ] **Step 3: Implement `drone_stats` in `shared.lua`** using the Design formulas, and delete `data.drone_quality`.

- [ ] **Step 4: Rewrite the data stage in `construction_drone.lua`**
  - Delete the dead `quality_stats` table (lines 35-38) and the loop that copies it (lines 133-135).
  - Set the base proxy chest's `inventory_size` to `shared.drone_stats(0).inventory_size`.
  - Build the per-quality proxy chests in the existing `data.raw.quality` loop at line 304, using `shared.drone_stats(quality_value.level)`, not a separate loop over `shared.drone_quality`.
  - Units and spectral units take `max_health` and `movement_speed` from the same call.

- [ ] **Step 5: Run `lua tests/run.lua`.** Expected: 3× PASS.

- [ ] **Step 6: Search for remaining uses:** `grep -rn drone_quality --include=*.lua .`. Expected: only `script/command_processor.lua:36`, `:242` and `script/event_processor.lua:98`, which later tasks remove.

- [ ] **Step 7: Check the game loads.** Run `./deploy.ps1 -NoBump -Local -Start`, then start a new game twice: once with the `quality` mod on and once with it off. Expected: no load error, and a legendary drone shows 112 HP in its tooltip.

- [ ] **Step 8: Commit** `shared.lua`, `construction_drone.lua` and `tests/` with the message "Derive drone quality stats from quality level".

---

### Task 2: Pure batch planner

**Files:**
- Create: `script/batch_planner.lua`, `tests/test_batch_planner.lua`

**Interfaces:**
- Produces: `require("script/batch_planner").plan(target_count: integer, free: FreeDrone[]) -> Batch[]`
  - `FreeDrone = { quality: string, count: integer, capacity: integer }`. Any order is accepted.
  - `Batch = { quality: string, size: integer }`, returned in descending capacity. The sum of sizes is ≤ `target_count`. Returns `{}` when there are no free drones or no targets.

- [ ] **Step 1: Write the failing tests**

```lua
local plan = require("script/batch_planner").plan
local function sizes(b) local t = {} for i, x in ipairs(b) do t[i] = x.quality .. ":" .. x.size end return table.concat(t, ",") end
-- more_drones_than_targets: one target each, best drones used
assert(sizes(plan(3, {{quality="normal",count=10,capacity=4},{quality="legendary",count=2,capacity=14}})) == "legendary:1,legendary:1,normal:1")
-- even_spread_within_capacity
assert(sizes(plan(8, {{quality="normal",count=4,capacity=4}})) == "normal:2,normal:2,normal:2,normal:2")
-- best_drones_absorb_overflow
assert(sizes(plan(20, {{quality="normal",count=2,capacity=4},{quality="legendary",count=1,capacity=14}})) == "legendary:12,normal:4,normal:4")
-- one_drone_many_targets
assert(sizes(plan(30, {{quality="normal",count=1,capacity=4}})) == "normal:4")
-- nothing_free
assert(#plan(5, {}) == 0 and #plan(0, {{quality="normal",count=3,capacity=4}}) == 0)
```

- [ ] **Step 2: Run `lua tests/run.lua`.** Expected: FAIL, `module 'script/batch_planner' not found`.

- [ ] **Step 3: Implement `plan`.** Expand the list into individual drones sorted by capacity, best first. Keep the first `min(#drones, target_count)` of them. Then walk that list from worst to best, giving each drone `math.min(capacity, math.ceil(remaining / drones_left))`. Return the batches best first. The file must use no Factorio globals.

- [ ] **Step 4: Run `lua tests/run.lua`.** Expected: all PASS.

- [ ] **Step 5: Commit** with the message "Add adaptive batch planner".

---

### Task 3: Runtime drone accounting and quality reservation

**Files:**
- Modify: `script/drone_manager.lua:4-23` (`make_path_request`), `:25-95` (`make_player_drone`), `:97-108` (`get_quality_drones`)
- Modify: `script/event_processor.lua:95-105` (`get_available_drones`), `:285-320` (path-finished handler)
- Modify: `script/inventory_manager.lua` (add the capacity helper next to `get_drone_stack_capacity`)

**Interfaces:**
- Consumes: `shared.drone_stats` from Task 1, and `FreeDrone` from Task 2.
- Produces:
  - `get_drone_counts(player) -> { [quality_name]: integer }`: counts `shared.units.construction_drone` items with an exact name match across `inventories(player.character)`. Returns `{}` when there is no character.
  - `get_drone_capacity(quality_name: string) -> integer`: `shared.drone_stats(prototypes.quality[quality_name].level).inventory_size`.
  - `get_free_drones(player) -> FreeDrone[]`: counts minus `storage`-backed `data.reserved_drones[player.index][quality]`. The total is then trimmed, starting from the lowest capacity, to `get_available_drones(player) - request_count`, because unbatched requests also hold a drone.
  - `reserve_drone(player_index, quality)` / `release_drone(player_index, quality)`: both do nothing when `quality` is nil, and `data.reserved_drones` is created lazily.
  - `make_player_drone(player, quality_name|nil) -> LuaEntity|nil`
  - `make_path_request` reserves `drone_data.drone_quality` when it is set.

- [ ] **Step 1: Make `get_quality_drones` and `get_available_drones` share `get_drone_counts`.** Delete the `script.active_mods["quality"]` branch and the `unit_data` require in `event_processor.lua`. Replace `string.find(item.name, "Construction_Drone")` with `item.name == shared.units.construction_drone`.

- [ ] **Step 2: Add `get_drone_capacity`, `get_free_drones`, `reserve_drone` and `release_drone`.** In `make_path_request`, call `reserve_drone(index, drone_data.drone_quality)` next to the `request_count` increment. In the path-finished handler, call `release_drone(...)` next to the `request_count` decrement. Also call it before the existing early return for an invalid player at `event_processor.lua:291-295`, which skips the decrement today.

- [ ] **Step 3: Change `make_player_drone(player, quality_name)`.** Use `quality_name` if the player still holds one. Otherwise fall back to the lowest-capacity drone they hold, then remove `math.random`. Pass `drone_data.drone_quality` from the call at `event_processor.lua:315`.

- [ ] **Step 4: Run `lua tests/run.lua`.** Expected: all PASS, nothing broken.

- [ ] **Step 5: In-game check.** Carry 3 normal and 1 legendary drone and place one ghost: the legendary drone goes out. Then carry only 1 legendary, place 2 ghosts far apart, and drop the drone right after the first dispatch: no script error, and the ghost is picked up on a later scan.

- [ ] **Step 6: Commit** with the message "Reserve drone quality per request and pick drones deterministically".

---

### Task 4: Use the planner for construction and deconstruction batches

**Files:**
- Modify: `script/command_processor.lua:35-76` (`check_ghost`) and `:240-261` (small-entity branch of `check_deconstruction`)

**Interfaces:**
- Consumes: `plan` (Task 2) and `get_free_drones` (Task 3). It sets `drone_data.drone_quality = batch.quality` on each dispatched request.

- [ ] **Step 1: Replace the fixed batch loop in `check_ghost`.** Call `plan(#all_targets, get_free_drones(player))`. Walk the batches in order, taking the next `batch.size` distance-sorted targets for each one: the first target is `target` and the rest go in `extra_targets`. Keep `batch_item.count = origCount * batch.size`.

- [ ] **Step 2: Release leftover targets in `check_ghost`.** Set `data.already_targeted[unit_number] = nil` for every target that didn't get a batch.

- [ ] **Step 3: Do the same in `check_deconstruction`.** Leftovers need both `data.already_targeted[idx] = nil` and `data.sent_deconstruction[idx]` decremented. Leave the large-entity `needed` branch on `get_drone_stack_capacity()` (normal size) as it is.

- [ ] **Step 4: Search for remaining uses:** `grep -rn "drone_quality\[" script`. Expected: no matches.

- [ ] **Step 5: In-game check.**
  - 10 normal drones and a 4-belt blueprint: 4 drones go out with 1 belt each.
  - 2 normal and 1 legendary drone and a 6×5 block of belt ghosts (it has to fit inside `check_ghost`'s 5-tile search radius): 3 drones go out (legendary carries 14, normals carry 4 each), and the remaining 8 are built by later trips.
  - Deconstructing a 15-belt line (inside the 8-tile search radius) with 5 drones: 5 drones go out with 3 each.

- [ ] **Step 6: Commit** with the message "Size drone batches by free drones and their quality".

---

### Task 5: Docs and packaging

**Files:**
- Modify: `changelog.txt` (new top entry, same format as 1.1.19, `Version:` left for the deploy bump), `info.json` (`description`), `TODO.txt`, `.github/copilot-instructions.md:22-28`
- Modify, but do not commit: `deploy.ps1:169`

- [ ] **Step 1: Add the changelog entry under "Changes".**
  - Quality stats now scale with the quality level, so modded qualities work.
  - Batch sizes adapt to the number of free drones.
  - Higher-quality drones carry bigger batches and are dispatched first.
  - Legendary speed is now 0.3, down from 1.2.

- [ ] **Step 2: Update the other text.** Remove "Quality drones only work with the default quality values…" from `info.json`. Clear the three finished items in `TODO.txt`. Rewrite the quality section of `copilot-instructions.md` to describe `drone_stats`, `batch_planner` and the reservations.

- [ ] **Step 3: Exclude test and plan files from the zip.** Add `"tests","docs"` to the `-Exclude` list at `deploy.ps1:169`, then run `./deploy.ps1 -NoBump -Local` and confirm the zip contains neither folder. Tell the user this line is changed but not committed.

- [ ] **Step 4: Commit** everything except `deploy.ps1` with the message "Document quality rework".
