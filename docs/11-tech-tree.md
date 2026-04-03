# Tech Tree

## Overview

3 research branches with 5 tiers each (15 techs total). Researching costs resources and time. Each tech provides a permanent bonus. Only one tech can be researched at a time. Requires HQ to exist (research points come from HQ production ticks).

## Branches

### Industrial (production & efficiency)
| Tier | ID | Name | Cost (G/S/O/W) | Duration | Bonus |
|------|-----|------|----------------|----------|-------|
| 1 | `ind_1` | Basic Efficiency | 150g 80w | 30s | +10% production |
| 2 | `ind_2` | Expanded Storage | 300g 100s | 45s | +200 storage |
| 3 | `ind_3` | Advanced Production | 500g 200s 100w | 60s | +15% production |
| 4 | `ind_4` | Rationing | 800g 300s 100o | 90s | -30% consumption |
| 5 | `ind_5` | Automation | 1200g 500s 200o | 120s | +25% production |

### Military (defense & morale)
| Tier | ID | Name | Cost (G/S/O/W) | Duration | Bonus |
|------|-----|------|----------------|----------|-------|
| 1 | `mil_1` | Discipline | 200g 50s | 30s | +1 morale recovery |
| 2 | `mil_2` | Training | 350g 150s | 45s | +1 morale recovery |
| 3 | `mil_3` | Advanced Tactics | 600g 250s 100w | 60s | +2 morale recovery |
| 4 | `mil_4` | Fortification | 900g 400s 150o | 90s | +2 morale recovery |
| 5 | `mil_5` | Military Supremacy | 1500g 600s 300o | 120s | +3 morale recovery |

### Logistics (market, storage, speed)
| Tier | ID | Name | Cost (G/S/O/W) | Duration | Bonus |
|------|-----|------|----------------|----------|-------|
| 1 | `log_1` | Trade Routes | 120g 60w | 25s | -5% market spread |
| 2 | `log_2` | Depot Network | 250g 120w 50s | 40s | +300 storage |
| 3 | `log_3` | Rapid Construction | 450g 150s 80w | 55s | +15% build speed |
| 4 | `log_4` | Trade Monopoly | 700g 250s 100o | 80s | -8% market spread |
| 5 | `log_5` | Logistics Empire | 1100g 400s 250o | 110s | +500 storage, +20% build speed |

## Prerequisites

Each tech requires the previous tier in its branch:
- `ind_2` requires `ind_1`, `ind_3` requires `ind_2`, etc.
- Tier 1 techs have no prerequisites (can start immediately)

## Bonus Application

Bonuses are applied via runtime modification of GameConfig values:
- `tech_production_bonus` — added to production multiplier in ProductionManager
- `tech_build_speed_bonus` — reduces build time in `get_build_time()`
- `tech_consumption_reduction` — reduces consumption per pop (planned)
- `base_storage_cap` — directly increased
- `market_spread` — directly reduced (min 0.1)
- `morale_satisfied_recovery` — increased morale recovery rate

## UI

TechTreePanel shows 3 columns (one per branch) with 5 tier buttons each:
- Green = researched
- Colored = available for research
- Gray = locked (prerequisites not met or already researching)

Progress bar shown during active research.

## Key Files

- `scripts/services/TechTreeManager.gd` — research logic, bonus application, save/load
- `scripts/services/GameConfig.gd` — `tech_definitions` array, `tech_*_bonus` runtime vars
- `scripts/ui/TechTreePanel.gd` — UI with branch columns
