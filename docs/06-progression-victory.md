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
| `hq_max` | Final Audit summoned (`MILE_AUDIT`) | Upgrade HQ to Level 3 — in Campaña and Supervivencia **summons the siege, does not win**; in Constructor it wins | 3 |

### Milestone Detection

- Building milestones: detected in `_on_construction_completed()` by checking `data.id`
- Military milestone: scans all buildings via `GridManager.get_all_buildings()`
- Trade milestone: counts trades via `_on_trade_completed()`
- HQ max: detected in `_on_upgrade_completed()` when level >= `max_building_level`

## Victory

What `hq_max` does depends on the game mode ([20-modos-de-juego.md](20-modos-de-juego.md)):

| Mode | HQ level 3 | Victory |
|------|-----------|---------|
| Campaña | `summon_final_audit()`: 3-5 defensive waves ([15-combat.md](15-combat.md) §6), entered with "QUE BAJEN" | Surviving the last wave. Losing is not a game over: the siege can be resummoned once 3 units stand |
| Supervivencia | Same siege, but only one (`resummon: false`) | Surviving it. Losing it ends the run (`run_ended`) and seals the save |
| Constructor | No siege (`audit_on_capstone: false`) | `_trigger_victory()` right away (`capstone_wins: true`) |
| Sandbox | Nothing (the siege is summoned only from the SANDBOX tab) | None (`victory: false`) |

`_complete_milestone("hq_max")` asks `GameMode.audit_enabled()` first and
`GameMode.capstone_wins()` second. In the siege modes, surviving the last wave emits
`storm_halted_forever` and only then `_trigger_victory()`:

1. Stats: `time_played` (**played seconds**, `ProgressionManager._played_seconds`,
   saved — not wall-clock time since creation), buildings built, trades, milestones,
   `storms_survived`, `tithes_repelled`, `audit_summons`
2. `EventBus.victory_achieved` emitted with the stats dict
3. `VictoryScreen`: title, "the Regency left with nothing" subtitle, the stats, a coda
   line, "Keep playing" / "New game"

"Keep playing" leaves a sandbox: the Storm is halted for good and the WHAT TO DO? panel
(`Objectives.next_step()`) says so.

## Player Flow (measured, real timings)

Measured with `tools/line_probe.gd` on ten seeds — full tables in
`docs/22-linea-jugable.md`. A reasonable player that follows the WHAT TO DO? panel:

```
Era 1 (Frontier)      0 -> 8-10 min    sawmill, gold mine, house, sawmill, warehouse
Era 2 (Industrial)    -> 26-44 min     foundry (the Storm arms), barracks, garrison
                                       (5 units, 2 guns); first storm ~10 min later
Era 3 (Petroleum)     -> 60-128 min    refinery on a well, two towers, HQ
Endgame               -> 123-188 min   HQ L2, six vehicles, storage techs, HQ L3
Final Audit           -> 138-239 min   3-5 waves; median victory 3 h 11 min
```

## Key Files

- `scripts/services/ProgressionManager.gd` — era tracking, milestones, victory
- `scripts/services/GameConfig.gd` — `era_names`, `milestone_definitions`, `hq_upgrade_costs`
- `scripts/ui/ProgressPanel.gd` — milestone UI with checklist
- `scripts/ui/VictoryScreen.gd` — victory overlay
