# Research: Combate Roguelike por Turnos (PVE)

**Feature**: `001-combate-pve` | **Date**: 2026-09-12 | **Phase**: 0

Resuelve las incógnitas técnicas del plan. Cada decisión lista qué se eligió, por qué y qué se descartó.

---

## D1 — Lenguaje: GDScript

**Decisión**: todo el combate en GDScript, como funciones puras y deterministas donde sea posible.

**Rationale**: no existe proyecto C# en el repo. El alcance acordado (tablero 8x8, 4-6 unidades por bando, sin línea de visión ni cobertura) no tiene ningún cálculo que GDScript no resuelva en microsegundos. Un segundo runtime añade compilación, marshalling y depuración doble a un proyecto mantenido por una sola persona. Requirió enmendar la constitución (1.0.0 → 2.0.0, Principio II).

**Alternativas descartadas**: C# desde el inicio (coste de andamiaje sin beneficio medible); GDScript con "puerto planificado" a C# (planificar un puerto sin evidencia es el mismo error especulativo).

## D2 — Presentación: tablero 2D como overlay, no escena 3D aparte

**Decisión**: `BattleScreen` es un `CanvasLayer` a pantalla completa (slot `full_overlay`) con un tablero de `Control`s (celdas como botones estilizados con `UITheme`) sobre un backdrop que oscurece la base. La base sigue viva debajo.

**Rationale**: legibilidad en móvil garantizada (celdas de tamaño fijo, targets táctiles ≥44px); reutiliza `UITheme` y `UILayoutManager` (Principio V); cero malabares de cámara 3D ni cambio de escena; el spec solo exige "tablero de batalla por celdas". Un tablero 2D limpio con iconografía dieselpunk es más legible en un GIF que 3D low-poly a 45°.

**Alternativas descartadas**: escena 3D separada con `change_scene` (rompe el estado de los autoloads de UI y complica reanudar); tablero 3D sobre la isla (ilegible en 6", colisiona con el grid 25x25 de la base).

## D3 — Un solo dueño del dominio: `CombatManager`

**Decisión**: nuevo autoload `CombatManager` (después de `ArmyManager`, antes de `RandomEventManager` en `project.godot`) que posee el estado de la expedición, el encuentro, el orden de turnos y la resolución. La UI (`BattleScreen`, `SkirmishPanel`) solo lee su API y reacciona a señales.

**Rationale**: Principio IV (un dominio, un servicio). Al no depender de nodos, la lógica corre en headless y es testeable con gdUnit4.

**Estructura de módulos** (`scripts/combat/`):
- `CombatRules.gd` — estático: daño, iniciativa, modificador de moral, validación de movimiento/ataque.
- `CombatUnit.gd` — `RefCounted`: instancia de unidad en combate (tipo, hp, posición, bando, actuó).
- `Encounter.gd` — `RefCounted`: tablero, unidades, turno, límite de turnos, estado.
- `Expedition.gd` — `RefCounted`: mapa de nodos, posición, grupo, mejoras del draft, recompensas, semilla.
- `ExpeditionGenerator.gd` — estático: genera mapa ramificado, encuentros y drafts a partir de una semilla.
- `CombatAI.gd` — estático: decide la acción de una unidad enemiga.

## D4 — Balance en `GameConfig` (`combat_*`)

**Decisión**: todo valor ajustable vive en `GameConfig.gd` bajo prefijo `combat_`. Estadísticas de combate por tipo de unidad como diccionario paralelo a `unit_types`.

| Clave | Valor inicial | Nota |
|---|---|---|
| `combat_board_size` | `Vector2i(8, 8)` | Legible en móvil |
| `combat_deploy_cap` | 6 | Máximo de unidades comprometibles por expedición |
| `combat_turn_limit` | 20 | Rondas; al agotarse gana quien tenga más HP total (FR-015) |
| `combat_unit_stats` | ver abajo | hp / atk / def / move / range / min_range / initiative |
| `combat_enemy_scale_per_depth` | 0.15 | +15% de fuerza enemiga por nodo de profundidad |
| `combat_enemy_scale_per_era` | 0.25 | Escala con la era del jugador (FR-021) |
| `combat_boss_multiplier` | 1.8 | Multiplicador del encuentro final |
| `combat_map_depth` | `Vector2i(4, 6)` | Nodos entre inicio y jefe (min, max) |
| `combat_map_branching` | `Vector2i(2, 3)` | Salidas por nodo (min, max) |
| `combat_draft_options` | 3 | Opciones por draft (SC-009 exige ≥2) |
| `combat_reward_base` | `{"gold": 60, "wood": 30}` | Recompensa base por encuentro, escalada por profundidad |
| `combat_morale_initiative_bonus` | 2 | Iniciativa extra a moral 100, penalización simétrica a 0 |
| `combat_morale_attack_range` | `Vector2(0.85, 1.15)` | Multiplicador de ataque de moral 0 a 100 |
| `combat_morale_on_victory` | +8 | Moral de la base al ganar la expedición |
| `combat_morale_per_casualty` | -3 | Moral por unidad perdida al regresar |

**Estadísticas iniciales** (`combat_unit_stats`):

| Unidad | HP | ATK | DEF | Move | Range | Min range | Iniciativa |
|---|---|---|---|---|---|---|---|
| infantry | 30 | 8 | 2 | 3 | 1 | 1 | 5 |
| artillery | 22 | 14 | 1 | 1 | 3 | 2 | 3 |
| vehicle | 60 | 12 | 5 | 4 | 1 | 1 | 4 |

Triángulo intencional: infantería barata y rápida, artillería frágil pero letal a distancia (no puede disparar a adyacentes), vehículo tanque lento de iniciativa. Todo ajustable sin tocar lógica (Principio III).

## D5 — Determinismo: semilla por expedición y daño sin dados

**Decisión**: cada expedición nace con `seed: int` guardado; toda aleatoriedad (mapa, composición enemiga, draft, posiciones de despliegue) sale de un `RandomNumberGenerator` sembrado. El daño es determinista: `max(1, atk - def) * morale_mod`.

**Rationale**: reproducible en tests; el guardado a mitad de expedición se reanuda regenerando desde la semilla + índice de nodo (FR-020, SC-006); sin frustración de RNG en el combate (riesgo documentado en XCOM 2). La variabilidad viene de la generación, no de los dados.

**Alternativas descartadas**: daño con varianza ±20% (añade ruido sin profundidad a esta escala); guardar el estado completo del tablero (frágil, innecesario con semilla).

## D6 — Persistencia: reanudar, no abandonar

**Decisión**: `CombatManager.get_save_data()` / `load_save_data()` bajo `data["expedition"]` en `GameManager`. Si hay expedición en curso al cerrar, al reabrir se reanuda en el nodo actual con las unidades y su HP tal como estaban; el encuentro en curso se reinicia desde su despliegue (no se guarda el turno intermedio).

**Rationale**: el spec permite reanudar o resolver como abandono; reanudar es lo que el jugador espera. Guardar solo `{seed, node_index, party[], draft_picks[], rewards}` es compacto y compatible hacia atrás (clave ausente = sin expedición).

## D7 — Señales: categoría `# ── Combat ──` en `EventBus`

Ver [`contracts/eventbus-combat.md`](contracts/eventbus-combat.md). Productores: `CombatManager`. Consumidores: `BattleScreen`, `SkirmishPanel`, `ArmyPanel`, `NotificationPanel`, `AudioManager`, `PopulationManager`.

## D8 — El puente de la moral (versión mínima, dentro del alcance)

**Decisión**: la moral de la base entra al combate en dos números (bono de iniciativa y multiplicador de ataque) y el resultado de la expedición devuelve moral a la base (victoria suma, cada baja resta). Se implementa en US3 porque es "el resultado impacta la economía" — la moral es economía.

**Rationale**: es el diferenciador identificado en `estrategia/02_VISION_Y_DIFERENCIADORES.md`, cuesta cuatro valores de `GameConfig` y una señal, y hace que el combate se sienta consecuencia de la base desde la primera versión. La "huelga por derrota" y los decretos quedan en `estrategia/IDEAS.md` para la fase 2.

## D9 — Testing: gdUnit4 sobre las funciones puras

**Decisión**: instalar gdUnit4 (`addons/gdUnit4`, gratis) y cubrir `CombatRules` (daño, iniciativa, moral, validaciones) y `ExpeditionGenerator` (mapa siempre conexo hasta el jefe, sin nodos huérfanos, dos semillas distintas → mapas distintos). La UI se valida jugando con Beckett (screenshot + `game_logs`).

**Rationale**: la constitución exige verificar corriendo el juego; los tests cubren justo lo que un juego de gestión rompe en silencio: fórmulas. Son opcionales según el spec, recomendados por la estrategia.

## D10 — Fuerza enemiga: espejo de las unidades del jugador

**Decisión**: el enemigo usa los mismos tres tipos de unidad (mismas estadísticas), con composición generada por profundidad y era, y un multiplicador de HP/ATK por dificultad. Sin tipos enemigos nuevos en v1.

**Rationale**: cero arte ni datos nuevos; el jugador entiende las unidades enemigas al instante porque son las suyas; el balance se ajusta con dos escalares. Tipos enemigos propios (bandidos, autómatas) van a `IDEAS.md`.
