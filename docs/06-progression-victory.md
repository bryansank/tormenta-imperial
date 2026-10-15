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

## Governor rank (rango del gobernador)

A third axis next to eras and milestones: **XP inside the run**. `RankManager`
(autoload, last in the list) listens to the EventBus and adds XP per
`GameConfig.rank_xp_sources`; the rank is **derived** from the XP with
`GameConfig.rank_xp_thresholds` and never saved on its own. Decided by the owner on
2026-10-04 (context doc 17).

### XP sources

| Source | Signal | XP |
|---|---|---|
| Building finished (not roads, not the Nucleo) | `construction_completed` | 15 (decoration: 5) |
| Upgrade finished | `building_upgrade_completed` | 25 |
| One passive production cycle | `production_tick` | 1 |
| Workshop process / hand mining | `process_completed` / `mining_completed` | 5 |
| Market trade | `market_trade_completed` | 5 |
| Unit trained | `unit_trained` | 10 |
| Fight won (board or blind defence) | `encounter_ended(true)` / `defense_auto_resolved(true)` | 40 |
| Expedition back with loot | `expedition_ended(0)` | 80 |
| Storm weathered | `storm_ended(severity)` | 30 + 10 per severity |
| Milestone | `milestone_completed` | 100 |

### Curve (18 ranks)

Going from rank n to n+1 costs `100 + 60*(n-1)` XP: cumulative 0, 100, 260, 480, 760,
1100, 1500, 1960, 2480, 3060, 3700, 4400, 5160, 5980, 6860, 7800, 8800, 9860. Rough
estimate for a 2-4 h campaign: ~4500 XP from actions plus ~1 XP per production
cycle, 9000-11000 in total, so rank 18 lands near the Final Audit. **Not measured
yet** with `tools/line_probe.gd`: re-tune `rank_xp_thresholds` / `rank_xp_sources`
after a probe run.

### Titles

1 Colono · 2 Capataz · 3 Maestro de obras · 4 Intendente · 5 Alcalde · 6 Regidor ·
7 Gobernador · 8 Superintendente · 9 Prefecto · 10 Comisario de Hierro · 11 Procurador ·
12 Tribuno · 13 Cónsul · 14 Legado · 15 Virrey · 16 Gran Canciller · 17 Señor del
Acero · 18 Archigobernador (keys `RANK_TITLE_<n>`, ES and EN).

### Rewards (`GameConfig.rank_rewards`)

| Rank | Reward |
|---|---|
| 1 | flag basics: patterns `plain`, `bands_h`, `bands_v`, `halves_h`, `cross`; emblems `none`, `gear`, `anchor`, `wheat`, `hammer`; colours ivory, brass, crimson, steel, moss, soot |
| 2 | Garden, Flower planter, Hay cart (decorations); emblem `tower` |
| 3 | +1 % production; pattern `border`; colour sky; Bonfire |
| 4 | +2 % storage; emblem `star` |
| 5 | Fountain, Flagpole |
| 6 | +1 % production; patterns `diagonal`, `saltire` |
| 7 | colours copper, red |
| 8 | Statue; +2 % storage |
| 9 | +1 % production; pattern `quartered`; emblem `wrench` |
| 10 | +2 houses (limit) |
| 11 | colours grass, slate; emblem `wheel` |
| 12 | +1 % production, +2 % storage; patterns `canton`, `hoist_triangle` |
| 13 | Palm trees (decoration); emblem `ship` (the old +2 statues/fountains did nothing once decorations had no cap) |
| 14 | colours terracotta, gold; emblem `cogs` |
| 15 | +1 % production; pattern `stripes` |
| 16 | +2 % storage; +1 tower (limit); emblem `sun` |
| 17 | +2 houses (limit); pattern `waves` |
| 18 | +2 % production; pattern `checks`; emblem `airship` |

Totals at rank 18: +7 % production, +8 % storage. The basic buildings keep their era
unlocks (the playable line in docs/22 does not move): the rank only opens
decorations, extra slots and cosmetics. A new optional building goes into the table
with `"buildings": [id]`. Sandbox has every rank unlock open.

- **Bonuses** are written into `GameConfig.rank_production_bonus` (added to the
  production multiplier next to the tech bonus), `rank_storage_bonus` (a fraction on
  top of `get_storage_cap()`) and `rank_limit_bonus` (added in `get_building_limit()`).
  `RankManager` **assigns** the total of the current rank, never adds: loading twice
  gives the same bonuses. Note: production is truncated with `int()` per cycle, so a
  +1-3 % bonus only shows on bigger yields (upgraded buildings, techs).
- **Locks:** `PlacementRules.check_rank()` blocks the purchase ("Necesitas rango N");
  CONSTRUIR draws a padlock and "Rango N" on the card.
- **The country (name and flag):** see "The player's country" below.
- **Save:** `"rank": {"xp", "colony": {"name", "flag": {"pattern", "emblem", "colors"}}}`.
  A save without it is XP 0 = rank 1. `RankManager.reset()` is called from the three
  fresh-game paths of GameManager.

### The player's country (decided 2026-10-12)

The player names the country and builds its flag from pieces. Data in `RankManager`,
pure helpers in `scripts/services/ColonyIdentity.gd`, drawing in `scripts/ui/ColonyFlag.gd`.

- **Recipe:** `{"pattern": id, "emblem": id, "colors": [field 1, field 2, emblem]}`, ids
  from `GameConfig.COLONY_PATTERNS` (14: plain, band, vertical band, two halves, Nordic
  cross, border, diagonal, saltire, quartered, canton, hoist triangle, stripes, waves,
  checkered), `COLONY_EMBLEMS` (none + 12: gear, anchor, wheat, hammer, tower, 8-point
  star, wrench, helm, steamer, cogwheels, sun, airship) and `colony_colors` (13: the six
  old colony colours + ivory, sky, red, grass, slate, terracotta, gold from ToyPalette).
  All own geometry drawn by code: nothing from other games, no real state, party or
  ideology symbols. What each rank opens is the table above (`patterns` / `emblems` /
  `colors` keys of `rank_rewards`); Sandbox has everything open.
- **Always readable:** two field colours must differ (`fields_distinct`: WCAG contrast
  ≥ 1.35 or hues ≥ 0.16 apart), the emblem must reach contrast 1.9 against what lies
  under it (`emblem_legible`, per pattern `on`), and gets a 1 px outline of the opposite
  tone. `fix_spec()` repairs a recipe (deterministic, idempotent); the editor greys out
  colours that would fail.
- **Name:** up to `COLONY_NAME_MAX` (26) characters, cleaned (`clean_name`). "Al azar"
  makes "<form> de <place>" or the place alone, ES and EN lists in ColonyIdentity
  ("República de Puerto Hierro", "Liga de Vaporia", "Duchy of Sootmoor"). A short ES/EN
  word filter (base64 in the code, substring and whole-word lists, accents and leet
  normalised, repeated letters squeezed) rejects rude names; the editor just says
  "Prueba otro nombre".
- **API:** `RankManager.get_colony_name()`, `get_flag_spec()`, `set_colony(name, spec) -> bool`
  (false if the name fails or a piece is locked; emits `colony_identity_changed` and
  saves only on change), `queue_colony_for_new_game(name, spec) -> bool` (validated at
  rank 1, consumed by the next `reset()`), `is_piece_unlocked(kind, id)`,
  `is_spec_unlocked(spec)`, `piece_rank(kind, id)`. `get_color()` / `get_color_id()` =
  the first colour (our board tokens). Drawing: `ColonyFlag.texture(spec)` (96x64),
  `small_texture(spec)` (48x32), `draw_spec(canvas_item, rect, spec)` — all cached per
  recipe, nothing per frame.
- **When:** the New Game step (`ColonyIdentityPanel.open("new")`, preset with a random
  name and flag, rank-1 pieces, "Saltar" accepts the preset) — wired by NewGameDialog —
  and later ☰ MENÚ → COLONIA → BANDERA Y NOMBRE (`open("edit")`, RankPanel applies it with
  `set_colony()`).
- **Where it shows:** the Nucleo and HQ masts (`ColonyFlag3D`: a 6-segment plane with
  the cached texture and a vertex-shader wave, no wave in low graphics quality, big on
  the HQ, hangs from the model's `FlagAnchor` Marker3D when the baked model has one,
  hidden while the HQ is a construction site; `ColonyFlag2D` draws the cached texture),
  the HUD badge (flag + name; the rank title moved to the tooltip and the card), and
  `ColonyByline` (small flag + name above the title, so sentences do not grow) on
  `WarReportScreen`, `AuditDefeatScreen`, `VictoryScreen` and the `BattleScreen` header.
- **Old saves:** `"colony"` missing → a country rolled from `GridManager.island_seed`
  (loaded first), stable for that save; an old `"flag"`/`"color"` pair becomes pieces
  (`COLONY_LEGACY_FLAGS`, e.g. `gear` → plain + gear emblem). A piece above the rank
  falls back to the default one; a name that fails the filter is re-rolled.
- **Probe:** `godot --path . -s tools/flag_probe.gd -- --shot-size=1280x800 --profile=tablet`
  (own `override.cfg`), screenshots and `gallery.png` in `docs/media/dev/flag/`.

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
- `scripts/services/RankManager.gd` — governor rank: XP, rank, rewards, cosmetics
- `scripts/ui/RankPanel.gd` — rank badge, rank-up toast, the COLONIA card
