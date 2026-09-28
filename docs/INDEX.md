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
| 10 | [Signals Reference](10-signals-reference.md) | All 97 EventBus signals with emitters and consumers, plus the 13 that are wired on only one side |
| 11 | [Tech Tree](11-tech-tree.md) | 3 branches x 5 tiers, research mechanics, bonus application |
| 12 | [Cloud Saves](12-cloud-saves.md) | Supabase integration, auth, cloud save/load setup |
| 13 | [Roadmap](13-roadmap.md) | Phased plan: all four milestones shipped, what is left open inside each, and the backlog |
| 14 | [Guía de juego](14-guia-de-juego.md) | Player-facing: what every building does (with renders), expeditions, the Final Audit and the path to victory, and the dev-mode timings |
| 15 | [Combat](15-combat.md) | The combat pillar: pure models, `CombatManager`, the three roads to the board, expeditions, the Final Audit, signals, balance, tests |
| 16 | [Balance de combate](16-balance-combate.md) | Spanish, measured not guessed: the `tools/balance_probe.gd` sweeps, the before/after numbers for every `combat_*` value T046 moved, the rounds→minutes conversion, and what the model cannot fix from `combat_*` alone |
| 17 | [Balance del asedio](17-balance-asedio.md) | La Auditoria Final: por que no se podia ganar, que se cambio y las tablas medidas |
| 18 | [Vista 2D](18-vista-2d.md) | Spanish: the flat top-down world view (`Main2D.tscn`, `scripts/view2d/`), how to switch (Settings, `-- --view=2d`), what is shared with the 3D view, the service hooks, what differs and the known gaps |
| 19 | [Exportar](19-exportar.md) | Spanish: building the Windows .exe (templates, preset, exclusions, `dev_mode` off in exports, Beckett gate, save folder), distributing it (`tools/package_release` zips with LICENSE, third-party notices and a LEEME for testers), the Android APK for tablets (toolchain, preset, signing via env vars, emulator findings, Google Play needs), and what Linux/macOS/Web would need |
| 20 | [Modos de juego](20-modos-de-juego.md) | Spanish: Campaña, Constructor, Supervivencia y Sandbox — the rules table per mode, `GameMode` + `GameConfig.game_mode_rules`, the New Game mode picker, the sealed Survival save, and how to add a mode |
| 21 | [Interfaz y dispositivos](21-interfaz-y-dispositivos.md) | Spanish: device profiles (PC/tablet/phone detection and defaults), canvas scaling without black bars, Settings tabs, HUD show/hide registry, movable panels and the layout editor, colour-blind palettes, high contrast, touch/mouse help texts |
| 22 | [Línea jugable](22-linea-jugable.md) | Spanish: the whole campaign played at real timings by `tools/line_probe.gd` (ten seeds, before/after tables), the dead ends found and fixed, the storm/Tithe pacing changes, the WHAT TO DO? panel (`Objectives.gd`), remaining risks and a human playtest checklist |
| 23 | [Prólogo, tutorial y ayudas](23-onboarding.md) | Spanish: the lore as a Regency dossier (PrologueScreen: back/next/skip, swipe, never behind the title menu), the guided coach-mark tutorial on the real UI (derived steps, resume, skip), and the help callouts (one at a time, ✕ + auto-close, seen list, HelpIndexPanel `help_index`) |

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
- [x] Process save/load (mining/crafting persists)
- [x] Audio (`AudioManager`: runtime buses, signal-driven music + SFX)
- [x] Unit system (infantry, artillery, vehicles) — `ArmyManager`, training, upkeep, desertion
- [x] Building health: storm damage, ruins that stop producing, proportional repair
- [x] The Imperial Storm: four-phase cycle, storm sky, selective damage, the Tithe
- [x] Tactical board (8x8): turn order, move/attack/defend/wait, enemy AI, `BattleScreen`
- [x] The Tithe is fought: garrison + tower crews on the board, or auto-resolved when the board is busy
- [x] The Final Audit: HQ 3 summons a 3-5 wave siege; surviving it is the victory
- [x] Expedition (roguelike run): seeded branching map, drafts, attrition and permadeath, save/resume — models, `CombatManager`, and the `BattleScreen` map / draft / final-report views
- [x] Unit silhouettes on the board (`tools/gen_unit_icons.gd`), with the boss marked and a fallback to the name's initial
- [x] Tutorial: paged intro + one contextual tip per event (`TutorialManager`)

## Partially Implemented

- [~] **Combat after-action reporting** — `defense_auto_resolved` and
  `final_audit_wave_cleared` are emitted but have no listener: a blind Tithe
  defence is summarised by a `StormManager` toast, and a cleared siege wave is
  felt only through the next one opening. See [15-combat.md](15-combat.md) §10
- [~] Cloud saves: `CloudSaveManager` (Supabase REST) implemented but **unwired** —
  nothing calls it; needs `.env` config + settings UI

## What's Planned

- [ ] Turn-based PVP combat (Nakama)
- [ ] Missions/contracts system
- [ ] Ambient audio track (`assets/audio/ambient/` still empty)
