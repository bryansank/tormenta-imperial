# GEMINI.md - Tormenta Imperial Master Context

Este archivo es el índice maestro para Gemini CLI. Define la arquitectura, los servicios activos y las convenciones del proyecto **Tormenta Imperial**.

## 1. Project Overview
Hybrid strategy game: persistent base management (meta-game) + RTS combat.
- **Aesthetic:** "Heroic Realism" / Dieselpunk (Monumentalism vs Mud).
- **Engine:** Godot 4.6 .NET Edition (Forward+ renderer).
- **Primary Architecture:** Service-Signal-Component (100% Decoupled).

## 2. Core Architecture: Service-Signal-Component
Todos los sistemas se comunican exclusivamente a través del **EventBus**. No hay referencias directas entre productores y consumidores.

### Golden Rules (From `docs/01-architecture.md`):
1. **Services never reference each other directly** — use `EventBus` signals.
2. **UI subscribes to EventBus in `_ready()`** and reacts to signals.
3. **Data flows one way:** Input -> Service -> EventBus -> Consumer.
4. **GameConfig holds all balance values** — zero magic numbers in code.

### Registered Autoload Services (Load Order Matters):
| Order | Service | Responsability |
|-------|---------|----------------|
| 1 | `Tr` | Localización (ES/EN). |
| 2 | `GameConfig` | Constantes de balance y tuning. |
| 3 | `EventBus` | Bus global de señales (solo declaraciones). |
| 4 | `InputService` | Mapeo de Input a señales del EventBus. |
| 5 | `GridManager` | Gestión de celdas 25x25 y lógica de terreno. |
| 6 | `ResourceManager` | Gestión de 4 recursos + desbloqueos. |
| 7 | `GameManager` | Ciclo de vida, guardado/carga (Local + Cloud). |
| 8 | `ProcessManager` | Procesos de edificios (minería, refinado). |
| 9 | `ProductionManager` | Producción pasiva y ciclos de construcción. |
| 10 | `ProgressionManager` | Eras, hitos (milestones) y victoria. |
| 11 | `MarketManager` | Comercio con precios dinámicos. |
| 12 | `PopulationManager` | Población, trabajadores y moral. |
| 13 | `RandomEventManager` | Eventos aleatorios del juego. |
| 14 | `CloudSaveManager` | Integración con Supabase (pendiente). |

## 3. Implementation Cheat Sheet
Para añadir un nuevo sistema o funcionalidad, sigue este flujo:

1. **Signals:** Declara la señal en `scripts/services/EventBus.gd`.
2. **Service:** Crea el manager en `scripts/services/`. Debe incluir:
   - `get_save_data()` / `load_save_data()` / `reset()`.
3. **Registration:** Añádelo a `project.godot` respetando el orden de dependencia.
4. **GameManager:** Conecta el nuevo servicio en `_new_game()`, `_load_game()` y `clear_save()`.
5. **UI:** Crea la escena en `scenes/ui/` y el script en `scripts/ui/` conectando señales en `_ready()`.

## 4. Coding Conventions
- **GDScript:** UI, Camera, Input, Signal Wiring, Audio. (`snake_case`)
- **C#:** (Planned) Performance-heavy systems: Unit AI, Combat Logic, Pathfinding. (`PascalCase`)
- **Resources:** Todos los datos de edificios están en `data/buildings/*.tres`.

## 5. Project Roadmap & Status
- [x] **Core Foundations:** Camera, Grid, Building Placer, EventBus.
- [x] **Economy & Management:** Resource system, Population, Market, Production.
- [x] **Progression:** Tech Tree, Eras, Milestones, Save System (Local).
- [~] **Persistence:** Local JSON working. Supabase/Cloud pending.
- [ ] **Combat Basics:** Drag selection box and NavigationAgent2D (Next Focus).
- [ ] **Assets:** Refine building models and unit sprites.

## 6. Key Documentation References
- `docs/01-architecture.md`: Detalles técnicos del flujo de datos.
- `docs/03-buildings.md`: Lista completa de los 14 tipos de edificios.
- `docs/09-save-system.md`: Estructura del JSON de guardado.
- `docs/10-signals-reference.md`: Diccionario completo de señales del EventBus.
