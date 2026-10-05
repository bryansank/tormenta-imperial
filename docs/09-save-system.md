# Save/Load System

## Overview

Game state is persisted to a JSON file at `user://save_game.json`. Auto-saves on every significant action. Supports offline progression.

## Save Path

- Godot path: `user://save_game.json`
- Windows, from the editor (F5): `%APPDATA%/Godot/app_userdata/Tormenta Imperial/save_game.json`
- Windows, exported `.exe`: `%APPDATA%/TormentaImperial/save_game.json`
  (`application/config/use_custom_user_dir.template` in `project.godot`)
- Android: the app's internal storage
- Tests: `%APPDATA%/TormentaImperial_tests/` — only if they are launched with
  `tools/run_tests.sh` / `.ps1`. Probes and experiments need an `override.cfg` with
  their own `custom_user_dir_name`; see `CLAUDE.md` → "Running the Project"

## Save Structure

```json
{
  "saved_at": 1743552000.0,

  "resources": {
    "gold": 450,
    "steel": 120,
    "oil": 0,
    "wood": 380
  },

  "unlocked_resources": {
    "gold": true,
    "steel": true,
    "oil": false,
    "wood": true
  },

  "buildings": [
    {
      "id": "nucleo",
      "cell_x": 12,
      "cell_y": 12,
      "level": 1,
      "custom_name": "My Base",
      "construction_remaining": 0.0
    }
  ],

  "deposits": [
    {
      "id": "gold_vein",
      "cell_x": 5,
      "cell_y": 8,
      "uses_remaining": 3
    }
  ],

  "progression": {
    "current_era": 2,
    "milestones": {"first_sawmill": true, "era_2": true},
    "trade_count": 5,
    "stats": {"buildings_built": 8, "resources_gathered": 2400, "trades_completed": 5},
    "start_time": 1743550000.0
  },

  "market": {
    "price_mods": {"wood": 1.1, "steel": 0.95, "oil": 1.0}
  },

  "population": {
    "population": 12,
    "morale": 68
  },

  "random_events": {
    "events_triggered": 3,
    "timer": 42.0,
    "next_event_time": 180.0,
    "active_event_id": "plague",
    "active_timer": 23.5
  },

  "camera": {
    "position": [0, 20, 20],
    "zoom": 1.0
  },

  "game_mode": {"mode": "campaign", "result": ""}
}
```

The example shows the older keys. `GameManager._write_save()` also writes
`active_processes` (ProcessManager), `tech_tree`, `army`, `expedition` (CombatManager:
the run in flight, as seed + cleared nodes — never an open board), `storm`
(StormManager: the cycle, the pending Tithe), `tutorial` (prologue, guided step, tips
and helps seen) and, inside `progression`, `played_seconds` and `final_audit`. Buildings
carry their `health`. The same save serves the 3D and the 2D view.

Since 2026-09-28 the save also carries:

- `"format": 2` (`GameManager.SAVE_FORMAT`). A save without it, or older, does not fit
  the map of 2x2 buildings and roads: it is copied to
  `user://save_game.v1-<date>.json` and a new colony starts, with a notice
  (`MSG_SAVE_OLD_FORMAT`). A test that writes a save fixture must add `"format"`.
- `"grid"`: width, height and island seed (`GridManager.get_save_data()`), restored
  **before** anything is placed. A save without it is 40x40.
- per building, `workers_off` when the player took its workers off.
- the four workshop materials, alongside the resources.

`game_mode` (docs/20-modos-de-juego.md) is read **first** on load. A save without
it is a Campaign in progress. `"result": "defeat"` marks a lost Survival run: the
save is kept but sealed (GameManager never writes it again), and Survival skips the
offline progression below.

## Auto-Save Triggers

Immediate writes (`GameManager.save_game()`):

| Event | Source |
|-------|--------|
| Building placed | `EventBus.building_placed` |
| Building moved | `EventBus.building_moved` |
| Building renamed | `EventBus.building_renamed` |
| Building demolished | `EventBus.building_demolished` |
| Deposit depleted | `MapGenerator` calls `GameManager.save_game()` |
| Research finished | `TechTreeManager` calls `GameManager.save_game()` |

Plus, through `GameManager.request_save()` (debounced by `GameConfig.autosave_debounce`),
the signals listed in `GameManager._autosave_triggers()`: trades, training started /
finished / cancelled, desertion, fight results, the Tithe, the Final Audit (summoned,
wave cleared, lost, storm halted, victory), expedition steps (started, node selected,
draft applied, ended), processes and mining, construction and upgrades, and every storm
phase change. On top of that: every `GameConfig.autosave_interval` real seconds (60),
on window close (`NOTIFICATION_WM_CLOSE_REQUEST`) and on pause / focus-out on mobile.

**Fights are never saved.** A checkpoint is written when a board opens, and nothing
is written while `CombatManager.is_save_safe()` is false (a fight in play, or a
siege-wave report not yet closed); the save waits as pending. A sealed Survival save
is never written again (`GameManager._can_write()`).

## Load Flow

1. `GameManager._try_start()` called when both the placer and the map generator register
   (3D or 2D), and it waits for the scene root to be ready, so load signals reach the UI.
   `ViewRouter` can `hold_start()` it while it switches to the other view
2. Check if `save_game.json` exists
3. If yes: parse JSON, restore all systems in order:
   - Resources (amounts)
   - Buildings (placement, level, construction state, names)
   - Warehouse count -> storage cap
   - Deposits (with remaining uses)
   - Progression (era, milestones, stats)
   - Market (price modifiers)
   - Population (pop count, morale)
   - Random events (trigger count)
   - Resource unlock state
   - Camera position
   - Offline progression calculation
4. If no: run `_new_game()` (reset all, place nucleo, generate deposits)

## Offline Progression

When loading a save, if `elapsed > 2 seconds`, `ProductionManager.apply_offline_progression(elapsed)`:
1. Ignores garbage: a negative elapsed (clock rolled back) or NaN pays nothing.
2. Caps the absence at 8 hours (`GameConfig.max_offline_seconds = 28800`). A suspicious
   forward jump (clock pushed ahead, years away) is clamped to the same cap.
3. Finishes constructions/upgrades that would have ended while away; those produce only
   for the leftover time, at their new level.
4. Each building earns `cycles * get_cycle_yield(node, data, false)` — the **same**
   per-cycle function the live tick uses. So a ruined building (`BuildingHealth.is_ruined`)
   or an unstaffed one produces nothing offline either, and level multiplier,
   `tech_production_bonus` and the morale multiplier all apply. Morale is the one at save
   time (it is not simulated).
5. Population consumption is subtracted, capped to what was produced offline (you never
   come back poorer than you left).
6. The result goes through the shared storage cap; the report shows what actually fit.

**Offline is production-only.** The Imperial Storm, random events (the plague), the army
(upkeep, desertion, training), manual processes and the tech research are *frozen* while
the game is closed and resume where they were. Simulating the storm or the army offline
would mean resolving fights and ruining buildings the player never saw and could not react
to; a management game should not punish closing the window. For the same reason the
storm's and the plague's production penalties are not applied to offline earnings: the
events themselves do not advance, so they do not charge either.

An unreadable save is copied to `user://save_game.corrupt-<date>.json` before a new
game replaces it.

## Clear Save

`GameManager.clear_save()`:
1. Delete save file
2. `GameMode.begin_run()` (keeps the chosen mode, drops the result), then `reset()` on
   ResourceManager, ProcessManager, ProgressionManager, MarketManager,
   PopulationManager, RandomEventManager, TechTreeManager, ArmyManager, CombatManager,
   StormManager, TutorialManager, ProductionManager and UIManager; `GridManager.clear_all()`
3. Unpause the tree and reload the current scene (full fresh start)

The same resets run in `_new_game()` and `clear_save_and_reload_from()` (used by the
3D↔2D switch and the cloud path). Any new persistent state must be added to all three —
see `CLAUDE.md` → "Adding Persistent State".

## Key File

`scripts/services/GameManager.gd`
