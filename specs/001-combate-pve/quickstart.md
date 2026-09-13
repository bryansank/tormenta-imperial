# Quickstart: validar el combate PVE de punta a punta

**Feature**: `001-combate-pve` | **Date**: 2026-09-12

Guía de verificación, no de implementación. Cada escenario mapea a un criterio de éxito del spec.

## Prerrequisitos

- Godot 4.7 (mono) con el proyecto abierto y el plugin Beckett activo (`addons/beckett`).
- `GameConfig.dev_mode = true` (tiempos cortos: entrenar una unidad tarda ~2 s).
- Partida limpia: Ajustes → **Nueva partida** → confirmar.
- Opcional: gdUnit4 instalado para los tests de `scripts/combat/`.

## Cómo observar sin jugar a mano

Con la sesión de Claude Code arrancada dentro de la carpeta del proyecto (o vía `python tools/beckett_mcp.py`):

```
play_scene {}                         # lanza Main.tscn
wait_until {"condition":"game_connected"}
screenshot {"target":"game"}          # ver el estado
game_logs {"level":"warning"}         # debe estar vacío al final de cada escenario
runtime_get_property {"path":"/root/CombatManager","property":"..."}
```

## Escenarios

### E1 — Un encuentro completo (US1, SC-001, SC-002, SC-003)

1. Construir un Cuartel y entrenar 2 infanterías (era 1).
2. Abrir **Escaramuzas** (botón lateral, visible solo con Cuartel) → comprometer las 2 → **Lanzar**.
3. Verificar: aparece el mapa de nodos; el nodo 0 abre un tablero 8x8 con las 2 unidades en las filas inferiores y los enemigos en las superiores.
4. Jugar hasta eliminar al enemigo: seleccionar unidad → mover a celda resaltada → atacar objetivo en rango.
5. **Esperado**: `encounter_ended(true, n)` con `n ≤ 20`; menos de 5 minutos de reloj; `game_logs` vacío.

### E2 — Expedición ramificada con draft y atrición (US2, SC-008, SC-009)

1. Tras ganar el nodo 0, se ofrecen **≥2 opciones de draft**; elegir una.
2. El mapa muestra 2-3 salidas; elegir una.
3. En el siguiente encuentro, las unidades **conservan el HP** con el que terminaron el anterior.
4. Repetir hasta el nodo jefe (marcado). Ganarlo → `expedition_ended(0, rewards, casualties)`.
5. Lanzar una **segunda expedición** y comparar: mapa y rosters distintos.

### E3 — Derrota y permadeath (US1 esc. 5, FR-010)

1. Lanzar con 1 infantería contra el nodo 0. Dejar que muera.
2. **Esperado**: `expedition_ended(1, ...)`; al volver a la base, el Cuartel muestra **0 infanterías** y el Poder Militar bajó 10.

### E4 — La economía recibe el resultado (US3, SC-004, SC-005)

1. Anotar oro/madera antes de lanzar. Completar una expedición con 1 baja y 1 superviviente dañada.
2. **Esperado**: recursos sumados según `rewards` con toast en `NotificationPanel`; ejército = exactamente las supervivientes; la superviviente vuelve al **100% de HP** en la próxima expedición.
3. Moral: anotar `PopulationManager` antes y después. Victoria → sube `combat_morale_on_victory` menos `combat_morale_per_casualty` por baja.

### E5 — IA que actúa (US4, SC-007)

1. En cualquier encuentro, pulsar **Terminar turno** sin mover.
2. **Esperado**: cada enemigo se aproxima o ataca en su turno; ninguno queda inerte si tiene objetivo alcanzable. La artillería enemiga no dispara a adyacentes (min_range 2).

### E6 — Cerrar el juego a mitad de expedición (FR-020, SC-006)

1. En el nodo 2 de una expedición, cerrar el juego (Alt+F4 o `stop_scene`).
2. Volver a lanzar: **esperado** la expedición se reanuda en el nodo 2 con el party y su HP; el encuentro se redespliega desde cero. `game_logs` sin errores de carga.
3. Cargar un **save anterior a esta feature** (sin clave `expedition`): el juego arranca normal, sin expedición activa.

### E7 — Abandonar (FR-016)

1. Con recompensas acumuladas, pulsar **Abandonar** → confirmar.
2. **Esperado**: `expedition_ended(2, ...)`; recompensas aplicadas; supervivientes de vuelta; sin bajas adicionales.

### E8 — Sin unidades (FR-002)

1. Sin Cuartel o con 0 unidades, intentar lanzar.
2. **Esperado**: mensaje `MSG_NO_UNITS`; no se crea expedición.

### E9 — Legibilidad móvil (riesgo documentado)

1. Cambiar la ventana a 400×720 (o `set_project_setting` de viewport en una prueba) y abrir un encuentro.
2. **Esperado**: las celdas del tablero ≥44 px, textos legibles, botones de acción alcanzables con el pulgar.

## Tests automáticos (si gdUnit4 está instalado)

```
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/combat
```

Cubren: `CombatRules` (daño mínimo 1, DEF×2 al defender, multiplicador de moral en los extremos, rango mínimo de artillería, BFS no atraviesa unidades) y `ExpeditionGenerator` (todo nodo alcanza al jefe, profundidad dentro de rango, dos semillas → mapas distintos, draft siempre con ≥2 aplicables).
