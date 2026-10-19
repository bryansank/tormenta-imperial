# Save/Load System

## Overview

Up to **five saved games** (2026-10-12), each one a JSON file in `user://partidas/`, plus
a small index to paint the list. The game being played is the **active** one. Auto-saves
on every significant action. Supports offline progression (silently: no report).

## Save Path

- Folder: `user://partidas/` (`scripts/services/SaveSlots.gd`, static, used with `preload`)
  - `partida_<id>.json` — one game, in the format below
  - `partida_<id>.corrupt-<date>.json` / `partida_<id>.v1-<date>.json` — copies set aside
    from that game (unreadable / old format)
  - `indice.json` — `{"version": 1, "slots": [...]}`, one summary per game
- Active game: `settings.cfg` `[partidas] activa = <id>` (`GameConfig.saves_active_slot`).
  It is a device preference, not game state. **`GameManager.save_path()`** is its file:
  nothing hard-codes a path any more (`GameManager.SAVE_PATH` is gone)
- Windows, from the editor (F5): `%APPDATA%/Godot/app_userdata/Tormenta Imperial/partidas/`
- Windows, exported `.exe`: `%APPDATA%/TormentaImperial/partidas/`
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
  **before** anything is placed. A save without it is 40x40. Since 2026-10-12 it also
  carries `"shape"` (2 = the irregular island) and `"coast"` (the
  `GameConfig.island_coast` parameters the island was made with). The land mask is
  not saved: it is derived from seed, size and those parameters
  (`IslandShape.build_mask`). A `"grid"` without `"shape"` is the old square island
  (all land) and loads as it always did; `SAVE_FORMAT` stays 2.
- per building, `workers_off` when the player took its workers off.
- the four workshop materials, alongside the resources.

Since 2026-10-04:

- `"food"` among the resources. A save without it loads with
  `GameConfig.legacy_save_food` (120) so nobody starves on opening it.
- `"stockpiles"` (`ProductionManager.get_save_data()`): one entry per producer with
  something waiting, a crop or a running clock — `cell_x`, `cell_y` (origin cell),
  `stock` (resource → amount), `age` (seconds uncollected), `crop` (Farm) and `timer`
  (the production clock, so a 20-minute crop does not restart on load). Loading is
  idempotent (it overwrites), an entry whose building is gone is ignored, and a save
  without the key has nothing to collect and default crops. Reset by
  `ProductionManager.reset()`, called from the three new-game paths of GameManager.
- the market's food price (`price_mods.food`); an old market save gets it at 1.0.

`rank` (since 2026-10-04): the governor rank, `{"xp": int, "flag": String, "color": String}`
(`RankManager`). The rank and its bonuses are derived from `xp`, so loading is
idempotent. A save without it is XP 0 = rank 1 with the default flag and colour; a
flag or colour above the saved rank falls back to the default. See
[06-progression-victory.md](06-progression-victory.md) §Governor rank.

`day` (since 2026-10-12): the time of day, `{"hour": float}` (0-1, `DayClock` /
`scripts/storm/DayCycle.gd`). Only the hour is saved: the phase lengths come from
today's `GameConfig.day_cycle_*`, so retuning them does not break old saves. Loading
just sets the hour (idempotent). A save without it starts in full daylight. Reset by
`DayClock.reset()` (a fresh morning, no signal), called from the three new-game paths
of GameManager. Not to be confused with `StormSky.reset()`, which is never called on a
new game (docs/21 §12).

`game_mode` (docs/20-modos-de-juego.md) is read **first** on load. A save without
it is a Campaign in progress. `"result": "defeat"` marks a lost Survival run: the
save is kept but sealed (GameManager never writes it again), and Survival skips the
offline progression below.

## Saved games (partidas)

**The index** holds, per game: `id`, `colony_name`, `flag_spec` (from
`RankManager.get_colony_name()` / `get_flag_spec()` when they exist — the flag-and-country
branch; empty until then, and the list says "Colonia N"), `color`, `mode`, `tier`, `era`,
`played_seconds`, `saved_at`, `sealed` (and `broken` for an unreadable file). It is a
cache: every write of a game updates its line (`SaveSlots.record`), and `SaveSlots.list()`
reconciles it with the files on disk (a file without a line is summarised by reading it,
a line without a file is dropped). Lose the index and it is rebuilt.

**Which game opens** (`GameManager._resolve_active_slot()`, on every start):
1. A `user://save_game.json` from before the slots is **migrated**: copied to the next free
   `partida_<id>.json`, the copy compared byte for byte, and only then the original
   deleted (a failed copy leaves the original untouched). It becomes the active game.
2. `start_new_game()` reserved a fresh id: a new game starts there.
3. The active game, if its file exists ("Continuar" = the last game played).
4. Otherwise the most recent (`saved_at`); with no games at all, a new id and a new game.

**Nueva partida never deletes.** `request_new_game()` opens the mode picker; confirming
calls `start_new_game(mode, tier, identity)`, which saves the current game (with its own
mode, before `GameMode.begin_run`), reserves `SaveSlots.next_id()` and reloads into a new
game. With five games (`is_save_list_full()`), `request_new_game()` opens the list in
`make_room` mode instead: delete one (confirmed) and it goes on to the picker; it never
deletes anything by itself, and `start_new_game()` refuses to make a sixth. An island that
was born by itself (there were no games) and was never built on
(`is_current_disposable()`) is not "a game": the next Nueva partida reuses its slot
(`clear_save()`). The picker has a hook for a name-and-flag step
(`ColonyIdentityPanel.gd`, if it exists: `open("new")`, `confirmed(name, spec)` /
`cancelled`); the choice is applied with `RankManager.set_colony()` right after the resets
of `_new_game()`.

**The list** (`SavesPanel`, `GameManager.open_saves_list()`, layer 40, works paused), from
the title menu ("PARTIDAS n/5") and from ☰ MENÚ → PARTIDA: one row per game, most recent
first — flag, name, EN JUEGO / TERMINADA, then mode · tier · era · played time · date, and
CARGAR / BORRAR. Delete asks in the same row. `load_slot(id)` saves the current game and
reloads with that one (`clear_save_and_reload_from`). `delete_slot(id)` removes file and
line; deleting the game in memory stops all writes to it (`_active_deleted`) and
`leave_deleted_slot()` opens the most recent one left, or a new game.

**Sealed per game.** A lost Survival run seals *its* slot: GameManager never writes that
file again, its line says `sealed`, the list shows it as TERMINADA with CARGAR disabled
(only BORRAR) and the title menu offers no "Continuar" while it is the active one. The
other games are untouched.

**Global, not per game:** the profile that unlocks Gobernador (`profile_runs_finished`,
`profile_campaigns_won` in `settings.cfg`) and every other device preference.

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
2. Resolve the active game (see "Saved games") and check if its file exists
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
   - Offline progression calculation (not after an internal reload)
4. If no: run `_new_game()` (reset all, place nucleo, generate deposits)

## Offline Progression

When loading a save, if `elapsed > 2 seconds`, `ProductionManager.apply_offline_progression(elapsed)`.
**Internal reloads are not an absence** (2026-10-12): the 3D↔2D switch
(`switch_to_scene()`), the language reload (`reload_keeping_game()`) and reopening the game
already in play from the list set `_skip_offline_once`, and that load applies nothing.
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
5. **What is produced waits in the buildings** (2026-10-04), up to each building's cap
   (a full building stops, also offline). Nothing is added to the bag.
6. People eat from the **food grown offline** (in the farms' stock), never from the bag:
   you never come back poorer than you left.
7. If `GameMode.spoilage_enabled()`, what sat uncollected for 2 h loses half per period
   (`ProductionManager.last_offline_spoiled`).
8. **There is no report** (2026-10-12: the "Mientras estuviste fuera" window and its
   `offline_report_closed` / `is_offline_report_open()` are gone, and VictoryScreen no
   longer waits for it). The buildings show on the map what is waiting to be collected.

**Offline is production-only.** The Imperial Storm, random events (the plague), the army
(upkeep, desertion, training), manual processes and the tech research are *frozen* while
the game is closed and resume where they were. Simulating the storm or the army offline
would mean resolving fights and ruining buildings the player never saw and could not react
to; a management game should not punish closing the window. For the same reason the
storm's and the plague's production penalties are not applied to offline earnings: the
events themselves do not advance, so they do not charge either.

The **day clock** is frozen too (2026-10-12): coming back, it is the same hour the
player left. It is visual only, so advancing it would change nothing but the light,
and reopening the game always at a random hour (often at night) would only surprise.
If the night ever gets rules (less production, say), this decision has to be revisited
together with the offline production, which today ignores the time of day.

An unreadable save is copied to `user://partidas/partida_<id>.corrupt-<date>.json` before
a new game replaces it in the same slot (an old-format one to `.v1-<date>.json`).

## Clear Save

`GameManager.clear_save()` discards **only the active game** and starts a new one in its
slot. The UI reaches it only for an untouched fresh island (`start_new_game` reusing it);
tests use it too. Every other path keeps the games:
1. Delete the active game's file and its index line; mark the slot as fresh
2. `GameMode.begin_run()` (keeps the chosen mode, drops the result), then `reset()` on
   ResourceManager, ProcessManager, ProgressionManager, MarketManager,
   PopulationManager, RandomEventManager, TechTreeManager, ArmyManager, CombatManager,
   StormManager, TutorialManager, ProductionManager and UIManager; `GridManager.clear_all()`
3. Unpause the tree and reload the current scene (full fresh start)

The same resets run in `_new_game()` and `clear_save_and_reload_from()` (used by the
3D↔2D switch, the language reload, loading a game from the list, a new game in a new slot
and the cloud path, which writes into the active game). Any new persistent state must be added to all three —
see `CLAUDE.md` → "Adding Persistent State".

## Tests

`tests/save/save_parking.gd` parks the whole `user://partidas/` folder (renamed to
`<backup>.partidas`), the active slot id (`<backup>.activa`) and a legacy
`save_game.json`, restores them afterwards, and still refuses to touch the player's
folders. Suites that write a save use `GameManager.save_path()`. The slots themselves:
`tests/save/test_save_slots.gd` and `tests/save/test_save_slots_game.gd`.

## Key Files

`scripts/services/GameManager.gd`, `scripts/services/SaveSlots.gd`, `scripts/ui/SavesPanel.gd`
