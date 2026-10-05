# Buildings System

## BuildingData Resource

Each building is defined as a `.tres` file in `data/buildings/` using the `BuildingData` class (`scripts/buildings/BuildingData.gd`).

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | String | Unique identifier (matches filename) |
| `display_name` | String | Fallback name; the UI shows `get_display_name()` (the `BLD_<ID>_NAME` translation) |
| `description` | String | Fallback text; the UI shows `get_description()` (`BLD_<ID>_DESC`) |
| `grid_size` | Vector2i | Cells occupied: 2x2 for everything except the Núcleo (3x3) and the road (1x1) |
| `cost_gold/steel/oil/wood` | int | Construction cost |
| `cost_materials` | Dictionary | Workshop materials it also asks for (`planks`, `ingots`, `beams`, `fuel`) |
| `build_time` | float | Seconds to construct (0 = instant) |
| `produces_gold/steel/oil/wood` | int | Passive production per cycle |
| `production_interval` | float | Seconds between production cycles |
| `workers_required` | int | Workers needed to operate |
| `population_capacity` | int | Housing capacity (houses only) |
| `morale_bonus` | int | Passive morale bonus (decorations) |
| `mesh_height` | float | Visual height for procedural mesh |
| `mesh_color` | Color | Visual color |
| `model_scene` | PackedScene | GLB model (12 of 16 buildings; `nucleo`, `road`, `market` and `laboratory` fall back to `DieselpunkBuildingFactory`) |
| `model_scale` / `model_stretch` | float / Vector3 | Scale a GLB made for 1x1 or 2x1 up to its 2x2 plot; spawn models only through `instantiate_model()` |
| `repeat_placement` | bool | Keep the same building in hand after placing it (decorations and roads do anyway; the rest place one and leave placement mode) |
| `max_health` | int | HP for storm and siege damage (`BuildingHealth`) |
| `is_core` | bool | Cannot be built/moved/demolished |
| `is_decoration` | bool | No production, no workers, morale only |

## Complete Building List

### Production Buildings

| ID | Name | Size | Cost G/S/O/W | Workers | Build Time | Produces | Interval |
|----|------|------|--------------|---------|------------|----------|----------|
| `nucleo` | Núcleo | 3x3 | Free | 0 | instant | — (manual processes, +5 worker room) | — |
| `sawmill` | Aserradero | 2x2 | 80/0/0/50 | 2 | 5s | 6 wood (+ planks by hand) | 12s |
| `gold_mine` | Mina de Oro | 2x2 | 120/0/0/80 | 3 | 8s | 8 gold (+ ingots by hand) | 12s |
| `foundry` | Fundición | 2x2 | 200/0/0/120 | 3 | 12s | 5 steel (+ beams by hand) | 15s |
| `refinery` | Refinería | 2x2 | 300/150/0/100 + 6 beams | 4 | 18s | 4 oil (+ fuel by hand) | 18s |
| `headquarters` | Cuartel General | 2x2 | 500/300/200/200 + 20 beams, 10 ingots, 10 fuel | 5 | 30s | 10 gold | 20s |

Materials (planks, ingots, beams, fuel) are made with the first manual process of
each extractor and live outside the shared pool: see
[02-economy.md](02-economy.md) "4 Workshop Materials".

### Support Buildings

| ID | Name | Size | Cost G/S/O/W | Workers | Build Time | Special |
|----|------|------|--------------|---------|------------|---------|
| `house` | Vivienda | 2x2 | 50/0/0/30 | 0 | 3s | Room for 6 workers (9 / 12 at levels 2 / 3) |
| `warehouse` | Almacén | 2x2 | 60/0/0/40 | 1 | 4s | +500 shared storage cap (+250 per level above 1) |
| `market` | Mercado | 2x2 | 100/0/0/60 | 1 | 6s | Opens the market: ABRIR MERCADO in its panel |
| `laboratory` | Laboratorio | 2x2 | 150/0/0/100 | 2 | 8s | Opens the tech tree: INVESTIGAR in its panel |

**Market and Laboratory (2026-09-28).** Trading and research used to be entries of
☰ MENÚ → COLONIA; now each opens by tapping its building
(`BuildingInfoPanel.SCREENS`), and the button is disabled while the building has no
road. One of each (`building_limits`). ¿QUÉ HACER? asks for the Laboratory before any
research and does not suggest buying or selling without a Market. Both are
procedural (`DieselpunkBuildingFactory`, `BuildingArt2D`): no GLB yet.

### Military Buildings

| ID | Name | Size | Cost G/S/O/W | Workers | Build Time | Prereqs |
|----|------|------|--------------|---------|------------|---------|
| `barracks` | Cuartel | 2x2 | 250/100/0/80 + 10 planks | 3 | 15s | foundry + sawmill |
| `tower` | Torre | 2x2 | 150/60/20/30 + 4 beams | 1 | 8s | barracks |

The Barracks trains units (`ArmyManager`, one training slot per Barracks). Each
operational Tower cuts storm damage by 15% (cap 60%) and puts one artillery crew on
the defensive boards — the Tithe and each Final Audit wave — outside the deploy cap
(max 2). See [15-combat.md](15-combat.md).

### Decorations (morale only)

| ID | Name | Size | Cost G/S/O/W | Build Time | Morale |
|----|------|------|--------------|------------|--------|
| `road` | Carretera | 1x1 | 1/0/0/0 | instant | +2 |
| `garden` | Jardín | 2x2 | 30/0/0/20 | 2s | +5 |
| `fountain` | Fuente | 2x2 | 60/20/0/10 | 4s | +7 |
| `statue` | Estatua | 2x2 | 120/40/0/0 + 3 ingots | 6s | +10 |

The road is still a decoration in data, but it is the backbone of the map: see "Road
network" below.

## Road network (2026-09-28)

- **Everything touches a road joined to the Núcleo.** `PlacementRules.is_connected_spot()`
  is part of `evaluate_placement()` (reason `"road"`, message `LBL_NEEDS_ROAD`). A new
  road must touch the network or the Núcleo. A road whose removal would strand a
  building cannot be demolished or moved (`road_removal_strands()`). With no Núcleo on
  the grid (hand-built test scenes) the rule is off.
- **The Núcleo starts with its sidewalk:** `GameManager.pave_core_ring()` lays the 16
  road cells around it in `_new_game()`.
- **Auto-road:** placing (or moving) a building where the network does not reach is
  accepted when a free route exists; the route comes back as `"route"`, is charged with
  the building (`cost_with_route`, 1 gold per tile) and laid with `pave_route()`. No
  route → `LBL_NEEDS_ROAD`. Roads are instant (`build_time = 0`).
- **No road, no work:** `PopulationManager._recalculate_all()` sets the meta `connected`
  on every building; an unconnected one gets no workers, a house gives no room,
  ProductionManager skips it and its badge says "sin carretera".
- Roads and the Núcleo take no damage (`BuildingHealth.is_immune()`): the Storm and the
  Tithe do not spend themselves on the sidewalk. Roads are drawn as full-cell pavement
  with a curb on the unconnected sides, in 3D and 2D.
- **Workers you can see:** `scripts/map/WorkerWalkers.gd` sends little figures from the
  Núcleo along `PlacementRules.walk_route()` when a building gets staffed, plus one
  every 25 s as a shift change. View only.

## Workers per building

The player can take a building's workers off and put them back (RETIRAR / PONER
TRABAJADORES in its panel, `PopulationManager.set_workers_off()`, saved per building
as `workers_off`): they become free for other buildings and this one stops. A
Sawmill, Gold Mine or Foundry whose deposit was mined out by hand stops too ("sin
veta"). See [04-population-morale.md](04-population-morale.md).

## Status badge reasons

`BuildingStatusBadge.reason_text()` (3D) and `StatusBadge2D` (2D): "en obras", "en
ruinas", "sin trabajadores", "sin trabajadores (retirados)", "sin carretera", "sin
veta". While under construction the label above the building gives the percentage
and the time left ("En obras 61% · faltan 16 s") with a progress bar.

## Building Limits

Defined in `GameConfig.building_limits`:

| Building | Max |
|----------|-----|
| house | 10 |
| sawmill | 5 |
| gold_mine | 4 |
| foundry | 3 |
| refinery | 2 |
| warehouse | 5 |
| market | 1 |
| laboratory | 1 |
| barracks | 3 |
| tower | 6 |
| headquarters | 1 |
| statue | 5 |
| fountain | 5 |
| garden, road | unlimited |

## Deposit Rules

Defined in `GameConfig.building_deposit_rules` and checked by
`scripts/buildings/PlacementRules.gd` (same rule in 3D, 2D and touch placement):

| Building | Must touch | Reach | Consumes it |
|----------|-----------|-------|-------------|
| sawmill | forest | 1 | no |
| gold_mine | gold_vein | 1 | no |
| foundry | iron_deposit | 1 | no |
| refinery | oil_well | 0 (on top) | yes |

The three reach-1 extractors also need their deposit **alive**: if it is mined out by
hand, they stop ("sin veta", `PlacementRules.has_its_deposit()`).

## Prerequisites

Defined in `GameConfig.building_prerequisites`. The Foundry opens era 2 and the
Refinery era 3, so neither goes up without the base of the previous era standing
(2026-09-28):

| Building | Requires |
|----------|----------|
| foundry | sawmill + gold_mine + house + warehouse |
| market | gold_mine |
| laboratory | house |
| refinery | foundry + barracks |
| barracks | foundry + sawmill |
| tower | barracks |
| headquarters | barracks + refinery |

## Upgrade System

- Max level: 3
- Cost multiplier: L1=1.0x, L2=1.8x, L3=3.0x of base cost
- Production multiplier: L1=1.0x, L2=1.6x, L3=2.5x
- House room x1.5 / x2 (6 → 9 → 12, `upgrade_capacity_multiplier`); decoration morale
  x1.5 / x2 (`upgrade_morale_multiplier`); warehouse +250 storage per level above 1
  (`warehouse_level_bonus`)
- **Only what gains something offers an upgrade** (`PlacementRules.upgrade_does_something()`):
  producers, houses, the warehouse, decorations with morale and the HQ (its level 3
  summons the Final Audit). The Barracks, Tower, Road and Núcleo have no upgrade button.
- The panel lists what the next level gives, with real numbers
  (`PlacementRules.upgrade_effect_lines()`); in 3D the building grows and carries a
  II / III plate
- HQ has special override costs, materials included (see economy doc)

## Manual Processes

Buildings can run timed manual processes (one at a time per building). Defined in `GameConfig.building_processes`. Margins are ~1.5x to make the market meaningful.

## Construction Flow

1. Player selects building from ConstructionMenu. Every card shows its cost (red when
   it cannot be paid); a locked card can still be tapped and its detail says
   everything that is missing (resource to unlock, previous buildings, limit, workers,
   cost). The detail's CONSTRUIR button does not start while something is missing
   ("Te falta: 20 Madera")
2. `EventBus.building_selected_for_placement` emitted
3. BuildingPlacer (or `BuildingPlacer2D`) shows a green/red ghost on the grid; on touch, `PlacementAssist` highlights the valid spots, a tap aims and a tap on the ghost / ✓ builds
4. On confirm: `PlacementRules` checks the spot (deposit, footprint, road or auto-road), then `ResourceManager.spend_cost()` (building + route), `GridManager.place_building()`, and `pave_route()` for the road tiles
5. `EventBus.building_placed` emitted. Placement mode ends after one building; only
   decorations, roads and `repeat_placement` buildings stay in hand
   (`PlacementRules.keeps_placing()`)
6. ProductionManager starts construction timer (translucent visual + label)
7. Timer complete: `EventBus.construction_completed` emitted
8. Building starts producing, PopulationManager recalculates workers

## Key Files

- `scripts/buildings/BuildingData.gd` — Resource class definition
- `data/buildings/*.tres` — 16 building data files
- `scripts/buildings/PlacementRules.gd` — placement, road network, auto-road, upgrade effects
- `scripts/map/WorkerWalkers.gd` — the walking workers
- `scripts/services/GameConfig.gd` — limits, prerequisites, processes
- `scripts/services/ProductionManager.gd` — construction + passive production
- `scenes/buildings/BuildingPlacer.tscn` — placement/move/demolish logic
