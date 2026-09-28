# Roadmap

Development roadmap for Tormenta Imperial: what is done, what is still open, and in
which order things were built.
Status legend: ✅ done · 🚧 in progress · ⬜ planned · 💤 backlog / nice-to-have · ❓ open decision

> **The game is playable from the first sawmill to the victory.** All four milestones
> are shipped, and so is everything built around them: the 2D view, four game modes,
> a configurable UI with device profiles, touch play for tablets, the prologue and the
> guided tutorial, a measured balance line, and Windows and Android exports. What is
> left is the backlog below, a handful of open balance decisions, cloud saves and
> distribution.

---

## ✅ Shipped

### Core

- ✅ Grid building placement (**40×40**, the island covers every cell), 14 buildings,
  rotation, move, demolish; extractors must touch their deposit
  (`GameConfig.building_deposit_rules`)
- ✅ 4 resources in one shared pool + 3-era unlock, passive production, manual
  processes, mining
- ✅ Population / workers (really assigned) / morale / consumption, famine and the
  ruin floor
- ✅ Internal market with floating prices
- ✅ 8 random events (from the SURVIVAL phase, per mode)
- ✅ 9 milestones; the capstone summons the Final Audit (Campaña) or wins (Constructor)
- ✅ Tech tree (15 techs, 3 branches; storage techs +1000)
- ✅ Save/load with autosave, fight checkpoints, corrupt-save backup and offline
  progression — [09-save-system.md](09-save-system.md)
- ✅ Audio: `AudioManager` (runtime buses, signal-driven, music on/off) + 4 music
  tracks + 16 SFX
- ✅ i18n ES/EN with a language selector (reload keeping the game)

### Milestones

| Milestone | Status | Doc |
|---|---|---|
| M1 — Economic floor | ✅ | this file, below |
| M2 — The storm bites | ✅ | this file, below |
| M3 — Expedition & the double clock | ✅ | [15-combat.md](15-combat.md) §4 |
| M4 — The Final Audit | ✅ | [15-combat.md](15-combat.md) §6, [17-balance-asedio.md](17-balance-asedio.md) |

### Around the core

| Item | Status | Where it lives |
|---|---|---|
| **2D view**: flat top-down world on the same services, UI and save; switch in Settings or `-- --view=2d` | ✅ | `scenes/main/Main2D.tscn`, `scripts/view2d/`, [18-vista-2d.md](18-vista-2d.md) |
| **Game modes**: Campaña, Constructor, Supervivencia, Sandbox, picked in the New Game dialog and saved with the run | ✅ | `scripts/services/GameMode.gd`, `GameConfig.game_mode_rules`, `NewGameDialog`, `SandboxPanel`, [20-modos-de-juego.md](20-modos-de-juego.md) |
| **Configurable UI and devices**: PC / tablet / phone profiles, UI scale and text size, `aspect=expand`, Settings in tabs, show/hide HUD elements, movable panels per profile, colour-blind palettes, high contrast, panel opacity | ✅ | `DeviceProfile`, `HudRegistry`, `LayoutEditor`, `UITheme.configure()`, [21-interfaz-y-dispositivos.md](21-interfaz-y-dispositivos.md) |
| **One game menu**: ☰ MENÚ (COLONIA + PARTIDA, real pause, ESC / Android back) and the title menu | ✅ | `PauseMenu`, `TitleMenu`, [08-ui-systems.md](08-ui-systems.md) |
| **Tablet / touch**: one-finger grab-pan with the same maths as the mouse, pinch zoom, two-finger twist, tap-to-aim and tap-to-build placement with valid spots, finger-sized controls, hold-to-repeat, help texts per input | ✅ | `InputService`, `PlacementAssist`, `OnScreenControls`, `Tr.ti()`, [21-interfaz-y-dispositivos.md](21-interfaz-y-dispositivos.md) §9 |
| **Onboarding**: the prologue as a Regency dossier, a guided coach-mark tutorial on the real UI, help callouts one at a time, the AYUDA index | ✅ | `PrologueScreen`, `TutorialPanel`, `TutorialManager`, `HelperPanel`, `HelpIndexPanel`, [23-onboarding.md](23-onboarding.md) |
| **War reports**: blind-defence report, Tithe report (COBRADO / REPELIDO), siege banner, lost-siege report | ✅ | `WarReportScreen`, `AuditWaveBanner`, `AuditDefeatScreen` |
| **Balance line**: the whole campaign played at real timings over ten seeds; dead ends fixed; 10/10 won in 2 h 18 min – 4 h (median 3 h 11 min); the ¿QUÉ HACER? panel | ✅ | `tools/line_probe.gd`, `scripts/services/Objectives.gd`, [22-linea-jugable.md](22-linea-jugable.md) |
| **Combat balance** measured, not guessed | ✅ | `tools/balance_probe.gd`, `tools/siege_probe.gd`, [16-balance-combate.md](16-balance-combate.md), [17-balance-asedio.md](17-balance-asedio.md) |
| **Windows export**: one `.exe`, dev bridge gated, no dev files or tokens in the package, own save folder | ✅ | `export_presets.cfg` "Windows Desktop", [19-exportar.md](19-exportar.md) |
| **Release packaging**: zips for testers with the licence, third-party notices and a LEEME | ✅ | `tools/package_release.sh` / `.ps1`, `THIRD-PARTY-NOTICES.md`, `licenses/`, [19-exportar.md](19-exportar.md) §8 |
| **Android export**: debug APK (arm64, landscape, immersive, Mobile renderer, no permissions); an x86_64 OpenGL QA preset for the emulator | ✅ | "Android" and "Android QA (emulador)" presets, [19-exportar.md](19-exportar.md) §11 |
| **Tablet QA flows** on the Android emulator | ✅ | `qa/maestro/` (README inside) |
| **Tests isolated from the player's save** | ✅ | `tools/run_tests.sh` / `.ps1`, `tests/save/save_parking.gd` |

---

## ✅ Milestone 1 — Economic floor

Tuning on systems that already exist: the biggest change in feel for the least new code.

| Item | Status | Notes |
|------|--------|-------|
| Shared storage pool | ✅ | One cap for the **sum** of all resources. Era 1 = 600, Era 2 = 800, Era 3 = 1000, +500/warehouse (max 5) — Era 3 ceiling is exactly the HQ-3 price (3500), 4500 with the storage techs. Touches `GameConfig.get_storage_cap`, `ResourceManager.add`, `ResourceHUD`, save load |
| **Storm cycle** | ✅ | `CALM → WARNING → ASH → STORM → TITHE`, plus a `WARNING → CALM` false alarm that banks +1 severity for next time. Calm interval is a random range; phase durations stay fixed. Two production multipliers (ash 0.50, storm 0.15). The Storm arms with the first Foundry |
| Phase indicator instead of a clock | ✅ | `StormHUD`: colour and icon for the current phase, nothing in calm. Severity is not announced |
| Queue stays open, the storm ruins it | ✅ | Processes, mining and training can run through all phases, but anything still in flight when the STORM lands is lost with its cost |
| Corruption tax (cancellation) | ✅ | Refund 70% in calm and 40% while the storm cycle is active, clamped to the free space in the shared pool |
| Famine & desertion | ✅ | After two grace ticks, unpaid consumption kills population and unpaid upkeep deserts units |
| Ruin floor | ✅ | The Nucleo is never damaged, population never drops below 1 and regrows below 5 regardless of morale — there is always a thread to rebuild from |

## ✅ Milestone 2 — The storm bites

| Item | Status | Notes |
|------|--------|-------|
| Building health system | ✅ | `BuildingHealth` autoload: damage, ruined state that halts output, proportional repair cost, state persisted |
| Repair | ✅ | Costs scale with the damage taken — a scratch is cheap, a ruin nearly costs rebuilding |
| Storm sky | ✅ | `StormSky.gd` (3D) and `StormTint2D` (2D) — darkening scaled by severity |
| Selective damage | ✅ | Priority: defence and morale first, then housing, then production. Never the Nucleo, never the last sawmill or gold mine (anti-softlock) |
| Minimum Quota | ✅ | An empty warehouse no longer means a free Tithe: from the second visit the debt is collected in buildings and workers |
| Arms race | ✅ | `StormCycle.storms_survived` feeds `assessor_roster()`: winning today means heavier guns tomorrow |
| Defensive towers | ✅ | Mitigate storm damage (15% each, 60% cap) and field an artillery crew on the defensive boards (Tithe and Final Audit), outside the deploy cap, back row, max 2 — only while operational |

## ✅ Milestone 3 — Expedition & the double clock

Tasks T022-T029 are specified in `specs/001-combate-pve/tasks.md`. The expedition runs
end to end from the UI.

| Item | Status | Where it lives |
|------|--------|----------------|
| `ExpeditionGenerator` + `Expedition` pure models (boss reachable across many seeds) | ✅ | `scripts/combat/ExpeditionGenerator.gd`, `scripts/combat/Expedition.gd`, `tests/combat/test_expedition_generator.gd`, `tests/combat/test_expedition.gd` |
| `launch_expedition()` and the rest of the service API (`select_node`, `apply_draft`, `abandon_expedition`, `enter_current_node`) | ✅ | `scripts/services/CombatManager.gd`, `tests/combat/test_expedition_wiring.gd` |
| Expedition save/load — seed + cleared nodes, map regenerated, board never saved | ✅ | `Expedition.to_dict/from_dict`, `CombatManager.get_save_data/load_save_data`, `GameManager` |
| Chained encounters with attrition and permadeath | ✅ | `Expedition.build_encounter_units()`, `CombatManager.enter_current_node()` |
| **Unit lockout**: `get_garrison()` excludes units away on expedition | ✅ | `CombatManager.get_garrison()` / `get_units_on_expedition()` |
| **Defensive auto-resolve**: the *same* `Encounter` headless, AI on both sides | ✅ | `scripts/combat/AutoResolver.gd`, `CombatManager.auto_resolve_defense()`, `StormManager._auto_resolve_tithe()` |
| After-action report for the blind defence | ✅ | `WarReportScreen` listens to `defense_auto_resolved` |
| Storm notifications drawn over `BattleScreen` | ✅ | `NotificationPanel` toast layer vs `BattleScreen.layer`, `tests/storm/test_storm_toasts_over_board.gd` |
| **Skirmish panel, map view, draft modal, final report** | ✅ | `SkirmishPanel` calls `CombatManager.launch_expedition(party)`; `BattleScreen` builds the map, the draft modal and the report on top of the board. `tests/ui/test_expedition_ui.gd` (26 tests) |
| Listeners for the expedition signals | ✅ | `draft_offered` / `draft_applied` → BattleScreen; `expedition_node_selected` → BattleScreen, SkirmishPanel; `expedition_resumed` → BattleScreen, SkirmishPanel, ArmyPanel. A campaign in flight reopens its map on load |
| **Unit silhouettes on the board** | ✅ | `assets/textures/ui/units/*.png` from `tools/gen_unit_icons.gd`, `UITheme.unit_icon()`, boss marked; the name's initial is only a fallback |
| Combat audio | ✅ | `AudioManager` on the combat and Final Audit signals, `tests/audio/test_audio_combat.gd` (15 tests). The 9 combat keys are aliases onto existing SFX — see the backlog |
| Helper callout for Escaramuzas | ✅ | `HelperPanel` `SkirmishCallout`, `tests/ui/test_helper_skirmish_callout.gd` |
| End-to-end probe | ✅ | `tools/expedition_probe.gd` |

## ✅ Milestone 4 — The Final Audit

| Item | Status | Where it lives |
|------|--------|----------------|
| HQ level 3 summons the siege instead of instantly winning (Campaña, Supervivencia) | ✅ | `ProgressionManager._complete_milestone()` → `summon_final_audit()`; `scripts/combat/FinalAudit.gd`, `tests/combat/test_final_audit.gd` |
| 3-5 chained defensive encounters with attrition, entered with "QUE BAJEN" | ✅ | `final_audit_wave_ready` → `CombatManager._on_final_audit_wave_ready()` → `start_defense()`; `tests/storm/test_final_audit_wiring.gd` |
| Winning emits `storm_halted_forever` and the Storm stops for good | ✅ | `ProgressionManager._publish_audit()`, `StormManager._on_halted_forever()`, `StormSky.restore_now()` |
| Losing sacks the settlement; the siege can be summoned again after rebuilding (not in Supervivencia) | ✅ | `StormManager._on_final_audit_lost()`; `FinalAudit.can_resummon()` / `resummon()` with a floor of `final_audit_resummon_min_units` (3); `AuditDefeatScreen` |
| The siege is hard and winnable | ✅ | [17-balance-asedio.md](17-balance-asedio.md): the maximum garrison wins ~82% |

---

## ❓ Open balance decisions

Measured by the balance line and left to the owner
([22-linea-jugable.md](22-linea-jugable.md) §7):

1. ❓ **A "resolve alone" button for the Tithe.** Boards take about a third of a
   campaign (45-100 of 140-240 min); a Tithe that is won before it starts still has to
   be played. `AutoResolver` already exists and is the one used when the board is busy.
2. ❓ **The era-3 storage squeeze.** Steel and oil fill the shared pool on their own
   (1-25 min per game, 350-9,000 resources lost). Levers: the HQ-3 price (3,100 instead
   of 3,500 let 2 of 5 stuck games finish) or stopping steel/oil production when the
   pool is full instead of throwing it away.
3. ❓ **A scripted test storm in era 1.** Era 1 has no Storm by design; that is 8-10 min
   with no pressure but consumption.
4. ❓ **How long era 1 should last.** Manual mining is the strongest era-1 lever (era 2
   by minute 3 with it); if era 1 should last longer, the lever is `mining_data`.

Also pending on the balance side: a human playtest with real timings (checklist in
[22-linea-jugable.md](22-linea-jugable.md) §9) and a test on a physical tablet.

## 💤 Backlog

- 🚧 Cloud saves: `CloudSaveManager` (Supabase REST, auth + save/load) implemented but
  **unwired** — needs credentials an export can read (the package excludes `.env`) and
  a login UI ([12-cloud-saves.md](12-cloud-saves.md))
- 💤 Ambient audio track (`assets/audio/ambient/` holds only a `.gitkeep`)
- 💤 Dedicated combat audio files (the 9 combat keys are aliases onto existing SFX, and
  the `combat` theme borrows `era_3_petroleum` — `assets/audio/MANIFEST.md`)
- 💤 Missions / contracts: timed delivery challenges for rewards
- 💤 Towers with an attack of their own on the base map
- 💤 More buildings / decorations and a second island biome
- 💤 Day-night visual layer outside the storm
- 💤 Achievements / statistics
- 💤 Distribution: Windows code signing (SmartScreen), Android release keystore, AAB
  and store listing ([19-exportar.md](19-exportar.md) §8, §11.10)
- 💤 Small known gaps listed per system: [15-combat.md](15-combat.md) §10,
  [18-vista-2d.md](18-vista-2d.md) "Huecos conocidos",
  [21-interfaz-y-dispositivos.md](21-interfaz-y-dispositivos.md) §10,
  [23-onboarding.md](23-onboarding.md) §6, and the orphan signals in
  [10-signals-reference.md](10-signals-reference.md)

---

## Dependency order (as it was built)

```
M1 economy ──────────────┐
    │                    │
    └──▶ building ──────▶ M2 storm bites
         health           │
                          ├──▶ M3 expedition + double clock
                          └──▶ M4 Final Audit
                                   │
                                   └──▶ 2D view · modes · UI & devices · touch
                                        · onboarding · balance line · exports
```

Milestone 1 came first because it is tuning, not construction. Milestone 4 depended
only on Milestone 2.

## Out of scope

PvP and co-op · meta-progression between expeditions · non-combat expedition nodes.
