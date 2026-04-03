# Population, Workers & Morale

## Overview

Population is the human engine of the economy. Without workers, buildings don't produce. Without resources, population loses morale. Without morale, everything slows down.

## Population

- Tracked by `PopulationManager` (autoload singleton)
- Starts at 5 (from Nucleo's `population_capacity`)
- Grows by +1 every 20 seconds IF:
  - `morale > 30`
  - `population < max_population`
- Max population = sum of all completed buildings' `population_capacity`

### Housing

| Building | Pop Capacity |
|----------|-------------|
| Nucleo | 5 (built-in) |
| House | 6 per house |
| Max houses | 6 |
| Theoretical max pop | 5 + 6*6 = 41 |

## Workers

- Each production building requires workers (see `workers_required` in BuildingData)
- `used_workers` = sum of all completed buildings' `workers_required`
- `free_workers` = `population - used_workers`
- If `free_workers < 0`, some buildings may be starved (future: explicit disable)
- Player must balance: more production buildings need more houses

### Worker Requirements

| Building | Workers |
|----------|---------|
| Nucleo | 0 |
| House | 0 |
| Sawmill | 2 |
| Gold Mine | 3 |
| Foundry | 3 |
| Refinery | 4 |
| Barracks | 3 |
| Tower | 1 |
| Warehouse | 1 |
| HQ | 5 |
| Decorations | 0 |

Total workers needed for "everything": 2+3+3+3+3+4+3+3+1+1+1+1+1+5 = ~34

## Consumption

Every 30 seconds (`_consumption_interval`), each pop unit consumes:
- 1 wood (heating/shelter)
- 1 gold (wages)

### What happens when resources run out:
- Partial payment: spends whatever is available
- `EventBus.consumption_failed` emitted
- Notification posted to activity log
- Morale drops **-8 per failed tick**

### What happens when resources are sufficient:
- Morale recovers **+3 per tick** (+ decoration bonus)

## Morale (0-100)

### Starting Value: 75

### How Morale Changes

| Source | Amount | Condition |
|--------|--------|-----------|
| Consumption satisfied | +3/tick | All resources paid |
| Consumption failed | -8/tick | Any resource missing |
| Decoration bonus | +1/tick per 10 pts | Passive from decoration morale_bonus |
| Festival event | +20 | Random event |
| Mining accident | -15 | Random event |
| Plague event | -25 | Random event |
| Bandit raid | -10 | Random event |

### Morale Effects

| Morale | Production Multiplier | Growth |
|--------|----------------------|--------|
| 0 | 0.50x | Stopped |
| 20 | 0.64x | Stopped (danger notification at this threshold) |
| 30 | 0.71x | Starts growing |
| 50 | 0.85x | Normal |
| 75 | 1.025x | Good |
| 100 | 1.20x | Maximum |

Formula: `multiplier = 0.5 + (morale / 100.0) * 0.7`

### Decoration Morale

Decorations provide passive morale recovery. The bonus is calculated as:
```
morale_recovery_per_tick = total_decoration_bonus / 10
```

Example: 3 gardens (5 each) + 1 statue (10) = 25 total bonus = +2 morale/tick extra

## Recalculation

`PopulationManager._recalculate_all()` is called when:
- Building construction completes
- Building is demolished
- Building is upgraded

It recalculates: `max_population`, `used_workers`, `morale_bonus` from all buildings.

## Save/Load

Saved fields: `population`, `morale`
On load: calls `_recalculate_all()` to rebuild derived values from buildings.

## Key File

`scripts/services/PopulationManager.gd`
