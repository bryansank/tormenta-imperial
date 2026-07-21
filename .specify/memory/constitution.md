<!--
SYNC IMPACT REPORT
==================
Version change: (template) → 1.0.0
Bump rationale: Initial ratification of the project constitution (MAJOR baseline).
Modified principles: N/A (first version)
Added principles:
  - I. Comunicación Mediada por EventBus
  - II. El Lenguaje Correcto para Cada Trabajo (C# vs GDScript)
  - III. GameConfig como Única Fuente de Balance
  - IV. Fronteras de Servicios Autoload
  - V. Disciplina de Convenciones, i18n y Persistencia
Added sections:
  - Restricciones de Tecnología y Estructura
  - Flujo de Desarrollo
  - Governance
Removed sections: none
Templates requiring updates:
  - .specify/templates/plan-template.md ✅ reviewed (Constitution Check genérico, compatible)
  - .specify/templates/spec-template.md ✅ reviewed (sin conflicto)
  - .specify/templates/tasks-template.md ✅ reviewed (sin conflicto)
Follow-up TODOs: none
-->

# Tormenta Imperial Constitution

## Core Principles

### I. Comunicación Mediada por EventBus

Todos los sistemas se comunican a través de señales de `EventBus`. Un servicio productor
NUNCA referencia directamente a un consumidor: emite una señal en `EventBus` y los
componentes/servicios interesados se suscriben en su `_ready()`.

Reglas no negociables:
- Ninguna clase de servicio guarda una referencia directa a otro servicio para
  notificarle cambios de estado; la vía es siempre `EventBus`.
- Toda señal nueva se declara en `EventBus.gd` bajo su categoría antes de emitirse.
- El flujo canónico es `Input crudo → InputService → EventBus.signal → Consumidor`.

**Rationale:** El desacople productor/consumidor es lo que permite que 19 autoloads
evolucionen sin romperse entre sí y que UI, cámara y lógica se prueben de forma aislada.

### II. El Lenguaje Correcto para Cada Trabajo (C# vs GDScript)

El código sensible al rendimiento se escribe en **C#**; todo lo demás en **GDScript**.

- **C# (MUST):** IA de unidades, matemática de combate, pathfinding, serialización de red.
- **GDScript (MUST):** UI, cámara, input, servicios, gestión de escenas, cableado de señales.

**Rationale:** GDScript es más ágil para el pegamento del juego; C# aporta el rendimiento
determinista que exigen el combate por turnos y la futura capa de multijugador.

### III. GameConfig como Única Fuente de Balance

Todo valor ajustable —costos, duraciones, rendimientos, umbrales de moral, precios de
mercado, upkeep, bonificaciones de tech— vive en `GameConfig.gd`.

- PROHIBIDO incrustar "números mágicos" de balance en servicios, UI o escenas.
- Un cambio de balance se hace editando `GameConfig.gd`, no la lógica que lo consume.
- `dev_mode` acorta duraciones para pruebas; el código de producción no asume su valor.

**Rationale:** Centralizar el balance hace el ajuste económico reproducible, auditable y
seguro, sin cazar constantes dispersas por el código.

### IV. Fronteras de Servicios Autoload

Cada dominio del juego pertenece a exactamente un servicio autoload con responsabilidad
clara (ver la tabla de 19 autoloads en `CLAUDE.md`).

- Un servicio es dueño de su estado; los demás lo leen vía su API pública o reaccionan a
  sus señales, nunca mutando su estado interno directamente.
- El orden de carga en `project.godot` es significativo y debe respetarse al añadir
  servicios (las dependencias cargan primero: `Tr`, `GameConfig`, `EventBus`…).
- Las utilidades compartidas sin estado (`FloatingText`, `DieselpunkBuildingFactory`,
  `UITheme`) son clases estáticas, no autoloads.

**Rationale:** Fronteras nítidas evitan estado duplicado y condiciones de carrera al
guardar/cargar, y mantienen cada sistema comprensible por separado.

### V. Disciplina de Convenciones, i18n y Persistencia

El código respeta las convenciones del proyecto y preserva la integridad de datos del
jugador.

- Nombres: `snake_case` en GDScript, `PascalCase` en clases C#, `_camelCase` en campos
  privados C#, `PascalCase.tscn` en escenas, `snake_case` en señales, `UPPER_SNAKE` en
  claves de traducción.
- Todo texto visible al usuario pasa por `Tr.gd` con claves en ES **y** EN; no hay
  cadenas hardcodeadas visibles.
- Toda UI nueva se construye con las fábricas de `UITheme` y se posiciona vía
  `UILayoutManager`/`UILayoutConfig`; no se estilan controles a mano.
- Cualquier estado persistente nuevo se integra en el guardado JSON
  (`user://save_game.json`) manteniendo compatibilidad hacia atrás; las preferencias de
  dispositivo van en `user://settings.cfg`, separadas del save.

**Rationale:** La consistencia hace el código legible y traducible; la disciplina de
persistencia evita corromper partidas existentes al añadir features.

## Restricciones de Tecnología y Estructura

- **Motor:** Godot 4.6 .NET Edition (renderer Forward+). No introducir dependencias que
  rompan la edición .NET.
- **Definiciones de datos:** edificios como `.tres` en `data/buildings/`; unidades y techs
  como diccionarios inline en `GameConfig.gd` (`unit_types`, `tech_definitions`).
- **Mallas 3D:** generadas proceduralmente por `DieselpunkBuildingFactory` salvo que un
  edificio defina `model_scene`.
- **Backend/Multijugador (planificado):** Supabase (`CloudSaveManager`) y Nakama; su
  cableado debe seguir estos principios cuando se active.
- **Docs:** los sistemas se documentan en `docs/`; `CLAUDE.md` refleja la arquitectura
  vigente y se actualiza junto al código que cambia.

## Flujo de Desarrollo

- **Nuevo edificio:** crear `.tres` → añadir a `building_limits` → prerequisitos en
  `building_prerequisites` → procesos en `building_processes` → traducciones en `Tr.gd` →
  aparece solo en `ConstructionMenu`.
- **Nueva señal:** declarar en `EventBus.gd` → emitir en el productor → conectar en el
  consumidor dentro de `_ready()`.
- **Ajuste de economía:** editar exclusivamente `GameConfig.gd`.
- **Compatibilidad de guardado:** todo cambio que toque el estado persistente prueba carga
  de un save previo antes de considerarse hecho.
- **Verificación:** las features se validan corriendo el juego (F5) además de cualquier
  prueba; los fallos se reportan con su salida, no se ocultan.

## Governance

Esta constitución supersede cualquier otra práctica cuando exista conflicto. El código que
viole un principio marcado **MUST** es el hallazgo de mayor severidad en cualquier revisión
o convergencia de Spec Kit y debe corregirse antes de dar una feature por completa.

- **Enmiendas:** se documentan en este archivo, con justificación y bump de versión.
- **Versionado (semántico):** MAJOR = remoción/redefinición incompatible de principios o
  governance; MINOR = nuevo principio/sección o guía materialmente ampliada; PATCH =
  aclaraciones y correcciones no semánticas.
- **Cumplimiento:** cada plan generado por `/speckit-plan` valida su "Constitution Check"
  contra estos principios; las desviaciones justificadas se registran explícitamente.
- **Guía runtime:** `CLAUDE.md` es la guía operativa de desarrollo y debe mantenerse
  coherente con esta constitución.

**Version**: 1.0.0 | **Ratified**: 2026-07-20 | **Last Amended**: 2026-07-20
