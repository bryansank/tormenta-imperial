# Contrato: señales de combate en `EventBus`

Nueva categoría `# ── Combat ──` en `scripts/services/EventBus.gd`, declarada antes de emitir (Principio I). Único productor: `CombatManager`. Tipos en `snake_case` según convención.

| Señal | Argumentos | Cuándo se emite | Consumidores previstos |
|---|---|---|---|
| `expedition_started` | `(expedition_id: int, node_count: int)` | Al lanzar una expedición desde `SkirmishPanel` | `BattleScreen` (abre mapa), `ArmyPanel` (unidades comprometidas), `AudioManager` |
| `expedition_node_selected` | `(node_index: int)` | El jugador elige una ruta | `BattleScreen` |
| `encounter_started` | `(encounter_index: int, is_boss: bool)` | Tablero desplegado, listo para el primer turno | `BattleScreen`, `AudioManager` |
| `turn_started` | `(side: int, unit_uid: int)` | Empieza el turno de una unidad (`side`: 0 jugador, 1 enemigo) | `BattleScreen` (resalta, habilita acciones) |
| `unit_moved` | `(unit_uid: int, from: Vector2i, to: Vector2i)` | Movimiento resuelto | `BattleScreen` (animación), `AudioManager` |
| `unit_attacked` | `(attacker_uid: int, target_uid: int, damage: int)` | Ataque resuelto, HP ya descontado | `BattleScreen` (número flotante), `AudioManager` |
| `unit_defended` | `(unit_uid: int)` | Unidad en postura defensiva hasta su próximo turno | `BattleScreen` |
| `unit_died` | `(unit_uid: int, side: int)` | HP llegó a 0; la unidad sale del tablero | `BattleScreen`, `AudioManager` |
| `encounter_ended` | `(victory: bool, turns_used: int)` | Un bando eliminado o límite de turnos resuelto | `BattleScreen`, `NotificationPanel` |
| `draft_offered` | `(options: Array[Dictionary])` | Tras ganar un encuentro no final | `BattleScreen` (muestra opciones) |
| `draft_applied` | `(option: Dictionary)` | El jugador eligió una mejora | `BattleScreen` |
| `expedition_ended` | `(result: int, rewards: Dictionary, casualties: Dictionary)` | `result`: 0 victoria, 1 derrota, 2 abandono | `BattleScreen` (cierra), `NotificationPanel`, `PopulationManager` (moral), `ArmyPanel` |

## Señales existentes que el combate consume

| Señal | Uso |
|---|---|
| `army_changed` | `SkirmishPanel` refresca las unidades comprometibles |
| `morale_changed` (si existe; si no, leer `PopulationManager` en el momento de lanzar) | Modificador de moral fijado al inicio de la expedición |
| `game_load_completed` | `CombatManager` reanuda la expedición guardada; `BattleScreen` se abre si hay una en curso |

## API pública de `CombatManager` (lectura para UI)

```
func has_active_expedition() -> bool
func get_expedition() -> Expedition            # null si no hay
func get_encounter() -> Encounter              # null fuera de encuentro
func get_deployable_units() -> Dictionary      # unit_id -> count disponible
func can_launch(party: Dictionary) -> Dictionary  # {ok: bool, reason: String}
func launch_expedition(party: Dictionary) -> void
func select_node(node_index: int) -> void
func get_valid_moves(unit_uid: int) -> Array[Vector2i]
func get_valid_targets(unit_uid: int) -> Array[int]
func move_unit(unit_uid: int, to: Vector2i) -> bool
func attack(unit_uid: int, target_uid: int) -> bool
func defend(unit_uid: int) -> void
func wait(unit_uid: int) -> void
func apply_draft(option_index: int) -> void
func abandon_expedition() -> void
func get_save_data() -> Dictionary
func load_save_data(data: Dictionary) -> void
func reset() -> void
```

Toda mutación de estado pasa por estos métodos; la UI nunca toca `Encounter`/`Expedition` directamente (Principio IV).

## Claves de traducción nuevas (`Tr.gd`, ES y EN)

`BTN_SKIRMISH`, `BTN_LAUNCH_EXPEDITION`, `BTN_ABANDON`, `BTN_END_TURN`, `BTN_DEFEND`, `BTN_WAIT`,
`LBL_SKIRMISH_TITLE`, `LBL_DEPLOY_CAP`, `LBL_EXPEDITION_MAP`, `LBL_ENCOUNTER_N`, `LBL_BOSS`,
`LBL_TURN_PLAYER`, `LBL_TURN_ENEMY`, `LBL_DRAFT_TITLE`, `LBL_VICTORY`, `LBL_DEFEAT`,
`LBL_REWARDS`, `LBL_CASUALTIES`, `MSG_NO_UNITS`, `MSG_EXPEDITION_WON`, `MSG_EXPEDITION_LOST`,
`MSG_EXPEDITION_ABANDONED`, `DRAFT_*` (una por mejora del draft), `OBJ_ELIMINATE_ALL`.
