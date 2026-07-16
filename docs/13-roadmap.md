# Roadmap

Development roadmap for Tormenta Imperial. Ordered by priority and dependency.
Status legend: ✅ done · 🚧 in progress · ⬜ planned · 💤 backlog / nice-to-have

> The management/economy core is complete and shippable. Everything below the
> "Shipped" section is future work. Combat is the next major pillar.

---

## ✅ Shipped (current build)

The full management + economy loop is playable end-to-end:

- ✅ Grid building placement (25×25), 14 buildings, rotation, move, demolish
- ✅ 4 resources + 3-era unlock, passive production, manual processes, mining
- ✅ Population / workers / morale / consumption
- ✅ Internal market with floating prices
- ✅ 8 random events
- ✅ 9 milestones + Imperial Victory
- ✅ Tech tree (15 techs, 3 branches)
- ✅ Save/load, offline progression
- 🚧 Cloud saves: `CloudSaveManager` (Supabase REST, auth + save/load) implemented
  but **unwired** — nothing calls it yet; needs `.env` config + settings UI
- ✅ Audio: `AudioManager` (runtime buses, signal-driven) + 4 music tracks + 16 SFX
- ✅ i18n (ES/EN), notifications + activity log, mobile touch controls
- ✅ UI: global theme, hamburger sidebar, left-drag grab-pan, stepped camera rotation
- ✅ **Army as production**: Barracks trains units (cost + time + upkeep), gated by era,
  capacity scales with base, Military Power score — the bridge into combat

---

## 🚧 Milestone A — Polish & Foundations (near-term)

Small, high-value items that harden the current game and prep for combat.

| Item | Status | Notes |
|------|--------|-------|
| Audio: ambient track | ⬜ | Music + SFX done; `assets/audio/ambient/` still empty |
| Tutorial / onboarding | ⬜ | "¿Qué hacer?" panel exists; needs guided first-run flow |
| Touch grab-pan parity | ⬜ | Left-mouse now grabs terrain 1:1; make one-finger touch match |
| Balance pass | 💤 | Tune costs/durations once combat economy is known |
| Settings menu (audio/lang/save) | ⬜ | Central options panel; also the natural home for cloud-save login |
| Wire cloud saves | ⬜ | Call `CloudSaveManager` from settings/save flow + `.env` setup |

## ⬜ Milestone B — Combat Foundation (PVE)

The next major pillar. Turn-based tactical combat on a grid.

- ⬜ Tactical battle grid + turn/initiative system
- ⬜ Unit stats model (HP, attack, defense, move, range)
- ⬜ Actions: move / attack / defend / wait
- ⬜ Enemy AI (target selection, pathfinding)
- ⬜ Battle start/resolution flow + rewards back into the economy
- ⬜ **C# migration** for perf-sensitive parts (unit AI, combat math, pathfinding) — first real C# in the project

## 🚧 Milestone C — Units & Military Buildings

Turns Barracks/Tower from placeholders into a real production chain.

- ✅ Unit production from Barracks (infantry, artillery, vehicles) — `ArmyManager`
- ✅ Army management UI (`ArmyPanel`) with Military Power, capacity, training queue
- ✅ Upkeep economy for units (gold drain per tick)
- ⬜ Unit desertion / morale coupling when upkeep unpaid (currently just a warning)
- ⬜ Army capacity scaling from HQ level (currently barracks-only)
- ⬜ Tower / defensive building behavior
- ⬜ Wire "Commander" / "General" milestones to real military gameplay

## ⬜ Milestone D — Missions & Contracts

- ⬜ Timed delivery / production contracts for rewards
- ⬜ Mission board UI
- ⬜ PVE skirmish missions (uses Milestone B)

## ⬜ Milestone E — Multiplayer (PVP & Co-op)

Depends on combat being solid. Self-hosted Nakama (Docker).

- ⬜ Nakama backend setup (Docker)
- ⬜ Account / auth (extend Supabase auth already used for cloud saves)
- ⬜ Asynchronous PVP: attack another player's base with your army
- ⬜ Co-op play
- ⬜ Base snapshot / defense serialization for async battles

## 💤 Backlog — Nice-to-have

- 💤 More buildings / decorations & a second island biome
- 💤 Weather / day-night visual layer (dieselpunk atmosphere)
- 💤 Achievements / statistics
- 💤 Steam / mobile store packaging

---

## Dependency order

```
Shipped ──▶ A Polish ──▶ B Combat (PVE) ──▶ C Units ──▶ D Missions
                                   └────────────────────▶ E Multiplayer (needs C)
```

Combat (B) is the gate: units, missions, and multiplayer all build on it, and it
introduces C# to the codebase for the first time.
