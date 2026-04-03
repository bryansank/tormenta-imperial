# Buildings System

## BuildingData Resource

Each building is defined as a `.tres` file in `data/buildings/` using the `BuildingData` class (`scripts/buildings/BuildingData.gd`).

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | String | Unique identifier (matches filename) |
| `display_name` | String | Shown in UI |
| `description` | String | Tooltip text |
| `grid_size` | Vector2i | Cells occupied (e.g., 2x2) |
| `cost_gold/steel/oil/wood` | int | Construction cost |
| `build_time` | float | Seconds to construct (0 = instant) |
| `produces_gold/steel/oil/wood` | int | Passive production per cycle |
| `production_interval` | float | Seconds between production cycles |
| `workers_required` | int | Workers needed to operate |
| `population_capacity` | int | Housing capacity (houses only) |
| `morale_bonus` | int | Passive morale bonus (decorations) |
| `mesh_height` | float | Visual height for procedural mesh |
| `mesh_color` | Color | Visual color |
| `model_scene` | PackedScene | 3D model (optional, nucleo uses one) |
| `max_health` | int | HP (for future combat) |
| `is_core` | bool | Cannot be built/moved/demolished |
| `is_decoration` | bool | No production, no workers, morale only |

## Complete Building List

### Production Buildings

| ID | Name | Size | Cost G/S/O/W | Workers | Build Time | Produces | Interval |
|----|------|------|--------------|---------|------------|----------|----------|
| `nucleo` | Nucleo | 3x3 | Free | 0 | instant | 3 gold | 20s |
| `sawmill` | Aserradero | 2x1 | 80/0/0/50 | 2 | 5s | 6 wood | 12s |
| `gold_mine` | Mina de Oro | 2x2 | 120/0/0/80 | 3 | 8s | 8 gold | 12s |
| `foundry` | Fundicion | 2x1 | 200/0/0/120 | 3 | 12s | 5 steel | 15s |
| `refinery` | Refineria | 2x2 | 300/150/0/100 | 4 | 18s | 4 oil | 18s |
| `headquarters` | Cuartel General | 2x2 | 500/300/200/200 | 5 | 30s | 10 gold | 20s |

### Support Buildings

| ID | Name | Size | Cost G/S/O/W | Workers | Build Time | Special |
|----|------|------|--------------|---------|------------|---------|
| `house` | Vivienda | 1x1 | 50/0/0/30 | 0 | 3s | +6 pop capacity |
| `warehouse` | Deposito | 1x1 | 60/0/0/40 | 1 | 4s | +400 storage cap |

### Military Buildings (combat planned)

| ID | Name | Size | Cost G/S/O/W | Workers | Build Time | Prereqs |
|----|------|------|--------------|---------|------------|---------|
| `barracks` | Cuartel | 2x2 | 250/100/0/80 | 3 | 15s | foundry + sawmill |
| `tower` | Torre | 1x1 | 150/60/20/30 | 1 | 8s | barracks |

### Decorations (morale only)

| ID | Name | Size | Cost G/S/O/W | Build Time | Morale |
|----|------|------|--------------|------------|--------|
| `road` | Camino | 1x1 | 10/0/0/5 | 1s | +2 |
| `garden` | Jardin | 1x1 | 30/0/0/20 | 2s | +5 |
| `fountain` | Fuente | 1x1 | 60/20/0/10 | 4s | +7 |
| `statue` | Estatua | 1x1 | 120/40/0/0 | 6s | +10 |

## Building Limits

Defined in `GameConfig.building_limits`:

| Building | Max |
|----------|-----|
| house | 6 |
| sawmill | 3 |
| gold_mine | 2 |
| foundry | 2 |
| refinery | 1 |
| warehouse | 3 |
| barracks | 2 |
| tower | 4 |
| headquarters | 1 |
| statue | 3 |
| fountain | 3 |
| garden, road | unlimited |

## Prerequisites

Defined in `GameConfig.building_prerequisites`:

| Building | Requires |
|----------|----------|
| foundry | sawmill |
| refinery | foundry |
| barracks | foundry + sawmill |
| tower | barracks |
| headquarters | barracks + refinery |

## Upgrade System

- Max level: 3
- Cost multiplier: L1=1.0x, L2=1.8x, L3=3.0x of base cost
- Production multiplier: L1=1.0x, L2=1.6x, L3=2.5x
- HQ has special override costs (see economy doc)

## Manual Processes

Buildings can run timed manual processes (one at a time per building). Defined in `GameConfig.building_processes`. Margins are ~1.5x to make the market meaningful.

## Construction Flow

1. Player selects building from ConstructionMenu
2. `EventBus.building_selected_for_placement` emitted
3. BuildingPlacer shows green/red preview on grid
4. On click: `ResourceManager.spend_cost()`, `GridManager.place_building()`
5. `EventBus.building_placed` emitted
6. ProductionManager starts construction timer (translucent visual + label)
7. Timer complete: `EventBus.construction_completed` emitted
8. Building starts producing, PopulationManager recalculates workers

## Key Files

- `scripts/buildings/BuildingData.gd` — Resource class definition
- `data/buildings/*.tres` — 14 building data files
- `scripts/services/GameConfig.gd` — limits, prerequisites, processes
- `scripts/services/ProductionManager.gd` — construction + passive production
- `scenes/buildings/BuildingPlacer.tscn` — placement/move/demolish logic
