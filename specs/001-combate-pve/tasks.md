# Tasks: Combate Roguelike por Turnos (PVE)

**Input**: Design documents from `/specs/001-combate-pve/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/eventbus-combat.md, quickstart.md

**Tests**: incluidos para `scripts/combat/` (funciones puras) según research D9. La UI se valida con Beckett siguiendo quickstart.md.

**Organization**: por user story. Cada tarea cabe en una sesión de 2-4 h y deja el juego corriendo sin errores al terminar. Tras cada tarea: `validate_script` + `play_scene` + `game_logs` vacío + commit.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: paralelizable (archivos distintos, sin dependencias)
- **[Story]**: US1 encuentro · US2 expedición · US3 economía · US4 IA

---

## Phase 1: Setup

**Purpose**: dependencias, balance, señales y textos — todo lo que las stories consumen.

- [x] T001 Instalar gdUnit4 en `addons/gdUnit4/` (AssetLib) y activarlo en `project.godot` `[editor_plugins]`; crear `tests/combat/.gitkeep`
- [x] T002 [P] Añadir a `scripts/services/GameConfig.gd` las claves `combat_*` y `combat_unit_stats` con los valores de research.md D4, más `get_combat_stats(unit_id) -> Dictionary`
- [x] T003 [P] Declarar la categoría `# ── Combat ──` con las 12 señales de `contracts/eventbus-combat.md` en `scripts/services/EventBus.gd`
- [x] T004 [P] Añadir las claves `Tr` de `contracts/eventbus-combat.md` en ES y EN en `scripts/services/Tr.gd` (sin acentos, como el resto del archivo); validar con `validate_script` (detecta claves duplicadas)
- [x] T005 [P] Añadir slots en `scripts/ui/UILayoutConfig.gd`: `SkirmishPanel.button` → `sidebar_buttons` (tras `ArmyPanel.button` en `SIDEBAR_BUTTON_ORDER`), `SkirmishPanel.modal` → `center_modal` (`PANEL_SIZES` 520×0), `BattleScreen` → `full_overlay`

**Checkpoint**: el juego arranca igual que antes, `game_logs` vacío, sin UI nueva visible todavía.

---

## Phase 2: Foundational

**Purpose**: entidades y reglas puras + el servicio dueño. Bloquea todas las stories.

- [x] T006 [P] Crear `scripts/combat/CombatUnit.gd` (`RefCounted`) según data-model.md: campos, derivados (`attack()`, `defense()` con `defending` ×2, `initiative()`), `to_dict()` / `from_dict()`
- [x] T007 [P] Crear `scripts/combat/CombatRules.gd` (estático): `damage(attacker, target, morale_mod) -> int` (mín. 1), `morale_attack_mod(morale) -> float`, `morale_initiative_bonus(morale) -> int`, `manhattan()`, `in_attack_range()`, `reachable_cells(board, from, move_range, blocked) -> Array[Vector2i]` (BFS 4 direcciones), `resolve_timeout(units) -> int`
- [x] T008 Tests `tests/combat/test_combat_rules.gd`: daño mínimo 1; defender duplica DEF; moral 0/50/100 da 0.85/1.0/1.15; artillería no alcanza adyacente (min_range 2); BFS no atraviesa unidades; timeout con empate → derrota
- [x] T009 Crear `scripts/services/CombatManager.gd` (autoload): estado (`_expedition`, `_encounter`), API pública completa de `contracts/eventbus-combat.md` como stubs que emiten señales, `get_save_data()` / `load_save_data()` / `reset()`; registrar en `project.godot` **tras** `ArmyManager` y **antes** de `RandomEventManager`
- [x] T010 Cablear `scripts/services/GameManager.gd`: `data["expedition"] = CombatManager.get_save_data()` en guardado; `if data.has("expedition"): CombatManager.load_save_data(...)` en carga; `CombatManager.reset()` en `clear_save()`
- [x] T011 Crear `scenes/ui/BattleScreen.tscn` + `scripts/ui/BattleScreen.gd` (CanvasLayer, `layer = 12`, oculto; se registra en `UIManager` como `"BattleScreen"`) y `scenes/ui/SkirmishPanel.tscn` + `scripts/ui/SkirmishPanel.gd` (patrón exacto de `ArmyPanel.gd`: botón lateral visible solo con Cuartel, backdrop, modal); instanciar ambos en `scenes/main/Main.tscn`

**Checkpoint**: nuevo botón **Escaramuzas** en la barra lateral abre un modal vacío y lo cierra. Arranque limpio. Tests de reglas en verde.

---

## Phase 3: User Story 1 — Un encuentro táctico por turnos (P1) 🎯 MVP

**Goal**: un tablero 8x8 jugable de principio a fin contra una IA mínima, lanzado desde un botón de prueba en `dev_mode`.

**Independent Test**: quickstart E1 usando el botón dev; victoria y derrota declaradas; `game_logs` vacío; < 5 min.

- [x] T012 [US1] Crear `scripts/combat/Encounter.gd`: tablero, `deploy_zones` (filas 0-1 enemigo, 6-7 jugador), `deploy(units)`, cálculo de `turn_order` (iniciativa desc., jugador gana empates, luego `uid`), `advance_turn()` con reset de flags por ronda, transiciones `DEPLOYING → PLAYER_TURN/ENEMY_TURN → WON/LOST/TIMEOUT`
- [x] T013 [US1] `CombatManager`: `start_encounter(party, enemy_roster, is_boss)`, `get_valid_moves()`, `get_valid_targets()`, `move_unit()`, `attack()`, `defend()`, `wait()`, `end_turn()`; emitir `encounter_started`, `turn_started`, `unit_moved`, `unit_attacked`, `unit_defended`, `unit_died`, `encounter_ended`. Enemigo generado por `dev_encounter_roster()` provisional (2 infanterías + 1 artillería)
- [x] T014 [US1] `CombatManager.dev_start_encounter()` (solo `GameConfig.dev_mode`): toma hasta `combat_deploy_cap` unidades de `ArmyManager` y arranca un encuentro suelto. `SkirmishPanel`: botón **Escaramuza de prueba** visible solo en `dev_mode`
- [x] T015 [US1] `BattleScreen` — tablero: `GridContainer` 8x8 de botones-celda (`UITheme`, ≥44 px), backdrop oscuro sobre la base, cabecera con `LBL_ENCOUNTER_N`; pintar unidades (icono/letra + barra de HP + color de bando) desde `CombatManager.get_encounter()`; refrescar en cada señal
- [x] T016 [US1] `BattleScreen` — selección y movimiento: clic en unidad propia activa la resalta y pinta `get_valid_moves()`; clic en celda válida → `move_unit()`; deshabilitar si `moved_this_turn`
- [x] T017 [US1] `BattleScreen` — ataque y acciones: pintar `get_valid_targets()` tras seleccionar; clic en objetivo → `attack()` + número flotante de daño (reusar `FloatingText` o `Label` animado 2D); botones **Defender**, **Esperar**, **Terminar turno**
- [x] T018 [US1] `BattleScreen` — orden de turno visible (fila de retratos por iniciativa, activo resaltado, `LBL_TURN_PLAYER` / `LBL_TURN_ENEMY`) y contador de ronda con límite
- [x] T019 [US1] Crear `scripts/combat/CombatAI.gd` mínimo: para cada unidad enemiga, si hay objetivo en rango → atacar al de menor HP; si no → moverse por BFS hacia la unidad jugador más cercana respetando `min_range`; si nada → esperar. `CombatManager` ejecuta el turno enemigo con un `Timer`/`await` corto por acción para que se vea (duración en `GameConfig.combat_ai_step_delay`)
- [x] T020 [US1] Fin de encuentro: `encounter_ended` → `BattleScreen` muestra resultado (`LBL_VICTORY` / `LBL_DEFEAT`, turnos usados) y botón cerrar; en el flujo dev vuelve a la base. Límite de turnos aplica `CombatRules.resolve_timeout()`
- [x] T021 [US1] Legibilidad y táctil: probar a 400×720 (quickstart E9); ajustar tamaño de celda y posición de botones de acción; verificar con `ui_snapshot` que no hay controles fuera de pantalla

**Checkpoint**: 🎬 **Hito A cerrado.** Un encuentro completo, jugable de principio a fin. Es el primer incremento demostrable del pilar.

---

## Phase 4: User Story 2 — Expedición roguelike de encuentros encadenados (P1)

**Goal**: mapa ramificado procedural, draft, atrición, permadeath y jefe, lanzado desde `SkirmishPanel` real.

**Independent Test**: quickstart E2; dos expediciones consecutivas difieren; draft siempre ≥2 opciones.

- [ ] T022 [P] [US2] Crear `scripts/combat/ExpeditionGenerator.gd` (estático, recibe `RandomNumberGenerator`): `generate_map(rng, depth_range, branching_range) -> Array[Dictionary]` con invariante "todo nodo alcanza al jefe"; `enemy_roster(rng, depth, era, risk) -> Dictionary`; `boss_roster(...)`; `draft_options(rng, party, count) -> Array[Dictionary]` filtrando no aplicables
- [ ] T023 [P] [US2] Tests `tests/combat/test_expedition_generator.gd`: conectividad al jefe en 200 semillas; profundidad dentro de rango; dos semillas distintas → mapas distintos; draft nunca con < 2 aplicables; roster crece con `depth`
- [ ] T024 [US2] Crear `scripts/combat/Expedition.gd`: campos de data-model.md, `from_army(party_counts) -> party de CombatUnit`, `current_exits()`, `mark_cleared()`, `apply_draft(option)`, `is_finished()`, `to_dict()` / `from_dict()` (regenera `map` desde `seed` + `cleared`)
- [ ] T025 [US2] `CombatManager.launch_expedition(party)`: valida con `can_launch()` (FR-001, FR-002, cap), crea `Expedition` con semilla nueva y `morale_snapshot`, emite `expedition_started`, arranca el encuentro del nodo 0. `select_node()` valida que sea una salida del nodo actual
- [ ] T026 [US2] `SkirmishPanel` real: lista de unidades disponibles (`get_deployable_units()`) con +/- hasta `combat_deploy_cap`, resumen de poder comprometido, botón **Lanzar expedición**; `MSG_NO_UNITS` cuando no hay; ocultar el botón dev cuando `dev_mode` es false
- [ ] T027 [US2] `BattleScreen` — vista de mapa: nodos como botones en columnas por `depth`, líneas entre nodos (`Line2D` o `draw_line`), actual/limpiados/jefe distinguidos, riesgo indicado; clic en salida válida → `select_node()`
- [ ] T028 [US2] Encadenar encuentros: al ganar, `CombatManager` mantiene `hp` de supervivientes (FR-011), retira muertos del `party` activo (FR-010), y si no es jefe emite `draft_offered`; tras `apply_draft` vuelve a la vista de mapa
- [ ] T029 [US2] `BattleScreen` — draft: modal con `combat_draft_options` tarjetas (`Tr` `DRAFT_*`), clic → `apply_draft(i)`; mostrar bonos activos del party en la vista de mapa
- [ ] T030 [US2] Jefe y cierre: `is_boss` aplica `combat_boss_multiplier`; ganar el jefe → `COMPLETED`; party aniquilado → `DEFEATED`; ambos emiten `expedition_ended` y `BattleScreen` muestra pantalla final (`LBL_REWARDS`, `LBL_CASUALTIES`)
- [ ] T031 [US2] Abandonar: botón **Abandonar** (mapa y tablero) → `ConfirmationDialog` → `abandon_expedition()` (FR-016) → `expedition_ended(2, ...)`

**Checkpoint**: 🎬 **Hito C cerrado.** Expedición completa de lanzamiento a jefe, con draft y bajas.

---

## Phase 5: User Story 3 — El resultado impacta la economía (P2)

**Goal**: recompensas, bajas, curación y **moral** fluyen entre expedición y base; el guardado reanuda.

**Independent Test**: quickstart E3, E4, E6, E7.

- [ ] T032 [US3] `ArmyManager`: `get_available_for_deploy() -> Dictionary` (excluye unidades marcadas en expedición por `CombatManager`), `remove_casualties(casualties: Dictionary)` que descuenta `_units` y emite `army_changed`; `get_power()` inalterado hasta ese momento (SC-004)
- [ ] T033 [US3] `CombatManager._resolve_expedition(result)`: `ResourceManager` suma `rewards` (respetando tope de almacén; el sobrante se pierde con aviso), `ArmyManager.remove_casualties()`, supervivientes vuelven al 100% (FR-017), emite `expedition_ended`, descarta la expedición
- [ ] T034 [P] [US3] `NotificationPanel`: toasts en `expedition_started` y `expedition_ended` (`MSG_EXPEDITION_WON/LOST/ABANDONED` con botín y bajas) — FR-018
- [ ] T035 [US3] **Puente de moral** (hito B): `CombatUnit.initiative()` y `CombatRules.damage()` usan `morale_snapshot` vía `combat_morale_*`; `PopulationManager.apply_expedition_morale(result, casualties)` conectado a `expedition_ended` (+`combat_morale_on_victory`, `combat_morale_per_casualty` × bajas); mostrar el modificador activo en `SkirmishPanel` ("Moral 72 → iniciativa +1, ataque ×1.07")
- [ ] T036 [US3] Reanudar: `CombatManager.load_save_data()` reconstruye `Expedition` desde `seed`+`cleared`+`party`; en `game_load_completed`, si hay expedición activa `BattleScreen` abre la vista de mapa en el nodo actual (D6). Probar cerrar/abrir a mitad (E6) y cargar un save previo sin clave `expedition`
- [ ] T037 [P] [US3] `ArmyPanel` y `SkirmishPanel` se refrescan en `expedition_started` / `expedition_ended`; unidades en expedición aparecen como "en campaña" en `ArmyPanel`

**Checkpoint**: 🎬 **Hito D (parte 1).** La expedición se siente consecuencia de la base y vuelve a ella.

---

## Phase 6: User Story 4 — IA táctica y dificultad escalada (P3)

**Goal**: la IA elige objetivos con criterio y la dificultad crece con profundidad y era.

**Independent Test**: quickstart E5; SC-007.

- [x] T038 [US4] `CombatAI` prioridad de objetivo: (1) enemigo que puede matar este turno, (2) mayor `power`, (3) menor HP, (4) más cercano; artillería prefiere mantenerse a `attack_range` y retrocede si un enemigo está a `< min_range`
- [ ] T039 [US4] `CombatAI` movimiento: si ningún objetivo está en rango, elegir la celda alcanzable que minimiza la distancia al objetivo prioritario **y** deja en rango si es posible; unidades con `defending` disponible y sin objetivo alcanzable → defender en vez de esperar
- [x] T040 [US4] Escalado: `ExpeditionGenerator.enemy_roster()` aplica `combat_enemy_scale_per_depth` y `combat_enemy_scale_per_era` a HP/ATK y al tamaño del roster (cap `combat_deploy_cap`); el jefe añade una unidad de tier máximo disponible en la era
- [x] T041 [US4] Tests en `test_combat_rules.gd` / nuevo `tests/combat/test_combat_ai.gd`: la IA ataca cuando hay objetivo en rango; elige el objetivo matable; artillería no se acerca a adyacente; nunca devuelve "sin acción" con un objetivo alcanzable (SC-007)

**Checkpoint**: 🎬 **Hito D cerrado.** Combate PVE completo según spec.

---

## Phase 7: Polish & Cross-Cutting

- [ ] T042 [P] `AudioManager`: SFX en `unit_attacked`, `unit_died`, `encounter_ended`, `expedition_ended`; música de combate opcional por señal (usar tracks existentes; ambientes siguen fuera de alcance)
- [ ] T043 [P] `HelperPanel`: un callout para el botón **Escaramuzas** cuando aparece el Cuartel (un solo callout, no una pared)
- [ ] T044 [P] Docs: crear `docs/14-combat.md` (sistemas, señales, balance), añadir a `docs/INDEX.md`; actualizar tabla de autoloads (20) y estructura en `CLAUDE.md`; actualizar `docs/13-roadmap.md`
- [ ] T045 Recorrer `quickstart.md` E1-E9 completo con Beckett; capturar el tablero con `tools/ui_tour.gd` para el devlog
- [ ] T046 Balance inicial: sesión de juego real de 30 min; ajustar solo `GameConfig.combat_*` hasta que un encuentro dure 3-5 min y la primera expedición sea ganable con 3-4 unidades de era 1

---

## Dependencies & Execution Order

- **Phase 1 → Phase 2 → US1** son estrictamente secuenciales (US1 necesita reglas, servicio y escenas).
- **US2** depende de US1 (reutiliza tablero y flujo de encuentro).
- **US3** depende de US2 para el flujo completo, pero T032, T034 y T035 pueden empezar tras US1 (el puente de moral solo necesita el encuentro).
- **US4** depende de US1 (IA mínima) y de US2 para el escalado por profundidad.
- **Polish** al final, salvo T044 que puede ir actualizándose por hito.

### Parallel Opportunities

- Phase 1: T002, T003, T004, T005 en paralelo (archivos distintos).
- Phase 2: T006 y T007 en paralelo; T008 tras T007.
- US2: T022 + T023 en paralelo con T024.
- US3: T034 y T037 en paralelo con T033.

---

## Implementation Strategy

**MVP = Phase 1 + Phase 2 + US1.** Al cerrar T021 hay un juego de combate mostrable aunque no exista la expedición. Con < 5 h/semana eso son ~6-8 sesiones. Parar ahí, grabar el GIF, y solo entonces seguir con US2.

Reglas de higiene: una rama por hito (`feat/combate-encuentro`, `feat/combate-expedicion`, `feat/combate-economia`, `feat/combate-ia`), PR a `main`, y la base del juego congelada mientras dure el pilar de combate.

## Mapa de sesiones (estimación)

| Sesiones | Tareas | Hito |
|---|---|---|
| 1 | T001-T005 | Setup |
| 2-3 | T006-T011 | Foundational |
| 4-9 | T012-T021 | **A — encuentro jugable** |
| 10-14 | T022-T031 | **C — expedición** |
| 15-17 | T032-T037 | **B + D — moral, economía, reanudar** |
| 18-19 | T038-T041 | **D — IA** |
| 20-21 | T042-T046 | Pulido |

Coincide con las 12-16 sesiones de combate + pulido previstas en el plan estratégico.
