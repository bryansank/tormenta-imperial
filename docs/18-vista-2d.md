# 18 · La vista 2D

Una segunda forma de ver **la misma partida**: el mapa desde arriba, plano, con
el arte dibujado en codigo. Existe para que el juego sea mas facil de
desarrollar (no hace falta Blender ni GLB para probar un edificio nuevo) y para
que se lea bien en un movil.

Lo que cambia es solo el **mundo**: camara, isla, rejilla, yacimientos,
edificios, texto flotante y el cielo de la tormenta. Todo lo demas es lo mismo en
las dos vistas: los 24 autoloads, todos los paneles de la interfaz, el tablero
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
| Sorteo, registro, usos, agotamiento, guardado y alcance de yacimientos | `MapGenerator.gd` | `MapGenerator2D` hereda y solo cambia los 4 ganchos de dibujo (`_make_container`, `_build_deposit_node`, `_place_deposit_node`, `_show_depleted_text`) |
| Silueta de la isla | funciones estaticas de `IslandGenerator.gd` | `Island2D` |
| Regla del badge Zzz / obrero y su pictograma | `BuildingStatusBadge.derive()`, `worker_texture()` | `StatusBadge2D` |
| Pasos del cielo de tormenta | constantes de `StormSky.gd` | `StormTint2D.target_weight()` |
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
`ConstructionLabel`). **No escucha senales para pintarse**: cada frame compara
una firma barata de su estado (obra y su progreso a saltos de 5%, nivel, vida,
ruina, calzadas vecinas, giro, nombre) y solo repinta si cambio. Asi una
partida cargada, una tormenta o una reparacion se ven sin que ningun servicio
sepa que existe.

El dibujo es `BuildingArt2D`: la huella exacta (con un margen de 2 px) vista
desde arriba, con sombra, relieve y una silueta propia por edificio en la paleta
de `DieselpunkBuildingFactory` (hierro, laton, oxido, hormigon, fuego). Encima:
obra (rayas amarillo/negro, andamio, barra de progreso), dano (ceniza en
proporcion a lo perdido, como la capa 3D, y barra de vida), ruina (grietas,
escombro, humo), seleccion (borde de laton que late) y galones de nivel. El
mismo dibujo sirve al fantasma de colocacion y al menu de construccion
(`BuildingIcon2D`), asi que lo que se elige es lo que aparece en el suelo.

Rotulos y badges se contraescalan con el zoom para leerse igual a cualquier
distancia (algo mas pequenos al alejarse). En una pantalla estrecha la camara
se acerca sola (`Camera2DController.screen_boost()`) para que una celda siga
siendo tocable.

## Que es jugable en 2D

Todo lo que es partida: construir (con giro, fantasma verde/rojo, regla de
yacimiento, construccion en serie), mover, demoler, mejorar, reparar, procesos
y minado desde el panel del edificio o del yacimiento, produccion con texto
flotante, obreros y badges, almacen, mercado, tecnologia, ejercito, tutorial,
tormenta (tinte y ceniza, dano y ruinas visibles, el Diezmo en el tablero),
escaramuzas, expediciones y la Auditoria Final (el tablero es el mismo
`BattleScreen`), guardar y cargar, nueva partida. Raton (clic, arrastre, rueda,
boton central, derecho para cancelar), teclado (WASD, R, Esc) y tacto (arrastre
de un dedo, pellizco, toque para colocar al levantar el dedo).

## En que difiere de la 3D

- **Sin giro de camara.** Q/E y el boton derecho arrastrado no hacen nada; los
  botones de girar de OnScreenControls no aparecen. El `yaw` guardado se
  conserva para la 3D.
- **Las calzadas no giran**: sus uniones ya dicen hacia donde van.
- **La isla se sortea al abrir la escena** (la silueta no viaja en el guardado,
  igual que en 3D): cambiar de vista redibuja la costa con otra ondulacion. La
  rejilla y las celdas no cambian.
- **La tormenta** tine el mapa con `CanvasModulate` (la interfaz no se tine) y
  deja caer ceniza desde la fase de Ceniza; no hay niebla por profundidad.
- **El nivel** se ve como galones de laton, no como un modelo mas grande.
- **El nombre del edificio** aparece al seleccionarlo, debajo de la huella.

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
- Nodos que otro agente anada a `Main.tscn` (menu de titulo, pausa, informes)
  hay que anadirlos tambien a `Main2D.tscn`; `tests/view2d/test_view_mode.gd`
  comprueba que las dos escenas tienen la misma interfaz y conviene ampliar su
  lista.

## Herramientas y tests

- `tools/view2d_probe.gd`: siembra una partida con de todo y hace capturas en
  `docs/media/dev/` (ignorada por git). `-- --view=2d` para las capturas,
  `-- --view=2d --play` para jugar una partida nueva con eventos de raton de
  verdad (arrastrar, colocar un aserradero junto a un bosque, seleccionarlo),
  `--shot-size=400x720` para cambiar la ventana. Aparta el guardado del jugador
  y devuelve la preferencia de vista al terminar.
- `tests/view2d/`: colocar (huella, giro, ocupado, fuera de rejilla, regla de
  yacimiento, compra, mover, demoler), guardado cruzado 3D ↔ 2D por el camino
  real de GameManager, preferencia de vista y linea de comandos, pantalla →
  celda a varios zooms, la camara 2D y los pasos de la tormenta.
