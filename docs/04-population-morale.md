# Population, Workers & Morale

## Overview

Population is the human engine of the economy. Without workers, buildings don't produce. Without resources, population loses morale. Without morale, everything slows down.

## Population

- Tracked by `PopulationManager` (autoload singleton)
- Starts at 5 (from Nucleo's `population_capacity`)
- Grows by +1 every 20 seconds (40 s in the first two phases, `early_growth_interval`) IF:
  - `morale >= 30` (`morale_growth_threshold`) — or population is below
    `population_regrow_floor` (5), so a sunk colony always climbs back
  - `population < max_population`
- Never drops below `population_floor` (1): the ruin floor
- Max population = sum of all completed buildings' `population_capacity`

### Housing

| Building | Pop Capacity |
|----------|-------------|
| Nucleo | 5 (built-in) |
| House | 6 per house (9 at level 2, 12 at level 3: `upgrade_capacity_multiplier`) |
| Max houses | 10 (`building_limits`) |
| Theoretical max pop | 5 + 10*6 = 65 at level 1, 5 + 10*12 = 125 with every house at level 3 |

A house only counts while it is joined to the Núcleo by road.

## Workers

- Each production building requires workers (see `workers_required` in BuildingData)
- `used_workers` = sum of all completed buildings' `workers_required`
- `free_workers` = `population - used_workers`
- Workers are really assigned: `_recalculate_all()` marks each building with the
  `staffed` meta, first built = first served, and a building without enough workers
  does not produce. Its status badge says "sin trabajadores" (`BuildingStatusBadge` in
  3D, `StatusBadge2D` in 2D)
- Player must balance: more production buildings need more houses
- **Naming (2026-09-28):** the UI calls the people *trabajadores* everywhere. The HUD
  card reads "Trabajadores: 12 de 17" (population of room) and "En su puesto: 8 ·
  libres: 4"; a House "da sitio a 6"

### What takes a building out of the count

`_recalculate_all()` skips a building, which then neither gets workers nor produces,
when:

| Case | Meta | Badge | How it comes back |
|---|---|---|---|
| No road to the Núcleo | `connected = false` | "sin carretera" | Lay a road (a house without road gives no room either) |
| Its deposit was mined out by hand (Sawmill, Gold Mine, Foundry) | `has_vein = false` | "sin veta" | None: place it by another deposit |
| The player took its workers off | `workers_off = true` | "sin trabajadores (retirados)" | PONER TRABAJADORES |
| Under construction | `under_construction` | (the construction label) | It finishes |

**Retirar / poner trabajadores:** every building that uses workers has the button in
its panel (`BuildingInfoPanel._on_toggle_workers()` → `PopulationManager.set_workers_off()`).
The workers become free for other buildings; the flag is saved per building
(`workers_off` in the `buildings` entry).

**Manual mining** holds `GameConfig.mining_workers` (2) workers while it lasts
(`ProcessManager.busy_mining_workers()`), discounted before the buildings are staffed.
It also needs the deposit to touch a road joined to the Núcleo.

**Walking workers:** when a building gets staffed, little figures leave the Núcleo and
walk the road network to it (`scripts/map/WorkerWalkers.gd`, 3D and 2D, plus one every
25 s as a shift change). View only.

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
| Market | 1 |
| Laboratory | 2 |
| HQ | 5 |
| Decorations, roads | 0 |
| Manual mining (while it lasts) | 2 |

Workers for one of each: 2+3+3+4+3+1+1+1+2+5 = 25. For every building at its limit
(5 sawmills, 4 mines, 3 foundries, 2 refineries, 3 barracks, 6 towers, 5 warehouses,
1 market, 1 laboratory, 1 HQ): 10+12+9+8+9+6+5+1+2+5 = 67.

## Consumption

Every 30 seconds (`GameConfig.consumption_interval`; 60 s in the first two phases), each pop unit consumes:
- 1 wood (heating/shelter)
- 1 gold (wages)

### What happens when resources run out:
- Partial payment: spends whatever is available
- `EventBus.consumption_failed` emitted
- Notification posted to activity log
- After `unpaid_grace_ticks` (2) unpaid ticks in a row, **famine**: 1 death per tick
  (`starvation_deaths_per_tick`) and -6 morale (`starvation_morale_penalty`), emitted
  as `population_starved`. A fully paid tick clears the count
- Morale drops **-8 per failed tick**

### What happens when resources are sufficient:
- Morale recovers **+3 per tick** (+ decoration bonus)

## Morale (0-100)

### Starting Value: 75

### How Morale Changes

| Source | Amount | Condition |
|--------|--------|-----------|
| Consumption satisfied | +3/tick | All resources paid |
| Consumption failed | -8/tick (-3 in the first two phases, `early_morale_penalty`) | Any resource missing |
| Decoration bonus | +1/tick per 10 pts | Passive from decoration morale_bonus, from the SURVIVAL phase (first Warehouse) |
| Famine / desertion | -6 / -5 | Unpaid consumption or upkeep past the grace ticks |
| Imperial Storm | -0.25 per severity point per 5 s tick in the ash, x3 in the storm (`storm_morale_per_tick`) | ~12 morale per severity point per storm |
| Combat | +8 on a win, -3 per unit lost (`combat_morale_on_victory`, `combat_morale_per_casualty`) | Morale delta of a fight (`CombatRules`), applied to the base |
| Festival event | +20 | Random event |
| Mining accident | -15 | Random event |
| Plague event | -25 | Random event |
| Bandit raid | -10 | Random event |

### Morale Effects

| Morale | Production Multiplier | Growth |
|--------|----------------------|--------|
| 0 | 0.50x | Stopped |
| 20 | 0.70x | Stopped (danger notification at this threshold) |
| 30 | 0.80x | Starts growing |
| 50 | 1.00x | Normal |
| 75 | 1.10x | Good |
| 100 | 1.20x | Maximum |

Formula (piecewise linear through 0 -> 0.5x, 50 -> 1.0x, 100 -> 1.2x):
`m <= 50: 0.5 + m/50 * 0.5`, `m > 50: 1.0 + (m-50)/50 * 0.2` (`PopulationManager.morale_to_multiplier`).

### Decoration Morale

Decorations provide passive morale recovery. The bonus is calculated as:
```
morale_recovery_per_tick = total_decoration_bonus / 10
```

Example: 3 gardens (5 each) + 1 statue (10) = 25 total bonus = +2 morale/tick extra

## Recalculation

`PopulationManager._recalculate_all()` is called when:
- Building construction completes
- Building is placed (roads included: a new tile can connect others) or demolished
- Building is upgraded
- The player takes workers off or puts them back (`set_workers_off()`)
- Manual mining starts, ends or is cancelled, or a deposit is depleted

It recalculates: `max_population`, `used_workers`, `morale_bonus` from all buildings.

## Save/Load

Saved fields: `population`, `morale` (the `workers_off` flag travels with each building)
On load: calls `_recalculate_all()` to rebuild derived values from buildings.

## Key File

`scripts/services/PopulationManager.gd`
