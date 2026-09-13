<!--
SYNC IMPACT REPORT
==================
Version change: 1.0.0 → 2.0.0
Bump rationale: MAJOR — redefinición incompatible del Principio II. Pasa de "C# MUST
para IA/combate/pathfinding" a "GDScript primero; C# solo con evidencia de profiler".
Justificación: nunca existió el proyecto .NET (sin .csproj ni .cs); el alcance acordado
del combate (tablero 8x8, 4-6 unidades por bando) no justifica un segundo lenguaje, y un
solo runtime maximiza la probabilidad de terminar el proyecto.
Modified principles:
  - II. El Lenguaje Correcto para Cada Trabajo → II. GDScript Primero
Modified sections:
  - Restricciones de Tecnología y Estructura: motor Godot 4.7 (antes 4.6); se retira
    Nakama del backend planificado (PvP fuera de alcance; si algún día se hace, sobre
    Supabase). Definiciones de combate como diccionarios inline en GameConfig.
Templates requiring updates:
  - .specify/templates/plan-template.md ✅ sin cambios necesarios
  - CLAUDE.md ✅ ya refleja GDScript-first (2026-09-12)
Follow-up TODOs: none
Previous version: 1.0.0 (ratificada 2026-07-20)
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

### II. GDScript Primero

Todo el código del juego se escribe en **GDScript**, incluido el combate por turnos.

- **GDScript (MUST):** servicios, UI, cámara, input, gestión de escenas, cableado de
  señales, reglas de combate, IA de unidades y generación procedural.
- **C# (MAY, solo con evidencia):** un módulo puede portarse a C# únicamente si el
  profiler de Godot demuestra que es el cuello de botella y que GDScript no alcanza el
  objetivo de rendimiento. El puerto se hace por módulo aislado, nunca de forma
  especulativa, y requiere enmendar esta constitución.
- La lógica de combate se escribe como **funciones puras y deterministas** (sin nodos ni
  estado global) para que sea testeable en headless y portable si algún día hace falta.

**Rationale:** El proyecto entero (19 autoloads y toda la UI) ya es GDScript. A la escala
acordada para el combate —tablero 8x8, 4-6 unidades por bando— el rendimiento no es un
factor, y un segundo runtime añade compilación, marshalling y depuración doble sin
beneficio. Menos piezas es más probabilidad de terminar.

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

- **Motor:** Godot 4.7 (edición .NET/mono, renderer Forward+). El editor .NET se mantiene
  por compatibilidad futura, pero no existe proyecto C# y no se crea sin evidencia
  (Principio II).
- **Definiciones de datos:** edificios como `.tres` en `data/buildings/`; unidades, techs y
  combate como diccionarios inline en `GameConfig.gd` (`unit_types`, `tech_definitions`,
  `combat_*`).
- **Mallas 3D:** generadas proceduralmente por `DieselpunkBuildingFactory` salvo que un
  edificio defina `model_scene`.
- **Backend (planificado):** Supabase (`CloudSaveManager`, implementado pero desconectado).
  El PvP está fuera del alcance de la v1; si algún día se construye, va sobre Supabase
  (RLS + Edge Functions + Realtime), no sobre un servidor de juego dedicado.
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

**Version**: 2.0.0 | **Ratified**: 2026-07-20 | **Last Amended**: 2026-09-12
