# Progression & Victory System

## 3 Eras

| Era | Name | Key | Resources | Triggered By |
|-----|------|-----|-----------|-------------|
| 1 | Frontier | `ERA_FRONTIER` | Gold, Wood | Game start |
| 2 | Industrial | `ERA_INDUSTRIAL` | + Steel | First Foundry constructed |
| 3 | Petroleum | `ERA_PETROLEUM` | + Oil | First Refinery constructed |

### What Happens When Era Advances

1. `ResourceManager.unlock()` called for the new resource
2. `EventBus.resource_unlocked` emitted -> ResourceHUD animates new resource
3. `EventBus.era_advanced` emitted -> ProgressPanel updates, toast notification
4. ConstructionMenu rebuilds -> previously locked buildings become available
5. Deposits of that resource type become mineable
6. Market adds the new resource for trading

## 9 Milestones

| ID | Display Name | Condition | Era |
|----|-------------|-----------|-----|
| `first_sawmill` | Pioneer | Build first Sawmill | 1 |
| `first_gold_mine` | Prospector | Build first Gold Mine | 1 |
| `first_warehouse` | Stockpiler | Build first Warehouse | 1 |
| `era_2` | Industrialist | Build Foundry (triggers Era 2) | 2 |
| `era_3` | Oil Baron | Build Refinery (triggers Era 3) | 3 |
| `market_10_trades` | Merchant | Complete 10 market trades | any |
| `military_ready` | Commander | Have 1 Barracks + 2 Towers | 2-3 |
| `hq_built` | General | Build Headquarters | 3 |
| `hq_max` | **Imperial Victory** | Upgrade HQ to Level 3 | 3 |

### Milestone Detection

- Building milestones: detected in `_on_construction_completed()` by checking `data.id`
- Military milestone: scans all buildings via `GridManager.get_all_buildings()`
- Trade milestone: counts trades via `_on_trade_completed()`
- HQ max: detected in `_on_upgrade_completed()` when level >= `max_building_level`

## Victory

When `hq_max` milestone is completed:
1. `_trigger_victory()` collects stats (time, buildings, trades, milestones)
2. `EventBus.victory_achieved` emitted with stats dict
3. `VictoryScreen` shows full-screen overlay with:
   - "VICTORIA IMPERIAL" title
   - Flavor text
   - Time played, buildings built, trades, milestones count
   - "Keep playing" / "New game" buttons

## Player Flow (~35-45 min real time)

```
Era 1 (Frontier) ~10 min
  Start: 300 gold + 200 wood + Nucleo
  -> Build House (workers!)
  -> Build Sawmill (wood engine)
  -> Build Gold Mine (gold engine)
  -> Build Warehouse (storage pressure)
  -> Mine deposits (forests, gold veins)

Era 2 (Industrial) ~15 min
  -> Build Foundry = STEEL UNLOCKED
  -> Iron deposits now mineable
  -> Build Barracks, Towers
  -> Market: trade surplus for needed resources
  -> Upgrade buildings to L2

Era 3 (Petroleum) ~10 min
  -> Build Refinery = OIL UNLOCKED
  -> Oil wells now mineable
  -> Maximize all production
  -> Upgrade key buildings to L3

Victory Push ~10 min
  -> Build HQ (500g/300s/200o/200w)
  -> Upgrade HQ to L2 (800g/500s/300o/400w)
  -> Upgrade HQ to L3 (1500g/800s/500o/700w)
  -> IMPERIAL VICTORY!
```

## Key Files

- `scripts/services/ProgressionManager.gd` — era tracking, milestones, victory
- `scripts/services/GameConfig.gd` — `era_names`, `milestone_definitions`, `hq_upgrade_costs`
- `scripts/ui/ProgressPanel.gd` — milestone UI with checklist
- `scripts/ui/VictoryScreen.gd` — victory overlay
