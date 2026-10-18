# Combat

Everything that puts units on an 8x8 board: the pure models in `scripts/combat/`,
the `CombatManager` service that publishes them, and the screens that read them.

This document describes **the code as it stands**, not the specification. Where a
piece is specified but not wired, it says so.

> Number note: `docs/14-guia-de-juego.md` (Spanish, player-facing) already holds
> number 14, so the technical combat document is 15.

---

## Contents

1. [The three layers](#1-the-three-layers)
2. [The three roads to the same board](#2-the-three-roads-to-the-same-board)
3. [The board](#3-the-board)
4. [The expedition](#4-the-expedition)
5. [The auto-resolved defence](#5-the-auto-resolved-defence)
6. [The Final Audit](#6-the-final-audit)
7. [Signals](#7-signals)
8. [Balance](#8-balance)
9. [Testing](#9-testing)
10. [Known gaps](#10-known-gaps)
11. [Dominios: mar, aire (y espacio)](#11-dominios-mar-aire-y-espacio)

---

## 1. The three layers

The rule that holds the whole pillar together: **the models never emit**. Every
mutating method on a model returns an `Array` of plain event dictionaries. A
service drains that array and republishes it on the `EventBus`. The interface
only reads and calls.

```
scripts/combat/*.gd   → Array[Dictionary]   (pure, headless, deterministic)
        ↓
CombatManager / ProgressionManager  → EventBus.<signal>.emit(...)
        ↓
BattleScreen / SkirmishPanel / AudioManager / StormManager  (read-only)
```

### Layer 1 — pure models (`scripts/combat/`)

All `RefCounted`. No nodes, no timers, no `EventBus`, no global `randf()`.

| File | Class | What it owns |
|------|-------|--------------|
| `CombatUnit.gd` | `CombatUnit` | One unit: hp, position, side, draft bonuses, morale modifiers. Derived stats (`attack_power`, `defense`, `move_range`, `initiative`) read `GameConfig.combat_unit_stats` and apply bonuses on top — the stored stats are never mutated |
| `CombatRules.gd` | `CombatRules` | Static maths: damage, morale modifiers, Manhattan range, BFS reachability, turn order, timeout resolution, encounter rewards, morale delta |
| `Encounter.gd` | `Encounter` | One board: units, deploy zones, turn order, rounds, win/lose/timeout |
| `CombatAI.gd` | `CombatAI` | Plans one unit's turn. Pure: reads an `Encounter`, returns a list of steps, mutates nothing |
| `AutoResolver.gd` | `AutoResolver` | Plays a whole `Encounter` with `CombatAI` on **both** sides, returns the accumulated events |
| `Expedition.gd` | `Expedition` | One roguelike run: map, party, loot, current node, state |
| `ExpeditionGenerator.gd` | `ExpeditionGenerator` | Static and seeded: map graph, enemy rosters, rewards, draft options |
| `FinalAudit.gd` | `FinalAudit` | The closing siege: waves, garrison, summons counter |

Event dictionaries always carry an `"e"` key naming the event. The ones the models
produce:

| `e` | Payload | Produced by |
|-----|---------|-------------|
| `turn_started` | `side`, `uid` | `Encounter._advance()` |
| `unit_moved` | `uid`, `from`, `to` | `Encounter.move_unit()` |
| `unit_attacked` | `attacker`, `target`, `damage` | `Encounter.attack()` |
| `unit_died` | `uid`, `side` | `Encounter.attack()` |
| `unit_defended` | `uid` | `Encounter.defend()` |
| `encounter_ended` | `victory`, `rounds` | `Encounter._finish()` / `_resolve_timeout()` |
| `node_cleared` | `index`, `is_boss` | `Expedition.mark_cleared()` |
| `expedition_node_selected` | `index` | `Expedition.select_node()` |
| `draft_applied` | `option` | `Expedition.apply_draft()` |
| `expedition_ended` | `result` | `Expedition.mark_cleared/mark_defeated/abandon()` |
| `final_audit_summoned` | `waves`, `summons` | `ProgressionManager.summon_final_audit()` / `FinalAudit.resummon()` |
| `final_audit_started` | `waves`, `summons` | `FinalAudit.begin()` |
| `final_audit_wave_cleared` | `wave`, `remaining` | `FinalAudit.clear_wave()` |
| `final_audit_won` | `waves`, `summons` | `FinalAudit.clear_wave()` |
| `final_audit_lost` | `wave` | `FinalAudit.lose()` / `clear_wave()` |

### Layer 2 — the services

| Service | File | Owns |
|---------|------|------|
| `CombatManager` (autoload) | `scripts/services/CombatManager.gd` | The active `Encounter` and the active `Expedition`. The only thing that mutates combat state, drives the enemy turn, applies consequences to the base, and saves/loads the expedition |
| `ProgressionManager` (autoload) | `scripts/services/ProgressionManager.gd` | The `FinalAudit`. It publishes the siege's events; `FinalAudit` itself never emits |

`CombatManager._emit_events()` and `_publish_expedition_events()` are the two
translation tables from model events to `EventBus` signals.
`ProgressionManager._publish_audit()` is the third.

**Ordering that matters:** `encounter_ended` is emitted *after* `_apply_result()`
has already paid out, so any listener reading `CombatManager.get_last_result()`
sees it settled. The expedition follow-ups (draft offered, run ended) are held in
`_expedition_followups` and published *after* `encounter_ended`, so the UI always
sees the board close before it hears what comes next.

### Layer 3 — the interface

The expedition interface has landed. `BattleScreen` is one overlay with four
views that never share the screen — board, map, draft modal, final report — and
`SkirmishPanel` is the door out: its launch button calls
`CombatManager.launch_expedition()`. Every expedition signal has a real listener,
connected as a typed `EventBus.x.connect(…)`. Around the pillar, `WarReportScreen`,
`AuditWaveBanner` and `AuditDefeatScreen` report what has no board of its own (the
blind defence, the Tithe, each siege wave, a lost siege).

| Script | Role |
|--------|------|
| `scripts/combat_view/` + `scenes/combat/Board3D.tscn` | **El tablero 3D** (2026-10-12): la maqueta de 8x8 con unidades de juguete que `BattleScreen` pone de fondo en la vista del tablero. Solo vista: anima los eventos que ya publico `CombatManager`. Ver [§3, "El tablero 3D"](#el-tablero-3d-2026-10-12) |
| `scripts/ui/BattleScreen.gd` | The expedition screen. `CanvasLayer` at `layer = 18`, deliberately kept out of `UIManager`'s window stack so ESC cannot dismiss a fight. Four views (`View.BOARD`, `View.MAP`, the draft modal, the final report). Opens on `encounter_started` and on `expedition_started` / `expedition_resumed` / `game_load_completed`, redraws on every combat signal, routes every click back through `CombatManager`. Its close button calls `CombatManager.end_encounter()` — which is what advances the Final Audit to the next wave |
| `scripts/ui/SkirmishPanel.gd` | Troop commitment before a board opens, plus the "QUE BAJEN" button that begins or re-summons the Final Audit. Its launch button calls `CombatManager.launch_expedition()`; the dev-only test fight calls `dev_start_encounter()` (which uses `start_encounter()`). Nothing in `scripts/` calls `start_skirmish()` any more — only tests do. With a column out it stops being a selector and becomes the campaign status, with a "back to the map" button that calls `BattleScreen.open_map()` |
| `scripts/ui/ArmyPanel.gd` | Paints who is away "en campaña" from `CombatManager.get_units_on_expedition()`, and refreshes on `expedition_started` / `expedition_ended` / `expedition_resumed` |
| `scripts/ui/NotificationPanel.gd` | Log entries on `expedition_started` and `expedition_ended`, so a run leaves a trace in the base |
| `scripts/services/AudioManager.gd` | SFX on `encounter_started`, `unit_attacked`, `unit_died`, `encounter_ended`, `expedition_started`, `expedition_ended`, `final_audit_summoned`, `storm_halted_forever` |
| `scripts/ui/HelperPanel.gd` | One callout pointing at the Escaramuzas button once a Barracks exists |
| `scripts/services/TutorialManager.gd` | A one-shot contextual tip on `encounter_started` |
| Avisos retenidos (2026-10-14) | Con un tablero abierto (`CombatManager.is_board_open()`: pelea o parte) los avisos de la colonia **no salen en pantalla**: los toasts de `NotificationPanel` van al registro al momento y se retienen; las placas de hito/era de `ProgressPanel` esperan en su cola; el ascenso de `RankPanel` se guarda (el ultimo). Al cerrarse el tablero (`EventBus.encounter_closed`, emitida al final de `CombatManager.end_encounter()`) salen: los ultimos que caben y, si habia mas, "Mientras peleabas: N avisos mas en el REGISTRO" (`MSG_HELD_NOTICES`). Si el cierre abrio otro tablero (la oleada siguiente del asedio) siguen esperando. Una partida nueva o cargada tira lo retenido. Los avisos del propio combate (categoria `combat`: la columna sale / vuelve) si salen. Las ayudas de `HelperPanel` (consejos, globos, tarjetas) tambien esperan: `is_quiet()` y `_can_show()` miran `is_board_open()` (salvo el consejo `encounter`, que es del combate) y la cola se reanuda con `encounter_closed`. Los partes de guerra (`WarReportScreen`) ya tenian su cola |
| `scripts/ui/WarReportScreen.gd` | Queued war reports, never over an open board: the blind defence (`defense_auto_resolved`) and the Tithe with its COBRADO / REPELIDO stamp (`tithe_resolved`) |
| `scripts/ui/AuditWaveBanner.gd` | "Oleada X de N" on `final_audit_wave_ready`, with the cleared wave from `final_audit_wave_cleared` |
| `scripts/ui/AuditDefeatScreen.gd` | A lost siege (`final_audit_lost`): what was taken, in which wave, and what it takes to resummon — or, in Supervivencia, the end of the run |

The old `has_method()` / `has_signal()` scaffolding around the expedition calls is
gone; the only guards left in these panels are unrelated (`SkirmishPanel` asks
`PopulationManager.has_method("get_morale")` and `BattleScreen.has_method("open_map")`).

---

## 2. The three roads to the same board

Three different situations build an `Encounter`. The board, the rules and the AI
are identical in all three; what differs is who composes the player's side, who
pays, and what losing costs.

| | Skirmish / expedition node | Tithe defence | Final Audit wave |
|---|---|---|---|
| Entry point | `CombatManager.launch_expedition()` → `enter_current_node()` (`start_skirmish()`: tests only) | `CombatManager.start_defense()` | `EventBus.final_audit_wave_ready` → `CombatManager._on_final_audit_wave_ready()` |
| Who composes the player's side | The player, in `SkirmishPanel` (skirmish); `Expedition.party` (node) | `get_garrison()`: everything trained and **at home**, capped at `combat_deploy_cap` | `FinalAudit.living_garrison()`, carried wave to wave with its damage |
| Tower crews | No | Yes — `get_tower_crews()`, outside the deploy cap, back row | Yes, and crews lost earlier in the siege are **not** replaced (`FinalAudit.crew_losses`, saved) |
| `Encounter.is_defense` | `false` | `true` | `true` |
| Deployment rows | Enemy on row 1 then 0 | Enemy on row 0 then 1 (one extra round of approach for the defender) | Same as the Tithe defence |
| Loot on a win | Yes, `CombatRules.encounter_rewards(era)` — banked immediately for a skirmish, accumulated in the model for an expedition node | **None.** The reward is that the Tithe goes uncollected | None |
| Casualties | Struck off `ArmyManager` (at once for a skirmish, at the end of the run for an expedition) | Struck off `ArmyManager`; tower crews never are | Struck off `ArmyManager` **the moment each one falls** (`_settle_audit_death`), so a mid-wave save always balances; tower crews go to `FinalAudit.crew_losses` instead |
| Morale swing | `CombatRules.morale_delta()` | `CombatRules.morale_delta()` | `CombatRules.morale_delta()` |
| What losing costs | The dead, and the run | The Tithe is collected (`StormManager._pay_tithe()`) | The siege is lost: maximum-severity Tithe and maximum storm damage (`StormManager._on_final_audit_lost()`), but no game over |

Tower crews are marked by uid in `CombatManager._tower_crew_uids` and filtered out
of the casualty and survivor counts by `_roster_only()`. They fight for the player
but never touch the `ArmyManager` ledger — otherwise a lost defence would delete
artillery the player never trained.

**Who is at home.** `get_units_away()` is the expedition party plus
`get_units_on_board()` — army units standing on an open board whose fate has not
been settled yet (living, or fallen and not yet charged; never tower crews, never
the expedition's own board, and nothing once `_result_applied`). `get_garrison()`,
`get_deployable_units()` and `ArmyManager`'s desertion all subtract it. Without it
a Tithe resolved blind during a skirmish enlisted the very units on the skirmish
board and charged their deaths twice.

**The skirmish roster** is `ExpeditionGenerator.enemy_roster(rng, 0, era, 0)` — the
first node of an expedition — with its own seed (`start_skirmish(party, seed)`; 0
rolls a new one). The provisional unseeded `build_enemy_roster()` is gone.

---

## 3. The board

`GameConfig.combat_board_size` is `Vector2i(8, 8)`; `combat_deploy_cap` is 6 per
side. Both are read by `Encounter.create()`.

### Deployment (`Encounter._deploy()`)

- The player always holds the bottom two rows; the enemy the top two.
- Each side fills its **front** row first and centres it, so a squad opens as a
  line facing the enemy rather than a zigzag.
- `back_row_uids` (today: tower crews) take the rear row **before** the line
  forms. They are artillery with `min_range` 2 — in front they go mute the moment
  anything reaches contact.

### Reading the board

Units are drawn as **silhouettes, not letters**. `tools/gen_unit_icons.gd` is a
re-runnable headless tool (`godot --headless --path . --script
res://tools/gen_unit_icons.gd`) that traces one flat dieselpunk shape per unit
type into `assets/textures/ui/units/{infantry,artillery,vehicle}.png` — the same
"no artist, code instead" route as `tools/gen_ui_textures.gd`. Each shape is
traced at 4x and box-averaged down so the edge survives being shrunk to the 24 px
of the initiative strip, and the three silhouettes are deliberately different
*masses* — infantry tall and narrow, artillery a circle with a diagonal, vehicle
wide and low — so they separate without looking at detail.

The PNG is a single-colour mask (white RGB, antialiased alpha), so one file
serves both armies. `UITheme` owns the reading rules:

| API | What it gives |
|-----|---------------|
| `UITheme.unit_icon_path(unit_id, px)` / `unit_icon(unit_id, px)` | The texture, or **`null` when there is no file on disk**. With `px`, the icon traced at the matching scale of the icon system (24 / 42 / 60 / 96, `UITheme.icon_scale_for`), falling back to the 64 px file. The board asks for its cell size, the initiative strip for 24 |
| `UITheme.unit_icon_tint(is_player)` | `POSITIVE` / `DANGER` lightened by 0.62 — the cell behind is the same colour *darkened*, and that gap is what keeps the silhouette from dissolving into its own background |
| `UITheme.unit_face_color(is_player, spent)` | The same tint, dropped to `UNIT_ICON_SPENT_ALPHA` (0.42) once the unit has acted |
| `UITheme.mark_boss(style)` | The brass halo (`BOSS_GLOW_SIZE`, `BOSS_BORDER_MIN`) stamped on a cell style **last**, so it adds to whatever border the state already chose instead of hiding it |

`BattleScreen._paint_unit_face()` and `_paint_order_face()` both fall back to
`_unit_glyph()` — the first letter of the translated unit name — whenever
`unit_icon()` returns `null`. A missing or unimported PNG can therefore never
leave a unit unpainted; it only reverts the board to how it looked before.

Which enemy wears the boss mark is decided by `BattleScreen.boss_uid()`: only in
a boss encounter, and it is the enemy with the highest `power()`, ties broken by
`max_hp`. It scans dead units too, so killing the boss does not promote anybody
to the title. In era 1, where the enemy can only field infantry, everything ties
and the mark lands on whoever deployed first — still exactly one unit, which is
what the player needs to see.

### El tablero 3D (2026-10-12)

Decision del dueno: el combate se ve **en 3D, por turnos**, con el "flow" de
Empires & Allies como referencia de *sensacion* (nunca de arte). **Las reglas no
cambian**: el 8x8 de `Encounter` / `CombatRules` / `CombatAI`, el movimiento, el
alcance, la iniciativa y la IA son los mismos, y una pelea sembrada da el mismo
resultado en 2D y en 3D (`tools/battle_probe.gd`: victoria en 19 rondas con las
mismas bajas en las dos vistas). Solo cambia como se ve y como se siente.

**Donde vive.** Fuera de `scripts/combat/` (que son modelos puros):

| Pieza | Que hace |
|---|---|
| `scripts/combat_view/BoardViewport3D.gd` | `SubViewportContainer` a pantalla completa dentro de la vista del tablero de `BattleScreen`. Su `SubViewport` tiene **mundo propio** (`own_world_3d`): la luz y el cielo de la base no entran. Traduce toque / clic a casilla (`cell_pressed`), rueda y pellizco a un zoom leve, y da el tooltip de la casilla con raton |
| `scenes/combat/Board3D.tscn` + `scripts/combat_view/Board3D.gd` | La maqueta: camara, sol, entorno, terreno, marcas de casilla, piezas y la **cola de animaciones** |
| `scripts/combat_view/UnitToy3D.gd` | Una pieza: modelo horneado, barra de vida (dos `Sprite3D` en cartel), aros (rojo = se le puede pegar, laton = su turno, azul = en guardia) y las animaciones (saltitos, anticipacion, embestida, culatazo, sacudida, caida) |
| `scripts/combat_view/CombatFx3D.gd` | Fogonazo, trazadora, obus en parabola, polvo, numero de dano (`Label3D`), crater donde cae una pieza y la etiqueta de "quien es" |
| `scripts/combat_view/BoardTerrain3D.gd` | El terreno: losetas de hierba a dos tonos, alguna de tierra, craters pintados, y en el borde (fuera de las casillas) sacos terreros, arbolitos, piedras; todo sobre una peana y una mesa de guerra oscura. Una malla, semilla por encuentro |
| `scripts/combat_view/BoardLayout3D.gd` | Puro: casilla <-> mundo (2 m por casilla, la fila del jugador delante), la ruta casilla a casilla de un movimiento y la altura de cada dominio |
| `scripts/combat_view/UnitModels3D.gd` | Carga las piezas horneadas y el unico material que se anade: el del color de la colonia, **uno por color**, compartido |
| `scripts/combat_view/board_marks.gdshader` | Las marcas de casilla (alcanzable, objetivo, activa, bajo el puntero): una `MultiMesh`, el color por instancia en `INSTANCE_CUSTOM`, el latido con `TIME` |

**Como cuenta la pelea.** `BattleScreen` recibe los mismos eventos que antes
(`turn_started`, `unit_moved`, `unit_attacked`, `unit_defended`, `unit_died`) y,
con el tablero en 3D, se los pasa a `Board3D.push()`. Cuando llegan, el modelo
**ya** movio y ya pego: la maqueta solo los cuenta, uno detras de otro:

- `deploy` (al abrir): las piezas caen sobre la maqueta con rebote, la Regencia primero.
- `move`: la ruta casilla a casilla (`BoardLayout3D.path`, una BFS sobre lo que la
  VISTA tiene ocupado) con un saltito de juguete por casilla, mirando a donde va.
- `attack`: gira hacia el objetivo, anticipacion (se echa atras y se encoge), y
  segun el tipo (`Board3D.attack_kind`): la artilleria tira un obus en parabola
  con culatazo y un leve acercamiento de camara; la infanteria a una casilla
  embiste (bayoneta y descarga); el blindado dispara directo con trazadora. Al
  llegar: sacudida y aplastamiento del objetivo, polvo, numero de dano que salta
  y sube, la barra baja (la vista descuenta golpe a golpe: la vida del modelo
  puede ir por delante) y la imagen tiembla.
- `die`: la pieza se vuelca, se hunde y deja un crater.
- `defend`: aparece el aro azul de "en guardia".
- `turn`: aro de laton bajo quien actua; la camara se va un poco hacia el.

La cola acelera si se acumula trabajo (`_tempo()`), asi la vista nunca se queda
lejos del modelo; el ritmo del turno enemigo lo sigue marcando
`combat_ai_step_delay` en `CombatManager`, que no se ha tocado. Al vaciarse, la
maqueta se **reconcilia** con el `Encounter` (posicion, vida, guardia, "ya
actuo") por si algo no llego a animarse, y emite `idle`. Tambien emite
`event_played(ev)` al empezar cada evento (sondas, pruebas).

**Mientras anima no se juega** (`BattleScreen._board_busy()`): las casillas no
responden y los botones se apagan, para que el jugador nunca actue sobre algo
que aun no ha visto. Por lo mismo el parte del encuentro, el draft y el informe
final de la expedicion esperan a que la maqueta termine
(`BattleScreen._after_board_animations()`); en 2D todo eso sale al instante,
como siempre.

**Seleccion.** Igual que en 2D: la unidad que actua ya esta elegida (lo dice el
orden de iniciativa). Sus casillas alcanzables se encienden en azul, los enemigos
a tiro llevan aro rojo; tocar una casilla encendida mueve, tocar un enemigo con
aro ataca. Tocar cualquier otra pieza (propia, o enemiga fuera de alcance) dice
quien es encima de ella ("Infanteria · 80/100", y JEFE): con el dedo no hay
tooltip. Con raton, la casilla bajo el puntero se marca y el tooltip lo dice.

**Bandos y marcas.** Los nuestros con el color de la colonia
(`RankManager.get_color()`) y peana **redonda**; los recaudadores de la Regencia
en su morado (que no lleva ninguna colonia) con peana en **rombo**: el bando se
lee por la forma, como el circulo / rombo del tablero 2D. El jefe (el mismo que
elige `BattleScreen.boss_uid()`) es algo mayor y lleva estandarte y aro de
laton; las dotaciones de torre (`Encounter.back_row_uids`) llevan su nido de
sacos terreros.

**Camara.** Perspectiva estrecha (34 grados), picado de 52 y giro de -24: la
maqueta en tres cuartos. Se encaja sola en el hueco entre la cabecera y los
botones (`Board3D._fit()`: busca la distancia y corre la imagen con
`h_offset` / `v_offset`). Sigue la accion con suavidad (como mucho 1,1 m), hace
un leve vaiven en reposo (no en calidad sencilla) y deja acercar un poco con la
rueda o el pellizco (0,82-1,12).

**Las piezas** se hornean con la misma herramienta que los edificios:

```bash
godot --headless --path . -s tools/build_toy_models.gd -- --units
```

Recetas en `tools/toy_recipes/units/` (`infantry`, `artillery`, `vehicle`, mas el
atrezo `boss_mark` y `crew_nest`; piezas comunes en `_unit_parts.gd`), salida en
`assets/models/toy/units/<id>_player.tscn` / `<id>_regency.tscn` con su
`_mesh.res`. Una malla con color por vertice y los dos materiales de la maqueta;
las del jugador llevan ademas una superficie `team` en grises que la vista pinta
con el color de la colonia (`toy_team.tres` es solo el de por defecto). Marcadores
`Muzzle` (de donde sale el disparo) y `Top` (la barra va encima). Triangulos:

| Pieza | Jugador | Regencia |
|---|---|---|
| Infanteria (escuadra de tres soldaditos) | 564 | 474 |
| Artilleria (canon con escudo y artillero) | 510 | 418 |
| Vehiculo (blindado diesel; la Regencia, "caldera de cobro" con dos chimeneas) | 510 | 516 |
| Estandarte del jefe / nido de la dotacion | 230 / 180 | |

**Rendimiento** ("tiene que ir en una papa"). Una sola luz direccional para todo
el tablero (ninguna por pieza), con sombra solo si la calidad la tiene; terreno
de una malla; marcas en una `MultiMesh`; piezas de 400-600 triangulos con los
materiales compartidos; efectos de una o pocas mallas diminutas con material sin
luz y sin particulas de GPU; todo animado con tweens, ningun `_process`. Y,
sobre todo: **mientras el tablero 3D esta en pantalla el 3D del mapa se apaga**
(`Viewport.disable_3d` en la ventana, `BattleScreen._sync_world_render()`), porque
la maqueta lo tapa entero. Se devuelve al cerrar el tablero o volver al mapa de
la expedicion (y en `_exit_tree`).

Por calidad (`WorldLook.settings_for()`): **alta**, sombra de un corte y MSAA x2
en el SubViewport, polvo y vaiven; **baja**, sombra, sin MSAA, sin polvo ni
vaiven; **minima**, sin sombras, sin MSAA, sin polvo ni vaiven y el 3D a 0,7 de
resolucion (`scaling_3d_scale` del SubViewport; la UI no se escala).

Medido con `tools/battle_probe.gd -- --no-title --fps` (sin vsync; ventana
1280x800; NVIDIA RTX 3060 Laptop; la pelea animandose mientras se mide; GPU = ms
por fotograma de la ventana mas el SubViewport):

| Renderizador | Calidad | Mapa solo | Tablero 3D | Tablero 2D (sobre el mapa) |
|---|---|---|---|---|
| Forward+ | alta | 310 fps · 0,73 ms | 305 fps · 0,73 ms | 223 fps · 1,82 ms |
| Forward+ | baja | 286 fps · 1,25 ms | 370 fps · 0,62 ms | 264 fps · 1,26 ms |
| Forward+ | minima | 362 fps · 0,62 ms | 351 fps · 0,39 ms | 306 fps · 0,65 ms |
| Mobile | alta | 330 fps · 0,52 ms | 283 fps · 0,56 ms | 269 fps · 1,19 ms |
| Mobile | baja | 246 fps · 0,96 ms | 383 fps · 0,51 ms | 269 fps · 1,00 ms |
| Mobile | minima | 293 fps · 0,47 ms | 323 fps · 0,32 ms | 286 fps · 0,49 ms |
| Compatibility | alta | 90 fps | 80 fps | 64 fps |
| Compatibility | baja | 74 fps | 80 fps | 67 fps |
| Compatibility | minima | 83 fps | 80 fps | 67 fps |

(En Compatibility el tiempo de GPU que da Godot no es fiable; solo los fps.)

**Decision para la calidad minima: 3D simplificado, no el 2D.** La maqueta
cuesta en GPU lo mismo o menos que el mapa que ese equipo ya tiene que mover
(Mobile minima: 0,32 ms contra 0,47), porque el mapa deja de dibujarse mientras
ella esta en pantalla; el tablero 2D, en cambio, se pinta ENCIMA del mapa (su
fondo es translucido) y sale el mas caro de los tres en todas las filas. Quien
mueve el mapa mueve la pelea. El tablero 2D de siempre se queda como
alternativa donde tiene sentido (`BattleScreen.pick_board_style()`): en la
**vista 2D del mapa** (el jugador eligio lo plano) y **sin pantalla** (pruebas
headless, que fijan su lectura). `BattleScreen.force_board_style()` lo fuerza
para pruebas y sondas.

**Lo que no se ha tocado:** `CombatManager`, los modelos (salvo `domain`, §11) y
el sonido: `AudioManager` sigue sonando con las senales, asi que el golpe suena
cuando el modelo pega y la maqueta lo ensena unas decimas despues (la
anticipacion es corta a proposito).

Capturas: `tools/battle_probe.gd` (ver §9) deja `docs/media/dev/battle_<tag>_*.png`.

### Segunda tanda: leer la pelea (2026-10-12/13)

- **Ventaja por tipo** (piedra-papel-tijera). Circulo de tierra: artilleria >
  vehiculo > infanteria > artilleria (`GameConfig.combat_type_advantage`:
  `beats`, `advantage` 1,5, `disadvantage` 0,75). Va sobre el dano neto en
  `CombatRules.damage()` (redondeado, nunca menos de 1), asi que la aplican
  igual el jugador, `CombatAI` y `AutoResolver`. `CombatRules.type_matchup()`
  da +1 / -1 / 0. La IA la usa como segundo criterio de objetivo (tras "lo
  puedo matar"). Mar y aire entrarian anadiendo su fila (§11). Efecto medido en
  el asedio y propuesta pendiente en [17](17-balance-asedio.md) §"Ventaja por tipo".
- **Placa de vida** amarilla con el numero sobre cada pieza (`UnitToy3D`), **aro
  azul** del que actua, **mira roja** sobre los objetivos y la etiqueta
  "¡Buen objetivo!" / "Mal objetivo" (`BattleScreen.target_hints()`,
  `LBL_GOOD_TARGET` / `LBL_BAD_TARGET`).
- **Escenarios** de decorado (`BoardTerrain3D.SCENES`: tierra, playa, bosque),
  elegidos por semilla; en casa (Diezmo, asedio) casi siempre playa. Solo
  decorado: ni casillas ni reglas cambian.
- **x1 / x2 en la cabecera** del tablero (el del HUD queda tapado): las
  animaciones duran la mitad (`GameConfig.combat_pace`). La cabecera y los
  botones parten en dos filas en un movil (`HFlowContainer`).

### Las dos vistas (2026-10-14)

Decision del dueno: **dos vistas de combate**, elegibles, sobre la misma pelea.

| Vista | Que se ve | Como se juega |
|---|---|---|
| **Frente** (`"front"`, por defecto) | Los dos bandos cara a cara al estilo de Empires & Allies (solo el estilo: nada de su arte): los nuestros abajo a la izquierda, la Regencia arriba a la derecha, camara baja de costado (picado 30, giro 60, 30 de campo), un campo seguido hasta el horizonte con la tierra de nadie batida en medio, sacos terreros delante de cada bando y arboledas lejanas. **Ninguna casilla a la vista** | Tocar a un enemigo con mira: la unidad se acerca lo justo y dispara. **AVANZAR** acerca sin disparar. Defender / Esperar / Terminar como siempre. **Mover**: los sitios a los que llega la unidad se iluminan como **manchas** en el suelo (discos, no casillas) y se tocan para ir |
| **Tablero** (`"board"`) | El 8x8 3D de siempre, con las casillas marcadas | Tocar casilla encendida mueve, tocar enemigo con aro ataca |

**Es la misma maqueta.** `Board3D.set_style()` cambia solo camara, suelo
(`BoardTerrain3D.build(..., front)`: un plano de campo en lugar de 64 losetas),
la forma de las marcas y el sitio y tamano de las piezas; cola de animaciones,
efectos, placas y aros son los mismos.

- **Sitios, no casillas.** En el frente cada casilla se dibuja en su "sitio
  libre": el centro corrido hasta `BoardLayout3D.SPOT_JITTER` (0,38 m, menos de
  media casilla) por un hash de la casilla y la semilla
  (`BoardLayout3D.spot_offset`). Siempre el mismo para la misma casilla: las
  piezas no tiemblan y la mancha que se ilumina es justo donde acaba la pieza.
  Tocar el sitio cae en su casilla, asi que el toque no cambia.
- **Manchas.** Las marcas de mover del frente son discos de borde suave
  (`Board3D._front_spot_mesh`) en la misma `MultiMesh` y con el mismo shader;
  turno y objetivos ya los dicen el aro azul, el aro rojo con la mira y la
  etiqueta de ventaja, asi que en el frente solo se iluminan los sitios.
- **Piezas mayores**: x1,3 en el frente (`FRONT_UNIT_SCALE`,
  `UnitToy3D.set_view_scale`).
- **Placas y etiquetas que no se pisan** (2026-10-16). Con las piezas x1,3 y
  juntas, las placas de vida y las etiquetas de objetivo ("-18 de 75",
  "¡Buen objetivo!") de todos los enemigos a tiro se montaban unas sobre otras.
  En el frente: la etiqueta de objetivo sale **solo en la unidad en foco** (la
  que esta bajo el puntero; con el dedo, la que se pisa mientras se mantiene),
  con el pie encima de su chapa y en la capa mas alta (`HINT_PRIO`); aros y
  mira siguen en todos. Las placas de la unidad activa y la del foco van
  enteras y por encima (`PRIO_FOCUS`); las demas, compactas
  (`UnitToy3D.PLATE_COMPACT`) y `Board3D._layout_plates` las sube, de abajo
  arriba de la pantalla, lo justo para no tocar a ninguna ya colocada (medido
  con la camara, no por resolucion); si tendria que subir mas de un alto de
  placa, se apaga en su sitio. Se recoloca por evento (estado, foco, cola
  vacia, cambio de vista), nunca por fotograma. En el tablero 8x8 nada de esto:
  todas las etiquetas y placas como antes.
- **La linea entre bandos** (`BoardTerrain3D._divider`), a ras de suelo y con
  huecos, segun el escenario: un arroyo con piedras de paso en campo abierto, la
  linea de la marea en la playa, un seto bajo a trozos en la linde del bosque.
  Se cruza como cualquier casilla: el decorado no insinua obstaculos. Por eso se puede cambiar **a mitad de
pelea** sin rehacer nada (si la maqueta esta contando algo, al terminar).

**El mismo modelo.** El frente no tiene reglas propias:
`scripts/combat_view/FrontOrders.gd` (puro, de solo lectura) traduce las intenciones
del frente a las acciones de siempre:

- `approach_cell(enc, uid, target)`: la casilla alcanzable desde la que el
  objetivo queda a tiro con el camino mas corto (a igualdad, la mas lejana del
  objetivo: la artilleria no se mete encima); la propia si ya esta a tiro;
  `NO_CELL` si no se le llega este turno.
- `reachable_targets(enc, uid)`: los enemigos a los que se llega este turno
  (los que llevan mira en el frente; en el tablero solo los que ya estan a tiro).
- `advance_cell(enc, uid)`: la casilla a la que iria `CombatAI` con esa unidad
  (AVANZAR), sin atacar.

`BattleScreen.order_attack()` ejecuta "acercate y dispara" como
`CombatManager.move_unit()` + `CombatManager.attack()`: las dos mismas llamadas
que haria el jugador a toques en el tablero. Jugada igual, una pelea da lo
mismo en las dos vistas (`tests/ui/test_combat_views.gd`).

**La preferencia** es del dispositivo, no de la partida:
`GameConfig.ui_combat_view` (`COMBAT_VIEWS = ["front", "board"]`), en
`settings.cfg [interfaz] combat_view`; un valor desconocido vuelve a "front".
Se elige en Ajustes → Interfaz → Vista ("Vista del combate", fila
`CombatViewRow`) y con el boton de la cabecera del combate (`BoardViewToggle`,
dice a donde lleva: TABLERO / FRENTE), que la guarda. Restablecer la interfaz la
devuelve a "front". Pruebas y sondas: `BattleScreen.force_combat_view()`,
`tools/battle_probe.gd -- --view=front|board`. Con el tablero 2D (vista 2D del
mapa, headless) el selector de la cabecera no sale: no hay frente en 2D.

**Calidad minima: tablero.** Con `ui_graphics_quality` "minimal" la vista es
el tablero aunque la preferencia diga frente (`BattleScreen.combat_view()`): es
la vista medida mas barata (0,32 ms de GPU en Mobile minima, arriba) y el frente
pinta mas suelo hasta el horizonte, arboledas lejanas y cielo. La preferencia
no se toca: al subir la calidad vuelve el frente.

**Rendimiento.** El frente cuesta lo mismo o menos que el tablero: el suelo es
una malla con MENOS cajas (un plano de campo y unas manchas en vez de 64
losetas con sus matas), las marcas son la misma `MultiMesh` de 64 instancias con otra malla (un disco), y los arboles lejanos son 6
(sencilla) o 14 (alta) arbolitos de tres primitivas dentro de la misma malla
(una llamada de dibujo). Sin luces nuevas, sin `_process`, sin particulas. La
camara mas baja ensena mas suelo, que es un plano sin luz extra; la sombra
sigue el mismo reglaje por calidad. **Sin medir todavia** con
`battle_probe --fps` (pendiente del pase final, ver docs/26).

### Mar y aire en la maqueta (1.1, rama `feat/aire-mar-vista`)

La VISTA de las seis unidades de mar y aire y del agua del tablero. Las reglas
(quien pisa que, quien pega a quien, el terreno de cada encuentro) son de la
rama `feat/aire-mar-reglas`; esta vista solo pinta lo que el modelo diga y
funciona igual sin ella (todo lo que lee es `CombatUnit.domain()` y, de forma
defensiva, `encounter.get("terrain")`).

**Las piezas** (`tools/build_toy_models.gd -- --units`, recetas en
`tools/toy_recipes/units/<id>.gd`, piezas comunes nuevas en `_unit_parts.gd`:
`hull`, `sea_stand`, `funnel`, `turret`, `prop`, `ellipsoid`, `roundel`):

| Pieza | Dominio | Lo exagerado | Jugador | Regencia |
|---|---|---|---|---|
| Lancha torpedera (`torpedo_boat`) | mar | los dos tubos lanzatorpedos | 345 | 275 |
| Canonera (`gunboat`) | mar | la torreta de proa con un canon gordo | 324 | 302 |
| Acorazado (`dreadnought`) | mar | dos torretas de canones dobles, dos chimeneas | 478 | 438 |
| Caza (`fighter`) | aire | biplano con la helice enorme | 356 | 366 |
| Bombardero (`bomber`) | aire | bimotor con las dos bombas bajo la panza | 486 | 474 |
| Dirigible (`airship`) | aire | la envuelta con franjas del bando | 456 | 480 |

Todas por debajo de 800 (prueba `tests/ui/test_sea_air_view.gd`), con la
superficie `team` del color de la colonia en las nuestras (el regimiento la
pinta igual que en las de tierra, y su insignia sale en la placa) y el morado
horneado en las de la Regencia. Marcadores `Muzzle` y `Top` como siempre.

- **El bando por la forma, tambien aqui.** Un barco no lleva peana: lleva una
  mancha de **espuma** (que ademas es su estela, abierta en V por la popa) con el
  canto del bando, redonda los nuestros y en rombo la Regencia. Un avion tampoco:
  su **sombra en el suelo** es redonda o en rombo (`UnitToy3D.shadow_mesh`, dos
  mallas para todo el tablero). La sombra solo la llevan los de aire: sobre el
  agua no hay sombra.
- **Altura**: `BoardLayout3D.DOMAIN_HEIGHT` (mar -0,12, con la flotacion de la
  pieza en `_unit_parts.WATERLINE`; aire 1,7 y la pieza montada desde
  `AIR_Y` = 0,3 para que el oscurecimiento de contacto no le ensucie las alas).
- **Vaiven**: el de siempre (un tween en bucle en `_lift`, ningun `_process`),
  ahora por dominio (`UnitToy3D.BOB`: el barco 5 cm cada 1,6 s, el avion 12 cm
  cada 1,1 s) y desfasado por uid. En calidad baja y minima no hay vaiven
  (`calm`, la misma regla que el giro leve de la camara).
- **Moverse** (`UnitToy3D.move_along`): tierra a saltitos (`hop_along`); mar
  deslizandose casilla a casilla con una escora leve (`sail_along`), y su ruta
  dibujada no corta por tierra (`BoardLayout3D.route_blocked`); aire despega,
  vuela en linea recta al final de la ruta y aterriza (`fly_along`).
- **Atacar** (`Board3D.attack_kind`): el acorazado, el bombardero y el
  dirigible tiran en parabola (el obus de la artilleria); la lancha, la canonera
  y el caza disparan directo. Sin efectos nuevos.
- **Caer**: el barco levanta la proa y se hunde (y deja espuma, no crater); el
  avion cae en barrena hasta su sombra y deja crater.

**El agua del tablero** (`BoardTerrain3D.build(..., terrain)`). Las casillas
`"water"` son la misma lamina de mar de la playa, 7 cm por debajo de las
losetas (`BoardLayout3D.WATER_TOP`), sin junta entre una y otra, con una onda
clara y espuma en los lados que dan a tierra; las `"shore"`, losetas de arena.
Las marcas de casilla y las ✕ bajan a la lamina en el agua. Todo en la misma
malla del terreno: ni una llamada de dibujo mas. Con agua, la maqueta abre en
el escenario playa (`BattleScreen.board_scene_for`). Que casillas se iluminan
para mover lo sigue diciendo `valid_moves` del modelo: la vista no filtra nada.

**El frente.** Las casillas de agua son manchas de mar sobre el campo (y arena
las de orilla), algo mayores que la casilla para que no se vea rejilla; los
barcos flotan en ellas y los aviones van arriba, a su altura, con la sombra
debajo. Donde hay agua no se pintan craters, matas ni la linea entre bandos.
Donde cae el agua lo decide el terreno de las reglas (la propuesta de
`docs/15 §11`: una franja de agua en un lado o al frente).

**El tablero 2D** (`BattleScreen._style_cell`): las casillas vacias de agua se
pintan con `UITheme.BOARD_WATER` (INFO oscurecido) y las de orilla con
`BOARD_SHORE`; "puedes ir aqui" (`BOARD_MOVE`) manda sobre ellas. Las seis
siluetas nuevas salen de `tools/gen_unit_icons.gd` (barcos de perfil con la
proa a la derecha, aviones vistos desde arriba, el dirigible de perfil) a 64 y a
24 / 42 / 60 / 96 px.

### Enseñar el combate (2026-10-14, rama `feat/ensenar-combate`)

Diseño: `tormenta-imperial-contexto/21_REDISENO_CICLO_Y_CONTENIDO.md` §4.1-4.3. Tres
piezas, las mismas en las dos vistas 3D (frente y tablero) y en el tablero 2D. Todo lo
que se calcula sale de `CombatRules` (puro) y se recalcula en `BattleScreen._refresh()`,
que corre **por evento** del combate, nunca por fotograma.

**Vistas previas (`CombatRules`, solo funciones nuevas):**

| Función | Qué da | Dónde se ve |
|---|---|---|
| `preview_damage(attacker, target)` | `{damage, hp, max_hp, hp_after, kills, matchup, mult}`; usa `damage()`, así que la ventaja por tipo, la guardia y la moral ya van dentro. No toca a nadie | encima de cada objetivo: "-18 de 75" o "-75 ¡Cae!" (`LBL_PREVIEW_*`), junto a "¡Buen objetivo!" en la misma etiqueta 3D (`UnitToy3D.set_target_hint(matchup, preview, blocked)`); en 2D una etiqueta por casilla (`BattleScreen.board_cell_preview()`); con ratón, también en el tooltip |
| `threat_cells(units, side, board)` | toda casilla a la que alguna unidad viva de `side` llega y dispara en su próximo turno (su movimiento entero + su alcance) | botón **Ver alcance enemigo** (`BattleScreen.toggle_threat()`, del jugador, no se guarda): casillas naranjas (`Board3D.Mark.THREAT`; las azules que además están en peligro, `MOVE_THREAT`); en el frente salen como manchas. Se cachea por posiciones de los vivos |
| `min_range_cells(unit, board)` | las casillas dentro del alcance mínimo (la artillería: las cuatro de al lado) | una ✕ (`Label3D`, como mucho cuatro, reutilizadas) y casilla roja oscura (`NO_FIRE`); el enemigo que está ahí dice "✕ Muy cerca" en rojo |
| `fire_cells_from(unit, from, board)` | las casillas entre alcance mínimo y máximo | solo en el paso 6 del combate guiado (`FIRE`, rojo claro) |

`Board3D.set_overlays(threat, no_fire, fire)` pinta esas capas por debajo de las marcas
de turno (`overlay_mark()`: mover/atacar/activo mandan). Los valores nuevos de `Mark`
van al final del enum.

**Ficha de unidad (`scripts/ui/UnitCard.gd`):** vida, ataque, defensa, movimiento,
alcance (con "Dispara de 2 a 3 casillas" y "No dispara a quien tiene al lado" en la
artillería), fuerte contra / débil contra con la silueta y el multiplicador (×1,5 /
×0,75), y una frase (`UNIT_<ID>_CARD_TIP`). Iconos dibujados (`StatGlyph`), sin emojis
(la fuente no los garantiza). Números de `combat_unit_stats` y `combat_type_advantage`,
o de la unidad viva (mejoras, moral). Se abre al **tocar una pieza** (propia, o enemiga
que no se puede atacar) en cualquier vista — sigue a su unidad y se cierra si cae — y
con el botón **FICHA** de cada fila del Cuartel (`ArmyPanel.toggle_unit_card()`). La
selección de tropa (`SkirmishPanel`) aún no la lleva: es de la rama de escaramuzas.

**Combate guiado:** `TutorialManager` (docs/23 §2.4) decide el paso;
`BattleScreen.coach_anchor(target)` dice dónde está lo señalado en pantalla (una pieza o
una casilla 3D como punto, en 2D o un botón como rectángulo, `{"busy": true}` mientras la
maqueta anima); `TutorialPanel` pinta la tarjeta, la flecha y el aro en la capa 19,
encima del tablero. Tocar una pieza propia cuenta como el paso 1
(`TutorialManager.note_combat_fact("selected")`). Durante el paso 4 se ve el alcance
enemigo aunque el botón esté apagado (`BattleScreen.threat_visible()`).

**Simulacro (§4.4 del diseño): no hecho.** Pide un edificio nuevo y un `is_practice` en
`CombatManager`, que es de la rama de escaramuzas: queda para cuando esa rama entre.

### Turn flow

1. `start()` → `_begin_round()`: every living unit gets `begin_turn()` (clears
   `has_acted`, `moved_this_turn`, `defending`), then `CombatRules.build_turn_order()`
   sorts by initiative descending. Ties go to the player, then to the lower uid —
   the order is stable and observable.
2. `_advance()` walks to the next unit that can still act, setting `state` to
   `PLAYER_TURN` or `ENEMY_TURN` and emitting `turn_started`.
3. When the order is spent the round number rises. Past `combat_turn_limit`
   (20 rounds) the encounter is force-resolved.

### Actions

| Method | Ends the turn? | Notes |
|--------|----------------|-------|
| `move_unit(uid, to)` | **No** | A unit may move then attack, never move twice. Occupied cells block the BFS, so units cannot walk through each other |
| `attack(uid, target)` | Yes | Damage is `maxi(1, attacker.attack_power() - target.defense())` — deterministic on purpose, and never zero so a fight cannot stall |
| `defend(uid)` | Yes | Doubles `defense()` until the unit's next `begin_turn()` |
| `wait_unit(uid)` | Yes | |
| `end_turn()` | Yes | Closes whoever is active |

`in_attack_range()` uses Manhattan distance and enforces both `min_range` and
`range`. Artillery (`min_range` 2) cannot fire at an adjacent target: that single
rule is what makes positioning matter.

### Resolution

- Enemy side wiped → `WON`. Player side wiped → `LOST`.
- Round limit passed → `TIMEOUT`, decided by `CombatRules.resolve_timeout()`:
  the side with more total HP takes it, **and a tie is a player loss**. Stalling is
  a losing strategy by design.

### Enemy turns

`CombatManager._run_enemy_turn()` asks `CombatAI.plan_turn()` for a list of steps
and executes them with `GameConfig.get_combat_ai_step_delay()` seconds between
each (halved in dev mode), so the player can follow what hit them. It closes the
unit's turn afterwards if the plan did not.

Each board has a generation number (`_board_generation`), bumped whenever a
board opens or closes. The enemy-turn coroutine remembers the one it started on;
if it wakes up after an `await` on a different board it returns without acting,
without releasing `_enemy_turn_running` and without relaunching a turn. Before
that, closing a board mid-think and opening another left two enemy loops driving
the new one.

`CombatAI` is deliberately simple: score every reachable cell (a cell that lets
the unit shoot this turn is worth `SCORE_CAN_ATTACK` = 1000 more than any amount
of walking), move there, focus the lowest-HP target in range, break ties toward
the higher-`power` unit, and entrench (`defend`) when nothing is reachable. It
takes `rival_side(unit.side)`, so the same AI drives the enemy on the board and
either side under `AutoResolver`.

### `is_board_open()` is not `is_in_encounter()`

Two queries on `CombatManager` that read like synonyms and are not. Confusing them
cost three serious bugs. **"There is a fight" is not "there is a board."**

| Query | True when |
|-------|-----------|
| `is_in_encounter()` | `_encounter != null` **and** `_encounter.is_active()` — somebody still has a turn to take |
| `is_board_open()` | `_encounter != null`, full stop |

The gap between them is the stretch where the fight has resolved and the player
is **reading the after-action report**. The encounter object still exists, the
screen is still up, and nobody is acting. That stretch counts as board open.

Anything that asks "may I put a board on screen?" must ask `is_board_open()`.
`StormManager._begin_tithe()` does exactly that: with the board open it calls
`auto_resolve_defense()` instead, because opening the Tithe defence over an
unread report wipes the report off the screen before the player has seen it.
`CombatManager.start_defense()` refuses on `is_board_open()` for the same reason.

Anything that asks "is the player mid-fight?" — gating a launch, driving a turn —
asks `is_in_encounter()`: `start_skirmish()`, `select_node()`,
`enter_current_node()`, `SkirmishPanel.evaluate_launch()`.

The seams between the two live in `tests/storm/test_board_handoff.gd`.

---

## 4. The expedition

One roguelike run: march out with a committed party, fight a chain of encounters
across a branching map, and settle up only when the column comes home.

> Implemented and tested at the service level
> (`tests/combat/test_expedition_wiring.gd`) **and driven by the interface**:
> `SkirmishPanel` commits the party and calls `launch_expedition()`;
> `BattleScreen` draws the map, the draft modal and the final report
> (`tests/ui/test_expedition_ui.gd`).

### The map is a seed

`ExpeditionGenerator.generate_map()` builds a layered graph from a single
`RandomNumberGenerator`:

- Depth 0 is always a single, low-risk opening node.
- `combat_map_depth` layers of `combat_map_branching` nodes each follow.
- The boss is the last layer, always alone, always risk 2.
- Edges only run from one layer to the next. Two passes — every parent gets exits,
  then every unadopted child gets a parent — guarantee the invariant that
  **every node reaches the boss**, with no repair pass. `every_node_reaches_boss()`
  exposes it for tests.
- Risk is rolled at 45% / 37% / 18% for low / medium / high, so high risk reads as
  a choice the player made, not the map's default mood.
- Rosters are assigned last, in index order, so the RNG stream stays stable if the
  linking code changes.

`Array.shuffle()` is banned here — it reaches for the global generator.
`_shuffled()` is a Fisher-Yates against the expedition's own RNG.

### The first sortie

The first fight of a game is not a full expedition. With the normal map, a lone
infantry fresh from the Barracks walks into node 0 (two full-strength infantry) and
loses it in almost every seed, so the player's first contact with combat was a
defeat — or nothing at all, because nothing in the game pointed at it. Now:

- **The step.** As soon as one unit stands at home, `Objectives.next_step()` asks
  for it (`kind: "sortie"`, "Lanza tu primera escaramuza: MENÚ > ESCARAMUZAS"),
  **before** the five-unit garrison and before any other line step. Not with a
  column already out, nor with the Final Audit summoned or under way. The route
  shows it as its own row just before the garrison.
- **The tip.** The first `unit_trained` offers `first_sortie` (`TutorialManager.TIPS`,
  `HelpCatalog`, category army): a tip card whose blue frame points at ☰ MENÚ, where
  ESCARAMUZAS lives (`TUT_TIP_FIRST_SORTIE_BODY`, with a `_TOUCH` variant). It goes
  out before the upkeep tip that the same signal triggers.
- **The run.** `SkirmishPanel` launches with
  `CombatManager.launch_expedition(party, 0, CombatManager.is_first_sortie_due())`.
  When that flag is true, `Expedition.create(..., first_sortie = true)` swaps the
  generated map for `ExpeditionGenerator.first_sortie_map()`: **one node**, depth 0,
  risk 0, no exits, not a boss, carrying its own `enemy_roster`, `enemy_scale` and
  `rewards` (`GameConfig.combat_first_sortie_*`). `node_scale()` and `node_rewards()`
  prefer those fields to the depth/era/risk curve, so the fight is the same in every
  era. Winning the node ends the run won (`Expedition.at_end()`: the boss, or a node
  with no exits — in a generated map only the boss has none), with no draft.
- **Done.** `TutorialManager.first_sortie_done` goes true on the first
  `expedition_ended` with `RESULT_WON`. Losing or abandoning does not spend it: the
  next launch is the easy one again. It travels in the save (`"tutorial"` key),
  `reset()` clears it, loading is idempotent, and a save without the key derives it
  from the `expedition_map` tip (whoever saw it has been on an expedition before).
  The `expedition_map` tip is held back for the first sortie, which has no map.
- **Saved mid-run.** `Expedition.to_dict()` carries `first_sortie`; `from_dict()`
  rebuilds the single node instead of the seed's map. A save without it is a normal
  expedition.
- `launch_expedition()` without the third argument is a normal expedition: the tests
  and probes that launch with a seed keep their maps. `tools/line_probe_player.gd`
  answers the `sortie` step the way the panel says.

Measured in `tests/combat/test_first_sortie.gd` with `AutoResolver` (the same AI on
both sides), 50 seeds, launch morale spread 0-100: one infantry wins it **46 of 50
(92%)**, about 12 rounds, coming home with ~69% HP on average (the losses are the
lowest-morale launches); two infantry win 50 of 50. On the normal node 0 the same
lone infantry wins **0 of 50**, and two infantry 25 of 50. Loot: 150 gold + 100 wood, against 60 + 30 for a normal
node 0 — a quarter of the era-1 bag, and almost four times what the infantry cost.

### Nodes and rosters

`enemy_pressure(depth, era, risk)` sums `combat_enemy_scale_per_depth`,
`combat_enemy_scale_per_era` and `combat_risk_enemy_scale`. It drives two things
at once: the number of bodies (`combat_enemy_base_slots * pressure`, clamped to
`combat_deploy_cap`) and the HP/ATK multiplier handed to `CombatUnit.create()`.
The boss multiplies both by `combat_boss_multiplier` and adds one unit of the
highest tier the era fields.

Composition is a line of infantry with guns behind it, plus armour once era 3
allows it and the slot count reaches 4 — enough shape that artillery's minimum
range matters from the first node.

### The draft

After a won non-boss node, `_offer_draft()` puts `combat_draft_options` (3) cards
on the table, rolled from `draft_rng(seed, node_index)` — an independent stream,
so drafts stay reproducible across a save/load even though the map generator is
not replayed alongside them.

Five catalogue entries: `+atk`, `+def`, `+move`, `+initiative`, and a heal. With
more than one unit type alive, a 40% roll narrows the card to one type and doubles
its value (`combat_draft_focus_multiplier`); healing never doubles. Only
*applicable* options are offered — a field station is not on the table for a party
at full health (`is_applicable()`).

Bonuses live in `CombatUnit.draft_bonuses` and die with the expedition. There is
no meta-progression.

While a draft is pending, `select_node()` and `enter_current_node()` both refuse:
first the card, then the route.

`Expedition.can_select()` also requires the current node to be **cleared**
(`is_current_cleared()`). `needs_fight()` is the opposite state — standing on a node
nobody has won yet — which is exactly what a save made mid-node reloads into.

### Attrition, permadeath, lockout

- **Attrition.** `build_encounter_units()` hands the board the *same*
  `CombatUnit` instances that live in `Expedition.party`. The board damages them
  directly, so a survivor walks into the next node wounded. Nothing heals between
  nodes; HP only comes back at the base, and only because the party objects are
  discarded when the run resolves.
- **Permadeath.** A fallen unit stays in `party` as a casualty. `living_party()`
  and `_living()` skip it; a draft never brings anybody back.
- **Lockout.** `get_units_on_expedition()` counts the whole party, living and
  fallen. `get_garrison()` subtracts it, so units on campaign do not defend the
  base, and `get_deployable_units()` subtracts it too. `ArmyManager` is **not**
  debited at launch — Military Power never lies mid-run — the dead are struck off
  only at settlement.

### Settlement

`_resolve_expedition()` runs exactly once, when the model emits `expedition_ended`:

1. Accumulated `rewards` go into `ResourceManager` (the shared pool trims and fires
   `storage_overflow` on its own).
2. `ArmyManager.remove_units(casualties)`.
3. `PopulationManager.adjust_morale(CombatRules.morale_delta(won, dead))` — a
   costly victory can still leave the town worse than it started.
4. `EventBus.expedition_ended.emit(result, rewards, casualties)`.

`result` is `0` won, `1` lost, `2` abandoned. Abandoning (`abandon_expedition()`)
keeps the loot and the survivors: quitting while ahead has to be a real option.
Abandoning closes **only the expedition's own board** (`_is_expedition_board()`):
a Tithe defence opened between two nodes stays on the board and resolves normally,
because swallowing its `encounter_ended` left `StormCycle` stuck in `TITHE`.
`BattleScreen` does not offer the abandon button on a defence board.

### What is saved and what is regenerated

`CombatManager.get_save_data()` writes `Expedition.to_dict()` plus a
`draft_pending` flag into `data["expedition"]` (see `GameManager`).

| Saved | Regenerated on load |
|-------|---------------------|
| `id`, `seed`, `era`, `current_node`, `state`, `morale_snapshot` | The whole `map` — rebuilt from the seed, then repainted with the saved `cleared` indices |
| `party` (each unit's uid, type, hp, max_hp, draft bonuses, scale) | `morale_attack_mod` / `morale_initiative_bonus` — pure functions of `morale_snapshot` |
| `draft_picks`, `rewards`, `cleared` | The draft cards, from `draft_rng(seed, node)` — the same three cards come back |
| `draft_pending` (service state, not model state) | |

The **encounter in progress is never saved**. On load the party carries its current
HP and the node is still uncleared, so the board is redeployed from scratch.
`load_save_data()` emits `expedition_resumed`. `BattleScreen` answers it by
reopening the map view (and `game_load_completed` covers the same ground when the
signal is not there), so the player lands back on the campaign map and re-enters
the node themselves rather than being dropped straight onto a board. On that map
the current uncleared node is the only enabled button (tooltip `LBL_NODE_FIGHT`);
pressing it calls `enter_current_node()`. No exit lights up until the node is won,
so a reload can no longer walk past an unfought node. A save with
no `expedition` key simply means no expedition and is never an error.

`era` is stored on top of the documented schema because the rosters depend on it:
the player can reach a new era while a run is paused.

---

## 4b. Salidas cortas, botín exclusivo, retirada y "resolver solo" (2026-10-14)

Rama `feat/escaramuzas`, doc de contexto 21 §3 y §8 filas 1.1-1.3, decisiones de Bryan
D2 = A, D3 = A, D6 = A, D7 = B. **Sin probar todavía** (pase final único).

### El tablón (`SortieBoard`, modelo puro)

`scripts/combat/SortieBoard.gd` guarda las ofertas a la vista, cuándo llega la
siguiente, los planos conseguidos y el apunte de la rebaja del Diezmo. No emite ni
sortea: `CombatManager` le da el reloj (`ProgressionManager.get_played_seconds()`) y las
semillas (`refresh_sorties()`, un `Timer` de `combat_sortie_refresh_interval` = 2 s,
pausable). Una oferta es `{id, kind, flavor, seed, era, blueprint, seen}` y **con ella se
rehace el mapa entero** (`ExpeditionGenerator.sortie_map()`), así que el jugador lo ve
antes de salir y el guardado solo lleva la oferta.

| Tipo | Combates | Cuándo aparece | Botín exclusivo |
|---|---|---|---|
| Incursión: saqueadores | 1 (profundidad `combat_raid_depth` 1) | Con Cuartel y la primera escaramuza ganada; una a la vez; `combat_raid_cooldown` 240 s de juego tras gastarla | Repuestos 1-2, colonos 2-4 |
| Incursión: avanzadilla de la Regencia | 1 (riesgo 1) | Alterna con los saqueadores mientras la Tormenta está armada y el modo tiene Diezmo; se va con el Diezmo | Repuestos 1 y rebaja del Diezmo (`sortie_tithe_discount_pct`, 10 %) |
| Expedición corta | 3: apertura → 1 de 2 → jefe (`combat_expedition_depth` (1,1), `branching` (2,2)) | Desde la era `combat_expedition_min_era` 2; `combat_expedition_cooldown` 480 s | 2 repuestos por combate de paso; jefe: 4 repuestos, 3 colonos y un plano si queda alguno |

- Oro y madera de las salidas nuevas: la mitad de la curva de siempre
  (`combat_sortie_reward_mult` 0.5), fijados en el nodo al sortear.
- El jefe de la expedición corta lleva `combat_expedition_boss_escort_cut` (1) infante
  menos.
- **Cura entre combates:** la expedición corta cura `combat_expedition_heal_between`
  (30 %) a cada superviviente herido al pasar al siguiente (`Expedition.mark_cleared`,
  evento `party_healed`). La expedición antigua sigue sin curar.
- Lanzada, la oferta sale del tablón y su tipo no vuelve a salir hasta que la columna
  vuelve. Si no ganó **ningún** combate, la misma oferta vuelve (se puede reintentar); con
  algún combate ganado se da por gastada (si no, abandonar tras el primero y relanzar
  sería repetir botín).
- La primera escaramuza (§4) no cambia: mientras toca, el panel solo ofrece esa.
- La expedición de siempre (`launch_expedition()`, 6-8 combates) sigue intacta para los
  guardados a medias, los tests y las sondas con semilla: `Expedition.kind` vacío.

### Botín exclusivo (D2 = A)

Se acumula en `Expedition.loot` nodo a nodo y se liquida al volver
(`CombatManager._apply_loot`), igual que el oro: lo de los nodos ganados llega aunque se
abandone.

- **Repuestos** (`ResourceManager.Type.PARTS`, material fuera de la bolsa, ver
  `docs/02-economy.md`): los pide el nivel 3 de los productores.
- **Colonos:** `PopulationManager.remove_population(-n)` hasta llenar las casas; los que
  no caben se van y el parte lo dice.
- **Planos:** `combat_blueprint_buildings` (Enfermería, Herrería, Chatarrería, Central
  diésel). Un id solo se ofrece cuando su `data/buildings/<id>.tres` existe, así que hoy
  no sale ninguno: lo activan las ramas que traigan esos edificios. Gancho:
  `CombatManager.blueprint_locked(id)` / `has_blueprint(id)`; **PlacementRules tiene que
  llamarlo** (un `check_blueprint()` como `check_rank()`) y ConstructionMenu poner el
  candado — no se tocó aquí. Señal `blueprint_unlocked`.
- **Rebaja del Diezmo:** la avanzadilla echada llama, si existe,
  `StormManager.add_tithe_discount("expedicion", pct)` (rama `feat/orden-regencia`). Sin
  esa función (la base de hoy) la rebaja solo se anota y se enseña: no hay un segundo
  mecanismo de rebaja.

### Antes de salir (`SkirmishPanel`)

Arriba del selector de tropa: las ofertas (botón por oferta) y la ficha de la elegida
con el mapa por capas (iconos de unidad y número por combate), el botín (lo exclusivo y
oro/madera con su icono) y "Tu fuerza X · enemigo Y" con **Favorable / Igualada /
Difícil** (`CombatRules.odds_label`: ≥ 1.25 favorable, < 0.85 difícil). La fuerza es
`CombatRules.side_strength()` (poder × vida / vida base: cuenta heridas y escala); antes
de lanzar, `roster_power()` de la columna contra el nodo más duro del mapa.

### Botón ESCARAMUZAS y ¿QUÉ HACER? (1.1)

`SkirmishButton` (CanvasLayer 10, en Main y Main2D, slot `skirmish_button` a la derecha
de CONSTRUIR; en móvil encima), visible con un Cuartel, registrado en `HudRegistry`.
Punto rojo cuando `CombatManager.sortie_reason()` no está vacío: la primera escaramuza,
la avanzadilla antes del Diezmo, repuestos que faltan para una mejora, o una oferta nueva
sin mirar (abrir el panel la marca vista). ¿QUÉ HACER? enseña la misma razón como
segunda línea (`Objectives.sortie_step()`); `next_step()` no cambia, así que la sonda de
línea sigue igual.

### Retirada enemiga (D7 = B)

`Encounter.create(..., p_can_rout)`: en los tableros de la columna (expedición,
incursión, primera escaramuza) el enemigo se retira cuando le queda menos de
`combat_retreat_ratio` (30 %) de la vida con la que empezó: eventos `enemy_routed` +
`encounter_ended {victory: true, routed: true}`, estado `WON`. **Nunca en defensa**
(Diezmo ni asedio): `create()` lo apaga si `is_defense`. La fórmula de daño no cambia.

### "Resolver solo" (D6 = A)

`CombatManager.can_auto_resolve()`: tablero activo, no oleada del asedio, incursión o
Diezmo, y tu fuerza ≥ `combat_auto_resolve_ratio` (2.0) × la enemiga.
`auto_resolve_current()` juega el mismo `Encounter` con `AutoResolver` y solo publica
muertes y final; el parte dice "Resuelto solo". Botón en la cabecera de acciones de
`BattleScreen` y, para incursiones, en `SkirmishPanel` antes de salir
(`launch_sortie(id, party, true)`).

### Guardado

Clave nueva **`sorties`** (`CombatManager.get_sorties_save_data()` /
`load_sorties_save_data()`, `SortieBoard.to_dict/from_dict`): ofertas, relojes (−1 =
esperando a la columna), planos, apunte de la rebaja, contadores. `CombatManager.reset()`
crea un tablón vacío (ya se llama en los tres sitios de `GameManager`). La clave
`expedition` gana `kind`, `offer` y `loot`; sin ellas es la expedición antigua. Un
guardado sin `sorties` carga con el tablón vacío y las ofertas salen en el siguiente tic.

### Qué medir en el pase final

- `tools/balance_probe.gd`: incursión ≤ 3 min, nodo de expedición corta ≤ 4 min, Diezmo
  ≤ 4 min; tasa de victoria de la incursión con 3-5 unidades de era 2.
- `tools/siege_probe.gd`: el asedio no cambia (sin retirada), debe seguir en su 82 %.
- `tools/line_probe.gd`: sigue ganando sin salir (los repuestos solo frenan mejoras de
  nivel 3 que la línea no pide); enseñar a su jugador a lanzar incursiones es otra rama.

## 5. The auto-resolved defence

When the Tithe lands while the player is already on a board,
`StormManager._begin_tithe()` cannot open a second one. It calls
`CombatManager.auto_resolve_defense()` instead. The check is
`CombatManager.is_board_open()`, not `is_in_encounter()` — see
[§3](#is_board_open-is-not-is_in_encounter): a resolved fight whose report is
still on screen counts as a board.

**Why it uses the same `Encounter` rather than a formula.** A separate resolution
formula would be a second set of combat rules to keep in sync with the first, and
it would drift: towers, minimum range, deployment rows, the timeout tiebreak and
the morale snapshot would all have to be re-expressed. Instead the defending side
is composed exactly as `start_defense()` composes it (garrison + tower crews, same
morale, same enemy scale), a private `Encounter` is built, and `AutoResolver` plays
it with `CombatAI` on both sides. Same model, same numbers, no second arithmetic.

`AutoResolver.resolve()` is pure and deterministic — neither `Encounter` nor
`CombatAI` rolls dice — so the same board always produces the same result. It has
a step budget (`(turn_limit + 1) * units * 4 + 4`) purely as a hang guard against a
future AI bug; a healthy board never reaches it. If the budget runs out, the
defence counts as lost.

The private encounter is **never** assigned to `_encounter`, so it emits no
`encounter_started` / `turn_started` / `unit_*` / `encounter_ended` — those would be
read by `BattleScreen` as belonging to the board the player is actually looking at.
The single signal for this fight is `defense_auto_resolved(victory, rounds, summary)`.
The result is applied through the same `_apply_result_for()` as a played defence.

Final Audit waves deliberately do **not** take this path: `can_launch()` blocks an
expedition while the Regency is summoned or active, so there is never a board to
dodge — and resolving the endgame blind would take away exactly what makes it the
endgame.

---

## 6. The Final Audit

In Campaña and Supervivencia HQ level 3 no longer wins the game.
`ProgressionManager._complete_milestone()` catches the `hq_max` milestone and, when
`GameMode.audit_enabled()`, calls `summon_final_audit()`. Constructor wins right there
(`GameMode.capstone_wins()`), Sandbox summons the siege only from its SANDBOX tab, and
Supervivencia allows no resummon: a lost siege emits `run_ended`
([20-modos-de-juego.md](20-modos-de-juego.md)).

| Stage | Call | State |
|-------|------|-------|
| Summoned | `summon_final_audit()` | `PENDING` — nobody on the board yet; `SkirmishPanel` offers the button. The garrison mustered here is only a preview |
| Begun | `begin_final_audit()` | `ACTIVE`; the garrison is mustered **now** from `get_garrison()` (`FinalAudit.begin(counts)`), then `_announce_wave()` emits `final_audit_wave_ready`. Refused while `CombatManager.final_audit_block_reason()` is non-empty (a board open, a column out) |
| Wave on the board | `CombatManager._on_final_audit_wave_ready()` → `start_defense(roster, defenders, scale)` | A normal defensive `Encounter` |
| Wave reported | `CombatManager.end_encounter()` → `ProgressionManager.report_audit_wave(won)` | `clear_wave()` or `lose()` |
| Won | last `clear_wave()` | `WON` → `storm_halted_forever` **then** `victory_achieved` |
| Lost | `lose()` | `LOST` — not a game over |

**The seam.** `ProgressionManager` never calls `CombatManager.start_defense()`. It
emits `final_audit_wave_ready(wave, roster, scale)`; whoever drives the board
listens. Today that listener is `CombatManager._on_final_audit_wave_ready()`. The
report comes back the other way, and deliberately from `end_encounter()` rather
than from the end of the fight — reporting earlier would leave
`is_in_encounter()` still true when the next wave arrives, and the wave would be
lost.

`end_encounter()` also reads `_audit_wave_won`, noted when the wave *resolved*,
rather than deducing the outcome from `_last_result`: that field is overwritten by
any other fight — the blind Tithe defence, for one — and a won wave reported as
lost razes the base as a side effect.

- **Waves:** `final_audit_waves` (3–5), rolled from the siege seed. The seed comes
  from `randi()` and is **not** saved as a re-rollable choice — a lost siege that is
  summoned again is a different night, so reloading cannot shop for an easier one.
- **Attrition across waves.** `build_encounter_units()` hands over
  `living_garrison()` — the same objects, wound by wound. No retraining, no
  reinforcement. That, not the scaling, is the real difficulty curve.
- **Tower crews** are rebuilt each wave from the standing towers, minus every crew
  that has already fallen (`FinalAudit.crew_losses`, recorded as each one falls and
  saved with the siege). A tower does not tire; a dead crew is not replaced — not
  even by reloading.
- **Who fights is decided at the gate, not at the summons.** `FinalAudit.begin()`
  re-musters the garrison the first time a summons begins (`started` is false),
  so whatever a Tithe killed, upkeep deserted or the barracks trained in between is
  reflected. Once `started`, a siege is never re-mustered — that would heal the
  wounded and raise the dead — only `reconcile()`d: living units in excess of what
  the army still has are dropped (not counted as casualties).
  `ProgressionManager._announce_wave()` reconciles against `get_deployable_units()`
  before **every** wave, so a desertion between waves takes a soldier out of the
  siege too. Reinforcements never join a siege in progress.
- **So is the morale (2026-10-04, Bryan's call).** `ProgressionManager.begin_final_audit()`
  hands `FinalAudit.begin(home, morale)` the town's morale **when "QUE BAJEN" is
  pressed**; the first time a summons begins it replaces `morale_snapshot` and is
  stamped on the garrison. The summon-time value is only a preview. Once `started`,
  the snapshot is frozen for the rest of the siege (a reload does not change it). A
  save with a summoned, never-opened siege (`started` false, or no key) follows the
  new rule when the gate opens.
- **A fallen tower crew leaves its tower damaged** (2026-10-04, Bryan's call), in any
  defensive board — Tithe (open or blind) or siege wave. `CombatManager._apply_result_for()`
  calls `damage_towers_for_lost_crews()`: one operational tower per fallen crew, the
  soundest first, loses `storm_tower_crew_loss_damage` (40%) of its max health through
  `BuildingHealth`, **never down to ruins** (it keeps at least 1 HP, so it still
  mitigates and still fields a crew), and has to be repaired. The result carries
  `towers_damaged`; `BattleScreen`'s report and `WarReportScreen`'s blind-defence
  report print it (`LBL_REPORT_TOWERS_DAMAGED`).
- **The Tithe still comes while the siege is only summoned.** That is a decision,
  not an accident: the Regency waits for the player, the Assessors do not. The
  garrison defends as usual, casualties leave `ArmyManager`, and the muster at the
  gate simply finds fewer soldiers. Only an `ACTIVE` siege stands the Tithe down
  (below).
- **The ledger is settled live.** Garrison units are the same `CombatUnit`
  objects as the board's, and the save stores their HP. Every player death on a
  wave board is charged at once (`CombatManager._settle_audit_death()`, from the
  `unit_died` event, idempotent by uid; anything that fell without that event is
  settled when the wave resolves), and `_apply_result_for(..., precharged)` reports
  those deaths without subtracting them again. No save is written while a wave is
  in play (`CombatManager.is_save_safe()`), but the ledger does not depend on that:
  the siege and the barracks always hold the same dead.
- **A wave that finds the board busy waits.** `_on_final_audit_wave_ready()` sets
  `_audit_wave_queued` instead of counting the wave as lost (which used to cost the
  maximum Tithe and maximum damage); `end_encounter()` releases it with
  `call_deferred("_release_queued_audit_wave")` once the board is free. The normal
  path never needs it — "QUE BAJEN" is disabled, with the reason in its tooltip,
  while `final_audit_block_reason()` answers `MSG_AUDIT_BOARD_BUSY` or
  `MSG_AUDIT_EXPEDITION_OUT` — it is the safety net.
- **Shape.** `wave_slots()` grows from `final_audit_base_slots` by
  `final_audit_slots_per_wave`, capped by `combat_deploy_cap`. Guns appear from
  wave 1, armour from `final_audit_armour_wave`, and the last wave gets an extra
  vehicle. Once bodies stop fitting, `wave_scale()` is the only thing still
  pushing.
- **Losing** costs a maximum-severity Tithe and maximum storm damage
  (`StormManager._on_final_audit_lost()`), but the siege can be re-summoned once
  `final_audit_resummon_min_units` (3) units stand again
  (`can_resummon()` / `resummon()`). `resummon()` rolls a new seed, a new garrison
  and new waves, and increments `summons` — the only record that it happened.
- **Persistence:** `to_dict()` saves seed, era, state, `current_wave`, `summons`,
  `started`, `crew_losses`, `morale_snapshot` and the garrison. A save without
  `started` guesses it: any state but `PENDING`, a wave behind it or a wounded unit
  means the siege had started. The waves themselves are rebuilt from the
  seed and the era, exactly the way `Expedition` rebuilds its map.
- **A saved siege comes back `PENDING`, never `ACTIVE`.** `FinalAudit.from_dict()`
  downgrades a stored `ACTIVE` state to `PENDING` on purpose. The board is not
  saved, so an `ACTIVE` siege on load would be a siege nobody can resume: the
  "QUE BAJEN" button hides itself because the siege is already running, no wave is
  re-announced because nothing calls `begin()`, and the expedition stays blocked
  forever (`can_launch()` refuses while the Regency is up). Degrading it keeps the
  wave in progress and the wounded garrison, and hands control back to the player —
  press QUE BAJEN again and the wave comes down.

Winning emits `storm_halted_forever` **before** `victory_achieved`: the world goes
quiet before the screen says so. `StormManager._on_halted_forever()` sets `_halted`,
disarms the cycle and resets the production multiplier; `StormSky` restores the
sky; `AudioManager` plays the unlock sting.

### Closing a wave opens the next one, inside the same call

**Whoever touches `end_encounter()` or `BattleScreen._close_board()` has to know
this.** Closing a wave's report runs, without ever yielding:

```
BattleScreen._close_board()
  → CombatManager.end_encounter()                    # _encounter = null
    → ProgressionManager.report_audit_wave(won)
      → FinalAudit.clear_wave()                      # advances current_wave
      → ProgressionManager._announce_wave()
        → EventBus.final_audit_wave_ready
          → CombatManager._on_final_audit_wave_ready() → start_defense()
            → _open_board()                          # _encounter = a new board
              → EventBus.encounter_started → BattleScreen._on_encounter_started()
                → BattleScreen._open_board()         # _board_open = true
```

By the time `end_encounter()` returns, `_encounter` is a **new** board and
`BattleScreen._board_open` is `true` again. Any code that keeps running after that
call is running on top of a board that has just opened. `_close_board()` therefore
re-checks `_board_open` immediately after `end_encounter()` and returns early if
it is set; without that early return the tail of the method hides the board it
just opened, and the siege becomes unplayable — the player is left looking at the
base, with no board and no button that leads back to it. That exact path is
`tests/storm/test_board_handoff.gd::test_closing_a_wave_report_leaves_the_next_wave_on_screen`.

### The Tithe stands down while the Audit is being fought

`StormManager._begin_tithe()` returns early when
`ProgressionManager.is_final_audit_active()`: it posts
`STORM_TITHE_DURING_AUDIT`, emits `tithe_resolved(true, {})` and settles. No
Tithe is collected and no second defence is opened.

The reason is not mercy, it is bookkeeping. The Regency is already at the door;
collecting on one side while the garrison fights on the other would set the same
troops to defend two places at once. `CombatManager.get_garrison()` knows nothing
about the units standing in the siege's waves, so it would re-enlist them and then
deduct their casualties twice — the player would lose soldiers who never died.

A siege that is only **summoned** (`PENDING`) does not stop the Tithe: the check
is `is_final_audit_active()`, and both cases are pinned in
`tests/storm/test_board_handoff.gd`.

---

## 7. Signals

The parameter and consumer tables now live in
[`10-signals-reference.md`](10-signals-reference.md) — sections **Combat** and
**The Final Audit**. That file is the one to update when a listener appears or
disappears; duplicating the rows here is how this section went stale the last
time. What follows is only what a reader of *this* document needs on top of them.

- **`expedition_resumed`** is connected as a typed `.connect` in `BattleScreen`,
  `SkirmishPanel` and `ArmyPanel`. `final_audit_summoned` and
  `storm_halted_forever` are connected typed in `AudioManager` (the old
  string-form `_connect_optional()` is gone).
- `result` on `expedition_ended`: 0 = victory, 1 = defeat, 2 = abandoned.
- `summary` on `defense_auto_resolved` is `CombatManager.get_last_result()`, and
  that signal is the **only** one that fight emits — no `encounter_*` accompanies
  it, because the open board would claim them.
- `defense_auto_resolved` is read by `WarReportScreen` (the after-action report:
  casualties on both sides — `summary.enemy_casualties` — rounds, tower crews,
  outcome), and `final_audit_wave_cleared` by `AuditWaveBanner` ("Oleada X de N").
  `StormManager` still reads `auto_resolve_defense()`'s return value for its toast.
- `tithe_resolved`'s first argument is **true when nothing was taken** (repelled,
  or stood down during the Audit), despite its name `paid`. `WarReportScreen`
  stamps it COBRADO / REPELIDO; the maximum Tithe of a lost siege is left to
  `AuditDefeatScreen`, which matches it to `final_audit_lost` by process frame.
- `victory_achieved(stats)` is still emitted by `ProgressionManager` and consumed
  by `VictoryScreen`, but it is now reached **only** through a won Final Audit.
- `encounter_closed()` (2026-10-14) is emitted at the very end of
  `CombatManager.end_encounter()`, after a siege wave may have opened the next
  board: listeners (`NotificationPanel`, `ProgressPanel`, `RankPanel`, which
  release the notices held during the fight) re-check `is_board_open()`.

---

## 8. Balance

All of it in `scripts/services/GameConfig.gd`. No magic numbers anywhere in
`scripts/combat/`.

### `combat_*`

| Key | Default | What it does | Turn it up / down |
|-----|---------|--------------|-------------------|
| `combat_board_size` | `(8, 8)` | Board dimensions | Bigger boards mean longer approaches and more value in `move`; the deploy rows are hardcoded as two per side, so a very small board leaves no neutral ground |
| `combat_deploy_cap` | `6` | Max units per side (also caps garrisons and generated rosters) | Higher = longer, busier fights and more that can die at once. It is also the ceiling every roster generator clamps to, so raising it makes the whole game heavier at once |
| `combat_turn_limit` | `20` | Rounds before the HP tiebreak | Lower punishes slow, defensive play harder (a tie is a player loss); higher lets attrition decide instead of the clock |
| `combat_ai_step_delay` | `0.45` s | Pause between enemy actions | Lower is snappier and harder to read; 0 makes the enemy round vanish in a frame. Halved automatically in dev mode |
| `combat_unit_stats` | see below | `hp`/`atk`/`def`/`move`/`range`/`min_range`/`initiative` per unit type | The single most sensitive dial in the pillar. `min_range` is what makes positioning matter — set artillery's to 1 and the board flattens into a brawl |
| `combat_enemy_scale_per_depth` | `0.15` | Pressure added per map layer | Higher makes a deep run steepen fast; it drives both roster size and HP/ATK |
| `combat_enemy_scale_per_era` | `0.25` | Pressure added per era past 1 | Higher keeps late-era fights dangerous; it also scales encounter loot (`encounter_rewards`), so raising it is not purely a tax |
| `combat_boss_multiplier` | `1.8` | Boss stat and reward multiplier | Higher makes the boss a wall rather than a capstone |
| `combat_map_depth` | `(4, 6)` | Layers between start and boss | Longer maps mean more attrition before the boss, which matters more than any stat here |
| `combat_map_branching` | `(2, 3)` | Nodes per layer and exits per node | Wider maps give more route choice and more risk-dodging |
| `combat_draft_options` | `3` | Cards offered after a won node | More options is strictly more power for the player |
| `combat_risk_enemy_scale` | `0.20` | Extra pressure per risk level (0–2) | Raise with `combat_risk_reward_bonus`, or the dangerous road stops being worth taking |
| `combat_risk_reward_bonus` | `0.35` | Extra loot per risk level | The other half of the same bet |
| `combat_enemy_base_slots` | `2` | Roster size at depth 0, era 1, risk 0 | The opening fight's size. Higher makes the first node of every run harsh |
| `combat_draft_values` | `atk 2, def 2, move 1, initiative 2, heal_pct 0.3` | What one pick is worth | A run is 6–8 fights: a pick should tilt a fight, never decide the expedition |
| `combat_draft_focus_multiplier` | `2` | Multiplier when a card targets one unit type | Higher rewards mono-type parties |
| `combat_reward_base` | `{gold 60, wood 30}` | Loot per cleared encounter, before scaling | The whole economic case for going out at all |
| `combat_first_sortie_roster` | `{infantry 1}` | The only enemy of the first sortie (§4) | More bodies and a lone infantry stops winning it: keep it at one unless the scale drops |
| `combat_first_sortie_enemy_scale` | `0.6` | HP/ATK multiplier of that enemy, instead of the depth/era/risk curve | 0.6 is a 60 HP infantry hitting for 3 net; at 1.0 the fight is an even duel that morale decides |
| `combat_first_sortie_rewards` | `{gold 150, wood 100}` | Fixed loot of the first sortie, no curve | It has to show in the era-1 bag (600) and pay back the infantry (40 gold + 20 wood) several times over |
| `combat_morale_initiative_bonus` | `2` | Initiative swing across the morale range | At ±2 a demoralised squad can lose the first move entirely; at 0 morale stops touching turn order |
| `combat_morale_attack_range` | `(0.85, 1.15)` | Attack multiplier at 0 and 100 morale | Widen it and the base's mood decides fights; narrow it and the two halves of the game stop talking |
| `combat_morale_on_victory` | `8.0` | Morale gained by a win | |
| `combat_morale_per_casualty` | `3.0` | Morale lost per unit that does not come back | With the default pair, three dead cancel a victory. That is the point: a costly win should be able to leave the town worse off |

Default `combat_unit_stats` (los HP son los de `GameConfig`: x3,3 sobre los
30/22/60 originales, docs/16):

| Unit | hp | atk | def | move | range | min_range | initiative | domain |
|------|----|-----|-----|------|-------|-----------|------------|--------|
| `infantry` | 100 | 8 | 2 | 3 | 1 | 1 | 5 | `land` |
| `artillery` | 75 | 14 | 1 | 1 | 3 | 2 | 3 | `land` |
| `vehicle` | 200 | 12 | 5 | 4 | 1 | 1 | 4 | `land` |
| `torpedo_boat` | 90 | 15 | 1 | 4 | 1 | 1 | 6 | `sea` |
| `gunboat` | 140 | 12 | 3 | 3 | 3 | 1 | 4 | `sea` |
| `dreadnought` | 280 | 16 | 6 | 2 | 4 | 2 | 2 | `sea` |
| `fighter` | 90 | 12 | 2 | 5 | 1 | 1 | 7 | `air` |
| `bomber` | 110 | 18 | 1 | 4 | 1 | 1 | 3 | `air` (no ataca al aire) |
| `airship` | 260 | 10 | 4 | 2 | 2 | 1 | 2 | `air` |

`domain` decide por donde anda la unidad, a quien pega y en que capa ocupa la
casilla: ver [§11](#11-dominios-mar-aire-y-espacio). Las claves nuevas de
`combat_*` (`combat_domain_moves`, `combat_domain_targets`, `combat_coast_*`,
`combat_coastal_*`, `combat_loot_coastal_parts`, `combat_home_coast_seed`) estan
explicadas alli.

Morale is captured once and frozen for the whole expedition or siege: at launch for
an expedition (`_morale_snapshot`), when the gate opens ("QUE BAJEN",
`FinalAudit.begin()`) for the siege — the battle is fought with the spirit the town
had when the column marched out or the gate opened.

### `final_audit_*`

| Key | Default | What it does | Turn it up / down |
|-----|---------|--------------|-------------------|
| `final_audit_waves` | `(3, 5)` | Waves per siege, rolled from the seed | The single biggest lever on how much army the endgame demands |
| `final_audit_base_slots` | `3` | Bodies in wave 0 | |
| `final_audit_slots_per_wave` | `1` | Bodies added per wave (capped by `combat_deploy_cap`) | Once the cap is hit this does nothing; only `scale_per_wave` still bites |
| `final_audit_scale_per_wave` | `0.22` | HP/ATK multiplier added per wave | The real curve after the board fills |
| `final_audit_scale_per_era` | `0.25` | HP/ATK multiplier added per era past 1 | |
| `final_audit_last_wave_multiplier` | `1.5` | Extra multiplier on the closing wave | It is the end of the game, not one more step |
| `final_audit_artillery_share` | `3` | One gun per N bodies, from wave 1 | Lower = more guns = the garrison gets punished for bunching up. **Pendiente:** con la ventaja por tipo, 4 devuelve el asedio maximo al 83 % ([17](17-balance-asedio.md)); se decide al integrar con `balance/campana-4-6h` |
| `final_audit_armour_wave` | `2` | First wave that can field a vehicle | |
| `final_audit_extra_gun_chance` | `0.35` | The siege's one coin flip | Set to 0 and every siege of the same era looks identical |
| `final_audit_resummon_min_units` | `3` | Living units needed to call the Regency back after a loss | The price of losing: rebuild this much before trying again |
| `final_audit_air_min_era` | `3` | From this era the closing wave brings airships (§11) | |
| `final_audit_airships_last_wave` | `1` | Airships in the closing wave, each in a gun's slot | 0 turns the air out of the siege. Unmeasured: docs/17 |
| `final_audit_air_escort_fighters` | `1` | Enemy fighters in the closing wave when your garrison has planes | |

### Gobernador: the same rules, a harder enemy

The **Gobernador** tier of the Campaign (docs/20) does not touch `CombatRules`,
the AI, the board or the loot. It only multiplies the enemy, through three keys of
`GameConfig.game_tier_rules["governor"]`, read via `GameMode` (all 1.0 in Colono,
and 1.0 whenever `GameMode.combat_hard()` is false):

| Key | Gobernador | Applied in | Effect |
|-----|-----------|------------|--------|
| `expedition_enemy_mult` | `1.05` | `ExpeditionGenerator.enemy_scale()` | Every expedition enemy (and the boss) has +5 % HP/ATK (1.15 was measured and is a wall: docs/16). The first sortie keeps its fixed `combat_first_sortie_enemy_scale` |
| `tithe_force_mult` | `1.34` | `StormManager.assessor_roster()` | One more Assessor at severities 1-3 (3/4/5 → 4/5/6, rounding `raw × 1.34`); from severity 4 both tiers sit at `combat_deploy_cap` (6), so the late Tithe is as big as ever — the escalation per Tithe repelled gets there sooner |
| `audit_enemy_mult` | `1.06` | `FinalAudit.wave_scale()` | Every siege wave hits 6 % harder |

Measured with `tools/siege_probe.gd -- --tier=governor` and
`tools/balance_probe.gd` (`-- --tier=governor`): the siege stays winnable with the
maximum garrison (docs/17, "Gobernador") and expeditions get harder without
becoming a wall (docs/16, "Gobernador").

Tower crews are configured on the storm side, not here:
`storm_tower_garrison_unit` (`artillery`), `storm_tower_garrison_per_tower` (1),
`storm_tower_garrison_max` (2), and `GameConfig.get_tower_garrison()`, which caps
the crews so the defender's row never overflows `combat_board_size.x`.
`storm_tower_crew_loss_damage` (0.4) is what a tower loses when its crew falls.

---

## 9. Testing

gdUnit4, headless. The tree holds **37 suites / 697 cases**; 20 of them are the
combat pillar. Whole suite:

```bash
GODOT=godot tools/run_tests.sh   # own user dir; never call GdUnitCmdTool directly
```

Just the combat models:

```bash
GODOT=godot tools/run_tests.sh -a tests/combat
```

| Suite | Covers |
|-------|--------|
| `tests/combat/test_combat_rules.gd` | Damage floor, morale modifiers, Manhattan/range checks, BFS reachability, turn order and its tiebreaks, timeout resolution, rewards, morale delta |
| `tests/combat/test_encounter.gd` | Deployment rows and centring, move-then-attack, blocked cells, defend, win/lose/timeout, `release_survivors()` |
| `tests/combat/test_combat_ai.gd` | The AI attacks when a target is in range, picks the killable one, keeps artillery at stand-off, never idles with a reachable target |
| `tests/combat/test_auto_resolver.gd` | A whole encounter resolved headless, determinism, the step budget, the returned event list |
| `tests/combat/test_expedition_generator.gd` | Map connectivity (every node reaches the boss), seed reproducibility, risk weighting, roster and reward scaling, draft applicability |
| `tests/combat/test_expedition.gd` | Party construction, node selection legality, attrition, permadeath, drafts, abandon, `to_dict`/`from_dict` round-trip |
| `tests/combat/test_expedition_wiring.gd` | `CombatManager`'s side: `can_launch` refusals, launch, chained nodes, draft gating, settlement, save/resume |
| `tests/combat/test_army_casualties.gd` | Casualties reaching `ArmyManager`, and tower crews staying out of it |
| `tests/combat/test_final_audit.gd` | Wave rolling, shape per wave, attrition across waves, loss without game over, resummon floor, persistence |
| `tests/storm/test_defense.gd` | The Tithe defence path through `start_defense()` |
| `tests/storm/test_defense_auto_resolve.gd` | `auto_resolve_defense()` when the board is busy |
| `tests/storm/test_tower_garrison.gd` | Crew count, back-row deployment, crews outside the deploy cap and outside the ledger, and the tower damaged (never ruined) when its crew falls |
| `tests/storm/test_final_audit_wiring.gd` | `ProgressionManager` ↔ `CombatManager` seam, `storm_halted_forever`, victory ordering |
| **`tests/storm/test_board_handoff.gd`** | **The seams.** A resolved board still counts as open; the Tithe never opens a board over an unread report; winning the boss and losing a run both close the board they were fought on; the Tithe stands down while the siege is *active* but not while it is merely summoned; and closing a wave's report leaves the next wave on screen. Four bugs that left the game unfinishable lived here, and none of them was visible from the pure models |
| `tests/storm/test_storm_toasts_over_board.gd` | Notification toasts draw above `BattleScreen` and below `VictoryScreen` |
| `tests/audio/test_audio_combat.gd` | `AudioManager` connects the combat and audit signals it claims to |
| `tests/ui/test_expedition_ui.gd` | `BattleScreen`'s map, draft modal, final report and abandon flow, plus `SkirmishPanel`'s launch refusals — including that the map stays touchable on a phone |
| `tests/ui/test_battle_board_3d.gd` | El tablero 3D: 3D salvo sin pantalla y en la vista 2D, casilla <-> mundo, la ruta casilla a casilla, una pieza por unidad viva, nada se juega ni sale el parte mientras la maqueta anima, la pieza acaba donde dice el modelo, la barra baja golpe a golpe y se reconcilia, el 3D del mapa se apaga bajo la maqueta, piezas horneadas de los dos bandos <= 800 triangulos, un material por color de colonia, y `domain` ("land" hoy, ninguna regla cambia) |
| `tests/combat/test_type_advantage.gd` | El circulo de ventaja por tipo, los multiplicadores sobre el dano neto con suelo 1, y que la IA prefiere el buen objetivo |
| `tests/combat/test_front_orders.gd` | `FrontOrders`: objetivo ya a tiro sin mover, casilla de acercamiento alcanzable y con tiro por el camino mas corto, la artilleria no se mete encima, objetivo inalcanzable, unidad que ya movio, AVANZAR = el movimiento de `CombatAI`, que no muta nada y que ejecutar una orden es mover + atacar legales |
| `tests/ui/test_combat_views.gd` | Las dos vistas: "front" por defecto, la preferencia en `settings.cfg` (no en la partida; un valor raro vuelve a "front"), la fila de Ajustes, textos ES/EN, el frente sin casillas (piezas en sitios libres con desorden, x1,3, manchas de mover en vez de casillas) y con AVANZAR, la calidad minima con el tablero sin tocar la preferencia, el tablero con casillas, el boton de la cabecera cambia a mitad de pelea sin rehacer piezas, tocar a un enemigo en el frente acerca y ataca, **la misma pelea jugada igual da el mismo resultado en las dos vistas**, y el campo del frente para cada escenario |
| `tests/ui/test_held_notices.gd` | Avisos retenidos: un toast con tablero abierto va al registro y sale al cerrar, sin tablero sale al momento, muchos se resumen en uno con la cuenta, una partida nueva tira lo retenido, placas de hito y ascenso de rango esperan al cierre, los avisos `combat` si salen, `HelperPanel` calla con el tablero abierto, y `encounter_closed` se emite |
| `tests/ui/test_battle_board_icons.gd` | Unit silhouettes on the cell and on the initiative strip, side tint, the dimming of a unit that already acted, the boss frame and who wears it, the fallback to the name's initial when the PNG is missing, and the cell still fitting a 400x720 screen |
| `tests/ui/test_helper_skirmish_callout.gd` | The Escaramuzas callout appears with the Barracks and only once |
| `tests/combat/test_combat_integrity.gd` | The ledger across boards and saves: no walking past an unfought node, the siege ledger balanced through a mid-wave save (garrison and tower crews), the garrison mustered at the gate and reconciled before every wave, abandoning leaving a Tithe board alone, one enemy loop per board, a busy board queuing a wave instead of losing it, board units never counted at home, and the seeded skirmish roster |
| `tests/combat/test_combat_previews.gd` | *(sin correr aún, 2026-10-14)* `preview_damage` = el golpe de verdad y no toca a nadie, "cae", la guardia; la ✕ de la artillería (centro y esquina), la infantería sin ✕, la zona de tiro; el alcance enemigo (mover + pegar, ni muertos ni el otro bando, no mueve a nadie) |
| `tests/ui/test_unit_card.gd` | *(sin correr aún)* fuerte/débil del círculo, números de `GameConfig`, vida de la unidad viva, el alcance mínimo en la ficha, la ficha se monta con su ✕, "×1,5" / "×1.5", el círculo con tres flechas, las seis guías de combate en AYUDA |
| `tests/ui/test_combat_teaching.gd` | *(sin correr aún)* la primera pelea empieza la lección y señala a la unidad, la tarjeta del tablero no sale encima, tocar tu pieza abre la ficha y pasa el paso 1, el daño previsto, Ver alcance enemigo, la ✕ de la artillería |

| `tests/combat/test_air_sea_rules.gd` | *(corridos, ronda de la 1.1)* Aire y mar: el terreno de costa (determinista, columnas de agua y orilla), quien pisa que, las dos capas (avion encima de soldado), quien pega a quien (soldado a 1, artilleria nunca, bombardero no al aire), despliegue por dominio y reserva, la tabla de ventajas sin parejas en los dos sentidos, la IA solo se planta donde su dominio pisa, AutoResolver reproducible en la costa, y que un tablero de tierra despliega igual que antes |
| `tests/combat/test_air_sea_missions.gd` | *(corridos)* Que oferta es de costa, nodos con agua y UN barco por combate en el sitio de un cuerpo (sin acorazado enemigo), la misma oferta = la misma costa, el repuesto de mas, los mapas de tierra intactos, y los dirigibles y la escolta de cazas del Ataque Final (apagados de serie; forzados a 1 para fijar como entran, y su guardado) |
| `tests/economy/test_air_sea_army.gd` | *(corridos)* Cada unidad en su edificio, huecos por edificio, capacidad, guardado viejo, los dos edificios y la costa, los barcos solo a misiones con agua, el agua en casa solo con barcos, textos ES/EN |

`test_board_handoff.gd`, `test_expedition_ui.gd` and `test_battle_board_icons.gd`
touch the real autoloads and private members on purpose: what they are watching —
the handover between boards and the actual drawing — has no seam that can be
reached any other way. Each case restores what it moved.

### Probes (`tools/`)

Probes are dev-only `Node` scripts. Each is registered **temporarily** as an
autoload in `project.godot`, the game is run **with a window** (not headless), and
the line is removed afterwards. They all no-op unless `GameConfig.dev_mode` is on.

| Probe | What it does |
|-------|--------------|
| `tools/battle_probe.gd` | Seeds an army, opens the skirmish panel and a showcase board (a home defence with a boss and a tower crew), plays the whole fight and screenshots it into `res://docs/media/dev/battle_<tag>_*.png`: deploy, move (mid-hop), attack, shell, targets, death (two frames), result, and on a tablet the tap-to-inspect label. In 3D it shoots when the **maqueta** reaches each event (`Board3D.event_played`), not when the signal fires. Args after `--`: `--no-title --profile=pc\|tablet --quality=high\|low\|minimal --board=3d\|2d --view=front\|board --scene=land\|beach\|forest --x2 --tag=<name>`; `--fps` measures FPS and GPU ms (map alone vs board, every quality) instead of shooting |
| `tools/audit_probe.gd` | Summons the Final Audit, plays the whole siege without touching the UI, and logs what happened. `FORCE_SHORT_SIEGE = true` forces a one-wave siege so the victory path (the Storm stopping for good) can be seen without luck. It is the proof that **the game can be finished** |
| `tools/expedition_probe.gd` | Plays a whole expedition without the UI (same `CombatAI`, applied through the public `CombatManager` API) and checks the roguelike invariants: attrition, permadeath, one payout on return, and that the army left at home is exactly the one that survived (T045, `specs/001-combate-pve/quickstart.md`) |

Two balance probes run headless and open no board: `tools/siege_probe.gd`, an
`extends SceneTree` script run with `-s`, plays whole sieges in memory over hundreds
of seeds without touching `CombatManager` (`godot --headless --path . -s
tools/siege_probe.gd -- --seeds=200`, [17-balance-asedio.md](17-balance-asedio.md));
`tools/balance_probe.gd`, a temporary autoload, sweeps the `combat_*` values with
`AutoResolver` ([16-balance-combate.md](16-balance-combate.md)). Every probe runs with a private
user dir (`override.cfg`, see `CLAUDE.md`).

Besides the probes, the expedition is exercised by
`tests/combat/test_expedition_wiring.gd` (the service) and
`tests/ui/test_expedition_ui.gd` (the screens).

`tools/unit_toy_probe.gd` (`extends SceneTree`, `godot --path . -s
tools/unit_toy_probe.gd`) photographs the six baked unit toys and the two props
in a row (`docs/media/dev/unit_toys.png`); re-run it after touching a unit recipe.

`tools/gen_unit_icons.gd` is not a probe: it is a one-shot generator, run headless
and never registered as an autoload. Re-run it after touching a silhouette.

---

## 10. Known gaps

Verified against the code, not the spec. Update this list as things land.

- **Mid-wave saves from before the live ledger** (no `started` key) may still
  carry deaths of the interrupted wave that `ArmyManager` never charged: nothing
  tells them apart from deaths of earlier waves, which were charged. New saves
  cannot produce this.
- **Towers have no behaviour of their own** beyond mitigating storm damage
  (`StormManager._damage_buildings()` via `GameConfig.get_storm_damage()`) and
  fielding a crew on a defensive board (and taking damage when that crew falls).
  There is no tower attack on the base map.
- **What losing a siege costs is a balance call, per mode.** In Campaña
  `final_audit_lost` takes a maximum-severity Tithe and maximum storm damage, and the
  siege can be resummoned once `final_audit_resummon_min_units` (3) stand — but the
  smallest garrison that can resummon does not win (`docs/17-balance-asedio.md`,
  `test_the_smallest_garrison_that_can_resummon_does_not_win`), so a retry means
  rebuilding the army first. In Supervivencia the loss ends the run (`run_ended`).

Landed since this document was first written, and no longer gaps: the expedition
interface (map, draft modal, final report, abandon), listeners for
`draft_offered` / `draft_applied` / `expedition_node_selected` /
`expedition_resumed`, `ArmyPanel` painting who is away on campaign, real unit
silhouettes on the board in place of the name's initial, the after-action report
for the blind defence (`WarReportScreen`), the siege banner (`AuditWaveBanner`), and
the removal of the `has_method()` / `has_signal()` scaffolding.

---

## 11. Dominios: mar, aire (y espacio)

**Hecho (2026-10-17, rama `feat/aire-mar-reglas`, 1.1).** Seis unidades nuevas,
dos edificios, agua en algunos tableros, barcos enemigos en las misiones de costa
y dirigibles de la Regencia en la ultima oleada del Ataque Final. La vista
(modelos, iconos, agua pintada) va en `feat/aire-mar-vista`; esta rama es el
modelo, la colonia, los textos y los tests. El espacio sigue siendo una idea.

### Las unidades

| Unidad | Dominio | Edificio | Era | Coste | Sueldo | Poder | Papel |
|---|---|---|---|---|---|---|---|
| Lancha torpedera `torpedo_boat` | mar | Astillero | 2 | 100 oro, 40 acero, 40 madera | 2 | 24 | Rapida y fragil; sus torpedos hunden al Acorazado |
| Canonera `gunboat` | mar | Astillero | 2 | 130 oro, 60 acero, 6 tablones | 2 | 30 | Alcance 3; barre la playa (infanteria), caza lanchas y derriba cazas |
| Acorazado `dreadnought` | mar | Astillero | 3 | 320 oro, 160 acero, 60 petroleo, 10 vigas | 5 | 75 | Mucha vida, alcance 4 (minimo 2), lento |
| Caza `fighter` | aire | Aerodromo | 3 | 200 oro, 60 acero, 6 combustible | 3 | 40 | El mas rapido; gana a bombardero y dirigible |
| Bombardero `bomber` | aire | Aerodromo | 3 | 260 oro, 90 acero, 40 petroleo, 8 combustible | 4 | 50 | Ataque 18 contra tierra y barcos; no puede atacar al aire |
| Dirigible `airship` | aire | Aerodromo | 3 | 280 oro, 60 acero, 60 petroleo, 10 combustible | 4 | 55 | 260 de vida, alcance 2, lento; la Regencia lo trae al asedio |

Estadisticas de combate en el §8. Ningun precio esta medido con `line_probe`.

### El terreno

`Encounter.terrain: Dictionary` (Vector2i -> `"land"` | `"water"` | `"shore"`;
vacio = todo tierra) y `Encounter.has_water()`. El generador puro es
`CombatRules.coastal_terrain(board, seed)`: `combat_coast_water_columns` (2)
columnas de agua pegadas a un lado (izquierda o derecha, por la paridad de la
semilla) y una columna de orilla; rellena las 64 casillas. El tablero no se
guarda: basta la semilla (`terrain_seed` del nodo, o `combat_home_coast_seed` en
casa).

**Quien pisa que** (`GameConfig.combat_domain_moves`): tierra en `land` y
`shore`; mar en `water` y `shore`; aire en todo. La BFS
(`CombatRules.reachable_cells(origin, move, board, blocked, terrain, domain)`)
solo entra y pasa por lo que el dominio pisa. Sin terreno y con unidades de
tierra, sale la BFS de siempre.

### Las dos capas

Aire y superficie (tierra + mar) **comparten casilla**: un avion puede estar
encima de un soldado o de un barco. `CombatUnit.layer()` (`"air"` /
`"surface"`), `CombatRules.layer_of(domain)`, y
`CombatRules.occupied_cells(units, ignore_uid, layer)` bloquea solo la propia
capa. `Encounter.get_unit_at(cell)` devuelve la de superficie si la hay (si no, la
de aire); `get_unit_at_layer(cell, layer)` y `get_units_at(cell)` para elegir.
Entre capas la distancia de un golpe nunca baja de 1
(`CombatRules.strike_distance`): el avion justo encima de un soldado esta "a 1
casilla" y se pueden pegar los dos.

### Quien pega a quien

`GameConfig.combat_domain_targets[atacante][objetivo]` = alcance maximo (-1 su
alcance, 0 no puede, N como mucho N), y la fila `targets` de una unidad lo
corrige (el bombardero: `{"air": 0}`). `CombatRules.can_hit_from(attacker, from,
target)` / `in_attack_range()` / `max_reach()` lo aplican; si el tope queda por
debajo del alcance minimo, no le llega nunca.

| Atacante -> objetivo | tierra | mar | aire |
|---|---|---|---|
| tierra | su alcance | su alcance | **solo a 1** (la artilleria y las dotaciones de torre: nunca) |
| mar | su alcance | su alcance | **solo a 1** (el Acorazado: nunca, por su minimo 2) |
| aire | su alcance | su alcance | su alcance (el bombardero: nunca) |

No hay artilleria antiaerea: el caza es el antiaereo. Los barcos pegan a tierra
desde el agua o la orilla, que es donde estan siempre.

### Ventajas (×1,5 / ×0,75, `combat_type_advantage.beats`)

| Gana a... | |
|---|---|
| artilleria | tanque, canonera |
| tanque | infanteria |
| infanteria | artilleria |
| lancha torpedera | acorazado |
| acorazado | canonera, tanque |
| canonera | lancha torpedera, infanteria, caza |
| caza | bombardero, dirigible |
| bombardero | tanque, artilleria, canonera, acorazado |
| dirigible | infanteria, lancha torpedera |

El circulo de tierra no cambia (lo fija `test_type_advantage.gd`); ninguna
pareja va en los dos sentidos (`test_air_sea_rules.gd`). `TypeCircle` (el paso 7
del combate guiado) dibuja solo el circulo de tierra (`circle_ids(domain)`); la
ficha de cada unidad (`UnitCard`) lista todos sus cruces.

### Despliegue y reserva

`Encounter._deploy()` forma cada dominio por su cuenta, solo en las casillas que
pisa: primero el mar (agua y orilla), luego la tierra, luego el aire en su capa.
Las mismas dos filas por bando y el mismo centrado. Quien no encuentra sitio (un
barco en un tablero sin agua) pasa a `Encounter.reserve`: no esta en `units`, no
pelea, no muere y no cuenta para la retirada. Con solo tierra y sin terreno, el
despliegue es identico al de antes (`test_air_sea_rules.gd` lo compara).

### Donde hay agua

- **Misiones de costa** (`ExpeditionGenerator.offer_is_coastal(offer)`), desde la
  era `combat_coastal_min_era` (2): la expedicion al Puerto
  (`SORTIE_DEST_DOCK`) siempre; las incursiones de saqueadores con probabilidad
  `combat_coastal_raid_chance` (0,35, "piratas", flujo de azar propio
  `COAST_SEED_STRIDE`, no mueve nada de lo de antes); la avanzadilla de la
  Regencia y la primera escaramuza, nunca. `make_coastal(map, seed, era)` marca
  cada nodo (`coastal`, `terrain_seed`), pone **barcos enemigos**
  (`add_ships`: UN barco por combate, en el sitio de un cuerpo —un infante si
  sobra, si no un canon—, nunca deja la tierra vacia: era 2 una lancha, o canonera
  si el roster es grande o es jefe; era 3 una canonera, tambien el jefe. Sin
  acorazado enemigo: medido, el jefe del Puerto no se ganaba ni con flota, docs/16
  "Aire y mar") y da `combat_loot_coastal_parts` (1)
  repuesto de mas en el ultimo combate. `sortie_preview()` lleva `"coastal"` y la
  seleccion de tropa lo dice antes de salir.
- **En casa** (Impuesto, Ataque Final, escaramuza de pruebas):
  `CombatManager.home_terrain(units)` pone la costa de `combat_home_coast_seed`
  **solo si en el bando del jugador hay barcos**: tu flota guarda la playa. Sin
  barcos el tablero es todo tierra y el equilibrio de siempre no cambia. Los
  barcos enemigos no traen el agua (los Tasadores son de tierra).
- **Los barcos solo salen a misiones con agua**:
  `CombatManager.can_launch_to(party, offer)` (`MSG_SHIPS_NEED_WATER`),
  `launch_sortie()` y `launch_expedition()` (la de siempre y la primera
  escaramuza son de tierra) lo comprueban; `SkirmishPanel` agrupa la tropa por
  medio y deja los barcos sin poder elegirse cuando la salida no tiene agua. Si
  no tienes barcos, la mision de costa se juega igual: tus soldados pelean en la
  orilla y la artilleria alcanza a los barcos desde tierra.

### El Ataque Final

El codigo deja que la ultima oleada, desde la era 3, traiga dirigibles en el
hueco de un canon y, si tu guarnicion tiene aviones, cazas de escolta
(`FinalAudit.air_escort`, va en el guardado). **Medido, los dos van APAGADOS**
(`final_audit_airships_last_wave` = 0, `final_audit_air_escort_fighters` = 0): con
un dirigible la guarnicion de referencia bajaba del 86 % al 13,5 % (la IA se
engancha en el), y la escolta hacia que tener cazas restara. Cifras y por que:
[17](17-balance-asedio.md), "Aire y mar".

### La colonia

- **Astillero** (`shipyard`, 2x2, era 2: pide Fundicion; tiene que tocar la costa,
  `PlacementRules.SHORE_ONLY`) y **Aerodromo** (`aerodrome`, 2x2, era 3: pide
  Refineria). Topes 1/1/2. Ver [03](03-buildings.md).
- `ArmyManager`: cada unidad se entrena en su edificio
  (`unit_types[...]["building"]`, sin clave = Cuartel), con un hueco por
  edificio solo para las suyas (`max_slots(building)`, `training_in(building)`);
  la capacidad suma `army_capacity_per_building` (Cuartel 8, Astillero 4,
  Aerodromo 4). `has_military_building()` abre el panel del ejercito y las
  escaramuzas. No hay estado nuevo en el guardado: un guardado viejo carga igual.
- `ArmyPanel` agrupa TIERRA / MAR / AIRE con su edificio; sin el, candado y
  "Construye: Astillero".
- `get_garrison()` sigue llenando por poder: barcos y aviones tambien defienden.

### Pendiente

- Medido (ronda de la 1.1): `balance_probe -- --only=coast` y `siege_probe` ya
  componen flotas y aviones; cifras en docs/16 y docs/17, "Aire y mar".
- **La IA y los objetivos duros:** `CombatAI._target_quality` prefiere el rival
  de mas `power` a igual ventaja, asi que los blindados persiguen un dirigible
  (260 de vida, solo a 1 casilla) mientras los canones los rompen. Es lo que
  hunde el asedio con dirigible; antes de volver a encenderlo, la IA tiene que
  pesar el dano que hace de verdad (o el dirigible de la Regencia, otra fila).
- `BattleScreen` (2D): el avion encima de un soldado ya se ve (silueta pequena
  arriba, `board_air_mark`), pero tocar la casilla selecciona al soldado
  (`get_unit_at`); para elegir capa hara falta un gesto.
- Los barcos forman en el agua: `Encounter._fill_row` deja la orilla (arena) para
  cuando el agua de la fila no basta. Antes centraba entre agua y orilla y un
  acorazado empezaba varado en la playa.
- Tablero 3D con escenario de playa: las columnas de agua siguen por el borde del
  fondo hasta el mar (`BoardTerrain3D._beach`), no las corta la arena.

### La vista

**1.1: la vista ya esta** (rama `feat/aire-mar-vista`, ver §3 "Mar y aire en la
maqueta"): las seis piezas (`torpedo_boat`, `gunboat`, `dreadnought`,
`fighter`, `bomber`, `airship`), sus siluetas 2D, el agua del tablero 3D, del
frente y del 2D, el despegue y el deslizarse en lugar del saltito, y las
maquetas del Astillero y el Aerodromo. Las reglas (terreno del encuentro,
movimiento y objetivos por dominio, entrenamiento) van en `feat/aire-mar-reglas`.

## 12. El regimiento (solo cosmético)

Fila 3.1 del rediseño (doc 21 §5.1, rama `feat/regimiento`, 2026-10-14). El
ejército del jugador tiene **nombre, color, emblema, pintura y estrellas**. Nada
de esto cambia una cifra del combate: ni `CombatUnit`, ni `CombatRules`, ni
`Encounter`, ni la IA lo leen (`tests/combat/test_regiment.gd` lo fija leyendo
sus fuentes).

| Qué | Cómo se elige | Se abre con |
|---|---|---|
| Nombre | Texto libre (mismo filtro y largo que el nombre del país) o AL AZAR ("Brigada del Faro") | Libre; vacío = "Primer Regimiento" |
| Color | "Como la bandera" o uno de `colony_colors` | Los colores de la bandera abiertos por rango |
| Emblema | "Como la bandera" o uno de `COLONY_EMBLEMS` | Los emblemas de la bandera abiertos por rango |
| Pintura | Liso, rayas, manchas, desierto, nieve, gala (`REGIMENT_PAINTS`) | Rangos 1, 3, 6, 9, 12, 15 (`rank_rewards` clave `paints`) |
| Estrellas | Automáticas | 10 / 25 / 50 combates ganados (`regiment_star_wins`) |

- **Dónde se edita:** tarjeta REGIMIENTO arriba de la lista del Cuartel
  (`scripts/ui/RegimentCard.gd`, dentro de `ArmyPanel`). Insignia, nombre y
  victorias; CAMBIAR despliega la galería. Cada elección se aplica al momento; lo
  cerrado sale con candado y "Rango N".
- **Datos:** `ArmyManager` guarda `"regiment": {"name", "color", "emblem", "paint",
  "wins"}` dentro de `"army"`. "" en color o emblema = el de la bandera (un
  regimiento sin tocar sigue a la colonia). Guardado viejo = el de serie;
  `reset()` lo tira; `load_save_data()` deriva de lo guardado (idempotente) y **no
  recorta** por rango, porque el ejército carga antes que el rango: lo que se pinta
  lo resuelve `ArmyManager.get_regiment_look()` (`RegimentLook.resolve()`), que
  cambia por la de la bandera (o liso) cualquier pieza que el rango no abra.
  `set_regiment()` rechaza piezas cerradas y nombres que no pasan el filtro.
  Las victorias se cuentan con `encounter_ended(true)` y
  `defense_auto_resolved(true)`, como la XP del rango. Señal: `regiment_changed`.
- **Cómo se ve:**
  - **Vista frontal y tablero 8x8 3D** (`Board3D`, opción `regiment`): la
    superficie `team` de nuestras piezas lleva el color y la pintura. Liso usa el
    `StandardMaterial3D` de siempre; con pintura, un `ShaderMaterial` de
    `scripts/combat_view/regiment_paint.gdshader` (patrón procedural en espacio
    del modelo, sin texturas), **uno por color y pintura**, compartido por todas las
    piezas. Junto a la placa de vida va la **insignia** (disco del color con el
    emblema y las estrellas debajo): un `Sprite3D` por ficha con **una sola
    textura** en caché (`RegimentLook.badge_texture()`). La Regencia no lleva nada.
  - **Tablero 2D:** la marca circular de nuestras fichas toma el color del
    regimiento, y un aro de latón si tiene estrellas.
- **Rendimiento:** sin `_process`, sin luces, como mucho un material más por pelea;
  la insignia y las muestras de pintura se generan una vez por aspecto.
- **Pendiente (doc 21 §5.1):** cascos y chapas (piezas sueltas por planos raros),
  "por tipo de unidad" en vez de por regimiento entero, coste en oro de pinturas.
