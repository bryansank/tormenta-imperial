# Data Model: Combate Roguelike por Turnos (PVE)

**Feature**: `001-combate-pve` | **Date**: 2026-09-12 | **Phase**: 1

Todas las entidades son `RefCounted` en `scripts/combat/` (sin nodos), poseídas por `CombatManager`. Los valores de balance vienen de `GameConfig.combat_*` (ver `research.md` D4).

---

## CombatUnit (`scripts/combat/CombatUnit.gd`)

Instancia de una unidad dentro de una expedición. Persiste entre encuentros hasta morir.

| Campo | Tipo | Regla |
|---|---|---|
| `uid` | `int` | Único dentro de la expedición; asignado por `Expedition` al comprometer o al generar enemigos |
| `unit_id` | `String` | Clave de `GameConfig.unit_types` (`infantry`, `artillery`, `vehicle`) |
| `side` | `int` | 0 jugador, 1 enemigo |
| `hp` | `int` | 0 < hp ≤ `max_hp`; al llegar a 0 → muerte permanente (FR-010) |
| `max_hp` | `int` | `combat_unit_stats[unit_id].hp` × multiplicador de dificultad (solo enemigos) |
| `position` | `Vector2i` | Celda del tablero; `Vector2i(-1,-1)` fuera de tablero (entre encuentros) |
| `has_acted` | `bool` | Se pone en `true` al mover+actuar o al defender/esperar; se resetea por ronda |
| `moved_this_turn` | `bool` | Permite mover y luego atacar en el mismo turno, pero no dos movimientos |
| `defending` | `bool` | DEF ×2 hasta su próximo turno (FR-008 "defender") |
| `draft_bonuses` | `Dictionary` | Modificadores acumulados por drafts (`{"atk": +2}`); solo jugador, solo esta expedición (FR-018) |

**Derivados** (no se guardan): `attack()`, `defense()`, `move_range()`, `attack_range()`, `min_range()`, `initiative()` = stat base + bonos de draft + modificador de moral (solo jugador).

**Transiciones**: `alive → dead` (irreversible). Entre encuentros: `position` se limpia, `hp` **no se restaura** (FR-011), `defending` y flags de turno se resetean.

---

## Encounter (`scripts/combat/Encounter.gd`)

Una batalla en un nodo del mapa.

| Campo | Tipo | Regla |
|---|---|---|
| `board_size` | `Vector2i` | `GameConfig.combat_board_size` |
| `units` | `Array[CombatUnit]` | Vivas y muertas de ambos bandos en este encuentro |
| `turn_order` | `Array[int]` | `uid`s ordenados por iniciativa desc.; empate → jugador primero, luego `uid` (FR-006, observable) |
| `turn_index` | `int` | Índice en `turn_order` de la unidad activa |
| `round` | `int` | Incrementa al agotar `turn_order`; límite `combat_turn_limit` |
| `is_boss` | `bool` | Aplica `combat_boss_multiplier` |
| `state` | `enum` | `DEPLOYING → PLAYER_TURN / ENEMY_TURN → WON / LOST / TIMEOUT` |
| `deploy_zones` | `Dictionary` | `{0: Array[Vector2i], 1: Array[Vector2i]}` — filas 0-1 enemigo, filas 6-7 jugador |

**Validaciones**:
- Una celda contiene como máximo una unidad viva.
- `move`: destino alcanzable por BFS en 4 direcciones dentro de `move_range`, sin atravesar unidades.
- `attack`: distancia Manhattan al objetivo ∈ `[min_range, attack_range]`, objetivo vivo del bando contrario.
- `TIMEOUT` (FR-015): al superar `combat_turn_limit`, gana el bando con mayor suma de HP; empate → derrota del jugador (la expedición castiga el estancamiento).

---

## ExpeditionNode

Diccionario plano dentro de `Expedition.map`.

| Campo | Tipo | Regla |
|---|---|---|
| `index` | `int` | Posición en `map`; 0 = inicio, último = jefe |
| `depth` | `int` | Distancia desde el inicio; escala la dificultad |
| `exits` | `Array[int]` | Índices alcanzables; ≥1 salvo el jefe; **todo nodo alcanza al jefe** (invariante del generador) |
| `enemy_roster` | `Dictionary` | `unit_id -> count`, generado por semilla, profundidad y era |
| `risk` | `int` | 0 bajo, 1 medio, 2 alto — escala roster y recompensa (FR-003a) |
| `is_boss` | `bool` | Solo el último |
| `cleared` | `bool` | Marcado al ganar |

---

## Expedition (`scripts/combat/Expedition.gd`)

| Campo | Tipo | Regla |
|---|---|---|
| `id` | `int` | Incremental; para logs y señales |
| `seed` | `int` | Fuente de toda aleatoriedad (D5) |
| `map` | `Array[Dictionary]` | Nodos; regenerable desde `seed` |
| `current_node` | `int` | Índice del nodo actual |
| `party` | `Array[CombatUnit]` | Unidades del jugador (vivas y caídas) |
| `draft_picks` | `Array[Dictionary]` | Mejoras elegidas, en orden |
| `rewards` | `Dictionary` | `resource_name -> int` acumulado |
| `morale_snapshot` | `float` | Moral de la base al lanzar; fija los modificadores de toda la expedición |
| `state` | `enum` | `ACTIVE → COMPLETED / DEFEATED / ABANDONED` |

**Transiciones**:
- `launch` → `ACTIVE`, `current_node = 0`, se genera el primer encuentro.
- `encounter WON` → si `is_boss` → `COMPLETED`; si no → `draft_offered`, luego el jugador elige salida.
- `encounter LOST` (party aniquilado) → `DEFEATED`.
- `abandon` → `ABANDONED` (conserva `rewards` y supervivientes, FR-016).
- Cualquier estado terminal → `CombatManager` aplica resultado a la base y descarta la expedición.

---

## DraftOption

Diccionario generado por `ExpeditionGenerator.draft_options(rng, party)`; siempre ≥2 aplicables (SC-009).

| Campo | Tipo |
|---|---|
| `id` | `String` (`draft_atk`, `draft_def`, `draft_hp_heal`, `draft_move`, `draft_init`) |
| `label_key` | clave `Tr` |
| `effect` | `Dictionary` (`{"stat": "atk", "delta": 2}` o `{"heal_pct": 0.3}`) |
| `applies_to` | `"all"` o un `unit_id` |

"Aplicable" = al menos una unidad viva se beneficia (curar con todos al 100% no es aplicable).

---

## ExpeditionResult (valor de retorno, no persistido)

```
{ result: int (0/1/2), rewards: Dictionary, casualties: Dictionary (unit_id -> count),
  survivors: Dictionary (unit_id -> count), nodes_cleared: int, boss_defeated: bool }
```

`CombatManager` lo traduce en: `ResourceManager.add(...)` por recompensa, `ArmyManager` descuenta bajas (las supervivientes ya estaban contadas; nunca se duplican), `PopulationManager` recibe el ajuste de moral (D8), `EventBus.expedition_ended`.

---

## Esquema de guardado (`data["expedition"]`)

```json
{
  "id": 3,
  "seed": 918273645,
  "current_node": 2,
  "state": 0,
  "morale_snapshot": 72.0,
  "party": [ {"uid": 1, "unit_id": "infantry", "hp": 18, "draft_bonuses": {"atk": 2}}, ... ],
  "draft_picks": [ {"id": "draft_atk", ...} ],
  "rewards": {"gold": 120, "wood": 60},
  "cleared": [0, 1]
}
```

- Clave ausente o `state` terminal → sin expedición activa (compatibilidad hacia atrás, Principio V).
- El mapa **no** se guarda: se regenera desde `seed` y se aplica `cleared`.
- El encuentro en curso no se guarda a mitad de turno: al reanudar, el nodo actual se redespliega (D6).

---

## Relación con estado existente

- `ArmyManager._units` es la **fuente de verdad** del ejército. Al lanzar, `CombatManager` no descuenta unidades; marca `party` como "en expedición" y `ArmyManager.get_count()` sigue contándolas. Al terminar, descuenta solo las bajas. Así `army_changed` y el Poder Militar reflejan exactamente supervivientes (SC-004).
- Unidades en expedición no pueden ser comprometidas de nuevo mientras esté activa (`get_deployable_units()` las excluye).
- `ArmyManager.get_power()` no cambia durante la expedición; cambia al resolverla.
