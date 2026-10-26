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
| Campaña | The single key (2026-10-25): `summon_final_audit()`: 3-5 defensive waves ([15-combat.md](15-combat.md) §6), entered with "QUE BAJEN". HQ level 3 itself asks for the three campaign pieces | Surviving the last wave. Losing is not a game over: the siege can be resummoned once 3 units stand |
| Supervivencia | Same key, same siege, but only one (`resummon: false`) | Surviving it. Losing it ends the run (`run_ended`) and seals the save |
| Constructor | No siege (`audit_on_capstone: false`) | `_trigger_victory()` right away (`capstone_wins: true`) |
| Sandbox | Nothing (the siege is summoned only from the SANDBOX tab) | None (`victory: false`) |

`_complete_milestone("hq_max")` asks `GameMode.audit_enabled()` first and
`GameMode.capstone_wins()` second.

**One key for the Final Audit (2026-10-25, `feat/ritmo-colono`,
[15-combat.md](15-combat.md) §13 "La condición del Ataque Final").** Before it there
were two keys (HQ level 3 and the three campaigns, `feat/tres-campanas`). Now each
**campaign boss hands over a piece** of HQ level 3 — **Planos del Bastión** (Land),
**Casco del Leviatán** (Sea), **Motor del Zepelín** (Air) — and HQ level 3 asks for
the three pieces on top of its cost (`GameConfig.hq_needs_pieces()`,
`CombatManager.hq_missing_pieces()`, refused in `ProductionManager.start_upgrade()`).
HQ level 3 summons the siege, as in the 1.0: `final_audit_ready()` is `hq_max`.
`final_audit_missing()` / `final_audit_gate_text()` list the missing pieces and HQ 3;
¿QUÉ HACER? says "Para el CG 3 te faltan: pieza de Mar, pieza de Aire"
(`CombatManager.hq_pieces_text()`) and the pieces are steps of its line (the three
campaigns with the HQ standing, before its level 2; Land first). Rule `audit_needs_campaigns`
(`GameMode.audit_needs_campaigns()`), global switch
`GameConfig.final_audit_needs_campaigns`. Old saves: a piece is a boss already beaten;
an old save with HQ 3 done and campaigns unfinished can call the siege (it paid its
key). Each mission won gives rank XP (`campaign_mission` 60, `campaign_boss` 250). In
the siege modes, surviving the last wave emits `storm_halted_forever` and only then
`_trigger_victory()`:

1. Stats: `time_played` (**played seconds**, `ProgressionManager._played_seconds`,
   saved — not wall-clock time since creation), buildings built, trades, milestones,
   `storms_survived`, `tithes_repelled`, `audit_summons`
2. `EventBus.victory_achieved` emitted with the stats dict
3. `VictoryScreen`: title, "the Regency left with nothing" subtitle, the stats, a coda
   line, "Keep playing" / "New game"

"Keep playing" leaves a sandbox: the Storm is halted for good and the WHAT TO DO? panel
(`Objectives.next_step()`) says so.

## Capítulos (2026-10-25, rama `feat/ritmo-colono`)

Decisión de Bryan tras la crítica (contexto 27, B1): **Colono dura 3-4 h en tres
capítulos**, que son los tres actos del lore (contexto 03 §7); Gobernador se queda en
6-8 h. Cada capítulo tiene un objetivo visible en ¿QUÉ HACER? y se cierra con una
pantalla corta.

| Capítulo | Acto del lore | Qué abre | Se cierra con |
|---|---|---|---|
| **I · Nadie nos mira** | Acto I (Era Frontera) | oro, madera, comida, casas; Cuartel, primer soldado y primera misión; la Tormenta de prueba; la Campaña de Tierra | la **Fundición** (era 2) |
| **II · La cuenta** | Acto II (Era Industrial) | acero; la Tormenta de verdad y el Impuesto (la Visita); la guarnición, el Astillero y la Campaña de Mar; la Refinería, las torres y el Cuartel General | la **Refinería** (era 3) **y** los **Planos del Bastión** (jefe de Tierra) |
| **III · El libro** | Acto III (Era Petrolera) | petróleo, torres, Cuartel General, Aeródromo; Mar y Aire | **Casco del Leviatán** y **Motor del Zepelín**, el **CG nivel 3** y **aguantar el Ataque Final** (la victoria) |

- **Lógica.** `scripts/services/Chapters.gd` (estático, como `Objectives`, sin estado):
  `current()` (1-3; 4 con la partida ganada), `is_done(n)`, `goals(n)` (metas con su
  clave de Tr y si están hechas), `heading(n)` ("Capítulo II · La cuenta"),
  `goal_text(n)`, `goal_lines(n)` ("✓ …", "· …"), `close_text(n)`. Solo hay
  capítulos donde hay Ataque Final (`Chapters.enabled()`: Campaña, en los dos niveles,
  y Supervivencia).
- **Estado.** `ProgressionManager.chapters_closed` (los cerrados, para no repetir la
  pantalla), en el guardado como `progression.chapters`; se limpia en `reset()`.
  `check_chapters()` los cierra **en orden** y de uno en uno al cambiar de era, al
  completar una campaña, con el CG nivel 3 y al ganar, y emite
  `EventBus.chapter_completed(n)`. Al cargar (`game_load_completed`) los ya cumplidos
  se dan por cerrados **sin pantalla**: un guardado de antes de los capítulos no ve
  tres tarjetas seguidas.
- **¿QUÉ HACER?** (`ObjectivePanel`): arriba, "CAPÍTULO II · LA CUENTA", el objetivo
  del capítulo en una frase y sus metas con ✓ (`_paint_chapter()`, con el refresco de
  siempre: nada por fotograma). La línea (`Objectives.LINE`) lleva las piezas donde
  las pide su capítulo (docs/15 §13).
- **El cierre** (`scripts/ui/ChapterScreen.gd`, capa 19, grupo `modal_screen`): una
  tarjeta con la cinta "CAPÍTULO I COMPLETO", el nombre, una frase del lore
  (`CHAPTER_n_CLOSE`), "Ahora: Capítulo II · La cuenta" con su objetivo y
  **¡ADELANTE!**. La crea `ObjectivePanel` en las dos escenas (no es un nodo de
  `Main.tscn`). Espera a que no haya tablero abierto ni otro parte a la vista. El
  capítulo III no saca tarjeta: lo cierra la pantalla de victoria.
- **El ritmo de Colono** (regla de nivel, `GameConfig.game_tier_rules`):
  `campaign_missions` (Tierra 4, Mar 2, Aire 2; Gobernador las 16), `hq_resource_mult` 0,75 (lo de la bolsa del CG; Gobernador 1) y
  `hq_material_mult` 0,5 (vigas, lingotes y combustible de los niveles 2 y 3 del CG;
  Gobernador 1). La bolsa del CG no cambia (el nivel 3 sigue pidiendo la bolsa
  entera). Medido en [22-linea-jugable.md](22-linea-jugable.md) §17.

## Orden de la Regencia (2026-10-14, 1.1)

The goal of every calm (doc 21 §2.2 of the private context; Bryan's D5 = A). It does not
change the Tithe formula (`get_tithe_ratio`, `get_tithe_debt`, the escort): it only
discounts the debt that formula gives, and shows it in advance.

**State** lives in the pure `StormCycle` and travels in the `storm` save section:

| Key | What | Old save |
|---|---|---|
| `tithe_discounts` | `source → fraction` (`"entrega"`, `"expedicion"`…) | `{}` |
| `order` | `{"res", "amount", "done"}`, the Regency delivery of this calm | `{}`, rolled on load |
| `calm_total` | length of this calm when it began (barometer fill) | the calm left |
| `barometer_offset` | random shift of the barometer centre, seconds | `0` |

`settle_tithe()` empties `tithe_discounts` and `order` (paid or repelled); a false alarm
keeps them (the Tithe has not come). `from_dict()` **assigns**, never adds, so loading
twice is safe. `StormManager.reset()` builds a new cycle, so the three new-game paths of
`GameManager` already clear it (no new line there). The Order and the barometer draw
from their own `RandomNumberGenerator` (`_order_rng`, seed + 1): rolling an order never
moves the storm clock under a fixed seed.

**Rules.**
- The order is rolled when the clock arms (Foundry) and after every Tithe
  (`StormManager._ensure_order(fresh)`), among the **unlocked materials**; with none,
  wood or gold. Amount: `storm_order_delivery_base[res] × min(1 + growth × storms_survived,
  growth_max)`. Delivering pays it and adds `storm_order_delivery_pct` (0.15) as source
  `"entrega"`.
- Discounts add up per source and in total, capped by `storm_order_discount_max` (0.5).
  `StormManager._collect_tithe()` applies `cycle.discounted(debt)` (rounded up) to the
  whole debt — share and Minimum Quota — before collecting. The lost Final Audit
  (`_on_final_audit_lost`) collects **without** discounts.
- Barometer (`StormCycle.barometer()`): only in CALM, with the real clock running. Margin
  ±`storm_barometer_margin` (60 s, through `get_duration()`) around `seconds_left +
  barometer_offset`, with `|offset| ≤ storm_barometer_jitter × margin` (0.5): the real
  time to the Warning is always inside `[low, high]` minutes, never at a known place.
  `low = 0` reads "< high min".
- The card's Tithe preview uses the severity the colony **earned** (`cycle.severity`),
  not the effective one: what a false alarm deferred stays hidden, as before.

**Public API (for any branch that adds a discount).**

```gdscript
# Additive and capped; lasts until the next Tithe. Returns the total discount, or -1.0
# if nothing was written (clock not armed, mode without Tithe, Assessors at the door).
StormManager.add_tithe_discount(source: String, pct: float, notify := true) -> float
StormManager.get_tithe_discount() -> float
StormManager.get_discount_from(source: String) -> float
```

The 1.0 sorties (`feat/escaramuzas`, now in `integracion/arte-v1`) wire it: beating the
Regency outpost raid (the "campamento", only with the clock armed) pays `tithe_pct` loot
(`GameConfig.sortie_tithe_discount_pct()` = `storm_order_expedition_pct`), and
`CombatManager._apply_loot()` calls `StormManager.add_tithe_discount("expedicion", pct / 100)`.
So `GameConfig.storm_order_expedition_way` is `true` and the card shows the third way
("Echar su campamento (MISIONES) → −10 %").
Contracts (doc 21 §2.3) would use their own source name (`"contrato"`).

**UI.** `StormHUD` shows the barometer in calm and the Order card on tap (it opens by
itself on a fresh order, `storm_order_changed(true)`). `Objectives.calm_goal()` gives the
second line of ¿QUÉ HACER? ("Antes de la Tormenta: entrega …"); it is **not** part of
`next_step()`, so `tools/line_probe.gd` does not follow it.

**Tunables (new keys only):** `storm_order_discount_max`, `storm_order_delivery_pct`,
`storm_order_expedition_pct`, `storm_order_expedition_way`, `storm_order_delivery_base`,
`storm_order_delivery_growth`, `storm_order_delivery_growth_max`, `storm_order_towers_goal`,
`storm_barometer_margin`, `storm_barometer_jitter`. No existing `storm_*`, `combat_*` or
`final_audit_*` value changed. Not measured with the line probe yet: a delivered order every
calm takes 15 % off every Tithe.

Tests: `tests/storm/test_regency_order.gd`, `tests/storm/test_storm_hud.gd`.

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
| 1 | flag basics: patterns `plain`, `bands_h`, `bands_v`, `halves_h`, `cross`; emblems `none`, `gear`, `anchor`, `wheat`, `hammer`; colours ivory, brass, crimson, steel, moss, soot; regiment paint `plain` |
| 2 | Garden, Flower planter, Hay cart (decorations); emblem `tower` |
| 3 | +1 % production; pattern `border`; colour sky; Bonfire; regiment paint `stripes` |
| 4 | +2 % storage; emblem `star` |
| 5 | Fountain, Flagpole |
| 6 | +1 % production; patterns `diagonal`, `saltire`; regiment paint `spots` |
| 7 | colours copper, red |
| 8 | Statue; +2 % storage |
| 9 | +1 % production; pattern `quartered`; emblem `wrench`; regiment paint `desert` |
| 10 | +2 houses (limit) |
| 11 | colours grass, slate; emblem `wheel` |
| 12 | +1 % production, +2 % storage; patterns `canton`, `hoist_triangle`; regiment paint `snow` |
| 13 | Palm trees (decoration); emblem `ship` (the old +2 statues/fountains did nothing once decorations had no cap) |
| 14 | colours terracotta, gold; emblem `cogs` |
| 15 | +1 % production; pattern `stripes`; regiment paint `parade` |
| 16 | +2 % storage; +1 tower (limit); emblem `sun` |
| 17 | +2 houses (limit); pattern `waves` |
| 18 | +2 % production; pattern `checks`; emblem `airship` |

Totals at rank 18: +7 % production, +8 % storage. The basic buildings keep their era
unlocks (the playable line in docs/22 does not move): the rank only opens
decorations, extra slots and cosmetics. A new optional building goes into the table
with `"buildings": [id]`. Sandbox has every rank unlock open.

- **Regiment (cosmetic only, docs/15 §12):** the `paints` key opens the regiment's
  paint schemes (plain, stripes, spots, desert, snow, parade). The regiment's colour
  and emblem reuse the flag pieces (`colors` / `emblems`) already open. The rank-up
  toast says "pintura nueva para el regimiento". Locks resolve through
  `ColonyIdentity.piece_rank("paints", id)`, like the flag pieces.

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
  saves only on change), `is_piece_unlocked(kind, id)`,
  `is_spec_unlocked(spec)`, `piece_rank(kind, id)`. `get_color()` / `get_color_id()` =
  the first colour (our board tokens). Drawing: `ColonyFlag.texture(spec)` (96x64),
  `small_texture(spec)` (48x32), `draw_spec(canvas_item, rect, spec)` — all cached per
  recipe, nothing per frame.
- **When:** the New Game step (`ColonyIdentityPanel.open("new")`, preset with a random
  name and flag, rank-1 pieces, "Saltar" accepts the preset) — wired by NewGameDialog,
  whose `chosen_identity` goes to `GameManager.start_new_game(mode, tier, identity)`;
  `_new_game()` applies it with `set_colony()` right after `RankManager.reset()` (the
  only path: `clear_save()` also resets before the reload, so the choice cannot wait
  inside RankManager) — and later ☰ MENÚ → COLONIA → BANDERA Y NOMBRE (`open("edit")`, RankPanel applies it with
  `set_colony()`).
- **Where it shows:** the masts of the Nucleo and of **every Barracks** — and only
  there among the buildings (Bryan, 2026-10-18; `ColonyFlag.FLAG_BUILDINGS =
  ["barracks"]`; the HQ no longer has a mast or flag, and the flagpole/colony-sign
  decorations keep theirs) (`ColonyFlag3D`: a 6-segment plane with the cached texture
  and a vertex-shader wave, no wave in low graphics quality; medium size on the
  Barracks (`BARRACKS_SCALE` 0.62), hanging from the short roof mast's `FlagAnchor`
  in the baked model; hidden while under construction or ruined and back when finished
  or repaired; Barracks have no building cap, so every flag shares the plane, material,
  shader and pole/knob meshes and none has a `_process`; `ColonyFlag2D` draws the
  cached texture from `BuildingArt2D.flag_mount()`),
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
