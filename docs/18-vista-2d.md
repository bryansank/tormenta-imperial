# 18 · La vista 2D

Una segunda forma de ver **la misma partida**: el mapa desde arriba, plano, con
el arte dibujado en codigo. Existe para que el juego sea mas facil de
desarrollar (no hace falta Blender ni GLB para probar un edificio nuevo) y para
que se lea bien en un movil.

Lo que cambia es solo el **mundo**: camara, isla, rejilla, yacimientos,
edificios, texto flotante y el cielo de la tormenta. Todo lo demas es lo mismo en
las dos vistas: los 25 autoloads de juego, todos los paneles de la interfaz, el tablero
de combate y `user://save_game.json`.

## Como se cambia de vista

| Donde | Que hace |
|---|---|
| **Ajustes → Vista del mapa → [3D] [2D]** | Guarda la preferencia, guarda la partida y abre la otra escena, que carga el mismo guardado. |
| `godot --path . -- --view=2d` (o `--view=3d`) | Manda sobre la preferencia **solo en esa sesion**, sin tocar `settings.cfg`. Para desarrollar. |
| `GameConfig.ui_view_mode` | La preferencia (`"3d"` o `"2d"`), persistida en `user://settings.cfg` → `[ui] view_mode`. Por defecto `"3d"`. |

La escena principal del proyecto sigue siendo `Main.tscn`. Su raiz lleva
`ViewRouter.gd`: al arrancar mira `ViewMode.requested()` y, si toca 2D, cambia a
`Main2D.tscn` **antes** de que empiece la partida (`GameManager.hold_start()`
impide que el colocador 3D, que muere en ese mismo frame, cargue o empiece
nada). `Main2D.tscn` lleva el mismo router con `view_mode = "2d"`, asi que el
enrutado funciona en los dos sentidos.

**Hacer la 2D la vista de serie es cambiar una linea**: el valor por defecto de
`ui_view_mode` en `GameConfig.gd`.

## Arquitectura

```
Main2D (Node2D, ViewRouter view_mode="2d")
  Camera2D          Camera2DController   — mismas senales de camara, mismo estado guardado
  StormTint         StormTint2D          — CanvasModulate + ceniza (capa 1)
  Island            Island2D             — agua, espuma, arena, hierba (z -20)
  GridOverlay       GridOverlay2D        — la rejilla (z -10)
  BuildingPlacer    BuildingPlacer2D     — colocar/mover/demoler/seleccionar
  OnScreenControls, ResourceHUD          — los mismos .tscn que Main
  MapGenerator      MapGenerator2D       — hereda MapGenerator
  ConstructionMenu ... TutorialPanel     — los mismos .tscn que Main, en el mismo orden
```

Los nombres `BuildingPlacer`, `MapGenerator` y `GridOverlay` son los de `Main`
a proposito: `ArmyManager`, las reglas de yacimiento y el colocador los buscan
por nombre.

### Coordenadas (`scripts/view2d/View2D.gd`)

El mundo es el de siempre: la rejilla de GridManager en unidades de mundo sobre
el plano XZ. La 2D lo pinta con `PX_PER_UNIT = 16` (32 px por celda): X del
mundo → X de pantalla, Z → Y. "Arriba" en 2D es "hacia -Z", que es hacia donde
mira la camara 3D con giro cero. Todas las cuentas (mundo ↔ pixel ↔ pantalla ↔
celda, y el arrastre) son estaticas y puras. `px_to_cell` **no recorta**: un clic
en el agua es una celda invalida, no la del borde.

### Lo que se comparte

| Pieza | Donde vive | Quien la usa |
|---|---|---|
| Veredicto de colocacion, giro, topes, requisitos, bolsa, demoler, uniones de calzada, entrada de guardado | `scripts/buildings/PlacementRules.gd` | `BuildingPlacer` (3D) y `BuildingPlacer2D` |
| Sorteo, registro, usos, agotamiento, guardado y alcance de yacimientos | `MapGenerator.gd` | `MapGenerator2D` hereda y solo cambia los 5 ganchos de dibujo (`_make_container`, `_build_deposit_node`, `_place_deposit_node`, `_refresh_deposit_look` (la etapa de agotamiento, docs/02), `_show_depleted_text`) |
| Silueta de la isla | isla irregular: `IslandGenerator.coast_for_grid()` (de la mascara de `GridManager`, `IslandShape`); isla cuadrada vieja: funciones estaticas de `IslandGenerator.gd` | `Island2D` (los anillos de arena, espuma y agua con `Geometry2D.offset_polygon`) |
| Tierra y agua de la rejilla | `GridManager.is_land_cell()` | `GridOverlay2D` (solo los lados que tocan tierra), `Camera2DController` (limites = rectangulo de la tierra), el colocador (motivo `"water"`) |
| Regla del badge Zzz / obrero y su pictograma | `BuildingStatusBadge.derive()`, `worker_texture()` | `StatusBadge2D` |
| Pasos del cielo de tormenta | constantes de `StormSky.gd` | `StormTint2D.target_weight()` |
| Obreros y ciudadanos que andan: quien, a donde, puertas, rutas, Tormenta | `scripts/map/WorkerWalkers.gd` (+ `WalkerActor.gd`) | las dos vistas; dibujan `WalkerFigures3D` (MultiMesh) y `scripts/view2d/WalkerFigures2D.gd` (un solo `_draw`: las cuatro siluetas vistas desde arriba, encogen y se desvanecen en la puerta, saltito al andar) |
| Formato del guardado | `PlacementRules.serialize_building`, `MapGenerator.get_all_deposits`, `get_state()` de la camara | las dos vistas |

### Los ganchos en los servicios

Los servicios no saben que vista corre. Lo que hizo falta tocar:

- **Firmas**: toda senal de EventBus y todo metodo de servicio o panel que
  recibe un edificio o yacimiento lo tipa `Node` (antes `Node3D`).
- **Texto flotante**: `FloatingText.spawn_on(node, ...)` /
  `spawn_resource_on(node, ...)`. Un `Node3D` recibe el `Label3D` de siempre; un
  `Node2D`, `FloatingText2D`.
- **Obra**: `ProductionManager._apply_construction_visual` delega en
  `node.apply_construction_visual()` si existe (Building2D pinta su obra y pone
  su propio `ConstructionLabel`, cuyo texto sigue actualizando ProductionManager).
- **Camara**: `GameManager.register_camera(node)`; si nadie registra, se busca la
  Camera3D como antes. El estado guardado es el de MonumentalCamera
  (`target_x`, `target_y`, `yaw`, `distance`); la 2D traduce `distance` a zoom
  (`zoom = 36 / distance`) y conserva `yaw` sin usarlo.
- **Cambio de escena**: `GameManager.switch_to_scene(path)` guarda, suelta los
  servicios igual que una carga desde la nube (`clear_save_and_reload_from`, que
  ahora acepta la escena) y abre la otra. `hold_start()` / `release_start()`
  para el enrutado al arrancar.
- **Dedo**: `InputService` sin Camera3D calcula el arrastre con
  `View2D.screen_drag_to_world_delta` (misma unidad: mundo XZ).
- **Rotulos**: `BuildingInfoPanel` y `GameManager` aceptan un `Label` ademas del
  `Label3D` (nombre del yacimiento, renombrar el Nucleo).

### Como se pinta un edificio

`Building2D` es la entidad que ven los servicios, con los mismos metadatos
(`level`, `rotation_steps`, `health`, `staffed`, `under_construction`,
`custom_name`) y los mismos hijos con nombre (`NameLabel`, `StatusBadge`,
`ConstructionLabel`). **No escucha senales para pintarse**: cada
`CHECK_FRAMES` fotogramas (repartidos entre edificios; las calzadas, nunca) compara
una firma barata de su estado (obra y su progreso a saltos de 5%, nivel, vida,
ruina, calzadas vecinas, giro, nombre, y el aspecto de `BuildingLook`: fase de
obra, mejora, ruina, trabajando) y solo repinta si cambio. Asi una
partida cargada, una tormenta o una reparacion se ven sin que ningun servicio
sepa que existe.

**La parcela** (docs/03, "Parcela y atrezo"): debajo, el suelo de la parcela
con su borde oscuro y el remate de los lados sin calzada
(`BuildingArt2D.draw_lot_ground`) y la sombra de contacto bajo el edificio
(`draw_lot_shadow`); encima, el atrezo del patio y el elemento exagerado
(`draw_lot_props`: la grua del Almacen, la chimenea de la Fundicion, el
emblema sobre el Cuartel General...). Es el mismo plan que la 3D
(`LotPlan.plan`), con la misma semilla por celda. El plan se rehace solo si
cambia la celda, las calzadas vecinas (que se releen cuando llega
`building_placed` / `building_demolished` / `building_moved` /
`game_load_completed`, no cada frame), la obra o la ruina. El fantasma y el
icono no llevan parcela; el fantasma si deja libre el patio, para medir lo
mismo que el edificio.

El dibujo es `BuildingArt2D`: la huella menos el patio de su parcela (opcion
`inset` de `draw_building`; el icono del menu usa la huella entera) vista
desde arriba, con sombra, relieve y una silueta propia por edificio en la paleta
de `DieselpunkBuildingFactory` (hierro, laton, oxido, hormigon, fuego). Encima:
obra (rayas amarillo/negro, andamio, barra de progreso), dano (ceniza en
proporcion a lo perdido, como la capa 3D, y barra de vida), seleccion (borde de
laton que late) y la placa de nivel (`draw_level_plate`). El
mismo dibujo sirve al fantasma de colocacion y al menu de construccion
(`BuildingIcon2D`), asi que lo que se elige es lo que aparece en el suelo.

**Obra, ruina y actividad** (la regla compartida con 3D, docs/03 "Aspecto en
el mapa"):

- **Obra nueva**: en lugar del edificio se pinta su fase
  (`BuildingArt2D.draw_construction_phase(ci, size, phase, progress, n, id,
  seed)`): valla con pilas de material, luego losa con zapatas, luego la
  estructura con andamio. Debajo, la barra de progreso. Como en 3D, cada
  edificio la viste con su **estilo** (`BuildingLook.site_style`: pilas, valla
  de tablas/chapa/lona, color de la lona, silueta de la fase 2 —chimenea,
  tejado a dos aguas, torre, depositos, cupula, pedestal...— y lo que ya asoma
  en la 1) y cada instancia con su **semilla** (`BuildingLook.seed_of`, de la
  celda de origen: la misma que en 3D, estable tras guardar y cargar): lado de
  la puerta, postes, sitio de las pilas y la lona, desorden, lado del
  andamio, esquina de la grua. La semilla entra en la firma de repintado.
  Lo que se mueve no se repinta: `Building2D` cuelga un `SiteFx` (girado con
  el edificio) con la pluma y el contrapeso (`Line2D`/`Polygon2D`) y el carro
  de la grua, que un shader `canvas_item` gira y desliza por la pluma; el
  banderin (`Polygon2D` que ondea) y las chispas o el polvo (`Sprite2D` de
  `BuildingFx`), en los puntos de `BuildingArt2D.site_anchors()`. Se rehace
  solo al cambiar de fase, semilla o giro, y se va al acabar la obra
  (docs/03, "Obra por edificio y por instancia"). La obra ocupa el
  rectangulo del edificio (la huella menos el patio, tambien para los puntos
  de `site_anchors`): el patio de alrededor es la parcela a medio preparar
  (tierra, jalones, palet de losas, el remate puesto lado a lado), con la
  misma semilla.
- **Mejora**: el edificio a la vista con rayas amarillo/negro, andamio en aspa
  y barra (`draw_construction`).
- **Ruina**: encima del dibujo, `draw_ruin` (tizne, muro dentado, cascotes,
  vigas carbonizadas con ascuas, grietas) y un sprite de humo negro animado
  (`RuinFx`). Al reparar se apaga. El dano y la ruina van sobre el edificio;
  la parcela tiene los suyos (suelo quemado, atrezo volcado y carbonizado).
- **Trabajando**: sprites de humo, serrin o luz (`ActiveFx`) en las chimeneas
  del propio dibujo (`BuildingArt2D.fx_anchors`, fracciones del rectangulo del
  edificio; el serrin del Aserradero sale de la sierra), girados con el edificio. Los
  anima un shader `canvas_item` con `TIME` sobre la hoja de `BuildingFx`
  (`Sprite2D` recortado al fotograma 0): el edificio no repinta por la
  animacion.

Rotulos y badges se contraescalan con el zoom para leerse igual a cualquier
distancia (algo mas pequenos al alejarse). En una pantalla estrecha la camara
se acerca sola (`Camera2DController.screen_boost()`) para que una celda siga
siendo tocable.

### Maqueta de juguete en 2D (2026-10-12)

La 2D sigue la misma direccion de arte que la 3D (guia de estilo de edificios):
**los diez colores de `ToyPalette`** (`scripts/buildings/ToyPalette.gd`, solo
lectura para la 2D: `BuildingArt2D` toma sus casillas como constantes),
volumenes gruesos, la funcion a la vista y un elemento exagerado por edificio
(la sierra del Aserradero, la rueda del castillete de la Mina, la chimenea alta
de la Fundicion, la columna de la Refineria, la cupula azul del Laboratorio, el
canon de la Torre, la bandera del Cuartel, los toldos del Mercado, el silo de la
Granja, el torreon con el emblema del Cuartel General, la cupula de laton del
Nucleo...).

**El Nucleo monumental y la bandera del pais (2026-10-14).** Como la receta 3D
(`tools/toy_recipes/nucleo.gd`), el Nucleo domina la colonia sin salirse de
sus 3x3 casillas: peana de losas, escalinata circular, las dos calderas detras
con chimeneas altas (de la izquierda sale el humo, `fx_anchors`), un tambor
alto con su anillo de columnas y dos pisos de ventanas, la cupula de laton
escalonada con nervios, la linterna encendida y, delante, puerta, manometro y
faroles. Lo alto sube hacia arriba en pantalla; el tambor se adelanta un poco
para que la cupula quepa en la huella. La bandera del pais (`ColonyFlag2D`)
cuelga de un mastil que sale de la linterna, y en el Cuartel General del mastil
de la esquina delantera derecha del tejado (su peana va en el dibujo):
`BuildingArt2D.flag_mount(id, size, inset, rot, level)` da la base con las
mismas medidas que el dibujo y `Building2D` se la pasa a la bandera solo
cuando cambia la firma (giro, nivel). El palo lo pinta la bandera, no el
horneado: es lo mas alto y se saldria del margen de `ArtCache2D`. Acento por funcion: rojo industrial, amarillo/negro militar, laton
civico, verde residencial (tambien en el atrezo: `BuildingArt2D.lot_accent`).

La vista es "de maqueta": desde arriba, pero cada volumen ensena su tejado y,
**hacia abajo en pantalla**, su pared (`_block`, `_cyl`); mastiles y chimeneas
suben hacia arriba en pantalla. Como el edificio se dibuja girado,
`draw_building` recibe `"rot"` y traduce "abajo en pantalla" a su marco local:
la pared y la sombra caen siempre al sur de la pantalla y la luz viene siempre
de arriba a la izquierda. Contorno fino calido (`OUTLINE`) y sombra suave
(`SHADOW`) en todos.

La isla (cesped GREEN, arena crema, mar SKY, el canto WOOD de la placa), las
calzadas (adoquin de piedra calida, bordillo crema, raya de laton), la obra, la
ruina, el atrezo y los caminantes (`WalkerFigures2D`: munecos con cabeza, cuerpo
y sombrero, colores llevados a la casilla de paleta mas cercana) usan la misma
paleta. La Tormenta tine hacia una ceniza **calida** (sepia-oxido,
`StormTint2D.ASH_TINT`), pasando por un tono calido en el Aviso (`WARN_TINT`).

### Rendimiento: la 2D tiene que ir "en una papa"

La 2D es la vista de los equipos flojos. Medido con la sonda
(`tools/view2d_probe.gd -- --view=2d --no-title --perf`: 482 piezas, unas 320
calzadas y 160 edificios, vistas enteras, sin vsync):

| | Antes | Despues |
|---|---|---|
| Fotograma | ~83 ms | ~7 ms |
| `_process` de edificios y sus badges | ~42 ms | ~2 ms |
| CPU de render del mapa | ~21 ms | ~2.5 ms |
| Primitivas | ~600 000 | ~13 000 |

Donde estaba el coste y que se cambio:

- **Cada edificio eran cien o doscientas ordenes de dibujo** (discos,
  poligonos, lineas) que el renderizador recorre en cada fotograma, y
  `draw_circle()` gasta 64 lados por disco aunque mida dos pixeles. Ahora:
  - `ArtCache2D` **hornea** cada dibujo una vez en un SubViewport pequeno y lo
    guarda como textura con mipmaps. El cuerpo, compartido por clave (edificio,
    giro, nivel, calzadas vecinas: unos 20 en una partida normal, ~2 MB). La
    parcela entera de cada instancia en pie (suelo, cuerpo y atrezo), suelta y
    propiedad del edificio (~70 KB cada una a 1.5 px por px). Un edificio es
    un rectangulo con textura.
  - Lo que cambia a menudo no se hornea: obra, ruina, dano, seleccion y el
    cultivo de la Granja (va a mano encima).
  - Sin renderizador (pruebas headless) o mientras la textura no esta, se
    dibuja a mano como antes.
  - Los discos de lo que se dibuja a mano son poligonos de pocos lados (`_dot`).
- **`_process` en todos los nodos, todos los fotogramas.** Cada edificio
  recalculaba su firma (unos 40 us) en cada fotograma, y cada uno, calzadas
  incluidas, tenia un badge que releia el estado cada 0.25 s y se recolocaba
  cada fotograma. Ahora: las calzadas no tienen `_process` (ni su badge), se
  repintan cuando la rejilla cambia a su alrededor; los demas edificios miran su
  firma cada `Building2D.CHECK_FRAMES` (10) fotogramas, repartidos; los badges
  releen cada 0.5 s, repartidos, y solo se recolocan si cambia el zoom (leido una
  vez por fotograma para todos).
- **Isla**: el detalle menudo (matas, flores, olas) va en 6x6 trozos que Godot
  descarta si no se ven, se oculta al alejarse mucho, y son rectangulos y
  polilineas en vez de discos y arcos. La textura de hierba, a un texel cada 6 px.
- **Caminantes**: un disco blanco con contorno, generado una vez y tenido por
  pieza: 4 o 5 cuadrados por figura en un solo lote; tope `GameConfig.life_figure_cap`
  por perfil y, si hace falta, `WalkerFigures2D.max_fps`.
- **Ceniza**: menos particulas en tableta y movil (`StormTint2D.ASH_AMOUNT`).

## Que es jugable en 2D

Todo lo que es partida: construir (con giro, fantasma verde/rojo, regla de
yacimiento, construccion en serie), mover, demoler, mejorar, reparar, procesos
y minado desde el panel del edificio o del yacimiento, produccion con texto
flotante, obreros y badges, almacen, mercado, tecnologia, ejercito, tutorial,
tormenta (tinte y ceniza, dano y ruinas visibles, el Diezmo en el tablero),
escaramuzas, expediciones y la Auditoria Final (el tablero es el mismo
`BattleScreen`), guardar y cargar, nueva partida. Raton (clic, arrastre, rueda,
boton central, derecho para cancelar), teclado (WASD, R, Esc) y tacto (arrastre
de un dedo, pellizco; al construir, tocar lleva el fantasma, tocarlo o ✓ lo
planta y las casillas validas de un extractor salen en verde: PlacementAssist,
docs/21 §9).

## En que difiere de la 3D

- **Sin giro de camara.** Q/E, el boton derecho arrastrado y el giro con dos
  dedos no hacen nada (un giro de dos dedos tampoco da zoom); los botones de
  girar de OnScreenControls no aparecen. El `yaw` guardado se
  conserva para la 3D.
- **Las calzadas no giran**: sus uniones ya dicen hacia donde van.
- **La isla sale de la semilla** (`GridManager.island_seed`): la costa irregular
  es la misma en las dos vistas y al cargar. Solo una partida vieja de isla
  cuadrada sin semilla (`island_seed` = -1, escenas de test) sortea su ondulacion
  al abrir la escena.
- **La tormenta** tine el mapa con `CanvasModulate` (la interfaz no se tine),
  con suelos propios mas oscuros que la 3D, vineta y ceniza que cae desde la
  fase de Ceniza; de noche se encienden ventanas y farolas (ver "Noche,
  Tormenta, carteles y bancos"). No hay niebla por profundidad.
- **El nivel** (2026-10-17, como la 3D): el MISMO dibujo un 8 % mayor por nivel
  (`BuildingArt2D.level_scale` / `grown_rect`), con sombra mas larga, sobre un
  zocalo de piedra con fleje de laton (`_level_plinth`, dos escalones en el III)
  y con las piezas de `LevelTrim` vistas desde arriba (`_level_trim`): chimeneas
  de ladrillo con bandas de laton atras a la derecha (y otra a la izquierda en
  el III, con farol); en las decoraciones, farolas en las esquinas. Todo dentro
  del horneado, que ya va por nivel. La marca de nivel (`draw_level_plate`) son
  galones de laton sin caja (dos o tres), sin girar, en la esquina de
  abajo-izquierda de la huella. Ya no hay aro de laton con banderin rojo. Humo, sombra de la
  parcela, obra de mejora y dano siguen al dibujo crecido.
- **El nombre del edificio** aparece al seleccionarlo, debajo de la huella.

## Mar y aire (1.1, rama `feat/aire-mar-vista`)

- **Astillero y Aerodromo** se dibujan en `BuildingArt2D` (`_shipyard`,
  `_aerodrome`), en el marco local del edificio como todos: delante (+y local)
  la darsena del Astillero y la pista del Aerodromo, asi que giran con el
  edificio. El icono de CONSTRUIR es el mismo dibujo (`BuildingIcon2D`).
- **El tablero de combate 2D** pinta las casillas vacias de agua y de orilla con
  sus tokens (`UITheme.BOARD_WATER`, `BOARD_SHORE`, derivados de la paleta: siguen
  al daltonismo y al alto contraste); lo alcanzable manda sobre ellas.
- **Siluetas**: las seis unidades nuevas tienen su PNG blanco tenible en
  `assets/textures/ui/units/` (`tools/gen_unit_icons.gd`).
- Coste: ninguno nuevo en el mapa (dos dibujos horneados en la cache como los
  demas); en el tablero, el color de fondo de una casilla.
- **El giro es el de la 3D** (ronda de la 1.1): `rotation_steps` se guarda con el
  convenio de la vista 3D y `Building2D.view_steps()` lo dibuja cambiado de signo
  (el giro de un Node2D va en el sentido del reloj; el de la 3D, al reves visto
  desde arriba). Antes, un edificio girado 90° salia mirando al lado contrario en
  cada vista: la darsena del Astillero, hacia tierra. La huella solo depende de la
  paridad y no cambia; el boton de girar sigue dando cuartos de vuelta.
- **Un avion encima de una unidad** (ronda de la 1.1): la casilla pinta la de
  superficie (`get_unit_at`); el avion de encima sale como una silueta pequena
  arriba en el centro, con el tinte de su bando (`BattleScreen._paint_air_overhead`,
  `board_air_mark(cell)`). Antes desaparecia del tablero 2D. Elegir la capa con el
  dedo sigue pendiente (docs/15 §11).

## Noche, Tormenta, carteles y bancos (1.1, rama `feat/vista2d-y-prologo`)

La ronda de la 1.0 (`tormenta-imperial-contexto/25_RONDA_PRUEBAS_1.0.md`, mejora
11 y revision visual) vio tres cosas flojas en 2D. Lo que se hizo:

**La noche y la Tormenta se notan** (`StormTint2D`, `NightLights2D`):

- **Suelos propios de la 2D** (`StormTint2D.VIEW_FLOOR`, `view_target()`): con
  los pesos de la 3D (0.12 - 0.22 fuera del golpe) el mapa solo se calentaba.
  En 2D el Aviso pide al menos 0.3 (calido), la Ceniza 0.48 (empieza a apagar)
  y la Tormenta y el Diezmo 0.6 (ceniza de verdad, aun legible: luminancia
  ~0.7). El golpe sube a `max(punch_weight, 0.8)` para seguir notandose.
  `target_weight()` no cambia: es el de la 3D y sus pruebas.
- **Noche mas honda**: `NIGHT_TINT` (0.42, 0.5, 0.86), antes (0.56, 0.64, 0.92).
- **Luces de la colonia** (`scripts/view2d/NightLights2D.gd`): ventanas
  encendidas (1 a 3 por edificio en pie, en sitios fijos de su huella) y una
  farola cada `LAMP_EVERY` (4) calzadas, por hash de la celda. Van en su
  `CanvasLayer` "LightsLayer" (capa 1, `follow_viewport_enabled`): el
  `CanvasModulate` no la tine, asi que con el mapa azul las luces siguen
  calidas, en mezcla aditiva. Se encienden de noche y con la Tormenta apagando
  (`StormTint2D.lights_for(light, weight)`). Sin `_process`: StormTint2D le pasa
  la intensidad (`set_intensity`, solo `modulate`); de dia esta oculta (coste
  cero); la lista se rehace solo si cambia `GridManager.map_version()` o llega
  una ruina, reparacion, obra acabada o carga, y solo con las luces a la vista.
  Una textura de brillo compartida, tope `MAX_POINTS` (360).
- **Vineta** (en "AshLayer", ahora capa 2): un `TextureRect` con un degradado
  radial generado una vez; azul de noche, sepia con Tormenta
  (`vignette_for`). Solo cambia su `modulate`.
- **Ceniza que cae despacio** ("AshDrift") en la Ceniza y la Tormenta, ademas
  de la rafaga del golpe: 60 / 40 / 24 motas (PC / tableta / movil,
  `DRIFT_AMOUNT`). Su rectangulo solo se recoloca al encender o al cambiar la
  ventana.
- Con calidad Minima (`GraphicsQuality.fx_enabled()` falso) queda solo el tinte.

**Los carteles de estado ya no se pisan** (`StatusBadge2D`): el cartel "Zzz sin
trabajadores" salia hacia la izquierda desde la esquina y tapaba al vecino.
Ahora, en reposo, es una **ficha compacta**: "Zzz" en el color del motivo y un
pictograma (obrero tachado, calzada tachada, mineral tachado, llama, caja llena,
pausa; `draw_reason_glyph`), con la esquina de arriba a la derecha **dentro** de
la huella. Nunca pasa del 90 % del ancho de su huella (`chip_scale`: si al
alejarse no cabe, encoge), asi que dos vecinos parados no se tocan. **El texto
entero sale solo con el edificio seleccionado** (`Building2D.set_selected` →
`set_expanded`, sin mirar cada fotograma) y en su ficha, como siempre. En obras
no se pinta (lo dice el rotulo de la obra), igual que en 3D.

**Los bancos de peces estan en el agua** (`Island2D`, `BuildingArt2D`):

- La playa 2D (`SHORE_WIDTH` 4.5 unidades, mas de dos casillas) tapaba la
  primera franja de agua, que es donde viven los bancos. Como la 3D
  (`island_sand.gdshader`, `holes`), **la isla abre una cala**:
  `MapGenerator2D._push_sand_holes()` (la isla 2D se llama "Island") pasa los
  rectangulos de `sea_deposit_rects()` a `Island2D.set_sand_holes()`, que
  recorta la espuma y la arena (`Geometry2D.clip_polygons`) con un poligono que
  cubre el banco y sale hacia el mar (`cove_polygon`: el ovalo del banco unido
  al mismo ovalo llevado mar adentro; el lado del mar sale de las casillas de
  tierra que lo rodean, `_sea_dir`). La orilla se estrecha justo ahi, con una
  linea de espuma donde corta la arena. Se calcula al cambiar los bancos o la
  forma; `_draw` solo pinta lo guardado. Si un recorte no diera un solo
  poligono limpio, ese anillo se pinta entero (mejor charco que agujero).
- **El banco** (`_dep_fish_shoal`) ya no es un ovalo con borde: agua honda
  difusa sin contorno, ondas en corro, sombras de peces bajo el agua
  (`_fish_shadow`), tres lomos que asoman con su estela, el pez que salta y la
  boya.

Coste: ninguno por fotograma salvo dos asignaciones en StormTint2D (que ya
corria) y las motas de ceniza lenta mientras hay Ceniza o Tormenta.

## Huecos conocidos

- La escena 3D se instancia un frame antes de irse a la 2D cuando la preferencia
  es 2D (el enrutado vive en su raiz). No carga nada ni arranca partida, pero sus
  `_ready()` corren: el menu de construccion 3D empieza a renderizar miniaturas
  que se descartan. Cuando la 2D sea la de serie conviene hacer de `Main2D.tscn`
  la escena principal (o una escena de arranque minima).
- ~~`stretch/aspect = "keep_height"` ponia bandas negras en vertical.~~ Resuelto:
  `aspect = "expand"` y la escala por perfil de dispositivo
  (docs/21-interfaz-y-dispositivos.md). La camara 2D descuenta la escala de
  interfaz (`Camera2DController.ui_scale`).
- HelperPanel son rotulos anclados a la pantalla, no a cosas del mundo: valen
  igual en 2D. El que habla de girar la camara sobra en 2D.
- ~~El panel de Ajustes ya era alto~~ (ahora va en pestanas, docs/21); con la fila de vista (y el selector de idioma
  que llega en paralelo) hay que repasar que quepa a 720 de alto.
- `ResourceHUD` puede ensenar el tope de almacen viejo justo tras cargar (se
  refresca con el siguiente cambio de recursos). Pasa igual en 3D.
- Todo nodo de interfaz que se anada a `Main.tscn` hay que anadirlo tambien a
  `Main2D.tscn` (hoy las dos tienen los mismos 23, en el mismo orden);
  `tests/view2d/test_view_mode.gd` comprueba una lista de nombres en las dos y
  conviene ampliarla: `SandboxPanel` aun no esta en ella.

- **El combate desde la 2D** usa el tablero 2D de siempre
  (`BattleScreen.pick_board_style`: vista 2D del mapa -> "2d"), asi que la vista
  frontal y la maqueta 3D del tablero no se abren; el boton de cambiar de vista
  se esconde (`_refresh_view_button`) e `is_front_view()` es falso. No hay
  version 2D de la vista frontal (pendiente, si se quiere). Mientras el tablero
  2D esta abierto el mapa 2D sigue dibujandose debajo (horneado: barato); la 3D
  apaga su mundo (`disable_3d`), la 2D no tiene equivalente.
- **Tormenta y noche en las parcelas**: en 3D el suelo de la parcela necesito
  su shader con `storm_weight` / `night_weight`; en 2D no hace falta nada, el
  `CanvasModulate` de `StormTint2D` (Tormenta y DayClock) tine todo el mundo,
  parcelas incluidas.

## Herramientas y tests

- `tools/view2d_probe.gd`: siembra una partida con de todo y hace capturas en
  `docs/media/dev/` (ignorada por git). `-- --view=2d` para las capturas,
  `-- --view=2d --play` para jugar una partida nueva con eventos de raton de
  verdad (arrastrar, colocar un aserradero junto a un bosque, seleccionarlo),
  `--shot-size=400x720` para cambiar la ventana, `--no-title` para saltar el
  menu principal y `--perf` para medir un mapa grande (fotograma, `_process`,
  render y primitivas, con la cache y sin ella). Las capturas de arte
  (`2d_overview`, `2d_far`, `2d_close`, `2d_storm`, `2d_storm_warning`) van sin
  interfaz encima. Aparta el guardado del jugador y devuelve la preferencia de
  vista al terminar.
- `tests/view2d/`: colocar (huella, giro, ocupado, fuera de rejilla, regla de
  yacimiento, compra, mover, demoler), guardado cruzado 3D ↔ 2D por el camino
  real de GameManager, preferencia de vista y linea de comandos, pantalla →
  celda a varios zooms, la camara 2D y los pasos de la tormenta;
  `test_building2d_look.gd`: las fases (de los 16 edificios, con dos semillas),
  la ruina y los efectos se dibujan sin
  error y Building2D enciende/apaga lo que toca (incluida la grua y el
  banderin de la obra, con su semilla); `test_view2d_save_compat.gd` comprueba
  que una obra conserva su semilla al guardar en 3D, cargar en 2D y volver;
  `test_building2d_lot.gd`: los 16 edificios con su parcela en pie, en obra y
  en ruina. De la 1.1 (`feat/vista2d-y-prologo`): `test_view2d_mood.gd`
  (suelos de tinte, luces, vineta, ceniza lenta, capas), `test_status_badge_compact.gd`
  (la ficha nunca sale de su huella, se expande al seleccionar, pictogramas) y
  `test_fish_shoal_2d.gd` (la cala cubre el banco y llega al mar, la arena se
  abre y se cierra, el banco se dibuja).
- `tools/look_probe.gd`: captura de todos los aspectos en 3D y 2D, y de las
  obras (una fila por fase, varios edificios y dos casas)
  (docs/03, "Aspecto en el mapa"), y la fila "estilo": los 16 en su parcela,
  con luz normal y con el tinte de la Tormenta (docs/03, "Parcela y atrezo").
  `-- --only-2d` hace solo las 2D, mas `look_probe_close_2d.png` (los
  productivos de cerca) y `look_probe_icons_2d.png` (los iconos del menu a tres
  tamanos).
- `tools/life_probe.gd`: un pueblo sembrado con obreros y ciudadanos en la calle,
  en 3D y en 2D (`life_probe_2d.png`); `tests/map/test_city_life.gd` comprueba que
  las dos vistas dibujan tantas figuras como hay en la calle (docs/04, "Life in
  the streets").
