# 26. Rendimiento

Cuánto cuesta el juego en cada fotograma y en memoria, cómo se mide y qué hay que
cambiar para que corra "en una papa". Desde el 2026-10-12 el rendimiento es una
prioridad del dueño. Esta fase **mide y audita, no optimiza**. Las optimizaciones de
§6 se harán después de integrar las ramas de arte, sonido, comida y vista 2D, con
esta sonda como árbitro antes y después.

> Medido el 2026-10-12 en el worktree `perf/medida-y-auditoria`, que es
> `integracion/arte-v1` con las ramas de arte de ese día. Las cifras de §4 son de
> **este** PC. Sirven para comparar escenarios y calidades entre sí, no como
> promesa para otro equipo.
>
> **Al día (2026-10-14):** varias optimizaciones de §6 ya están hechas (la 2D horneada,
> las calzadas en lote, la interfaz que actualiza, la calidad Mínima...). El resumen y
> las cifras de §1 y §4 son de **antes** y no se han vuelto a medir: "la 2D es la más
> cara" ya no vale (ver §6).

---

## 1. Resumen

- **En un PC bueno el juego va bien, pero no sobrado.** Con una RTX 3060 Laptop, la
  colonia grande de era 3 (67 edificios, 276 carreteras y 48 caminantes) va a
  **44-48 fps en Forward+ Alta**, con un 1 % bajo de 26-28 fps. El inicio pasa de 160.
- **El 3D lo frena la CPU que prepara el render**, no la GPU. Son unos **5600 draw
  calls** para 2511 mallas, y la GPU se queda en 3-5 ms. Los scripts por fotograma
  suman menos de 1 ms. Lo que más pesa son las **carreteras procedurales** (mallas y
  materiales únicos por casilla, todo con sombra).
- **La vista 2D es hoy la más cara**: 14-17 fps en la colonia grande, porque cada
  edificio y cada carretera llevan dos `_process` (**37 ms por fotograma** entre los
  dos). Hasta que se arregle, la 2D no es la salida para equipos flojos.
- **La calidad "Mínima" funciona** (emulada por la sonda): −60 % de draw calls,
  −110 MB de VRAM, y la colonia grande pasa de 44 a 71 fps en Forward+, de 29 a 50 en
  Compatibility y a 97 en Mobile.
- **En una "papa" no llegamos todavía.** Compatibility en Baja deja la colonia grande
  en 29 fps incluso en esta RTX. Para cumplir 30 fps estables en una integrada vieja
  hacen falta Mínima **y** las optimizaciones 1, 2 y 6 de §6.
- **Memoria**: 900-1080 MB de proceso en Vulkan y 550-700 MB en OpenGL (binario del
  editor), y 170-290 MB de VRAM. El presupuesto de un PC de 4 GB (≤ 600 MB) solo lo
  roza Compatibility.
- **Tirones**: la auditoría encontró trabajo síncrono por casilla del auto-road (un
  guardado completo y un recálculo de población por tramo) y cientos de BFS al elegir
  dónde construir. No se ven en la media, pero son los saltos que nota quien juega.

Presupuesto propuesto en §2; las 12 optimizaciones en §6; Mínima, la detección en el
primer arranque y el tope de FPS en §7.

---

## 2. Presupuesto objetivo

Hay tres equipos mínimos, decididos por el dueño: un **PC viejo con gráfica
integrada**, una **tablet Android barata** y un **móvil Android de gama baja**. Las
cifras de abajo son la propuesta. Se razonan debajo de la tabla.

| Equipo de referencia | Calidad | Resolución | FPS objetivo | 1 % bajo | RAM del proceso | VRAM |
|---|---|---|---|---|---|---|
| **PC medio**: GTX 1650 / RX 6500 / Iris Xe, 8 GB, 4 núcleos | Alta | 1920×1080 | 60 estables | ≥ 45 | ≤ 900 MB | ≤ 512 MB |
| **"Papa" PC**: Intel HD 520 / UHD 620 (2016), 4 GB, 2 núcleos / 4 hilos | Mínima | 1280×720 | 30 estables | ≥ 24 | ≤ 600 MB | ≤ 256 MB (compartida) |
| **Tablet Android barata**: Mali-G52 / Adreno 610, 3-4 GB, Android 10+ | Mínima | nativa con `scaling_3d` 0,6-0,7 | 30 estables | ≥ 24 | ≤ 500 MB | ≤ 200 MB |
| **Móvil Android de gama baja**: Helio G35-G85 / PowerVR GE8320 / Mali-G52, 2-3 GB | Mínima (o vista 2D) | nativa con `scaling_3d` 0,6 | 30 estables | ≥ 24 | ≤ 400 MB | ≤ 150 MB |

| Paquete | Hoy (docs/19) | Objetivo | Cómo |
|---|---|---|---|
| `.exe` de Windows | 120,6 MB (104 MB de plantilla mono) · zip 48,9 MB. El 2026-10-14: **122,7 MB** (109 de plantilla release) · zip 48,4 MB | ≤ 90 MB · zip ≤ 40 MB | plantilla **compilada a medida** (optimizada para tamaño, con perfil de clases); la estándar no ahorra (docs/19 §13.4). Zip en `.7z`: 36,6 MB |
| APK Android | 38,9 MB (debug, arm64). El 2026-10-14: 41,8 MB debug · **39,9 MB release** | ≤ 30 MB (release, arm64) · AAB ≤ 30 MB | plantilla release compilada a medida con Gradle (docs/19 §13.4) |

Por qué estas cifras:

- **30 fps es el suelo** en los equipos flojos. El juego es de gestión con combate por
  turnos: no hay nada que exija 60 fps para jugar. Lo que sí se nota son los tirones,
  y por eso se fija también el **1 % bajo**: 24 fps son 42 ms, el umbral a partir del
  cual un arrastre de cámara se siente a saltos.
- **60 fps en un PC medio** con calidad Alta, porque es lo que espera quien juega en
  PC. Por encima de eso no hace falta gastar: el tope de FPS de §7.4 lo corta.
- **RAM**: un PC de 4 GB con Windows 10 deja libres entre 1,5 y 2 GB. Con 600 MB el
  juego no empuja al sistema a paginar. En Android, el sistema mata la app en segundo
  plano mucho antes en un móvil de 2-3 GB. De ahí los 400-500 MB.
- **VRAM**: las integradas no tienen memoria propia, la reservan de la RAM. 256 MB es
  lo que Windows suele dar a una HD 520 sin tocar la BIOS. Hoy el juego usa unos
  200-300 MB (§4), así que hay que recortar las texturas sin comprimir (§5.6).
- **Tamaño**: el 89 % del `.exe` es la plantilla del motor (docs/19 §13). El juego en
  sí son 13 MB. Medido el 2026-10-14, la plantilla estándar pesa lo mismo que la mono
  (−0,25 MB) y la release de Windows pesa **más** que la de depuración (109 frente a
  103 MB): con plantillas oficiales no se llega a 90 MB. El camino es una plantilla
  compilada para ocupar poco (docs/19 §13.4). En Android lo que más pesa es
  `libgodot_android.so`: 24 MB comprimido en release.

---

## 3. Cómo correr la sonda

`tools/perf_probe.gd` (lanzador, `extends SceneTree`) y `tools/perf_probe_runner.gd`
(el trabajo). Igual que `line_probe.gd` y `life_probe.gd`:

1. **Con ventana**. Headless no pinta, así que no habría draw calls ni GPU que medir.
2. **Con un `override.cfg` propio** en la raíz del proyecto (temporal, git-ignored):
   ```ini
   [application]
   config/use_custom_user_dir=true
   config/custom_user_dir_name="TI_rendimiento"
   ```
   La sonda escribe `user://save_game.json` y se niega a correr en la carpeta del
   jugador. Aun así aparca la partida que haya y la devuelve al terminar.
3. Desde la raíz del proyecto, con `GODOT` apuntando al ejecutable de consola:
   ```bash
   # Un escenario
   "$GODOT" --path . -s tools/perf_probe.gd -- --no-title --scenario=grande --seconds=15
   # Los seis escenarios, un proceso hijo por escenario (autoloads limpios en cada uno)
   "$GODOT" --path . -s tools/perf_probe.gd -- --no-title --scenario=all --quality=high
   # Aproximar Android (Mobile) y un equipo flojo (Compatibility / OpenGL)
   "$GODOT" --path . --rendering-method mobile -s tools/perf_probe.gd -- --no-title --scenario=all
   "$GODOT" --path . --rendering-method gl_compatibility -s tools/perf_probe.gd -- --no-title --scenario=all --quality=minima
   ```
4. **No correr dos sondas a la vez**, ni con otros Godot abiertos que trabajen
   (editor importando, tests, otra sonda): se reparten la CPU y la GPU y las cifras
   salen falseadas. En la primera tanda de hoy pasó y hubo que repetirla (§4).

### Escenarios

Todos se siembran escribiendo un guardado fijo. La semilla (`--seed`, por defecto 1)
fija la isla y los yacimientos sueltos. Los edificios van en una cuadrícula de calles
cada 5 casillas (manzanas de 4×4 con cuatro edificios 2×2 que tocan la calle). Las
manzanas de extractores llevan dos extractores arriba y su yacimiento de 4×2 debajo.
Sin `saved_at` (no hay progresión offline), sin eventos al azar, con la Tormenta en
calma lejana (salvo en `tormenta`), con el tutorial hecho y con `dev_mode` apagado
(tiempos reales).

| Escenario | Qué monta |
|---|---|
| `inicio` | Rejilla 40×40, Núcleo con su acera (16 carreteras), 16 yacimientos sueltos, era 1, 5 habitantes |
| `media` | Rejilla 44×44, 3×3 manzanas: 18 edificios (2 aserraderos, 2 minas, fundición, 4 casas nivel 2, 2 almacenes, mercado, laboratorio, cuartel, torre, 2 jardines), 112 carreteras, era 2, 41 habitantes |
| `grande` | Rejilla 48×48, 5×5 manzanas: 67 edificios, **todos los de `building_limits` en su tope** (más 15 jardines), 276 carreteras, era 3, 95 habitantes, 18 unidades. Unos 48 caminantes en la calle |
| `tormenta` | `grande` en plena Tormenta (fase STORM, severidad 2: cielo oscuro, niebla y daños) |
| `combate` | `media` con 6 unidades y una escaramuza abierta (`CombatManager.start_skirmish`): el tablero 8×8 sobre la colonia |
| `grande_2d` | `grande` en la vista 2D (`Main2D.tscn`) |

### Argumentos

`--scenario=` (uno de los seis o `all`), `--seconds=` (15), `--warmup=` (6),
`--quality=auto|high|low|minima`, `--view=3d|2d`, `--size=1280x720`, `--seed=`,
`--vsync=1` (por defecto se mide **sin vsync ni tope**, para ver el margen),
`--profile=` (segundos del perfil por script, 4; 0 lo apaga), `--tag=` y `--shot=0`.

`--quality=minima` **emula** la propuesta de §7 desde la sonda: calidad baja, sin
sombras (`shadow_enabled = false` en todas las luces), sin SSAO, SSIL, glow ni SSR,
`scaling_3d_scale` 0,6 bilineal, sin MSAA, sin humo (`building_fx` ocultos) y un tope
de 16 caminantes. No es un ajuste del juego.

### Qué mide

Durante `seconds`, en cada fotograma:

- **Tiempo de fotograma**: media, mediana, p99 y "1 % bajo" (fps de la media del 1 %
  de fotogramas más lentos).
- **Render**: tiempo de CPU y de GPU del render del viewport
  (`viewport_get_measured_render_time_cpu/gpu`), draw calls, objetos y primitivas
  (`RENDER_TOTAL_*_IN_FRAME`).
- **"Resto CPU"**: el fotograma menos el render en CPU. Ahí van los scripts, las
  señales, los timers, los tweens, la interfaz y la espera a la GPU.
- **`TIME_PROCESS` / `TIME_PHYSICS_PROCESS`**: ojo, el motor publica el **pico del
  último segundo**, no la media. Se guardan como `*_peak_ms`.

Al final se toman los nodos, los objetos, los recursos, los huérfanos, la memoria
estática (`MEMORY_STATIC`), la de vídeo, texturas y búferes (`RENDER_*_MEM_USED`) y el
**working set del proceso** (PowerShell en Windows, `/proc` en Linux y Android).
También el recuento de nodos por clase (`node_classes`).

**Perfil por script** (después de la medida limpia, sin tocarla): apaga el
`_process` / `_physics_process` de cada nodo con script, autoloads incluidos, y lo
llama a mano entre dos marcas de tiempo. El resultado son µs por fotograma por
script, con el número de nodos. Es aproximado: cambia el orden de proceso, y un nodo
que se apaga a sí mismo sigue recibiendo llamadas mientras dura el perfil. **No
mide** el trabajo que llega por señales ni por timers (`resource_changed`,
`production_tick`...): eso se estima en la auditoría (§5).

### Salida

En `reports/perf/` (git-ignored por la regla `reports/`):

- `<tag>_<escenario>.json`: todo lo de arriba, más la GPU, la CPU, la RAM del
  sistema, el renderer, la ventana y lo sembrado;
- `<tag>_<escenario>.png`: la captura de control (para ver que el escenario es el que
  dice);
- `perf_runs.csv`: una fila por ejecución, acumulativo.

El `tag` por defecto es `<renderer>_<calidad>`. Con `all`, el proceso padre imprime
al final una tabla con los seis JSON.

---

## 4. Medidas de hoy

**Máquina**: portátil con **NVIDIA GeForce RTX 3060 Laptop GPU** (Vulkan 1.4.303,
`RenderingServer.get_video_adapter_name()`), Intel Core i5-10500H (6 núcleos, 12
hilos), 16 GB de RAM, Windows 11, Godot 4.7-stable mono (binario del editor, con
`--no-title`). Ventana de 1280×720, **sin vsync ni tope**, semilla 1, 6 s de
calentamiento y 15 s de medida (10 s en el A/B de §4.2).

**Ojo con el ruido**: mientras se medía, otros 7 agentes corrían Godot en la misma
máquina (tests, sondas, importaciones): entre 6 y 34 procesos de Godot y la CPU al
40-100 %. Cada JSON guarda cuántos había (`process_mem_mb.godot_processes`). Por eso
las tablas de §4.1 sirven para **comparar escenarios entre sí** dentro de una misma
tanda, y la comparación de calidades se hace con el A/B intercalado de §4.2. Las
cifras absolutas, en una máquina en reposo, serán algo mejores.

### 4.1 Los seis escenarios por renderizador y calidad

Columnas: fps de media · 1 % bajo · p99 del fotograma (ms) · render en CPU (ms) ·
resto de CPU (ms) · GPU (ms) · draw calls · primitivas (miles) · nodos · VRAM (MB) ·
working set del proceso (MB).

**Forward+ Alta** (PC):

| Escenario | fps | 1 % | p99 | render CPU | resto CPU | GPU | draw calls | prim. k | nodos | VRAM | proceso |
|---|---|---|---|---|---|---|---|---|---|---|---|
| inicio | 160 | 97 | 9,8 | 3,8 | 2,5 | 1,7 | 1378 | 245 | 2177 | 250 | 888 |
| media | 86 | 52 | 18,3 | 7,4 | 4,2 | 3,3 | 3339 | 350 | 3292 | 270 | 968 |
| grande | 48 | 28 | 32,6 | 13,5 | 7,3 | 4,6 | 5628 | 560 | 5427 | 283 | 1056 |
| tormenta | 47 | 25 | 38,6 | 13,9 | 7,2 | 4,1 | 5652 | 549 | 5427 | 287 | 1070 |
| combate | 81 | 46 | 19,8 | 7,9 | 4,4 | 3,2 | 3476 | 380 | 3564 | 276 | 973 |
| grande_2d | 17 | 9 | 106,8 | 13,1 | 45,2 | 5,3 | 9342 | 345 | 2601 | 83 | 791 |

**Forward+ Baja**:

| Escenario | fps | 1 % | p99 | render CPU | resto CPU | GPU | draw calls | prim. k | nodos | VRAM | proceso |
|---|---|---|---|---|---|---|---|---|---|---|---|
| inicio | 218 | 134 | 7,0 | 2,6 | 2,0 | 1,1 | 994 | 176 | 2177 | 211 | 900 |
| media | 102 | 57 | 15,6 | 6,1 | 3,7 | 2,3 | 2519 | 268 | 3292 | 231 | 960 |
| grande | 57 | 31 | 29,2 | 11,2 | 6,4 | 3,8 | 4673 | 482 | 5427 | 244 | 1065 |
| tormenta | 55 | 26 | 32,2 | 11,7 | 6,6 | 4,1 | 4702 | 474 | 5427 | 248 | 1064 |
| combate | 78 | 45 | 20,4 | 8,0 | 4,9 | 1,8 | 2658 | 296 | 3564 | 236 | 964 |
| grande_2d | 14 | 8 | 122,5 | 15,8 | 54,9 | 5,3 | 9335 | 344 | 2604 | 83 | 801 |

**Mobile, "auto"** (= Baja; aproxima Android en Vulkan):

| Escenario | fps | 1 % | p99 | render CPU | resto CPU | GPU | draw calls | prim. k | nodos | VRAM | proceso |
|---|---|---|---|---|---|---|---|---|---|---|---|
| inicio | 134 | 97 | 9,7 | 4,3 | 3,2 | 1,1 | 996 | 176 | 2177 | 165 | 1027 |
| media | 78 | 52 | 17,2 | 7,8 | 5,0 | 2,4 | 2430 | 269 | 3292 | 185 | 1020 |
| grande | 47 | 29 | 29,4 | 13,2 | 8,2 | 4,4 | 4502 | 483 | 5427 | 199 | 1059 |
| tormenta | 47 | 29 | 28,9 | 13,7 | 7,8 | 4,5 | 4499 | 477 | 5427 | 203 | 1081 |
| combate | 81 | 49 | 17,1 | 7,5 | 4,8 | 2,2 | 2568 | 295 | 3564 | 191 | 998 |
| grande_2d | 14 | 9 | 109,9 | 16,5 | 56,2 | 5,6 | 9341 | 344 | 2604 | 82 | 785 |

**Compatibility (OpenGL 3), "auto"** (= Baja; aproxima un equipo sin Vulkan y el APK de QA):

| Escenario | fps | 1 % | p99 | render CPU | resto CPU | GPU | draw calls | prim. k | nodos | VRAM | proceso |
|---|---|---|---|---|---|---|---|---|---|---|---|
| inicio | 84 | 52 | 18,3 | 9,4 | 2,5 | 4,6 | 993 | 177 | 2177 | 200 | 621 |
| media | 52 | 35 | 26,9 | 16,2 | 2,9 | 6,6 | 2604 | 268 | 3292 | 137 | 591 |
| grande | **29** | **19** | 45,3 | 31,0 | 3,9 | 20,8 | 5161 | 481 | 5427 | 141 | 639 |
| tormenta | 29 | 18 | 50,8 | 31,3 | 3,8 | 20,0 | 5189 | 474 | 5427 | 141 | 696 |
| combate | 45 | 31 | 29,2 | 19,4 | 2,9 | 9,4 | 2740 | 296 | 3564 | 138 | 543 |
| grande_2d | **7** | **5** | 201,1 | 91,6 | 43,3 | 80,6 | 9328 | 344 | 2601 | 159 | 618 |

**Compatibility, Mínima** (emulada por la sonda):

| Escenario | fps | 1 % | p99 | render CPU | resto CPU | GPU | draw calls | prim. k | nodos | VRAM | proceso |
|---|---|---|---|---|---|---|---|---|---|---|---|
| inicio | 111 | 49 | 14,2 | 6,8 | 2,2 | 4,2 | 438 | 70 | 2177 | 155 | 595 |
| media | 68 | 33 | 21,8 | 12,0 | 2,7 | 4,9 | 1285 | 122 | 3292 | 104 | 587 |
| grande | 53 | 32 | 28,7 | 16,4 | 2,4 | 9,0 | 2501 | 206 | 5427 | 109 | 640 |
| tormenta | 52 | 28 | 31,5 | 17,0 | 2,4 | 8,7 | 2534 | 209 | 5427 | 109 | 695 |
| combate | 75 | 46 | 19,9 | 11,3 | 2,1 | 5,2 | 1423 | 151 | 3564 | 133 | 585 |
| grande_2d | 10 | 7 | 143,5 | 70,9 | 33,1 | 62,9 | 9273 | 341 | 2601 | 118 | 561 |

La tanda de Forward+ Mínima de §4.1 se midió con 24-34 procesos de Godot ajenos en
marcha y no se publica aquí. La comparación de calidades buena es la de §4.2.

### 4.2 A/B de calidades en la colonia grande

Seis configuraciones intercaladas en tres rondas, cada una con 10 s de medida. Se
publica la **mejor de las tres** (la menos contaminada por la carga ajena); entre
paréntesis, la peor.

| Renderizador · calidad | fps | 1 % bajo | p99 ms | render CPU ms | GPU ms | draw calls | primitivas | VRAM MB | proceso MB |
|---|---|---|---|---|---|---|---|---|---|
| Forward+ · Alta | 44 (29) | 26 | 37,0 | 14,4 | 4,1 | 5628 | 568 k | 283 | 1067 |
| Forward+ · Baja | 51 (40) | 34 | 26,2 | 12,2 | 2,7 | 4674 | 487 k | 244 | 1062 |
| Forward+ · **Mínima** | **71** (60) | **44** | 19,5 | 8,6 | 1,3 | **2244** | **207 k** | **172** | 1065 |
| Mobile · **Mínima** | **97** (80) | **59** | 15,1 | 6,4 | 0,5 | 2166 | 207 k | 165 | 1055 |
| Compatibility · Baja | 29 (24) | 19 | 43,6 | 30,9 | 19,7 | 5162 | 487 k | 141 | 645 |
| Compatibility · **Mínima** | **50** (37) | **29** | 30,9 | 17,2 | 8,5 | 2502 | 208 k | 109 | 631 |

Del **agente de mundo** (rama `feat/mundo-maqueta`, su calidad `minimal` de verdad,
con la isla sencilla, a 1600×900): Forward+ alta 85 fps frente a mínima 139; Mobile
alta 135 frente a mínima 151. Su escena y su resolución no son las de la sonda, así
que no se suman a la tabla, pero apuntan a lo mismo: **Mínima da entre un +12 % y un
+70 % de fps, y en Compatibility casi lo dobla**.

### 4.3 Perfil por script (µs por fotograma, Forward+ Alta)

| Script | inicio | grande | grande_2d |
|---|---|---|---|
| `view2d/Building2D.gd` (343 nodos) | — | — | **27 037** |
| `view2d/StatusBadge2D.gd` (343 nodos) | — | — | **9 911** |
| `map/WorkerWalkers.gd` | 147 | 448 | 343 |
| `buildings/BuildingPlacer.gd` | 20 | 131 | — |
| autoload `ProductionManager` | — | 131 | 101 |
| `view2d/Deposit2D.gd` (19 nodos) | — | — | 59 |
| autoload `StormManager` | 24 | 35 | — |
| `ui/HelpCallout.gd` (7 nodos) | 44 | 31 | 47 |
| `map/WorldLook.gd` | 35 | 25 | — |
| `ui/HelperPanel.gd` | 27 | 23 | — |
| `camera/MonumentalCamera.gd` | 37 | 19 | — |
| `mcp_runtime.gd` (Beckett, solo editor) | 68 | 14 | 57 |

En 3D, todos los `_process` juntos suman **menos de 1 ms** por fotograma en la colonia
grande. El fotograma de 20-23 ms se va en preparar el render (12-14 ms de CPU) y en lo
que llega por señales, timers e interfaz (6-8 ms de "resto"). En 2D, los dos scripts
por casilla **se comen 37 ms por fotograma ellos solos**.

### 4.4 Qué hay en la escena

| | inicio | grande (3D) | grande (2D) |
|---|---|---|---|
| Nodos | 2177 | 5427 | 2601 |
| `MeshInstance3D` | 618 | **2511** | — |
| `Node3D` | 76 | 942 | — |
| `Label3D` | 34 | 439 | — |
| `Node2D` | — | — | 745 |
| `Label` | 353 | 356 | **718** |
| Nodos con `_process` activo | 41 | 41 | **746** |
| Objetos | 7285 | 13 132 | 7349 |
| Recursos | 335 | 337 | 326 |
| Nodos huérfanos | 0 | 0 | 0 |

Solo la interfaz pone unos 350 `Label` y 150 `Button` en todas las escenas.

### 4.5 Memoria

- **Estática** (`MEMORY_STATIC`): 145 MB al inicio y 214 MB en la colonia grande en
  Vulkan; 117-156 MB en Compatibility.
- **VRAM** (`RENDER_VIDEO_MEM_USED`): 250-287 MB en Forward+ Alta, 211-248 en Baja,
  **~110-170 en Mínima**. De eso, unos 170 MB son "texturas" incluso al inicio: el
  atlas de sombras y los búferes de render, no los assets (que son pocos). En 2D baja
  a 83 MB.
- **Proceso** (working set): **~900-1080 MB en Vulkan** (Forward+ y Mobile) y
  **~550-700 MB en Compatibility**, con el binario del **editor**. Un export release
  pesa menos (sin las clases del editor), pero la diferencia Vulkan/OpenGL es sobre
  todo del driver. Para el PC de 4 GB del presupuesto (≤ 600 MB) habrá que medir el
  `.exe` exportado; si no entra, Compatibility es la vía.
- No hay fugas a la vista: 0 nodos huérfanos y el recuento de objetos estable durante
  la medida.

### 4.6 Lo que dicen las medidas

1. **El 3D está limitado por la CPU que prepara el render, no por la GPU.** En la
   colonia grande la GPU tarda 3-5 ms, y la CPU 12-14 ms solo en el render, con unos
   5600 draw calls para 2511 `MeshInstance3D`. Las carreteras (276 nodos con hasta 6
   mallas y 3 materiales cada una, todo con sombra) son el grueso (§5.2).
2. **La vista 2D es hoy la más cara**: 14-17 fps en la colonia grande, por 686
   `_process` de Building2D y StatusBadge2D (37 ms por fotograma) y 9300 draw calls
   de canvas. Está lejos de ser la salida para equipos flojos (§5.3).
3. **Mínima funciona**: −60 % de draw calls y primitivas, −110 MB de VRAM, +60 % de
   fps en Forward+ y +70 % en Compatibility. Con el renderizador **Mobile**, Mínima
   llega a 97 fps en la colonia grande, el mejor resultado de todos: su render en CPU
   es más ligero que el de Forward+.
4. **Compatibility es el caso "papa" que más se acerca**: en Baja, la colonia grande
   cae a 29 fps (1 % bajo de 19) incluso con una RTX 3060. En Mínima vuelve a 50 fps.
   En una integrada vieja hay que contar con la mitad o menos: **sin las
   optimizaciones 1, 2 y 6 de §6, el presupuesto de 30 fps estables en la colonia
   grande no se cumple** en un equipo así.
5. **La Tormenta no cuesta casi nada** (≤ 1-2 fps menos): cielo, niebla y daños son
   baratos en este estado. Solo el `material_overlay` de la ceniza sobre los
   edificios dañados (§5.2) puede crecer tras varias tormentas.
6. **El combate pesa lo mismo que su colonia** (la de `media`): el tablero 8×8 es
   interfaz y no añade coste apreciable.

---

## 5. Auditoría estática

Lo que cuesta en cada fotograma o en cada señal, leído en el código. El impacto es
**alto**, **medio** o **bajo**, y se apoya en la medida cuando la hay (§4). Las rutas
son relativas a `scripts/` salvo que se diga otra cosa.

### 5.1 Lo que ya está bien

- **Ningún edificio 3D tiene `_process` propio.** El aspecto (obra, ruina, activo)
  se sincroniza con un único reloj a 4 Hz en `buildings/BuildingPlacer.gd:213`.
- **Los caminantes van en MultiMesh** (`map/WalkerFigures3D.gd`), con un tope por
  perfil (`life_figure_cap`: 72 en PC, 44 en tablet, 26 en móvil). En la colonia
  grande cuestan 0,4-0,7 ms de CPU por fotograma (perfil, §4), y su sombra solo está
  encendida en PC (`WalkerFigures3D.gd:55`).
- **El humo, el polvo y las obras se animan por shader** (`TIME`), con materiales y
  hojas de sprites en caché (`buildings/BuildingFx.gd`, `SiteFx.gd`), sin
  partículas y sin sombra (`BuildingFx.gd:245`).
- **`WorldLook` ya baja la factura en Mobile y Compatibility**: "auto" es baja fuera de
  Forward+ (sin SSAO ni glow y con sombra ortogonal de un corte). Ver
  `map/WorldLook.gd:69-79`.
- **El audio es OGG Vorbis**, sin WAV: 4 músicas (3,8 MB) y 16 SFX, que se decodifican
  al sonar. Los carga todos al arrancar (`services/AudioManager.gd:146`), pero en
  comprimido no es caro. *(1.1: ya son 5 pistas, 47 SFX y 4 bucles de ambiente,
  6,4 MB en total; los 13 efectos de combate por unidad son mono a 22 kHz, 140 KB
  entre todos. Elegir el clip cuesta una búsqueda en un diccionario por evento; no
  hay `_process` nuevo y solo suena un bucle de ambiente, dos durante el fundido.)*
- **Física**: no hay cuerpos ni áreas. Los raycasts del ratón son matemáticos. Su
  coste medido es casi nulo (pico de física < 0,3 ms).
- **Autoloads**: 12 tienen `_process`, y todos son temporizadores O(1) u O(activos).
  El más caro es `ProductionManager`, con 0,1-0,25 ms en la colonia grande.
- Cachés que funcionan: `BuildingLot`, `ToyPalette`, `UITheme` (fuentes y
  texturas), `ColonyFlag` y el resaltado de casillas en MultiMesh
  (`BuildingPlacer.gd:946`).

### 5.2 Render 3D: demasiados nodos de malla (alto)

| Dónde | Qué pasa | Impacto |
|---|---|---|
| `buildings/DieselpunkBuildingFactory.gd:1280` (`_build_road`) | Cada carretera crea **3 `StandardMaterial3D` nuevos** (`_metal()` no tiene caché, `:39`) y hasta 6 `BoxMesh` + MeshInstance: firme, bordillos y raya. Todos **proyectan sombra** (no se toca `cast_shadow`). Con 276 carreteras salen unos 800 materiales únicos y más de 1000 mallas, repetidas en cada corte de sombra | **Alto**: el grueso de los 4000-5600 draw calls de `grande` (§4) |
| `DieselpunkBuildingFactory.gd:223-455` (`_build_nucleo`) | ~200 MeshInstance (73 `_add_*` más ~70 remaches), materiales sin caché y todo con sombra. El Mercado y el Laboratorio siguen el mismo patrón | **Medio**: ~200 draw calls × (1 + cortes de sombra), siempre en pantalla |
| `DieselpunkBuildingFactory.gd` (92 llamadas a `_metal()`) | Un material nuevo por pieza en todo lo procedural | Medio: impide que el motor agrupe por material |
| `buildings/BuildingPlacer.gd:436, 646, 671-691` | `_update_road_connections` rehace la carretera **y sus 4 vecinas** (`queue_free` de hijos más factoría nueva), directo y además diferido. Al cargar, cada carretera se rehace hasta 5 veces | **Alto en la carga** y al colocar; nulo en régimen |
| `services/BuildingHealth.gd:146-156` | Cada cambio de vida crea un `StandardMaterial3D` transparente y lo pone de `material_overlay` en **todas** las mallas del edificio. Con media base dañada tras una Tormenta, se duplican los draw calls de esos edificios y se suma un pase transparente | **Medio-alto**, recurrente con cada Tormenta |
| `buildings/BuildingStatusBadge.gd:79-92` | Un `Label3D` por edificio que trabaja (y en carreteras hasta su primera reconstrucción). Conecta 13 señales y responde a `production_tick` y `workers_changed` de **todos** | Medio (CPU por señal; sprites transparentes) |
| `map/water_border.gdshader:47-60` | Plano de agua de 400×400 con 6 `noise()` por píxel, animado con `TIME` | **Medio en móvil** (fill-rate) |
| `map/grass_ground.gdshader:41-67` | ~11 ruidos por píxel en toda la isla, y el patrón es estático | Medio en móvil; hornearlo a textura |
| `scenes/main/Main.tscn:121` + `GridOverlay` | Malla transparente del tamaño de la rejilla, **encendida por defecto** | Medio-bajo en móvil |
| `buildings/BuildingFx.gd:205-228`, `SiteFx.gd:101-137` | `Shader.new()` con el código en tiempo de ejecución: compila la primera vez que sale humo o una obra | Tirón puntual (más en Android) |

### 5.3 Vista 2D: un `_process` por casilla (alto)

| Dónde | Qué pasa | Impacto |
|---|---|---|
| `view2d/Building2D.gd:150-166` | `_process` **por edificio y por carretera**, cada fotograma: `_layout_labels()` con `reset_size()` y, en el seleccionado, `queue_redraw()`. Además arma una firma de 12 campos más 3 diccionarios (`LookRule.facts_of/derive`, `seed_of`, `road_neighbor_mask`) | **Alto: ~25 ms por fotograma** con 343 nodos en `grande_2d` (perfil, §4) |
| `view2d/StatusBadge2D.gd:63-72` | Otro `_process` por edificio y carretera: `refresh()` cada 0,25 s (diccionario de 10 claves) y `label_scale()` + `scale`/`position` cada fotograma. En las carreteras no se ve nunca | **Alto: ~9 ms por fotograma** en `grande_2d` |
| `view2d/Building2D.gd:348` + `Camera2DController.gd:71` | `label_scale()` → `screen_boost()` pregunta `DisplayServer.window_get_size()` y el `content_scale_factor`, **2 veces por nodo y fotograma** | Medio-alto (va dentro de las dos filas de arriba) |
| `view2d/Deposit2D.gd:32-38` | `_process` por yacimiento con `is_unlocked` | Bajo (0,06 ms) |
| `view2d/StormTint2D.gd:69-84` | `CPUParticles2D` de 220 partículas en la Ceniza, posición y extensión reasignadas cada fotograma | Bajo |

La vista 2D, que debería ser la salida para equipos flojos, es hoy **la más cara de
todas** en CPU: la colonia grande en 2D va a 14-18 fps en este PC (§4).

### 5.4 Señales que hacen trabajo O(n) o lo repiten (alto en ráfagas)

| Dónde | Qué pasa | Impacto |
|---|---|---|
| `services/GameManager.gd:707` + `buildings/PlacementRules.gd:461` | `pave_route` emite `building_placed` **por cada tramo** del auto-road, y `_on_building_changed` llama a `save_game()` síncrono por tramo (JSON indentado con `"\t"`, `GameManager.gd:596`). Una ruta de 15 casillas son 15 guardados completos en el mismo fotograma | **Alto**: tirón de 50-500 ms en colonia grande, más en móvil |
| `services/PopulationManager.gd:34` | Cada `building_placed` llama a `_recalculate_all()` síncrono: núcleo, BFS de la red y `has_its_deposit` por edificio | **Alto en ráfagas** (auto-road): O(tramos × n) |
| `grid/GridManager.gd:195-202` | `get_all_buildings()` **duplica el diccionario de cada edificio** en cada llamada, y la llaman `count_building`, `core_cells`, Objectives, ArmyManager, TutorialPanel... | Medio, multiplica todo lo demás |
| `buildings/PlacementRules.gd:64-86, 266, 276, 317, 386` | Cada `evaluate_placement` hace `load()`, 2-3 `core_cells()`, uno o dos BFS de la red y, si falla, un BFS por toda la rejilla libre (hasta 2304 casillas) | Alto en las rutas calientes de abajo |
| `buildings/PlacementAssist.gd:284-305` (`valid_spots`) | En cada `refresh_spots()` (al empezar a colocar y en cada giro) evalúa 100-250 orígenes con `evaluate_placement` | **Alto en tablet**: tirón al pulsar un extractor o al girar |
| `map/WorkerWalkers.gd:87-91, 274-282` | `workers_changed`, `population_changed` y `building_placed` rehacen la red y **vacían la caché de rutas** | Medio-bajo |
| `buildings/BuildingLot.gd:111-114` | Cada parcela hace `refresh.call_deferred()` por evento, sin deduplicar | Bajo-medio |

### 5.5 Interfaz que se reconstruye en vez de actualizarse (medio)

| Dónde | Qué pasa | Impacto |
|---|---|---|
| `ui/ConstructionMenu.gd:739-750` + `ui/TextKit.gd:60-64` | Con la lista abierta, **cada `resource_changed`** (uno por recurso y producción) libera y recrea las fichas de coste de ~15 tarjetas (45-60 Controls), y `purchase_block_detail` cuenta edificios con `get_all_buildings()` | **Medio**: es la pantalla más usada |
| `ui/NotificationPanel.gd:192-197` | Cada notificación, **aunque el registro esté cerrado**, hace `queue_free` de hasta 50 Labels con autowrap y los recrea | Medio (ráfagas con el auto-road) |
| `ui/TutorialPanel.gd:261-345` | Mientras dura el tutorial, `_layout_step()` corre **cada fotograma**: `step_hint()` con `load()`, `HelpTargets.rect()` con `find_child`, `get_all_buildings()`, `reset_size()` | Medio, justo en el arranque y en tablet |
| `ui/HelpTargets.gd:120-158` | Busca la tarjeta de un edificio con `find_children("*", "Button")` recursivo, cada fotograma | Medio |
| `ui/HelperPanel.gd:466-488` | `_update_pointer()` cada fotograma con una ayuda visible | Bajo (0,02-0,07 ms medidos) |
| `ui/ObjectivePanel.gd:148-175` | Abierto, cada segundo: `Objectives.next_step()` + `route()` O(L·n) y recrea todas las filas | Medio-bajo |
| `ui/RankPanel.gd:231` | Con el panel abierto, recrea botones en cada `production_tick` | Bajo-medio |
| `ui/ResourceHUD.gd:433-437`, `ui/UITheme.gd:895` (`flash_label`) | Un tween nuevo por aviso, sin `kill()` del anterior: se pisan | Bajo |
| `services/FloatingText.gd:14-23`, `view2d/FloatingText2D.gd` | Label3D/Label y tween nuevos por cada ganancia | Bajo; pool si crece |
| `ui/ConstructionMenu.gd:779-830` | 16 miniaturas renderizadas al arrancar con `get_image()` (lectura síncrona de la GPU) | Tirón al cargar en móvil |

### 5.6 Proyecto, assets y memoria

| Dónde | Qué pasa | Impacto |
|---|---|---|
| `project.godot:87` | `msaa_3d=2` sin variante `.mobile`: también se paga en Android | **Medio en móvil** |
| `project.godot` | Sin `application/run/max_fps` ni `scaling_3d`: en móvil corre al refresco nativo (90/120 Hz) y gasta batería | **Medio en móvil** |
| `project.godot` `[rendering]` | No fija `rendering_device/fallback_to_opengl3`: conviene dejarlo explícito para los móviles sin Vulkan | Bajo (seguridad) |
| `assets/textures/metal_plate_{diff,nor_gl,rough}_1k.jpg` | Importadas **sin compresión VRAM** (`compress/mode=0`) y **sin mipmaps**. Se cargan desde script (`DieselpunkBuildingFactory.gd:12`), así que `detect_3d` no llega a convertirlas: unos 12 MB de VRAM sin comprimir, con aliasing y fallos de caché a distancia | Medio (VRAM en integradas y móvil) |
| `assets/` | 16 MB en total: modelos 6,2 MB (21 GLB, el mayor `nucleo.glb` con 390 KB), audio 4 MB, texturas 2,7 MB, fuentes 1,9 MB, marca 0,8 MB. Pocos y pequeños | Bajo |
| Plantilla de export | La de Windows release pesa 109 de los 123 MB del `.exe` (docs/19 §13); la estándar, 109,16 frente a 109,41 la mono | El mayor ahorro de tamaño: plantilla compilada a medida, no la estándar |
| `ResourceLoader` | Los `load()` en caliente (`PlacementRules.gd:46`, `HelpTargets.gd:130`) van a la caché, pero cada uno paga `exists`, formato de ruta y el bloqueo de la caché | Bajo por sí solo, multiplicado en §5.4 y §5.5 |
| `_process` siempre activos | `MonumentalCamera.gd:61` hace `look_at` cada fotograma aunque no se mueva; `WorldLook.gd:45` crea un diccionario de estado por fotograma; `InputService.gd:90` hace 10 `is_key_pressed` | Bajo (0,01-0,03 ms cada uno) |

Recuento: **40 scripts con `_process`**: 12 autoloads y 28 de escena (4 de buildings,
map o camera, 6 de view2d y 18 de ui). En la colonia grande quedan **41 nodos con
`_process` activo en 3D**, frente a **746 en 2D**, porque cada Building2D y cada
StatusBadge2D lleva el suyo. `get_nodes_in_group` y `find_child` en bucle solo
aparecen en el tutorial y en las ayudas (§5.5). En el editor se suma el
`mcp_runtime.gd` de Beckett (~0,015 ms), que no va en los exports.

---

## 6. Optimizaciones priorizadas

Por orden de ganancia esperada frente a riesgo. La columna "Zona" dice qué agente o
qué parte del código lo toca, para repartirlo después de integrar. **Ninguna está
hecha** en la rama de medida. Desde entonces (todo en `integracion/arte-v1`,
2026-10-12/14) están hechas la **1** (`feat/2d-maqueta`), la **2**, la **12** y parte de
la **10** (`perf/render-3d`), la **3** y la **7** (`perf/calidad-minima`, §7.6), la **4**,
la **5** y la **8** (`perf/servicios`) y la **9** (`perf/interfaz`); detalle debajo de la
tabla. **Ninguna se ha vuelto a medir con esta sonda**: las cifras de §4 son de antes. Cada una se valida con la sonda antes y después, con el
mismo escenario, semilla y calidad, y la máquina en reposo.

| # | Qué | Dónde | Ganancia esperada | Riesgo | Zona |
|---|---|---|---|---|---|
| 1 | **Vista 2D sin `_process` por casilla**: repintar por señal (obra, ruina, mejora, `building_placed`) más un reloj único a 4 Hz en `BuildingPlacer2D`, como ya hace el 3D. Sin badge ni firma en las carreteras. `label_scale()` / `screen_boost()` en caché de la cámara (se recalcula en `size_changed` o al cambiar el zoom) | `view2d/Building2D.gd:150`, `StatusBadge2D.gd:63`, `Camera2DController.gd:71` | **−30 a −35 ms por fotograma** en `grande_2d` (perfil: 27 + 10 ms). De 14-17 fps a más de 60 en este PC. Es lo que convierte la 2D en la vista para equipos flojos | Bajo-medio: el aspecto de las obras y la ruina tiene que seguir al día (tests `tests/view2d`) | Vista 2D |
| 2 | **Carreteras 3D baratas**: materiales compartidos (caché de `_metal()` por color, metálico y rugosidad), `BoxMesh` en caché por tamaño, `cast_shadow = OFF` en firme, bordillo y raya. Mejor todavía: las 16 variantes por máscara de vecinos en caché y solo cambiar `mesh`; o una malla (o un MultiMesh por pieza) por trozo de 8×8 casillas | `buildings/DieselpunkBuildingFactory.gd:39, 1280`, `buildings/BuildingPlacer.gd:436, 646, 671` | Con 276 carreteras, **−1500 a −2500 draw calls** de los ~4700-5600 de `grande`, y el render en CPU de ~12 ms a ~5 ms. En Compatibility es aún más: allí el render en CPU de `grande` es de 31 ms | Medio: conectividad, selección y demolición de un tramo, el bordillo por lado | Arte / mundo |
| 3 | **Calidad "Mínima" en el juego, con detección en el primer arranque y tope de FPS** (§7) | `map/WorldLook.gd`, `services/GameConfig.gd` (`GRAPHICS_QUALITY_MODES`), `ui/SettingsPanel.gd`, `services/DeviceProfile.gd` | Medido con la emulación de la sonda: **−50 a −60 % de draw calls y primitivas**, **−110 MB de VRAM** y, en Compatibility, de 29 a 53 fps en la colonia grande (§4.2). En una integrada, donde manda la GPU, la ganancia será mayor que en esta RTX | Bajo | Mundo (ya empezada en `feat/mundo-maqueta`) + Interfaz |
| 4 | **Coalescer `building_placed`**: el auto-road emite una vez por lote (o los oyentes se apuntan con una bandera de "sucio" y `call_deferred`). `_on_building_changed` pasa a `request_save()` (con debounce) y el JSON se escribe sin indentar | `services/GameManager.gd:596, 707`, `services/PopulationManager.gd:34`, `buildings/PlacementRules.gd:461`, `map/WorkerWalkers.gd:87`, `buildings/BuildingLot.gd:111` | Quita los tirones de **50-500 ms** al colocar con auto-road en una colonia grande (15 guardados y 15 recálculos en un fotograma). No se ve en la media, sí en el 1 % bajo y en la sensación | Medio: hay tests que esperan el efecto síncrono (dotación, guardado) | Servicios |
| 5 | **Caché de la red de carreteras y del núcleo**, con una versión del mapa que se invalida en placed, demolished y moved. `GridManager.count_by_id()` / `for_each_building()` sin `duplicate()` | `buildings/PlacementRules.gd:64-86, 266, 276, 317, 386`, `grid/GridManager.gd:195`, `buildings/PlacementAssist.gd:284` | `valid_spots` pasa de cientos de BFS a uno: quita el tirón al elegir un extractor o al girar en tablet. Abarata también Objectives, ArmyPanel, TutorialPanel y el fantasma | Bajo-medio | Colocación / servicios |
| 6 | **Materiales y mallas compartidos en lo procedural**: el Núcleo, el Mercado y el Laboratorio combinados con `SurfaceTool` en 1-3 mallas por material, y remaches y tuberías sin sombra | `buildings/DieselpunkBuildingFactory.gd:223-455` y siguientes | −200 a −400 draw calls siempre en pantalla (el Núcleo solo son ~200 MeshInstance) | Bajo con la caché; medio al combinar | Arte |
| 7 | **`project.godot` para móvil**: `anti_aliasing/quality/msaa_3d.mobile=0`, `application/run/max_fps` por perfil (§7.4), `rendering/scaling_3d/scale.mobile=0.75` (o FSR), `rendering/rendering_device/fallback_to_opengl3=true` explícito (hoy depende del valor por defecto del motor) | `project.godot` | MSAA 2x es caro en las GPU de móvil (ancho de banda). El tope de FPS ahorra batería y calor | Bajo | Interfaz / exportar |
| 8 | **Ceniza de los edificios con material compartido**: 4-5 niveles cuantizados en caché en vez de un `StandardMaterial3D` nuevo por cambio de vida | `services/BuildingHealth.gd:146-156` | Evita la explosión de materiales únicos y de draw calls tras cada Tormenta | Bajo | Tormenta / servicios |
| 9 | **Interfaz que actualiza en vez de recrear**: ConstructionMenu con un refresco por fotograma como mucho y fichas reutilizadas; el registro de NotificationPanel solo se reconstruye al abrirlo; TutorialPanel a 4 Hz con el destino en caché; ObjectivePanel solo si cambia el paso; tweens con `kill()` | `ui/ConstructionMenu.gd:739`, `ui/NotificationPanel.gd:192`, `ui/TutorialPanel.gd:261`, `ui/HelpTargets.gd:120`, `ui/ObjectivePanel.gd:148`, `ui/ResourceHUD.gd:433`, `ui/UITheme.gd:895` | Quita trabajo O(n) por señal en las pantallas más usadas; más visible en tablet y durante el tutorial | Bajo | Interfaz |
| 10 | **Texturas y shaders para GPU flojas**: las tres `metal_plate_*_1k.jpg` con compresión VRAM y mipmaps (o a 512 px); el agua a 2 octavas en Mobile/Compatibility; la hierba horneada a textura al generar la isla; `GridOverlay` apagado por defecto en tablet y móvil; shaders de humo y obra como `.gdshader` precargados y calentados al cargar | `assets/textures/*.import`, `map/water_border.gdshader`, `map/grass_ground.gdshader`, `scenes/main/Main.tscn:121`, `buildings/BuildingFx.gd:205`, `SiteFx.gd:101` | −10 MB de VRAM, menos fill-rate en móvil (el agua y la hierba cubren casi toda la pantalla), sin tirón la primera vez que sale humo | Bajo (el agente de mundo ya tiene una "isla sencilla") | Arte / mundo |
| 11 | **Export más ligero**: ~~plantilla estándar (no mono) y release~~ (medido: la estándar pesa lo mismo) → plantilla compilada a medida, y fuera del export lo que el juego no carga | `export_presets.cfg`, docs/19 §13 | `.exe` de 120 a ≤ 90 MB y APK a ≤ 30 MB solo con la plantilla a medida (sin medir); las exclusiones dan −2 MB | Bajo-medio (la plantilla a medida hay que probarla entera) | Exportar |
| 12 | **Badges 3D por despachador**: no crear el `Label3D` de estado en carreteras ni decoraciones; un único receptor de `production_tick` / `workers_changed` en BuildingPlacer que refresca solo el badge afectado | `buildings/BuildingStatusBadge.gd:79-92` | −300 `Label3D` en `grande` (hay 439) y de O(n²) a O(n) por ronda de producción | Bajo | Arte / edificios |

**Hecho en `feat/2d-maqueta` (2026-10-12), punto 1:** `ArtCache2D` hornea cada dibujo
una vez en un SubViewport pequeño y el edificio pasa a ser un rectángulo con textura;
las calzadas no tienen `_process` (ni badge) y se repintan cuando cambia la rejilla a su
alrededor; los demás edificios miran su firma cada `Building2D.CHECK_FRAMES` (10)
fotogramas, repartidos; los badges releen cada 0,5 s y solo se recolocan si cambia el
zoom. Medido con `tools/view2d_probe.gd -- --perf` (no con esta sonda): de ~83 ms a
~7 ms por fotograma en un mapa de 482 piezas. Detalle en
[18-vista-2d.md](18-vista-2d.md), "Rendimiento: la 2D tiene que ir en una papa".

**Hecho en `perf/render-3d` (2026-10-14, sin medir todavía), puntos 2, 12 y parte del 10:**

- **2**: las calzadas 3D van en `RoadBatch3D` (`scripts/buildings/RoadBatch3D.gd`): un
  MultiMesh por máscara de vecinos (16 como mucho), malla en caché
  (`DieselpunkBuildingFactory.road_mesh()`) y material común de `ToyPalette`, sin sombra
  proyectada. El nodo de cada calzada ya no lleva malla, badge ni rótulo; el reparto se
  rehace una vez por fotograma. `_metal()` en caché y remaches sin sombra.
- **12**: el rótulo `NameLabel` nace solo al seleccionar (`ensure_name_label`) y no hay
  badge en lo que no trabaja (casas, decoración, calzadas).
- **10** (parte): las texturas `metal_plate` rough/normal con compresión VRAM, mipmaps y
  512 px; `BuildingFx` comparte 2 shaders 3D y un QuadMesh por medida, y humo, polvo,
  chispas, farol, grúa y banderín se calientan al cargar. El suelo de las parcelas usa
  `lot_ground.gdshader` (una textura por tipo de suelo). `ColonyFlag3D` con materiales de
  bandera y mástil compartidos; `StockIcon3D` sin `_process` cuando no se ve.
- El punto **6** quedó sin objeto: el Núcleo, el Mercado y el Laboratorio ya no son
  procedurales, son modelos horneados de una malla (docs/03, "Modelos: maqueta de
  juguete").

**Hecho en `perf/interfaz` (2026-10-14, sin medir todavía), punto 9:** ConstructionMenu
solo recrea la rejilla si cambia qué tarjetas hay o su bloqueo (si no, repinta los
costes), y con la lista cerrada no hace nada; TutorialPanel busca destino, texto y lo que
falta a 4 Hz; HelpTargets pide la tarjeta por id; `TextKit.fill_cost_row` no rehace una
fila igual; ResourceHUD refresca una vez por fotograma y mata el tween anterior;
`UITheme.flash_label` sin tweens apilados; ObjectivePanel reutiliza filas y solo corre
abierto; ArmyPanel y TechTreePanel repintan solo abiertos y una vez por fotograma;
RankPanel junta la XP del mismo fotograma.

**Hecho en `perf/servicios` (2026-10-14, sin medir todavía):**

- **4**: `PlacementRules.pave_route` envuelve los tramos en una tanda
  (`EventBus.placement_batch_started` / `placement_batch_finished`). GameManager,
  PopulationManager y TutorialManager apuntan y hacen su trabajo una vez al cerrarla,
  en la misma llamada: una ruta de N tramos pasa de N guardados y N recuentos a 1 (más
  el del propio edificio). El JSON sigue indentado (no se toca el fichero).
  WorkerWalkers y BuildingLot no se tocaron (zona de mundo / arte).
- **5**: `GridManager.map_version()` sube con cada cambio de ocupación o de tierra;
  `PlacementRules` guarda por versión el Núcleo, la red (`network_view()`), las rutas
  de `road_route()` y los `BuildingData` cargados. `prepare_route_queries()` (lo llama
  `PlacementAssist.valid_spots`) calcula una vez las celdas libres que llegan a la red
  y descarta sin BFS los sitios sin camino. `GridManager.buildings_view()` /
  `count_by_id()` recorren sin copiar; los servicios los usan. `get_all_buildings()`
  sigue copiando (UI, herramientas y tests no cambian).
- **8**: `BuildingHealth` usa 8 escalones de ceniza con un material compartido cada uno.

**11, en parte, en `perf/paquete` (2026-10-14, medido, docs/19 §13):**

- Fuera del export, en los tres presets, `assets/models/cc0/*` y seis assets que solo
  usan las herramientas (`metal_plate_diff_1k.jpg`, `banner.png`, los SVG de la marca,
  `Rajdhani-Medium.ttf`): **−1,97 MB**. `.exe` 124,6 → 122,7 MB (zip 50,3 → 48,4);
  APK release 41,9 → 39,9 MB. `tests/build/test_export_guards.gd` falla si el juego
  vuelve a usar alguno.
- La plantilla estándar **no** ahorra (−0,25 MB, medido sobre el `.tpz` oficial), y el
  audio no se puede bajar desde la importación (ya es OGG en flujo). Lo que falta para
  el presupuesto es la **plantilla compilada a medida**, que tiene que compilar el
  dueño: pasos en docs/19 §13.4. Pendiente también decidir si el zip pasa a `.7z`
  (36,6 MB) y si se recodifica la música (~1,5 MB).
- La **12** (badges 3D por despachador) no es de esta rama: sigue pendiente.

Las dos primeras son las que mueven la aguja en la medida de hoy: el juego está
**limitado por la CPU que prepara el render** (draw calls) en 3D y **por los scripts**
en 2D. La GPU de este PC va holgada (3-5 ms por fotograma en 3D), pero en una
integrada no lo estará: ahí pesan la 3, la 7 y la 10.

---

## 7. Calidad "Mínima" y primer arranque

Decisiones del dueño (2026-10-12): los equipos mínimos son los tres de §2. En el
primer arranque, si el equipo es flojo o es un Android de gama baja, el juego pone
**solo** la calidad "Mínima", y el jugador puede cambiarla en Ajustes. El **tope de
FPS** lo elige el jugador en Ajustes.

El agente de mundo ya creó una calidad `minimal` en `WorldLook`, en la rama
`feat/mundo-maqueta`: sin sombras, SSAO ni glow, isla sencilla y `scaling_3d_scale`
0,7. Desde el 2026-10-14 está en `GameConfig.GRAPHICS_QUALITY_MODES` y en Ajustes
(§7.6). Midió a
1600×900: **Forward+ alta 85 fps frente a mínima 139**; **Mobile alta 135 frente a
mínima 151**. Este diseño parte de esa calidad y le añade lo que no es del mundo.

### 7.1 Qué apaga "Mínima"

| Ajuste | Alta | Baja (hoy) | **Mínima** | Por qué |
|---|---|---|---|---|
| Sombra del sol | 4 cortes (Forward+) / 2 (Mobile) | ortogonal, 1 corte | **apagada** (`shadow_enabled = false`) | Las sombras repiten cada malla en su pase: es lo que más baja los draw calls (−50 % medido) y libra el atlas (~110 MB de VRAM menos) |
| Sombra de contacto | — | — | la mancha de `BuildingLot` (`_shadow`), que ya existe y no cuesta | El aire de maqueta no se pierde del todo sin sombra |
| SSAO / SSIL / SSR | SSAO en Forward+ | no | **no** | Pase a pantalla completa |
| Glow | sí (no en Compatibility) | no | **no** | Pase a pantalla completa |
| MSAA 3D | 2x | 2x | **no** | Ancho de banda; el reescalado bilineal ya suaviza |
| `scaling_3d_scale` | 1,0 | 1,0 | **0,7** (0,6 en móvil), bilineal o FSR 1 | El 3D se pinta con la mitad de píxeles; la interfaz (`canvas_items`) sigue nítida a resolución nativa |
| Radiancia del cielo | 64 | 32 | 32, o luz ambiental de color sin cielo | Barato, pero en Compatibility cuenta |
| Niebla | solo en la Tormenta | igual | igual, y `fog_enabled` solo con peso > 0 (`StormSky.gd:113`) | Hoy está siempre encendida con densidad 0 |
| Isla | shaders de hierba y agua con ruido | igual | **isla sencilla** (la del agente de mundo): hierba horneada, agua de 1-2 octavas | Fill-rate en integradas y móviles |
| Rejilla (`GridOverlay`) | encendida | encendida | **apagada por defecto** | Pase transparente casi a pantalla completa |
| Humo, polvo, brillo | quads con shader | igual | **ocultos** (grupo `building_fx`) | Transparentes y con `TIME`; son adorno |
| Caminantes | 72 PC / 44 tablet / 26 móvil, con sombra en PC | igual | **16 / 12 / 8**, sin sombra | 0,4-0,7 ms de CPU en la colonia grande, más su dibujo |
| Tope de FPS | el del jugador (§7.4) | igual | **30** por defecto | Estable mejor que alto, y menos calor y batería |

Lo de la tabla lo cubre `WorldLook` (sol, entorno, escalado) más tres interruptores
fuera de él: `GameConfig.life_figure_cap`, la visibilidad del grupo `building_fx` y la
rejilla. Todos escuchan `EventBus.graphics_quality_changed`, que ya existe.

### 7.2 Cuándo es "flojo": detección en el primer arranque

Se decide **una vez**: cuando la preferencia es `auto` (la de serie) y
`settings.cfg` aún no trae `[interfaz] quality_detected`, o cuando el jugador pulsa
"Detectar de nuevo" en Ajustes. El resultado se guarda como preferencia normal
(`graphics_quality = "minimal"`, `"low"` o se queda en `"auto"`), más
`quality_detected = true` y `quality_detected_reason` para depurar. Nunca vuelve a cambiar sola una calidad que
el jugador eligió. Vive en `DeviceProfile` (que ya detecta PC, tablet y móvil y se
carga el último) y en `WorldLook` para aplicarla.

**Paso 1, señales estáticas (instantáneo).** Basta una para poner Mínima:

| Señal | Cómo se lee | Criterio de "flojo" |
|---|---|---|
| Renderizador | `RenderingServer.get_current_rendering_method()` | `gl_compatibility` (en Android significa que no hubo Vulkan y se cayó a OpenGL) |
| Tipo de GPU | `RenderingServer.get_video_adapter_type()` | `RenderingDevice.DEVICE_TYPE_INTEGRATED` **y** otra señal de esta tabla, o un nombre de la lista de abajo |
| Nombre de la GPU | `RenderingServer.get_video_adapter_name()` | PC: `Intel(R) HD Graphics`, `UHD Graphics 6xx`, `HD Graphics 5xx/4xx`, `Radeon R[2-7]`, `Vega 3/6/8` de portátil viejo. Android: `Mali-T*`, `Mali-G31/G51/G52/G57`, `Adreno (TM) 3xx/4xx/5xx/610/612/613`, `PowerVR` (`GE8xxx`, `IMG`) |
| RAM del sistema | `OS.get_memory_info()["physical"]` | PC ≤ 4 GB; Android ≤ 4 GB |
| Núcleos | `OS.get_processor_count()` | ≤ 4 hilos en PC; ≤ 4 en Android |
| Perfil | `DeviceProfile.current()` | `phone` con RAM ≤ 6 GB |

La lista de nombres va en `GameConfig` (una tabla de patrones), para ampliarla sin
tocar código cuando un probador diga "en mi equipo va mal".

**Paso 2, medida corta (si el paso 1 no decidió).** Detrás del menú de título ya
corre el mapa (`TitleMenu` va encima de la partida cargada), así que no hace falta
una escena aparte:

1. esperar 2 s a que compilen los shaders y se asiente la carga;
2. medir 3 s de tiempos de fotograma con la calidad que toca por defecto (Alta en
   PC, Baja en Mobile);
3. si la mediana pasa de **25 ms** (< 40 fps) o el p95 de **33 ms** → Mínima; si
   está entre 16,7 y 25 ms en Alta → Baja; si no, se queda.

Con vsync la medida no ve por encima del refresco, pero no hace falta: solo se busca
el suelo. La medida se descarta (y se repite en el siguiente arranque) si la ventana
pierde el foco o se minimiza mientras se mide.

**Paso 3, aviso.** Si se bajó la calidad, sale una tarjeta, una sola vez: "Hemos
puesto la calidad Mínima para que el juego vaya fluido en este equipo. Puedes
cambiarla en Ajustes → Interfaz." (claves `Tr` nuevas, ES y EN).

**Red de seguridad en partida (opcional).** Si con una calidad por encima de Mínima
la media de 10 s baja de 22 fps durante 30 s seguidos, se **sugiere** (no se impone)
bajarla, con la misma tarjeta. Una vez por sesión.

### 7.3 Cuándo recomendar la vista 2D

**Hoy, nunca**: con la colonia grande, la 2D va a 14-17 fps en este PC, frente a
47-57 la 3D (§4.1). Cada edificio y cada carretera llevan dos `_process` (§5.3). Una
vez hecha la optimización 1 de §6, la 2D debería ser la más barata (sin sombras,
sin 3D, unos 2600 nodos frente a 5400) y entonces se recomienda:

- en móviles (`phone`) con ≤ 3 GB de RAM o con Compatibility;
- cuando la medida del paso 2 sigue por debajo de 30 fps **ya en Mínima**;
- como sugerencia, nunca impuesta: cambia el aspecto del juego, y es decisión del
  jugador (Ajustes → Vista del mapa).

### 7.4 Tope de FPS

Ajustes → Interfaz → "Fotogramas por segundo", con estas opciones: 30, 45, 60, 90,
120 y "Sin tope". Se aplica con `Engine.max_fps` y se guarda en `settings.cfg`
(`[interfaz] fps_cap`, hecho en la rama `perf/tope-fps`, 2026-10-14). El vsync sigue encendido salvo con "Sin tope" en PC.

| Perfil | Por defecto | Por qué |
|---|---|---|
| PC, Alta o Baja | 60 | Lo que espera quien juega en PC; por encima no aporta en un juego de gestión |
| PC, Mínima | 30 | Estable antes que alto; una integrada a 30 no se calienta ni baja frecuencias |
| Tablet | 30 (60 si la detección dio Alta) | Batería y calor; las tablets baratas bajan reloj con el calor y entonces tironean |
| Móvil | 30 | Igual, y su pantalla es pequeña: 30 fps estables se ven bien |

En Android el refresco de pantalla puede ser 90 o 120 Hz. Sin tope, el juego intenta
seguirlo y gasta batería sin que se note en la jugabilidad.

### 7.5 ¿Y el renderizador?

En el A/B (§4.2), **Mobile en Mínima va a 97 fps** y Forward+ en Mínima a 71, con
los mismos draw calls: el render en CPU de Mobile es más ligero (6,4 frente a 8,6 ms).
Con Mínima, Forward+ no aporta nada que Mobile no tenga (SSAO, SSIL y glow ya están
apagados). Así que en un PC flojo, **Mínima debería ir con el renderizador Mobile**.

El renderizador no se cambia en caliente: se lee al arrancar. Opciones, de menos a
más riesgo:

1. que el PC arranque siempre en Mobile (`renderer/rendering_method="mobile"`),
   y aceptar perder el SSAO de Alta, que es lo único que Forward+ añade aquí;
2. que Ajustes guarde la elección y el juego la aplique en el siguiente arranque con
   un `override.cfg` junto al ejecutable (`rendering/renderer/rendering_method`). Hay
   que comprobar que esa carpeta se puede escribir (en `Program Files` no se puede);
3. dejar Forward+ en PC y aceptar la diferencia.

**Decisión del dueño (2026-10-14): la opción 2, pero con el override en el user
dir.** Elegir Mínima en PC avisa "se aplica al reiniciar" y el siguiente arranque va
en Mobile. El archivo no va junto al ejecutable (en `Program Files` no se puede
escribir) sino en `user://renderer_override.cfg`, y el motor lo lee porque
`project.godot` lo nombra en `application/config/project_settings_override`. Los
argumentos `--rendering-method` se descartaron: solo valen si alguien relanza el
juego con ellos, y el `.exe` se abre con doble clic. Detalle en §7.6.

### 7.6 Hecho (2026-10-14, rama `perf/calidad-minima`)

- **Mínima en Ajustes**: `"minimal"` en `GameConfig.GRAPHICS_QUALITY_MODES` y cuarta
  opción de la fila de calidad (Ajustes → Interfaz), con una línea de ayuda y el
  botón **DETECTAR DE NUEVO**. Una sola puerta para cambiarla:
  `GraphicsQuality.set_quality()` (`scripts/services/GraphicsQuality.gd`).
- **Lo que apaga**, todo de §7.1 salvo lo marcado abajo: `WorldLook` (sombras, SSAO,
  glow, isla sencilla, **sin MSAA**, `scaling_3d_scale` 0,7 en PC y **0,6 en
  móvil**); `GraphicsQuality.apply_runtime()` (lo llama `DeviceProfile`): humo,
  serrín, farol y chispas ocultos (grupo `building_fx_anim`, los nuevos nacen
  ocultos), banderines de obra quietos (uniform `wave` de `SiteFx`), rejilla
  "siempre visible" apagada, caminantes a `life_figure_cap_minimal` (12). La bandera
  de la colonia ya solo ondeaba en Alta. El tablero de combate 3D lee la calidad de
  `WorldLook.settings_for` (`BattleScreen`).
- **FPS**: el "Del perfil" de un PC en Mínima es 30 (`GameConfig.fps_minimal_pc`,
  `DeviceProfile.auto_fps()`).
- **Renderizador** (§7.5): Mínima en PC escribe `user://renderer_override.cfg`;
  cualquier otra calidad lo borra. No se pide Mobile si hoy va en Compatibility.
- **Detección del primer arranque** (§7.2) en `DeviceProfile`, con las reglas puras
  en `GraphicsQuality` y los umbrales y la lista de GPU en `GameConfig`
  (`quality_weak_gpu_patterns`, `quality_weak_ram_mb` 4600, `quality_weak_threads` 4,
  `quality_phone_ram_mb` 6600, `quality_detect_*`). La RAM se compara con 4600 MB y
  no con 4096: un equipo de 4 GB declara algo menos. La medida corre sin tope de FPS
  (la pausa del título lo bajaría a 30), solo en la vista 3D, y se salta en headless
  y con `-- --no-title` / `-- --no-detect`. El aviso sale al cerrar el menú de
  título. Se guardan `[interfaz] quality_detected` y `quality_detected_reason`.
- **`project.godot`** (§6, punto 7): `msaa_3d.mobile=0`, `scaling_3d/scale.mobile=0.75`,
  `rendering_device/fallback_to_opengl3=true` y `config/project_settings_override`.
  El tope de FPS ya estaba (`perf/tope-fps`).
- **Rejilla tras construir**: hecho después en `perf/render-3d` (commit `399eabc`):
  `BuildingPlacer.gd` y `BuildingPlacer2D.gd` restauran la rejilla con
  `GraphicsQuality.grid_always_visible()`, así que en Mínima no vuelve a pintarse.
- **Arreglo de la medida (2026-10-16, rama `fix/deteccion-calidad`)**: el .exe
  1.0.0 puso Mínima en una RTX 3060 Laptop con una "mediana 33.3 ms": medía un
  tope, no la GPU. La medida usaba el `delta` de `_process`, que con el vsync
  encendido (nadie lo quitaba) el suavizado de delta del motor redondea a periodos
  enteros del refresco. Ahora, mientras calienta y mide, `DeviceProfile` quita
  el tope **y el vsync** en cada fotograma (`apply_fps()` lo respeta), mide con
  `Time.get_ticks_usec()` y al acabar restaura los dos. Una medida con la mediana a
  ±1 ms de 1000/30, 1000/60, el refresco o su mitad, o con p10-p90 por debajo de
  0,3 ms, se descarta y la calidad se queda en "auto"
  (`GraphicsQuality.measure_rejection`, umbrales `quality_detect_known_caps`,
  `quality_detect_cap_tolerance_ms`, `quality_detect_flat_ms`). El registro lleva
  la medida bruta (fps medio, percentiles, refresco, tope y vsync vistos).
  **Reparación**: `[interfaz] quality_detect_version` (2 = esta regla); al
  arrancar, una detección de versión anterior decidida por la medida (motivo
  `medida ...`) que dejó Mínima, o Baja con la mediana en un tope, vuelve a
  "auto", borra `renderer_override.cfg` y se detecta de nuevo (en el siguiente
  arranque si venía en Mobile). Una calidad elegida en Ajustes guarda el motivo
  `manual: <calidad>` y no se toca nunca.
- **No hecho**: la "red de seguridad en partida" (opcional en §7.2); los topes de
  caminantes por perfil (16 / 12 / 8 en la tabla de §7.1: hoy uno solo, 12); la
  niebla solo con peso > 0 (`StormSky`). Sin medir todavía con la sonda la Mínima de
  verdad.

### 7.7 Mar y aire (1.1): coste a ojo por triángulos

Sin medir con la sonda (va en la ronda final de pruebas); contado al hornear y
con `UnitModels3D.tri_count`:

| Qué | Triángulos | Llamadas de dibujo | Nota |
|---|---|---|---|
| Piezas de mar (jugador / Regencia) | 275-478 | 1-3 por pieza (sólido, brillo, bando) | Menos que la infantería (564). Espuma y estela dentro de la malla |
| Piezas de aire | 356-486 | 1-3 por pieza + la sombra | La sombra es un `CylinderMesh` de 12 o 4 lados compartido (dos mallas, un material) |
| Tablero 8x8 con dos columnas de agua y una de orilla | 3.270 (alta) / 1.786 (sencilla) | 1 (el terreno) | Sin agua: 3.236 / 1.754. +1 % |
| Frente con el mismo terreno | 3.182 (alta) / 1.384 (sencilla) | 1 | Sin agua: 3.526 / 1.428 (el agua quita matas y craters) |
| Astillero / Aerodromo (mapa) | 1.328 / 1.315 | 1-2 | Como un edificio útil de la 1.1 |

- **Sin `_process`, sin luces, sin partículas.** El vaivén es el tween en bucle que
  ya tenían las piezas que no son de tierra; en calidad baja y mínima no hay
  vaivén. Despegar, deslizarse, hundirse y caer son tweens de un solo uso.
- **Materiales**: ninguno nuevo en las piezas (los dos de la maqueta y el del bando,
  uno por color); uno para todas las sombras de los aviones (el que ya existía).
- **Mínima**: igual que la tierra (tablero, sin sombras del sol, 0,7 de
  resolución); el agua es la misma malla del terreno, sin shader propio.

---

## 8. Límites de esta medida

- **Una sola máquina, y fuerte.** No hay datos de una integrada ni de un Android real.
  Mobile y Compatibility en esta RTX **aproximan** la carga de CPU de esos caminos,
  pero no el fill-rate ni el ancho de banda de una GPU de móvil. Lo siguiente es
  correr la sonda en el APK de QA (`--rendering-method gl_compatibility`) en el
  emulador y, sobre todo, en una tablet barata real. La sonda vive en `tools/`, que el
  export excluye: para un dispositivo hará falta un preset de QA que la incluya, o una
  versión mínima dentro del juego en `dev_mode`.
- **Ruido de la máquina compartida** (§4): la carga ajena fue del 40 al 100 % de CPU.
  Las tablas comparan bien dentro de una tanda y el A/B intercalado compara calidades.
  Con la máquina en reposo, todo saldrá algo mejor.
- **Binario del editor**, no un export release. La memoria del proceso y parte de la
  CPU incluyen lo del editor (y Beckett, `mcp_runtime.gd`, ~0,02-0,07 ms).
- **Mínima está emulada**: la sonda apaga cosas desde fuera. La `minimal` de verdad
  del agente de mundo (con la isla sencilla) será algo más barata todavía.
- **El perfil por script no ve las señales ni los timers.** Lo que cuestan
  `resource_changed`, `production_tick` o el auto-road sale de la auditoría (§5), no
  de una medida. Una sonda de tirones (colocar una ruta de 15 casillas en la colonia
  grande y medir el fotograma más largo) sería el siguiente paso.
- **Escenarios sintéticos**: la ciudad es una cuadrícula perfecta y sin obras en
  marcha, sin edificios dañados ni paneles abiertos (las ayudas y el tutorial se
  ocultan). Las obras, la ceniza sobre edificios dañados y la lista de construcción
  abierta cuestan más (§5.2, §5.5).
