# Economy System

## Overview

The economy is era-gated: resources unlock progressively as the player advances. Gold is the universal currency. All balance lives in `GameConfig.gd`.

## 4 Resources

| Resource | Key | Role | Starting | Unlock |
|----------|-----|------|----------|--------|
| Gold | `gold` | Currency, wages, trading | 300 | Era 1 (always) |
| Wood | `wood` | Basic construction, heating | 200 | Era 1 (always) |
| Steel | `steel` | Advanced construction | 0 | Era 2 (build Foundry) |
| Oil | `oil` | Late-game construction | 0 | Era 3 (build Refinery) |

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
Deposits (finite, by hand)    Buildings (infinite, slow)
  gold_vein -> 20 gold (12s)    Sawmill -> 6 wood/12s
  forest -> 20 wood (8s)        Gold Mine -> 8 gold/12s
  iron_deposit -> 15 steel (18s) Foundry -> 5 steel/15s
  oil_well -> 10 oil (22s)      Refinery -> 4 oil/18s
  (GameConfig.mining_data)      HQ -> 10 gold/20s
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

## Storage

One **shared pool** for all four resources (not a cap per resource):

- Base cap by era: 600 / 800 / 1000 (`base_storage_cap_by_era`)
- Each warehouse: +500 (`warehouse_storage_bonus`), max 5; each level above 1 adds
  +250 more (`warehouse_level_bonus`, `ResourceManager.refresh_warehouse_levels()`)
- Tech: Logistics 2 +300, Industrial 2 +200, Logistics 5 +500 (`tech_storage_bonus`)
- Era 3 with five warehouses: 1000 + 5×500 = **3500**, exactly the HQ level 3 upgrade;
  with the three storage techs (+1000) the ceiling is **4500** (`GameConfig.get_storage_cap()`)
- Sandbox ignores the cap (`sandbox_storage_cap`) and refills resources to `sandbox_resource_floor`
- What does not fit is lost — gold and wood for food included. In era 3 steel and oil
  fill the pool on their own; see `docs/22-linea-jugable.md` §3.1 (A4, A5)

## Where extractors can go

Sawmill, Gold Mine and Foundry must touch a forest, a gold vein and an iron deposit
(reach 1); the Refinery sits on an oil well and consumes it
(`GameConfig.building_deposit_rules`, applied by `PlacementRules`). Like every
building, they also need a road joined to the Núcleo (docs/03 "Road network").

## The random map (2026-09-28)

- **Grid:** each new game rolls its width and height between `grid_size_min` (40) and
  `grid_size_max` (48), even sides, centred on the world origin. Saved in the `grid` key
  with the island seed; a save without it is 40x40.
- **Deposits:** each type (forest, gold vein, iron, oil well) rolls its own count
  between `deposit_per_type_min` (3) and `deposit_per_type_max` (6), so no island comes
  without oil or forest. Sizes from `deposit_sizes` (2-3 cells a side, forests 2-4).
- None lands on the Núcleo or its sidewalk (`deposit_core_gap` = 2 free cells,
  `deposit_center_exclusion` = 6) nor on the outer shore band (`map_shore_band` = 1,
  kept for future sea and shore resources: `MapGenerator.shore_cells()`).
- Every deposit leaves room for its extractor and a free path to the Núcleo's
  sidewalk; a final pass removes and re-rolls any that ended boxed in.
- The island shape (margin, corners, waviness) also comes from the seed, in 3D and 2D.

## Consumption (Population Drain)

Each population unit consumes per tick (30s):
- 1 wood (heating/shelter)
- 1 gold (wages)

If resources run out:
- Morale drops -8 per failed tick
- Partial payment is still deducted

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
- Player has 300g + 200w; roads cost 1 gold per tile and are laid automatically
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
