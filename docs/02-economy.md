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

## Resource Flow

```
Deposits (finite)           Buildings (infinite, slow)
  gold_vein -> 20 gold        Nucleo -> 3 gold/20s
  forest -> 20 wood           Sawmill -> 6 wood/12s
  iron_deposit -> 15 steel    Gold Mine -> 8 gold/12s
  oil_well -> 10 oil          Foundry -> 5 steel/15s
                              Refinery -> 4 oil/18s
                              HQ -> 10 gold/20s

Manual Processes (active, ~1.5x margin)
  Wood Planks: 20 wood -> 35 wood (30s)
  Charcoal: 25 wood -> 12 steel (25s)
  Deep Mining: 10 steel -> 35 gold (35s)
  ...etc (see GameConfig.building_processes)
```

## Storage

- Base cap: 800
- Each warehouse: +400
- Max warehouses: 3
- Max total storage: 800 + 3*400 = 2000

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

Formula: `0.5 + (morale / 100) * 0.7`

## Economy Balance Design

### Early Game (Era 1)
- Player has 300g + 200w
- House: 50g + 30w (first priority for workers)
- Sawmill: 80g + 50w (wood engine)
- Gold Mine: 120g + 80w (gold engine)
- Foundry: 200g + 120w (era transition)

### Mid Game (Era 2)
- Steel enables: Barracks (250g+100s+80w), Refinery (300g+150s+100w)
- Market becomes important for converting surplus

### Late Game (Era 3)
- Oil enables: Tower (requires oil), HQ (requires all 4)
- HQ L1: 500g+300s+200o+200w
- HQ L2: 800g+500s+300o+400w
- HQ L3: 1500g+800s+500o+700w (VICTORY)

## Key Files

- `scripts/services/ResourceManager.gd` — resource tracking + unlock system
- `scripts/services/GameConfig.gd` — ALL balance values
- `scripts/services/ProductionManager.gd` — passive production + construction
- `scripts/services/ProcessManager.gd` — manual timed processes
- `scripts/services/PopulationManager.gd` — consumption logic
