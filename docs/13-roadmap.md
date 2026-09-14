# Roadmap

Development roadmap for Tormenta Imperial. Ordered by priority and dependency.
Status legend: ✅ done · 🚧 in progress · ⬜ planned · 💤 backlog / nice-to-have

> The management core and the Imperial Storm cycle are both live. The storm is the
> game's clock: everything below is measured against it.

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
- ✅ Audio: `AudioManager` (runtime buses, signal-driven) + 4 music tracks + 16 SFX
- ✅ **Tactical encounter**: 8×8 board, turn order, move/attack/defend/wait, enemy AI,
  `Encounter` + `CombatAI` as pure headless-testable models (59 tests)
- ✅ **The Imperial Storm**: four-phase cycle (warning → storm → tithe → aftermath),
  production collapse, morale bleed, severity scaled by industrial footprint
- ✅ **The Tithe is fought, not just paid**: `CombatManager.start_defense()` puts the
  garrison on the board against the Assessors; repel it and they take nothing
- ✅ **Storm HUD on screen** (about to become a phase indicator — see Milestone 1)
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

## 🚧 Milestone 3 — Expedition & the double clock

Tasks T022-T029 are specified in `specs/001-combate-pve/tasks.md`.

- ✅ `ExpeditionGenerator` + `Expedition` pure models with 59 tests (boss reachable across 200 seeds); wiring to `CombatManager` and UI still pending
- ⬜ `Expedition` model, `launch_expedition()`, real skirmish panel, map view, draft modal
- ⬜ Chained encounters with attrition and permadeath
- ⬜ **Unit lockout**: `get_garrison()` excludes units away on expedition
- ⬜ **Defensive auto-resolve**: run the *same* `Encounter` headless with the AI driving
  both sides — no separate combat maths
- ⬜ Storm notifications drawn over `BattleScreen`

## 🚧 Milestone 4 — The Final Audit

- ✅ HQ level 3 summons the siege instead of instantly winning (`FinalAudit` pure model, 32 tests; resummon floor of 3 units)
- 🚧 3-5 chained defensive encounters with attrition — model done, wiring waves onto the board in progress. **Until it lands the game cannot be finished: HQ 3 summons but nothing begins the siege.**
- 🚧 Winning emits `storm_halted_forever` — `StormManager` listener in progress
- ⬜ Losing sacks the settlement but the siege can be summoned again after rebuilding

## 💤 Backlog — Nice-to-have

- 💤 Tutorial / guided first run
- 💤 Ambient audio track (`assets/audio/ambient/` still empty)
- 💤 Real unit icons on the board (currently the name's initial)
- 💤 Touch grab-pan parity with mouse
- 💤 Settings home for cloud-save login + wiring `CloudSaveManager`
- 💤 More buildings / decorations & a second island biome
- 💤 Weather / day-night visual layer
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
