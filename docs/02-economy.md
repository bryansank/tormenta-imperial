# Economy System

## Overview

The economy is era-gated: resources unlock progressively as the player advances. Gold is the universal currency. All balance lives in `GameConfig.gd`.

## 5 Resources

| Resource | Key | Role | Starting | Unlock |
|----------|-----|------|----------|--------|
| Gold | `gold` | Currency, troop wages, trading | 300 | Era 1 (always) |
| Wood | `wood` | Basic construction | 200 | Era 1 (always) |
| Food | `food` | What people eat (2026-10-04) | 80 | Era 1 (always) |
| Steel | `steel` | Advanced construction | 0 | Era 2 (build Foundry) |
| Oil | `oil` | Late-game construction | 0 | Era 3 (build Refinery) |

**Food (2026-10-04).** `ResourceManager.Type.FOOD`, appended after the materials so no
number moves. It is a **pool** resource (it counts against the shared cap, the Tithe
takes it last) and it is grown at the **Farm** (docs/03). Buy and sell it at the
Market (base price 2, the cheapest: buying food is the immediate fix for hunger). A
save from before food loads with `GameConfig.legacy_save_food` (120) so nobody starves
on load.

## 4 Workshop Materials (2026-09-28)

Appended to `ResourceManager.Type` (`PLANKS, INGOTS, BEAMS, FUEL`), after the four
resources so their numbers do not move. Each specialised building makes one with its
own resource — the **first** process of its list in `GameConfig.building_processes`;
`GameConfig.material_sources` maps material → building.

| Material | Key | Made in | Recipe | Unlocked when |
|---|---|---|---|---|
| Tablones | `planks` | Sawmill | 20 wood → 5 (20 s) | the first Sawmill is finished |
| Lingotes | `ingots` | Gold Mine | 30 gold → 3 (30 s) | the first Gold Mine is finished |
| Vigas | `beams` | Foundry | 20 steel + 10 wood → 4 (30 s) | the first Foundry is finished |
| Combustible | `fuel` | Refinery | 15 oil → 5 (25 s) | the first Refinery is finished |

- **Outside the shared pool:** they live in the Núcleo's workshop (`ResourceManager.is_material()`;
  `get_total_stored()` skips them). The pool is tuned to the exact HQ L3 price, so they
  cannot count against it. The Tithe does not take them either.
- **Who asks for them** (`BuildingData.cost_materials`): Barracks 10 planks, Tower 4
  beams, Refinery 6 beams, Statue 3 ingots, HQ 20 beams + 10 ingots + 10 fuel, and the
  HQ upgrades (`hq_upgrade_costs`: L2 15 beams + 10 ingots + 15 fuel, L3 25 beams + 20
  ingots + 25 fuel).
- The HUD shows them in a **TALLER** row once one is unlocked; ¿QUÉ HACER? turns a
  missing material into a "make" step (`Objectives.make_step_for()`).
- Unlocked by `ProgressionManager._unlock_material_of()` on `construction_completed`.

## Resource Flow

```
Deposits (finite, by hand)    Buildings (infinite, slow) -- wait in the building
  gold_vein -> 20 gold (12s)    Sawmill -> 6 wood/12s
  forest -> 20 wood (8s)        Gold Mine -> 8 gold/12s
  iron_deposit -> 15 steel (18s) Foundry -> 5 steel/15s
  oil_well -> 10 oil (22s)      Refinery -> 4 oil/18s
  (GameConfig.mining_data)      HQ -> 10 gold/20s
                                Farm -> 20 / 125 / 600 food per 1 / 5 / 20 min crop
                                (Nucleo: no passive output, manual processes only)

Manual Processes (active, ~1.5x margin)
  Make planks / ingots / beams / fuel (the materials above)
  Wood Planks (Núcleo): 20 wood -> 35 wood (30s)
  Charcoal: 25 wood -> 12 steel (25s)
  Deep Mining: 10 steel -> 35 gold (35s)
  ...etc (see GameConfig.building_processes)
```

### Mining by hand

Mining a deposit by hand spends one of its uses (`deposit_max_uses`: 7-10) and, since
2026-09-28, **holds `GameConfig.mining_workers` (2) workers while it lasts** and only
works if the deposit **touches a road joined to the Núcleo**
(`ProcessManager.mining_blocker()` → `MINE_NEEDS_ROAD` / `MINE_NEEDS_WORKERS`; the
deposit card says why). Its specialised building produces next to it without using
it up.

A Sawmill, Gold Mine or Foundry whose deposit was mined out by hand **stops**: it
needs its vein alive next to it (`PlacementRules.has_its_deposit()`, badge "sin veta").

## Production that waits to be collected (2026-10-04)

**Every producer keeps what it makes** until the player collects it with one tap on
the building or on the floating icon above it (`StockIcon3D` / `StockIcon2D`, PC and
touch, 3D and 2D; also the RECOGER button in its panel). `ProductionManager` holds the
stock per building (`_stock`), and the cap is `GameConfig.get_stock_cap(id, level)`:
about six minutes of base production, multiplied by the level's production multiplier.

| Building | Holds at level 1 | ≈ minutes of its base output |
|---|---|---|
| Sawmill | 180 wood | 6 |
| Gold Mine | 240 gold | 6 |
| Foundry | 120 steel | 6 |
| Refinery | 80 oil | 6 |
| HQ | 180 gold | 6 |
| Farm | 800 food | one long crop with room for high morale |

- **Full, it stops.** The production clock does not run and the badge says "lleno:
  recógelo" (`BuildingStatusBadge` reason `full`; the smoke goes out).
- **Collecting** puts in the bag what fits (`ResourceManager.fit_into_storage`, split in
  proportion) and **leaves the rest in the building**: nothing is thrown away. This is
  Bryan's "bag full = stop production, do not throw it away". A workshop process whose
  output does not fit leaves the rest in its building too (`keep_in_building`); hand
  mining a deposit still loses what does not fit (a deposit has nowhere to keep it).
- **It goes bad** (`spoil_after_seconds` 7200 = 2 h, `spoil_ratio` 0.5): after 2 h
  uncollected, half is lost and the clock starts again. **Only when
  `GameMode.spoilage_enabled()`** (rule `spoilage`, false in every mode today; the
  Governor mode turns it on). Collecting resets the clock.
- **Offline**, production accumulates in the buildings with their caps (docs/09).
- Signals: `building_stock_changed`, `production_collected`, `stock_spoiled`,
  `crop_planted`. Saved under `stockpiles` (docs/09).

## Storage

One **shared pool** for the five resources (not a cap per resource):

- Base cap by era: 600 / 800 / 1000 (`base_storage_cap_by_era`)
- Each warehouse: +500 (`warehouse_storage_bonus`), max 5; each level above 1 adds
  +250 more (`warehouse_level_bonus`, `ResourceManager.refresh_warehouse_levels()`)
- Tech: Logistics 2 +300, Industrial 2 +200, Logistics 5 +500 (`tech_storage_bonus`)
- Era 3 with five warehouses: 1000 + 5×500 = **3500**, exactly the HQ level 3 upgrade;
  with the three storage techs (+1000) the ceiling is **4500** (`GameConfig.get_storage_cap()`)
- Sandbox ignores the cap (`sandbox_storage_cap`) and refills resources to `sandbox_resource_floor`
- Production no longer overflows: it waits in the buildings and stops when they are
  full. What still overflows (and is lost, with the one-time warning) is what enters
  the bag directly: hand mining, market purchases, loot, refunds, events

## Where extractors can go

Sawmill, Gold Mine and Foundry must touch a forest, a gold vein and an iron deposit
(reach 1); the Refinery sits on an oil well and consumes it
(`GameConfig.building_deposit_rules`, applied by `PlacementRules`). Like every
building, they also need a road joined to the Núcleo (docs/03 "Road network").

## The random map (2026-09-28)

- **Grid:** each new game rolls its width and its height separately between
  `grid_width_min/max` and `grid_height_min/max` (60-74 since the irregular island),
  even sides, centred on the world origin. Saved in the `grid` key with the island
  seed; a save without it is 40x40.
- **Irregular island (2026-10-12):** the sea comes into the grid. The land is a mask
  derived from the island seed (`scripts/map/IslandShape.gd`, pure and static, no
  global RNG): same seed, same island. See "The irregular island" below.
- **Deposits:** each type (forest, gold vein, iron, oil well) rolls its own count
  between `deposit_per_type_min` (3) and `deposit_per_type_max` (6), so no island comes
  without oil or forest. Sizes from `deposit_sizes` (2-3 cells a side, forests 2-4).
- None lands on the Núcleo or its sidewalk (`deposit_core_gap` = 2 free cells,
  `deposit_center_exclusion` = 6) nor on the shore band (`map_shore_band` = 1: the
  land cells within one cell, diagonals included, of the water; on an old square
  island that is the outer ring). It is kept for future sea and shore resources:
  `MapGenerator.shore_cells()`. Deposits are only rolled on land.
- Every deposit leaves room for its extractor and a free path to the Núcleo's
  sidewalk; a final pass removes and re-rolls any that ended boxed in.
- The island shape also comes from the seed, in 3D and 2D.

## The irregular island (2026-10-12)

Owner decision: the map is not a square any more. Bays, capes and peninsulas, with
the water inside the grid, and a different island every game.

**How the coast is made** (`IslandShape.build_mask`, parameters in
`GameConfig.island_coast`):

1. A field per cell: a superellipse (`power_min/max`, 2 = ellipse, 3 = nearly
   square) whose radius changes with the angle (harmonics of 2 to 6 lobes,
   `harmonic_amp`), fractal noise for the small coast (`noise_amp`, `noise_freq`),
   2-4 bays that bite the edge and 1-3 capes that stick out of it. Near the grid's
   sea border the field slopes down, so the coast never flattens against it.
2. The threshold is a quantile: exactly the target number of land cells stays land.
   The target is `fraction_min..max` (0.46-0.58) of the usable grid, clamped to
   `land_min..land_max` (1550-2300 cells; the old square was 1600-2304, all of it
   buildable, so the land is the same size within the ±25 % the owner asked for).
3. Morphological clean-up: a closing (`close_radius` 2.5: inlets narrower than about
   5 cells are filled, where the sand of both shores would overlap) and an opening
   (`open_radius` 1.5: every land cell sits in a 3x3 block of land, so no one-cell
   spits). Only the landmass that touches the Núcleo stays; lakes are filled. One
   island, no holes (no lagoon for now).
4. The Núcleo, its sidewalk and `core_margin` (3) cells around it are always land;
   the outer `edge_water` (3) cells of the grid are always sea.

The mask is about 150-250 ms per game and is never saved: the save keeps width,
height, seed, `"shape": 2` and the `"coast"` parameters used (so retuning
`island_coast` does not move the coast under an old game's buildings). A save
without `"shape"` is the old square island: every cell is land, exactly as before.
Changing the algorithm itself means a new shape version, keeping version 2 as is.

**What respects the water:** `GridManager.is_land_cell()`; `is_cell_free()` and
`can_place()` refuse water, so obstacles, buildings, roads and the auto-road
(`road_route`) never go there. `PlacementRules.evaluate_placement()` answers
`"water"` first (`LBL_ON_WATER`, "Ahí hay agua: construye en tierra."); touch
placement only offers spots on land; both cameras pan within the land's bounding
rectangle (`GridManager.land_world_rect()`); the grid overlay is drawn on land only
(3D: a one-texel-per-cell mask in the shader; 2D: only the cell sides that touch
land, the coast line a little brighter).

**The view:** the grass outline is the mask's contour
(`IslandShape.coast_polygon`): marching squares on the cell corners, two Chaikin
passes, ten relaxation steps that never come closer than 0.2 cells to land, and an
outward-only wobble. Every land cell is fully on grass (a test checks every corner);
grass shows at most about one cell beyond the land. 3D: the outline triangulated
(grass), a cliff skirt, a sand ring and a foam ring grown along its normals, and the
sea shades shallow water from a small distance texture. 2D: the same outline,
grown with `Geometry2D.offset_polygon`. Around a thousand outline points and a few
thousand triangles, built once per game.

**Land check (10 seeds, `tools/isla_check.gd`):** the same map a new game makes
(grid, island, Núcleo with its sidewalk, deposits). "Buildable" is free land after
the Núcleo, its sidewalk and the deposits; "enclosed" are free cells with no walk
to the sidewalk.

| Seed | Grid | Land | Buildable | Gold | Iron | Oil | Forest | Workable | Enclosed | Coast points |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 62x60 | 1609 | 1457 | 3 | 4 | 5 | 6 | yes | 0 | 832 |
| 7 | 66x62 | 1624 | 1440 | 4 | 6 | 4 | 6 | yes | 0 | 880 |
| 42 | 62x68 | 1740 | 1601 | 6 | 4 | 3 | 4 | yes | 0 | 896 |
| 99 | 64x64 | 1802 | 1645 | 5 | 3 | 6 | 3 | yes | 0 | 856 |
| 314 | 62x72 | 2026 | 1868 | 5 | 6 | 5 | 4 | yes | 0 | 968 |
| 2718 | 68x70 | 1968 | 1827 | 4 | 5 | 3 | 5 | yes | 0 | 1024 |
| 4242 | 64x64 | 1841 | 1675 | 6 | 4 | 5 | 6 | yes | 0 | 880 |
| 9001 | 66x66 | 1935 | 1784 | 3 | 5 | 6 | 5 | yes | 0 | 976 |
| 12345 | 68x66 | 1889 | 1770 | 3 | 3 | 4 | 3 | yes | 0 | 880 |
| 55555 | 74x64 | 2093 | 1926 | 5 | 3 | 5 | 6 | yes | 0 | 1072 |

Buildable 1440-1926 cells (mean about 1700). The old square island had 1600-2304
cells minus its deposits, about 1450-2150: the same size, within the ±25 %.

Every island has 3-6 deposits of each type, every one workable (room for its
extractor and a road to the network), and no free cell is cut off from the
Núcleo. The 4-6 h balance line (`tools/line_probe.gd`) is another branch's job.

## Consumption (Population Drain)

Since 2026-10-04 people eat **food**, not wood and gold. Each population unit eats
`GameConfig.food_per_pop` (1) food per tick (30 s; 60 s in the first two phases),
reduced by the consumption tech. Gold is still paid to the troops (army upkeep).

If food runs out:
- Morale drops -8 per failed tick
- Partial payment is still deducted
- After two unpaid ticks people starve (docs/04)

## Production Modifiers

Production output = `base * level_multiplier * morale_multiplier`

| Level | Multiplier |
|-------|-----------|
| 1 | 1.0x |
| 2 | 1.6x |
| 3 | 2.5x |

| Morale | Multiplier |
|--------|-----------|
| 0 | 0.5x |
| 50 | 1.0x |
| 100 | 1.2x |

Formula (piecewise linear, `PopulationManager.morale_to_multiplier`): `0.5 + m/50 * 0.5` up to 50, `1.0 + (m-50)/50 * 0.2` above.

## Economy Balance Design

### Early Game (Era 1)
- Player has 300g + 200w + 80 food; roads cost 1 gold per tile and are laid automatically
- Farm: 40g + 30w, 2 workers, anywhere with a road (the second step of the line)
- House: 50g + 30w (first priority for workers)
- Sawmill: 80g + 50w (wood engine)
- Gold Mine: 120g + 80w (gold engine)
- Market: 100g + 60w (after a Gold Mine); Laboratory: 150g + 100w (after a House)
- Foundry: 200g + 120w (era transition) — only with a Sawmill, a Gold Mine, a House
  and a Warehouse standing

### Mid Game (Era 2)
- Steel enables: Barracks (250g+100s+80w + 10 planks), Refinery (300g+150s+100w + 6
  beams; needs Foundry + Barracks)
- Market becomes important for converting surplus

### Late Game (Era 3)
- Oil enables: Tower (requires oil), HQ (requires all 4)
- HQ L1: 500g+300s+200o+200w + 20 beams, 10 ingots, 10 fuel
- HQ L2: 800g+500s+300o+400w + 15 beams, 10 ingots, 15 fuel
- HQ L3: 1500g+800s+500o+700w + 25 beams, 20 ingots, 25 fuel — summons the Final
  Audit in Campaña and Supervivencia (surviving it is the victory), wins directly in
  Constructor (docs/06, docs/20). The materials are outside the pool, so the 3,500 =
  3,500 invariant still holds

## Key Files

- `scripts/services/ResourceManager.gd` — resource tracking + unlock system
- `scripts/services/GameConfig.gd` — ALL balance values
- `scripts/services/ProductionManager.gd` — passive production + construction
- `scripts/services/ProcessManager.gd` — manual timed processes
- `scripts/services/PopulationManager.gd` — consumption logic
