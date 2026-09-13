# Implementation Plan: Combate Roguelike por Turnos (PVE)

**Branch**: `001-combate-pve` (trabajo actual en `chore/estrategia-y-tooling`; la implementación abre `feat/combate-encuentro` y sucesivas, una por hito) | **Date**: 2026-09-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-combate-pve/spec.md`

## Summary

Añadir el pilar de combate: el jugador compromete unidades ya entrenadas en el Cuartel a una **expedición** roguelike (mapa ramificado procedural con jefe final), resuelve cada nodo en un **tablero táctico 8x8 por turnos** (mover / atacar / defender / esperar contra una IA), sufre atrición y permadeath, elige mejoras por draft, y devuelve a la base recompensas, bajas y moral.

Enfoque técnico: un solo autoload nuevo (`CombatManager`) dueño del dominio, lógica de combate como funciones puras y deterministas en GDScript (`scripts/combat/`), tablero como overlay 2D construido con `UITheme`, aleatoriedad sembrada por expedición para reanudar partidas y testear, y balance íntegramente en `GameConfig.combat_*`. Decisiones detalladas en [research.md](research.md).

## Technical Context

**Language/Version**: GDScript, Godot 4.7-stable (edición mono; sin proyecto C#, ver constitución 2.0.0 Principio II)

**Primary Dependencies**: motor Godot únicamente. Herramientas de desarrollo: Beckett MCP (`addons/beckett`, ver el juego corriendo), gdUnit4 (`addons/gdUnit4`, tests; a instalar en Setup)

**Storage**: `user://save_game.json` vía `GameManager` (clave nueva `expedition`, compatible hacia atrás)

**Testing**: gdUnit4 sobre `scripts/combat/` (funciones puras); validación de UI jugando con Beckett (`screenshot`, `game_logs`, `ui_snapshot`). Escenarios en [quickstart.md](quickstart.md)

**Target Platform**: PC (Windows) primero; 100% jugable en móvil (táctil, tablero legible a 400 px de ancho)

**Project Type**: juego Godot de un solo proyecto (estructura existente `scripts/`, `scenes/`, `data/`)

**Performance Goals**: 60 fps estables en el tablero; resolución de un turno de IA < 16 ms (8x8, ≤ 6 unidades por bando: trivial)

**Constraints**: cero `print` en producción; cero warnings en `game_logs`; sin números mágicos fuera de `GameConfig`; textos ES+EN vía `Tr`; un encuentro típico < 5 min de reloj (SC-002); cada tarea cerrable en una sesión de 2-4 h

**Scale/Scope**: 3 tipos de unidad (existentes), tablero 8x8, 4-6 unidades por bando, mapas de 4-6 nodos de profundidad, 5 tipos de mejora de draft, 1 tipo de objetivo ("eliminar a todos") en v1

## Constitution Check

*GATE: evaluado contra la constitución **2.0.0** (enmendada 2026-09-12 para esta feature; ver SYNC IMPACT REPORT).*

| Principio | Cumplimiento | Cómo |
|---|---|---|
| I. EventBus | ✅ | Nueva categoría `# ── Combat ──` con 12 señales ([contracts/eventbus-combat.md](contracts/eventbus-combat.md)); `CombatManager` emite, UI/servicios se suscriben en `_ready()`. Ningún servicio referencia a otro para notificar |
| II. GDScript primero | ✅ | Todo en GDScript; reglas de combate como funciones estáticas puras (`CombatRules`, `CombatAI`, `ExpeditionGenerator`). Bajo 1.0.0 esto era una violación; la enmienda 2.0.0 la resuelve con justificación registrada |
| III. GameConfig única fuente de balance | ✅ | 15 claves `combat_*` + `combat_unit_stats` (research D4). La lógica no contiene constantes de balance |
| IV. Fronteras de autoloads | ✅ | `CombatManager` es el único dueño de Expedition/Encounter. `ArmyManager` sigue siendo la fuente de verdad del ejército; `CombatManager` solo le pide descontar bajas al final. Orden de carga: tras `ArmyManager`, antes de `RandomEventManager` |
| V. Convenciones, i18n, persistencia | ✅ | `snake_case`, escenas `PascalCase.tscn`; ~30 claves `Tr` en ES y EN; UI con fábricas de `UITheme` y slots de `UILayoutConfig`; guardado bajo `data["expedition"]`, clave ausente = sin expedición (compatibilidad probada en quickstart E6) |
| Restricciones | ✅ | Godot 4.7; definiciones de combate inline en `GameConfig`; sin mallas nuevas (tablero 2D) |
| Flujo de desarrollo | ✅ | Señal nueva → declarar/emitir/conectar; balance solo en `GameConfig`; compatibilidad de save probada antes de dar por hecho; verificación corriendo el juego |

**Re-check post-diseño**: sin violaciones. No hay entradas en Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/001-combate-pve/
├── spec.md              # Especificación (aprobada)
├── plan.md              # Este archivo
├── research.md          # Fase 0: decisiones D1-D10
├── data-model.md        # Fase 1: CombatUnit, Encounter, Expedition, DraftOption, esquema de save
├── quickstart.md        # Fase 1: escenarios de validación E1-E9
├── contracts/
│   └── eventbus-combat.md   # Señales, API pública de CombatManager, claves Tr
├── checklists/requirements.md
└── tasks.md             # Fase 2
```

### Source Code (repository root)

```text
scripts/
├── combat/                          # NUEVO — lógica pura, sin nodos
│   ├── CombatRules.gd               # static: daño, iniciativa, moral, validaciones, BFS
│   ├── CombatUnit.gd                # RefCounted
│   ├── Encounter.gd                 # RefCounted: tablero, turnos, estado
│   ├── Expedition.gd                # RefCounted: mapa, party, draft, recompensas, semilla
│   ├── ExpeditionGenerator.gd       # static: mapa ramificado, rosters, drafts (RNG sembrado)
│   └── CombatAI.gd                  # static: decisión de la unidad enemiga
├── services/
│   ├── CombatManager.gd             # NUEVO autoload — dueño del dominio, API pública, save/load
│   ├── EventBus.gd                  # + categoría Combat (12 señales)
│   ├── GameConfig.gd                # + combat_* y combat_unit_stats
│   ├── GameManager.gd               # + data["expedition"] en save/load
│   ├── ArmyManager.gd               # + get_available_for_deploy(), remove_casualties()
│   ├── PopulationManager.gd         # + apply_expedition_morale() (consume expedition_ended)
│   ├── AudioManager.gd              # + SFX en señales de combate (fase de pulido)
│   └── Tr.gd                        # + ~30 claves ES/EN
└── ui/
    ├── SkirmishPanel.gd             # NUEVO — comprometer unidades y lanzar (patrón ArmyPanel)
    ├── BattleScreen.gd              # NUEVO — mapa de nodos, tablero 8x8, acciones, draft, resultado
    ├── UILayoutConfig.gd            # + slots SkirmishPanel.button/.modal, BattleScreen (full_overlay)
    └── NotificationPanel.gd         # + toasts de expedición

scenes/ui/
├── SkirmishPanel.tscn               # NUEVO
└── BattleScreen.tscn                # NUEVO
scenes/main/Main.tscn                # + instancias de ambos

project.godot                        # + autoload CombatManager (orden: tras ArmyManager)

tests/combat/                        # NUEVO (gdUnit4)
├── test_combat_rules.gd
└── test_expedition_generator.gd

docs/
├── 14-combat.md                     # NUEVO (fase de pulido)
└── INDEX.md                         # + entrada
```

**Structure Decision**: se respeta la estructura existente (servicios como autoloads en `scripts/services/`, un `.gd` + `.tscn` por panel en `scripts/ui/` y `scenes/ui/`). Lo único nuevo es la carpeta `scripts/combat/` para la lógica pura —separada de los servicios porque no son autoloads ni tienen estado global— y `tests/` en la raíz siguiendo la convención de gdUnit4.

## Fases de entrega (mapa a `estrategia/05_PLAN_DE_TRABAJO.md`)

| Hito del plan estratégico | User Stories | Resultado visible |
|---|---|---|
| **A — Un encuentro jugable** | US1 (+ IA mínima) | Tablero 8x8 completo de principio a fin, lanzado desde un botón de prueba en `dev_mode`. **El incremento demostrable** |
| **B — La moral entra en combate** | parte de US3 | Iniciativa y ataque modulados por la moral; el resultado la devuelve a la base |
| **C — La expedición** | US2 | Mapa ramificado, draft, atrición, jefe, abandono |
| **D — Puente con la base** | resto de US3 + US4 | Recompensas, bajas, curación, guardado reanudable, IA con prioridades y escalado |

Cada hito se abre en su propia rama `feat/combate-*` con PR a `main`.

## Complexity Tracking

Sin violaciones de la constitución 2.0.0 que justificar.
