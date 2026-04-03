# Save/Load System

## Overview

Game state is persisted to a JSON file at `user://save_game.json`. Auto-saves on every significant action. Supports offline progression.

## Save Path

- Godot path: `user://save_game.json`
- Windows: `%APPDATA%/Godot/app_userdata/Tormenta Imperial/save_game.json`

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
    "events_triggered": 3
  },

  "camera": {
    "position": [0, 20, 20],
    "zoom": 1.0
  }
}
```

## Auto-Save Triggers

| Event | Signal |
|-------|--------|
| Building placed | `EventBus.building_placed` |
| Building moved | `EventBus.building_moved` |
| Building renamed | `EventBus.building_renamed` |
| Building demolished | `EventBus.building_demolished` |
| Deposit depleted | `EventBus.deposit_depleted` |

## Load Flow

1. `GameManager._try_start()` called when both BuildingPlacer and MapGenerator register
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

When loading a save, if `elapsed > 2 seconds`:
1. Calculate production cycles for each building: `cycles = elapsed / interval`
2. Award resources proportionally (capped by storage)
3. Show floating text report of earnings
4. Max offline time: 8 hours (`GameConfig.max_offline_seconds = 28800`)

## Clear Save

`GameManager.clear_save()`:
1. Delete save file
2. Reset: GridManager, ResourceManager, ProgressionManager, MarketManager, PopulationManager, RandomEventManager
3. Reload current scene (full fresh start)

## Key File

`scripts/services/GameManager.gd`
