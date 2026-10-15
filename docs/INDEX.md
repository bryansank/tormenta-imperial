# Tormenta Imperial — Documentation Index

Complete technical documentation for AI and developer context. `CLAUDE.md` (root) is
the operational guide; these are the per-system deep dives. Docs 14 and 16-26 are in
Spanish, the rest in English (some English docs carry newer sections in Spanish).

When a number in a doc disagrees with the code, the code wins: counts of autoloads,
signals, tests and scripts are kept up to date in `CLAUDE.md`.

## Documents

| # | Document | Description |
|---|----------|-------------|
| 01 | [Architecture](01-architecture.md) | Service-Signal-Component pattern, the game autoloads in load order, the two scenes, file structure, how to add a system. Its autoload count predates `DayClock` (27 game autoloads today, see `CLAUDE.md`) |
| 02 | [Economy](02-economy.md) | 5 resources in one shared pool (food included) and 4 workshop materials outside it, production that waits in the buildings and is collected, batches and the Núcleo as every workshop, manual mining, storage caps (3,500 / 4,500 with techs), deposit rules, the random map, the toy deposits, the irregular island (60-74 grid, bays, capes, sea), consumption, balance design |
| 03 | [Buildings](03-buildings.md) | 17 building definitions (all 2x2 but the Núcleo and the road; Farm, Market and Laboratory), the road network and auto-road, costs with materials, workers, limits, prerequisites, deposit rules, upgrades that do something, status badges, construction flow, the look on the map (sites, ruin, activity), lots and props, and the baked "toy diorama" models |
| 04 | [Population & Morale](04-population-morale.md) | Housing, real worker assignment, taking workers off, no road / no vein, workers held by mining, food consumption, famine and the ruin floor, every morale source, life in the streets (walkers, the Storm, the night) |
| 05 | [Market](05-market.md) | Buy/sell with floating prices, spread, mean reversion, configuration; opened from the Market building; the dynamic market of the Gobernador tier |
| 06 | [Progression & Victory](06-progression-victory.md) | 3 eras, 9 milestones, what HQ level 3 does in each mode, victory stats, the governor rank (XP, 18 ranks, rewards) and the player's country (name and flag from pieces), measured player flow |
| 07 | [Random Events](07-random-events.md) | 8 event types, weights, timing (per phase and mode), the timed plague |
| 08 | [UI Systems](08-ui-systems.md) | Every panel and its layer, the single ☰ MENÚ, title menu, war reports, configurable UI, prologue/tutorial/help, styling, less text |
| 09 | [Save System](09-save-system.md) | Up to five saved games in `user://partidas/` with their index, save paths per platform, JSON keys (format 2), autosave triggers, fights never saved, load flow, silent offline progression, resets, the sealed Survival game |
| 10 | [Signals Reference](10-signals-reference.md) | Every EventBus signal with emitters and consumers, plus the ones wired on only one side. Its header count predates the last branches (121 signals today) |
| 11 | [Tech Tree](11-tech-tree.md) | 3 branches x 5 tiers, costs, research mechanics, bonus application; opened from the Laboratory |
| 12 | [Cloud Saves](12-cloud-saves.md) | Supabase integration (auth, cloud save/load) — implemented, unwired, and why `.env` cannot ship |
| 13 | [Roadmap](13-roadmap.md) | What is shipped (M1-M4, everything around them and the 1.0 round), phase 1 of the loop redesign in progress, other branches landing, open balance decisions, backlog |
| 14 | [Guía de juego](14-guia-de-juego.md) | Player-facing: controls, the island and roads, every building, materials, workers, market, tech, army and combat, the Storm, the path to victory, phases, dev-mode timings. Written before the irregular island and the toy look: some figures (grid size, renders) are older |
| 15 | [Combat](15-combat.md) | The combat pillar: pure models, `CombatManager`, the three roads to the board, the 3D board and its two views (front and board), type advantage, notices held during a fight, expeditions, the auto-resolved defence, the Final Audit, signals, balance, tests, probes, known gaps, sea and air domains |
| 16 | [Balance de combate](16-balance-combate.md) | The `tools/balance_probe.gd` sweeps, the before/after numbers for every `combat_*` value moved in T046, rounds→minutes, what `combat_*` alone cannot fix, the Gobernador tier and the type advantage |
| 17 | [Balance del asedio](17-balance-asedio.md) | The Final Audit: why it could not be won, what changed, win rates per garrison measured with `tools/siege_probe.gd`, Gobernador, the effect of the type advantage |
| 18 | [Vista 2D](18-vista-2d.md) | The flat top-down world view (`Main2D.tscn`, `scripts/view2d/`), how to switch, what is shared with 3D, the service hooks, the baked 2D art and why it has to run on a potato, what differs, known gaps |
| 19 | [Exportar](19-exportar.md) | The Windows .exe (templates, preset, exclusions, `dev_mode` off, Beckett gate, save folder), distributing it (free direct downloads, `tools/package_release.sh` / `.ps1` zips with LICENSE, third-party notices and a LEEME), the Android APK for tablets (toolchain, presets incl. the emulator QA one, signing via env vars, emulator findings, Google Play) and the release checklist |
| 20 | [Modos de juego](20-modos-de-juego.md) | Campaña, Constructor, Supervivencia and Sandbox (only Campaña offered today, the rest set aside), the Colono / Gobernador tiers, rules per mode, `GameMode` + `GameConfig.game_mode_rules`, the New Game picker, the sealed Survival save, how to add a mode |
| 21 | [Interfaz y dispositivos](21-interfaz-y-dispositivos.md) | Device profiles, canvas scaling without black bars, Settings tabs, HUD show/hide, movable panels, colour-blind palettes and contrast, touch/mouse help texts, the single menu, touch play and placement, the FPS cap, light and atmosphere of the 3D map with its qualities, day and night, game speed x1 / x2 and bug reports |
| 22 | [Línea jugable](22-linea-jugable.md) | The whole campaign at real timings (`tools/line_probe.gd`, ten seeds, before/after), dead ends fixed, storm/Tithe pacing, the ¿QUÉ HACER? panel, remaining risks and open decisions, human playtest checklist. Measured before roads, materials, food and the irregular island |
| 23 | [Prólogo, tutorial y ayudas](23-onboarding.md) | The lore in three plain-language folios (`PrologueScreen`), the quick guide (`QuickGuide`, in AYUDA since it no longer opens by itself), the guided coach-mark tutorial on the real UI, the help callouts one at a time, the AYUDA index (`HelpIndexPanel`) |
| 24 | [Paleta](24-paleta.md) | The ten UI colours in `UITheme` (name, hex, use, where not to use them), what is derived from them, categories and tech branches, what stays out of the palette (world, resources, sides) |
| 25 | [Marco legal](25-marco-legal.md) | Venezuelan law that touches the game (the 2009 war-videogame ban, copyright and trademark at SAPI, third-party licences, personal data, selling), the content and communication rules that follow from it, the review checklist and what is pending before publishing |
| 26 | [Rendimiento](26-rendimiento.md) | Performance budget (60 fps mid PC, 30 fps on an old integrated GPU and low-end Android, RAM/VRAM/.exe/APK), the reproducible probe (`tools/perf_probe.gd`: six seeded scenarios, CSV/JSON in `reports/perf/`), the measurements of 2026-10-12 per renderer and quality, the static audit with file:line, the prioritised optimisation list and what is done, the "Mínima" quality, first-launch detection and the FPS cap |

## Quick Reference

- **All balance tuning:** `scripts/services/GameConfig.gd`
- **All translations:** `scripts/services/Tr.gd` (ES + EN)
- **Building data:** `data/buildings/*.tres` (17 files)
- **Baked models:** `assets/models/toy/` (buildings and `units/`), baked by `tools/build_toy_models.gd`
- **Audio sources and licences:** `assets/audio/MANIFEST.md`, `assets/CREDITS.md`, `THIRD-PARTY-NOTICES.md`
- **Tests:** `tools/run_tests.sh` / `tools/run_tests.ps1` only (own user dir)
- **AI guidance:** `CLAUDE.md` (root)
- **Player-facing:** `readme.md` (root) and [14-guia-de-juego.md](14-guia-de-juego.md)
- **Project rules:** `.specify/memory/constitution.md`
- **Combat spec:** `specs/001-combate-pve/`
- **Tablet QA flows:** `qa/maestro/`

## Status

Everything done, what is open and the backlog live in [13-roadmap.md](13-roadmap.md).
In short: version 1.0.0 is being assembled. The game is playable end to end in
Campaña (the only mode the New Game dialog offers; the other three still load), in 3D
and 2D, on PC and on an Android tablet build. In progress: phase 1 of the loop
redesign (visible and shorter skirmishes, teaching the combat, building limits by era,
decorations, the finishing "pop" and the camera). Not implemented: cloud save wiring,
missions/contracts and store distribution. PvP and co-op are out of scope.
