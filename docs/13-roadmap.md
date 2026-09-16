# Roadmap

Development roadmap for Tormenta Imperial. Ordered by priority and dependency.
Status legend: ✅ done · 🚧 in progress · ⬜ planned · 💤 backlog / nice-to-have

> The management core and the Imperial Storm cycle are both live. The storm is the
> game's clock: everything below is measured against it.
>
> **All four milestones are shipped.** The game can be played from the first sawmill
> to the Final Audit without a gap. What is left is the backlog, the leftovers listed
> under each milestone, and cloud saves — the only 🚧 left in this file.

---

## ✅ Shipped (current build)

The management loop, the tactical board and the storm cycle all run in-game:

- ✅ Grid building placement (25×25), 14 buildings, rotation, move, demolish
- ✅ 4 resources + 3-era unlock, passive production, manual processes, mining
- ✅ Population / workers / morale / consumption
- ✅ Internal market with floating prices
- ✅ 8 random events
- ✅ 9 milestones + Imperial Victory
- ✅ Tech tree (15 techs, 3 branches)
- ✅ Save/load, offline progression
- ✅ **Touch grab-pan parity with mouse**: one finger grabs the terrain with the same
  screen→world formula as the left-drag (`InputService.screen_drag_to_world_delta`),
  a tap under the threshold still selects, and the second finger hands over to the
  pinch without a jump (13 tests)
- ✅ Audio: `AudioManager` (runtime buses, signal-driven) + 4 music tracks + 16 SFX,
  combat included — see the Milestone 3 table for what "combat audio" ships as today
- ✅ **Tactical encounter**: 8×8 board, turn order, move/attack/defend/wait, enemy AI,
  `Encounter` + `CombatAI` as pure headless-testable models — see [15-combat.md](15-combat.md)
- ✅ **The Final Audit**: HQ 3 summons a 3-5 wave siege fought by the garrison with
  attrition across waves; surviving it stops the Storm for good and wins the game
- ✅ **Tutorial**: `TutorialManager` + `TutorialPanel` — paged intro on a new game and
  one contextual tip the first time each thing happens
- ✅ **The Imperial Storm**: four-phase cycle (warning → storm → tithe → aftermath),
  production collapse, morale bleed, severity scaled by industrial footprint
- ✅ **The Tithe is fought, not just paid**: `CombatManager.start_defense()` puts the
  garrison on the board against the Assessors; repel it and they take nothing
- ✅ **Storm HUD on screen**: `StormHUD.gd`, already the phase indicator Milestone 1
  called for — colour and icon per phase, no countdown, severity never announced
- ✅ **Building health**: `BuildingHealth` autoload — storm damage, ruins that stop
  producing, proportional repair, and towers that mitigate only while standing
- 🚧 Cloud saves: `CloudSaveManager` (Supabase REST, auth + save/load) implemented
  but **unwired** — nothing calls it yet; needs `.env` config + settings UI

---

## ✅ Milestone 1 — Economic floor

Tuning on systems that already exist: the biggest change in feel for the least new code.

| Item | Status | Notes |
|------|--------|-------|
| Shared storage pool | ✅ | One cap for the **sum** of all resources, not 800 of each. Era 1 = 600, Era 2 = 800, Era 3 = 1000, +500/warehouse — Era 3 ceiling is exactly the HQ-3 price (3500). Touches `GameConfig.get_storage_cap`, `ResourceManager.add`, `ResourceHUD`, save load |
| **Three-phase storm cycle** | ✅ | `CALM → WARNING → ASH → STORM → TITHE`, plus a `WARNING → CALM` false alarm that banks +1 severity for next time. Calm interval becomes a random range; phase durations stay fixed. Two production multipliers (ash 0.50, storm 0.15) instead of one |
| Phase indicator instead of a clock | ✅ | The storm HUD stops counting down: colour and icon for the current phase, nothing in calm. Severity is no longer announced |
| Queue stays open, the storm ruins it | ✅ | Processes, mining and training can run through all three phases, but anything still in flight when the STORM lands is lost with its cost. Closes the "hide the warehouse in the queue" hole — which also paid a 1.5× margin |
| Corruption tax (cancellation) | ✅ | Explicit cancellation of processes and training, refund 70% in calm and 40% while the storm cycle is active, clamped to the free space in the shared pool so the button never promises more than it can pay |
| Famine & desertion | ✅ | Sustained unpaid consumption kills population; sustained unpaid upkeep deserts units. Both APIs already exist (`remove_population`, `remove_units`) |
| Ruin floor | ✅ | The Nucleo is never damaged or destroyed and population never hits 0 — there is always a thread to rebuild from. No game-over screen |

## ✅ Milestone 2 — The storm bites

| Item | Status | Notes |
|------|--------|-------|
| Building health system | ✅ | `BuildingHealth` autoload: damage, ruined state that halts output, proportional repair cost, ash/blackened overlay, state persisted on the node |
| Repair | ✅ | Costs scale with the damage taken — a scratch is cheap, a ruin nearly costs rebuilding |
| Storm sky | ✅ | `StormSky.gd` — fog, darkening and sky scaled by severity. With severity hidden, this is the player's only read on what is coming |
| Selective damage | ✅ | Priority: defence and morale first, then housing, then production. Never the Nucleo, never the last sawmill or gold mine (anti-softlock) |
| Minimum Quota | ✅ | An empty warehouse no longer means a free tithe: the debt is collected in buildings and workers instead |
| Arms race | ✅ | `StormCycle.storms_survived` already tracked — feed it into `assessor_roster()` so winning today means heavier guns tomorrow |
| Defensive towers | ✅ | Mitigate storm damage (15% each, 60% cap) and field an artillery crew on the defensive board, outside the deploy cap, forming in the back row — only while operational (not ruined, not under construction) |

## ✅ Milestone 3 — Expedition & the double clock

Tasks T022-T029 are specified in `specs/001-combate-pve/tasks.md`.
The screens have landed: the expedition now runs end to end from the UI, not only
from tests.

> ⚠️ [15-combat.md](15-combat.md) §1 and §10 still say there is no expedition UI and
> that four combat signals have no listener. That was true when it was written and is
> not any more — `BattleScreen` and `SkirmishPanel` now drive the whole loop. Trust
> this table and [10-signals-reference.md](10-signals-reference.md) over those two
> sections until they are rewritten.

| Item | Status | Where it lives |
|------|--------|----------------|
| `ExpeditionGenerator` + `Expedition` pure models (boss reachable across many seeds) | ✅ | `scripts/combat/ExpeditionGenerator.gd`, `scripts/combat/Expedition.gd`, `tests/combat/test_expedition_generator.gd`, `tests/combat/test_expedition.gd` |
| `launch_expedition()` and the rest of the service API (`select_node`, `apply_draft`, `abandon_expedition`, `enter_current_node`) | ✅ | `scripts/services/CombatManager.gd`, `tests/combat/test_expedition_wiring.gd` |
| Expedition save/load — seed + cleared nodes, map regenerated, board never saved | ✅ | `Expedition.to_dict/from_dict`, `CombatManager.get_save_data/load_save_data`, `GameManager` |
| Chained encounters with attrition and permadeath | ✅ | `Expedition.build_encounter_units()` hands the board the same `CombatUnit` instances; `CombatManager.enter_current_node()` |
| **Unit lockout**: `get_garrison()` excludes units away on expedition | ✅ | `CombatManager.get_garrison()` / `get_units_on_expedition()` |
| **Defensive auto-resolve**: the *same* `Encounter` headless, AI on both sides, no separate combat maths | ✅ | `scripts/combat/AutoResolver.gd`, `CombatManager.auto_resolve_defense()`, `StormManager._auto_resolve_tithe()`, `tests/combat/test_auto_resolver.gd`, `tests/storm/test_defense_auto_resolve.gd` |
| Storm notifications drawn over `BattleScreen` | ✅ | `NotificationPanel` toast layer vs `BattleScreen.layer`, `tests/storm/test_storm_toasts_over_board.gd` |
| **Real skirmish panel, map view, draft modal** | ✅ | `SkirmishPanel._on_launch_pressed()` calls `CombatManager.launch_expedition(party)`. `BattleScreen` builds three views on top of the board — `_build_map_view()` (node graph, progress, accumulated bonuses, abandon), `_build_draft_panel()` (modal, one card per option, routes to `apply_draft`) and `_build_report_panel()` (the after-action report). Node clicks go through `select_node()`, abandoning through `abandon_expedition()`. `tests/ui/test_expedition_ui.gd` (25 tests) |
| Listeners for the four expedition signals | ✅ | `draft_offered` / `draft_applied` → BattleScreen; `expedition_node_selected` → BattleScreen, SkirmishPanel; `expedition_resumed` → BattleScreen, SkirmishPanel, ArmyPanel (string-form connect). A campaign in flight reopens its map on load |
| Combat audio | ✅ | `AudioManager` plays on `encounter_started`, `unit_attacked`, `unit_died`, `encounter_ended`, `expedition_started`, `expedition_ended`, plus `final_audit_summoned` / `storm_halted_forever` through `_connect_optional()`. `tests/audio/test_audio_combat.gd` (15 tests). **No new audio files shipped**: the 9 combat keys are manifest aliases onto existing SFX and the `combat` music borrows `era_3_petroleum` — see `assets/audio/MANIFEST.md` |
| Helper callout for Escaramuzas | ✅ | `HelperPanel` `SkirmishCallout` — appears once a Barracks exists and the sidebar is open, following the sidebar button. `tests/ui/test_helper_skirmish_callout.gd` (13 tests) |

Still open inside this milestone, none of it blocking:

- **No after-action report for the blind defence.** `defense_auto_resolved` is
  emitted by `CombatManager` and nothing in `scripts/` listens; `StormManager` reads
  the return value of `auto_resolve_defense()` and posts a one-line notification
  (`MSG_DEFENSE_AUTO_WON` / `MSG_DEFENSE_AUTO_LOST`). The expedition's own report
  panel exists; the garrison's does not.
- **`CombatManager.build_enemy_roster()` is still the provisional unseeded roster**
  used by `start_skirmish()`. Its own docstring says `ExpeditionGenerator.enemy_roster()`
  replaces it. Both still exist.
- **Unit glyphs on the board are the first letter** of the translated unit name
  (`BattleScreen._unit_glyph()`) — tracked in the backlog as an art task.

## ✅ Milestone 4 — The Final Audit

| Item | Status | Where it lives |
|------|--------|----------------|
| HQ level 3 summons the siege instead of instantly winning | ✅ | `ProgressionManager._complete_milestone()` → `summon_final_audit()`; `scripts/combat/FinalAudit.gd`, `tests/combat/test_final_audit.gd` |
| 3-5 chained defensive encounters with attrition | ✅ | `final_audit_wave_ready` → `CombatManager._on_final_audit_wave_ready()` → `start_defense(roster, defenders, scale)`; reported back from `end_encounter()` via `ProgressionManager.report_audit_wave()`. `tests/storm/test_final_audit_wiring.gd` |
| Winning emits `storm_halted_forever` and the Storm stops for good | ✅ | `ProgressionManager._publish_audit()`, `StormManager._on_halted_forever()`, `StormSky.restore_now()` |
| Losing sacks the settlement but the siege can be summoned again after rebuilding | ✅ | `StormManager._on_final_audit_lost()` (max-severity Tithe + max storm damage); `FinalAudit.can_resummon()` / `resummon()` with a floor of `final_audit_resummon_min_units` (3); the button lives in `SkirmishPanel._refresh_audit_button()` |

Full technical detail: [15-combat.md](15-combat.md).

## 💤 Backlog — Nice-to-have

- 💤 Ambient audio track (`assets/audio/ambient/` holds only a `.gitkeep`)
- 💤 Dedicated combat audio files (the 9 combat keys are aliases onto existing SFX
  today, and the `combat` theme borrows `era_3_petroleum` — `assets/audio/MANIFEST.md`
  lists what each one should become)
- 💤 Real unit icons on the board (currently the name's initial, `BattleScreen._unit_glyph()`)
- 💤 After-action report for the auto-resolved defence (`defense_auto_resolved` is
  emitted and unlistened — see Milestone 3)
- 💤 Settings home for cloud-save login + wiring `CloudSaveManager`
- 💤 More buildings / decorations & a second island biome
- 💤 Day-night visual layer. Storm weather itself is **done** (`StormSky.gd` scales
  fog, darkening and sky by severity); what is missing is a cycle outside the storm
- 💤 Achievements / statistics
- 💤 Steam / mobile store packaging

---

## Dependency order

```
M1 economy ──────────────┐
    │                    │
    └──▶ 2.1 building ──▶ M2 storm bites
         health           │
                          ├──▶ M3 expedition + double clock
                          └──▶ M4 Final Audit
```

Milestone 1 comes first because it is tuning, not construction. Milestone 4 depends only
on Milestone 2 — the game can be finished without the expedition if time runs short.

## Out of scope

PvP and co-op · meta-progression between expeditions · non-combat expedition nodes ·
enabling cloud saves · store publishing.
