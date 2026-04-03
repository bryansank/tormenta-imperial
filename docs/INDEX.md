# Tormenta Imperial — Documentation Index

Complete technical documentation for AI and developer context.

## Documents

| # | Document | Description |
|---|----------|-------------|
| 01 | [Architecture](01-architecture.md) | Service-Signal-Component pattern, autoload order, scene tree, file structure |
| 02 | [Economy](02-economy.md) | 4 resources, production flow, storage, consumption, balance design |
| 03 | [Buildings](03-buildings.md) | 14 building definitions, costs, workers, limits, prerequisites, upgrade system |
| 04 | [Population & Morale](04-population-morale.md) | Workers, housing, consumption, morale mechanics, decoration bonus |
| 05 | [Market](05-market.md) | Buy/sell system, floating prices, spread, mean reversion, configuration |
| 06 | [Progression & Victory](06-progression-victory.md) | 3 eras, 9 milestones, victory conditions, player flow |
| 07 | [Random Events](07-random-events.md) | 8 event types, probability weights, timed effects |
| 08 | [UI Systems](08-ui-systems.md) | All UI panels, layout, styling, construction pattern |
| 09 | [Save System](09-save-system.md) | JSON save format, auto-save triggers, offline progression, load flow |
| 10 | [Signals Reference](10-signals-reference.md) | Complete EventBus signal table with emitters and consumers |
| 11 | [Tech Tree](11-tech-tree.md) | 3 branches x 5 tiers, research mechanics, bonus application |
| 12 | [Cloud Saves](12-cloud-saves.md) | Supabase integration, auth, cloud save/load setup |

## Quick Reference

- **All balance tuning:** `scripts/services/GameConfig.gd`
- **All translations:** `scripts/services/Tr.gd` (ES + EN)
- **Building data:** `data/buildings/*.tres` (14 files)
- **AI guidance:** `CLAUDE.md` (root)
- **Player-facing:** `readme.md` (root)

## What's Implemented

- [x] Grid-based building placement (25x25)
- [x] 14 buildings (6 production, 2 support, 2 military, 4 decoration)
- [x] 4 resources with era-based unlock
- [x] Passive production + manual processes + mining
- [x] 3-era progression system
- [x] Internal market with floating prices
- [x] Population/worker management
- [x] Morale system with consumption
- [x] 8 random events
- [x] 9 milestones + victory condition
- [x] Save/load with offline progression
- [x] Notification system + activity log
- [x] i18n (Spanish + English)
- [x] Mobile touch controls
- [x] Real worker assignment with visual indicator (unstaffed buildings shown)
- [x] Tech tree (15 techs, 3 branches)
- [x] Cloud saves (Supabase integration)
- [x] Process save/load (mining/crafting persists)

## What's Planned

- [ ] Turn-based PVE combat
- [ ] Turn-based PVP combat (Nakama)
- [ ] Unit system (infantry, artillery, vehicles)
- [ ] Missions/contracts system
- [ ] Audio (music + SFX)
- [ ] Tutorial/onboarding
