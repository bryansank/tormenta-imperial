# Tormenta Imperial — Documentation Index

Complete technical documentation for AI and developer context. `CLAUDE.md` (root) is
the operational guide; these are the per-system deep dives. Docs 14 and 16-23 are in
Spanish, the rest in English.

## Documents

| # | Document | Description |
|---|----------|-------------|
| 01 | [Architecture](01-architecture.md) | Service-Signal-Component pattern, the 25 game autoloads in load order, the two scenes, file structure, how to add a system |
| 02 | [Economy](02-economy.md) | 4 resources in one shared pool, production flow, storage caps (3,500 / 4,500 with techs), deposit rules, consumption, balance design |
| 03 | [Buildings](03-buildings.md) | 14 building definitions: costs, workers, build times, limits, prerequisites, deposit rules, upgrades, construction flow |
| 04 | [Population & Morale](04-population-morale.md) | Housing, real worker assignment, consumption, famine and the ruin floor, every morale source, decoration bonus |
| 05 | [Market](05-market.md) | Buy/sell with floating prices, spread, mean reversion, configuration |
| 06 | [Progression & Victory](06-progression-victory.md) | 3 eras, 9 milestones, what HQ level 3 does in each mode, victory stats, measured player flow |
| 07 | [Random Events](07-random-events.md) | 8 event types, weights, timing (per phase and mode), the timed plague |
| 08 | [UI Systems](08-ui-systems.md) | Every panel and its layer, the single ☰ MENÚ, title menu, war reports, configurable UI, prologue/tutorial/help, styling |
| 09 | [Save System](09-save-system.md) | Save paths per platform, JSON keys, autosave triggers, fights never saved, load flow, offline progression, resets |
| 10 | [Signals Reference](10-signals-reference.md) | All 107 EventBus signals with emitters and consumers, plus the 9 wired on only one side |
| 11 | [Tech Tree](11-tech-tree.md) | 3 branches x 5 tiers, costs, research mechanics, bonus application |
| 12 | [Cloud Saves](12-cloud-saves.md) | Supabase integration (auth, cloud save/load) — implemented, unwired, and why `.env` cannot ship |
| 13 | [Roadmap](13-roadmap.md) | What is shipped (M1-M4, 2D, modes, UI and devices, touch, onboarding, balance line, exports), open balance decisions, backlog |
| 14 | [Guía de juego](14-guia-de-juego.md) | Player-facing: controls, every building (with renders), market, tech, army and combat, the Storm, the path to victory, phases, dev-mode timings |
| 15 | [Combat](15-combat.md) | The combat pillar: pure models, `CombatManager`, the three roads to the board, expeditions, the auto-resolved defence, the Final Audit, signals, balance, tests, probes, known gaps |
| 16 | [Balance de combate](16-balance-combate.md) | The `tools/balance_probe.gd` sweeps, the before/after numbers for every `combat_*` value moved in T046, rounds→minutes, and what `combat_*` alone cannot fix |
| 17 | [Balance del asedio](17-balance-asedio.md) | The Final Audit: why it could not be won, what changed, win rates per garrison measured with `tools/siege_probe.gd` |
| 18 | [Vista 2D](18-vista-2d.md) | The flat top-down world view (`Main2D.tscn`, `scripts/view2d/`), how to switch, what is shared with 3D, the service hooks, what differs, known gaps |
| 19 | [Exportar](19-exportar.md) | The Windows .exe (templates, preset, exclusions, `dev_mode` off, Beckett gate, save folder, distribution) and the Android APK for tablets (toolchain, presets incl. the emulator QA one, signing via env vars, emulator findings, Google Play) |
| 20 | [Modos de juego](20-modos-de-juego.md) | Campaña, Constructor, Supervivencia and Sandbox: rules per mode, `GameMode` + `GameConfig.game_mode_rules`, the New Game picker, the sealed Survival save, how to add a mode |
| 21 | [Interfaz y dispositivos](21-interfaz-y-dispositivos.md) | Device profiles, canvas scaling without black bars, Settings tabs, HUD show/hide, movable panels, colour-blind palettes and contrast, touch/mouse help texts, the single menu, touch play and placement |
| 22 | [Línea jugable](22-linea-jugable.md) | The whole campaign at real timings (`tools/line_probe.gd`, ten seeds, before/after), dead ends fixed, storm/Tithe pacing, the ¿QUÉ HACER? panel, remaining risks and open decisions, human playtest checklist |
| 23 | [Prólogo, tutorial y ayudas](23-onboarding.md) | The lore as a Regency dossier (`PrologueScreen`), the guided coach-mark tutorial on the real UI, the help callouts one at a time, the AYUDA index (`HelpIndexPanel`) |

## Quick Reference

- **All balance tuning:** `scripts/services/GameConfig.gd`
- **All translations:** `scripts/services/Tr.gd` (ES + EN)
- **Building data:** `data/buildings/*.tres` (14 files)
- **Tests:** `tools/run_tests.sh` / `tools/run_tests.ps1` only (own user dir)
- **AI guidance:** `CLAUDE.md` (root)
- **Player-facing:** `readme.md` (root) and [14-guia-de-juego.md](14-guia-de-juego.md)
- **Project rules:** `.specify/memory/constitution.md`
- **Combat spec:** `specs/001-combate-pve/`
- **Tablet QA flows:** `qa/maestro/`

## Status

Everything done, what is open and the backlog live in [13-roadmap.md](13-roadmap.md).
In short: the game is playable end to end in all four modes, in 3D and 2D, on PC and
on an Android tablet build. Not implemented: cloud save wiring, missions/contracts,
dedicated combat and ambient audio, and store distribution. PvP and co-op are out of
scope.
