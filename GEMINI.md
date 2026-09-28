# GEMINI.md - Tormenta Imperial

Contexto para Gemini CLI. **La guía completa y al día es [`CLAUDE.md`](CLAUDE.md)**:
arquitectura, los 25 autoloads, el árbol de escena, estructura, convenciones, cómo
correr los tests y qué falta. Este archivo solo resume lo imprescindible y remite allí;
si algo de aquí contradice a `CLAUDE.md`, manda `CLAUDE.md`.

## 1. Qué es
Juego dieselpunk de gestión de base + estrategia por turnos, en **Godot 4.7 .NET**
(Forward+ en PC, renderer Mobile en Android). Todo en **GDScript**: no hay proyecto C#
ni está previsto para la v1.

- Gestión: 4 recursos en una bolsa compartida, 3 eras, 14 edificios en una rejilla de
  **40x40**, población y moral, mercado, árbol tecnológico, ejército.
- La Tormenta Imperial vuelve por ciclos y cobra el Diezmo, que se paga o se pelea.
- Combate PVE por turnos en un tablero 8x8: expediciones roguelike (mapa, draft,
  informe), la defensa del Diezmo y la Auditoría Final (en Campaña, el Cuartel General
  nivel 3 convoca un asedio de 3-5 oleadas; sobrevivirlo es la victoria).
- Cuatro modos (Campaña, Constructor, Supervivencia, Sandbox), vista 3D y vista 2D,
  interfaz configurable por dispositivo, exportación a Windows y Android.

## 2. Reglas que no se negocian
1. Los cambios de estado se anuncian por `EventBus`; un productor no conoce a sus
   consumidores.
2. Todo valor ajustable vive en `scripts/services/GameConfig.gd`.
3. Los modelos de `scripts/combat/` y `scripts/storm/` son puros: sin nodos, sin
   señales, sin RNG global.
4. Los tests se lanzan **solo** con `tools/run_tests.sh` (o `.ps1`), que les da una
   carpeta de usuario propia. Nunca `GdUnitCmdTool.gd` a pelo: pisaría la partida del
   jugador.
5. Estado nuevo en el guardado: `reset()` llamado desde los tres sitios de
   `GameManager` (`_new_game()`, `clear_save()`, `clear_save_and_reload_from()`).
6. Constitución del proyecto: `.specify/memory/constitution.md`.

## 3. Dónde mirar
- `CLAUDE.md` — la guía técnica completa.
- `docs/INDEX.md` — un documento por sistema (01-23).
- `docs/13-roadmap.md` — lo hecho y lo pendiente.
- `docs/10-signals-reference.md` — las 107 señales del `EventBus`.
