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
- **Naming (2026-09-28):** the UI calls the people *trabajadores* everywhere; a House
  "da sitio a 6". **HUD (2026-10):** a worker icon in the resource row shows the
  *free* workers (warning colour when a building is left without them); inhabitants,
  room, working and withdrawn are in its tooltip. Morale is a heart icon in the same
  row, only once the Storm is armed (docs/08, ResourceHUD)

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

**Walking workers:** see "Life in the streets" below.

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

Every 30 seconds (`GameConfig.consumption_interval`; 60 s in the first two phases), each pop unit eats
**1 food** (`GameConfig.food_per_pop`; `PopulationManager.food_due()`), reduced by the
consumption tech. Until 2026-10-04 it was 1 wood + 1 gold; now wood and gold are not
eaten (gold still pays the troops). Food comes from the Farm (docs/03) and the Market.

### What happens when food runs out:
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

## Life in the streets (view only)

`scripts/map/WorkerWalkers.gd` (2026-10-04) puts the population on the roads. It
only **reads** PopulationManager and the buildings' metas; it decides nothing,
emits nothing and saves nothing (`tests/map/test_city_life.gd`).

**Who walks**

- **Workers.** Each one lives in a house and works in a building whose `staffed`
  meta is true. They leave home through its door, walk the road network to the
  work building's door, shrink into it, stay `life_stay_work` seconds, come out and
  walk home, stay `life_stay_home` and go again. A building that is not staffed —
  workers withdrawn, "sin carretera", vein gone, not enough people — gets nobody;
  when it loses its staff, the figures inside vanish and the ones on the way turn
  back home.
- **Citizens** (people not working). They leave home and either stop in front of a
  fountain, garden or statue (`life_pause_decoration`), go into the Market
  (`life_stay_market`), or stroll to a random road cell and back. Three
  silhouettes: man (hat), woman (skirt and bun), child (smaller, cap); workers wear
  a helmet and carry a toolbox. Each figure gets its own colours from a small
  palette per silhouette (all of it from the toy palette, `ToyTones`), and a
  skin tone. Toy-figurine proportions in 3D (2026-10-12): big head, short stout
  body, a block for the legs and an oversized hat or helmet.
- **How many.** One figure per `life_people_per_figure` (2) people: workers count
  the used workers, citizens the rest. Capped per device profile,
  `life_figure_cap` = PC 72 / tablet 44 / phone 26, and on top of it a quality
  cap `life_figure_cap_quality` (-1 = none; the future "Minima" preset will set
  it to `life_figure_cap_minimal`, 12); `WorkerWalkers.figure_cap()` takes the
  lower of the two. When the cap bites, it is split in proportion. Figures inside buildings count against the cap too.
- **Houses** are homes; with no house yet, the Núcleo is.

**Doors.** A building's door is the road cell of the network that its footprint
touches nearest to its centre; the figure enters along the half-cell between the
road and the wall, scaling from 1 to 0.25 (alpha too in 2D). No collisions.

**The Storm.** In the Warning they walk `life_hurry_multiplier` (1.8x) faster. From
the Ash through the Storm and the Tithe everybody out shrinks indoors in 0.6 s
and nobody leaves: the streets are empty. Back to calm, they trickle out over
0.5-8 s. The phase is re-read on `game_load_completed`, so a save made in the Ash
loads with empty streets.

**Night** (2026-10-12, view only). `WorkerWalkers` listens to
`EventBus.day_phase_changed` (DayClock): people go home and only a few stay out,
workers first (lamplighters, watchmen). Production and staffing do not change. A
night weight goes 0 (day) -> 0.5 (dusk, dawn) -> 1 (night) in steps of
`life_night_step` (0.1) every `life_night_step_seconds` (3 s): one reconcile per
step, nothing new per frame, and the extras walk home before vanishing. At full
night the head count is `life_night_presence` (0.3) of the day one and citizens
keep only `life_night_citizen_share` (0.15) of theirs (80 people, 6 workers: about
4 figures). On load the hour applies at once. The Storm wins: sheltered, nobody
goes out, day or night. `set_presence(fraction)` still scales on top. Both views
share it (the logic is in `WorkerWalkers`).

**How it is drawn.** Figures are plain data (`scripts/map/WalkerActor.gd`), moved by
WorkerWalkers and drawn by one node per view: `WalkerFigures3D` keeps one MultiMesh
per silhouette (four draw calls for the whole island; each silhouette is one merged
mesh whose `UV.x` says body / skin / accent, coloured per instance by a tiny shader;
the walk bob and sway go into the instance matrix; no shadows on tablet/phone) and
writes each MultiMesh buffer once per frame. `WalkerFigures2D` draws them all in one
`_draw`. Routes are a BFS over the road network when a figure sets out, cached per
pair of doors; the town is re-read on signals (workers, population, construction,
roads) and every 30 s as a safety net.

**Cost** (measured with `tools/life_probe.gd`, Windows desktop, editor binary — debug
GDScript —, with other Godot instances running on the machine): 72 figures, ~68 of
them in the street, cost ~0.36 ms per frame to move and ~0.33 ms to fill the
buffers (best of 15 batches of 60 frames; medians 0.39 / 0.33 ms), about 10 µs per
figure. Frame time with and without the figures differed by 0.8-2 ms, inside the
noise of the shared machine. A re-read of the town with ~330 buildings (250 of them
roads) costs 3-5 ms and only happens on signals. The phone cap of 26 is about a
third of the per-frame cost. GPU: four instanced draws. Not measured on a real
Android device yet.

**Probe.** `godot --path . -s tools/life_probe.gd -- --no-title --no-dev` with an
`override.cfg` of its own: seeds a town (road grid, 14 houses, workshops, market,
decorations, 80 people) and writes `docs/media/dev/life_probe_3d.png`,
`life_probe_3d_close.png`, `life_probe_3d_ash.png`, `life_probe_3d_stress.png` and
`life_probe_2d.png`, printing head counts and the cost.

Tunables in `GameConfig` ("Vida de la ciudad"): `life_people_per_figure`,
`life_figure_cap`, `life_walk_speed`, `life_hurry_multiplier`, `life_stay_*`,
`life_pause_*`, `life_night_presence`, `life_night_citizen_share`, `life_night_step`,
`life_night_step_seconds`.

### Traffic: trucks on the roads (view only, `feat/decoraciones-y-trafico`, 2026-10-18)

`scripts/map/RoadTraffic.gd` (doc 21 §7, V5) puts a few toy diesel trucks on the
road network, next to the people and built the same way: it only **reads** the
buildings and PopulationManager's metas, decides nothing, emits nothing and saves
nothing (`tests/map/test_road_traffic.gd`). Both placers create it next to
`WorkerWalkers`, on the same `Walkers` layer.

- **Where from, where to.** Sources are finished extractors that are staffed and
  connected (`staffed` / `connected`) and produce something that travels:
  wood, gold, steel, oil or food (`RoadTraffic.cargo_color()`: sawmill, gold
  mine, foundry, refinery, farm, fishing dock, HQ...). Destinations are the
  finished Warehouses (`traffic_depot_ids`) and, with none, the Núcleo; each
  truck goes to the one nearest its extractor. It leaves loaded (the load is the
  resource's colour: logs, brass, steel, black drums, green), drives the shortest
  route to the depot door, goes in to unload (`traffic_stay_unload`), comes back
  empty and goes in to load (`traffic_stay_load`). It keeps to the right-hand lane
  (`traffic_lane_offset`, 0.2 cell) so trucks crossing do not overlap. Purely
  visual: no resource moves.
- **How many.** One truck per `traffic_sources_per_truck` (2) sources, capped per
  device profile, `traffic_truck_cap` = PC 12 / tablet 8 / phone 5, and in the
  **Minimal** quality `traffic_truck_cap_minimal` (0: no trucks at all;
  `RoadTraffic.truck_cap()` reads `GraphicsQuality.is_minimal()` and re-reads it on
  `graphics_quality_changed`). Withdrawn workers, "sin carretera" and vein-less
  buildings get no truck.
- **The Storm.** Warning: `traffic_hurry_multiplier` (1.5x). Ash, Storm and Tithe:
  every truck on the road shrinks indoors in 0.6 s and none leaves until the calm
  (then they trickle out over 1-8 s); re-read on `game_load_completed`. Night does
  not change them.
- **How it is drawn.** Trucks are data (`scripts/map/TruckActor.gd`). 3D:
  `TrafficFigures3D`, ONE MultiMesh with one merged truck mesh (~400 triangles:
  long diesel bonnet, cab, open bed, four fat wheels, exhaust) whose `UV.x` says
  paint / chassis / load / lamp; the cab paint goes in the instance colour, the
  load colour in the custom data, and an empty truck flattens its load into the
  bed in the vertex shader. One draw call for every truck (plus shadows on PC
  only). 2D: `TrafficFigures2D`, six rotated rectangles per truck in one `_draw`,
  no textures, not redrawn while no truck is out.
- **Cost.** One `_process` for all of them, switched off when there are no trucks
  (and on again by a signal). Per frame: a few additions and one matrix per truck
  on the road, and one buffer write. Routes are a BFS over the network when a
  truck sets out, cached per pair of doors; the town is re-read on signals
  (workers, construction, placing or removing) and every 30 s. With the PC cap of
  12 it is about a sixth of the walkers' budget (72 figures). Not measured with
  the probe yet (Bryan's rule: one test pass at the end); `avg_frame_usec` and
  `last_reconcile_usec` are there for `life_probe`.

Tunables in `GameConfig` ("Decoraciones y trafico", at the end of the file):
`traffic_sources_per_truck`, `traffic_truck_cap`, `traffic_truck_cap_minimal`,
`traffic_depot_ids`, `traffic_speed`, `traffic_hurry_multiplier`,
`traffic_lane_offset`, `traffic_stay_load`, `traffic_stay_unload`,
`traffic_truck_paints`.
