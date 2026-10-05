# Buildings System

## BuildingData Resource

Each building is defined as a `.tres` file in `data/buildings/` using the `BuildingData` class (`scripts/buildings/BuildingData.gd`).

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | String | Unique identifier (matches filename) |
| `display_name` | String | Fallback name; the UI shows `get_display_name()` (the `BLD_<ID>_NAME` translation) |
| `description` | String | Fallback text; the UI shows `get_description()` (`BLD_<ID>_DESC`) |
| `grid_size` | Vector2i | Cells occupied: 2x2 for everything except the Núcleo (3x3) and the road (1x1) |
| `cost_gold/steel/oil/wood` | int | Construction cost |
| `cost_materials` | Dictionary | Workshop materials it also asks for (`planks`, `ingots`, `beams`, `fuel`) |
| `build_time` | float | Seconds to construct (0 = instant) |
| `produces_gold/steel/oil/wood` | int | Passive production per cycle |
| `production_interval` | float | Seconds between production cycles |
| `workers_required` | int | Workers needed to operate |
| `population_capacity` | int | Housing capacity (houses only) |
| `morale_bonus` | int | Passive morale bonus (decorations) |
| `mesh_height` | float | Visual height for procedural mesh |
| `mesh_color` | Color | Visual color |
| `model_scene` | PackedScene | GLB model (12 of 16 buildings; `nucleo`, `road`, `market` and `laboratory` fall back to `DieselpunkBuildingFactory`) |
| `model_scale` / `model_stretch` | float / Vector3 | Scale a GLB made for 1x1 or 2x1 up to its 2x2 plot; spawn models only through `instantiate_model()` |
| `repeat_placement` | bool | Keep the same building in hand after placing it (decorations and roads do anyway; the rest place one and leave placement mode) |
| `max_health` | int | HP for storm and siege damage (`BuildingHealth`) |
| `is_core` | bool | Cannot be built/moved/demolished |
| `is_decoration` | bool | No production, no workers, morale only |

## Complete Building List

### Production Buildings

| ID | Name | Size | Cost G/S/O/W | Workers | Build Time | Produces | Interval |
|----|------|------|--------------|---------|------------|----------|----------|
| `nucleo` | Núcleo | 3x3 | Free | 0 | instant | — (manual processes, +5 worker room) | — |
| `sawmill` | Aserradero | 2x2 | 80/0/0/50 | 2 | 5s | 6 wood (+ planks by hand) | 12s |
| `gold_mine` | Mina de Oro | 2x2 | 120/0/0/80 | 3 | 8s | 8 gold (+ ingots by hand) | 12s |
| `foundry` | Fundición | 2x2 | 200/0/0/120 | 3 | 12s | 5 steel (+ beams by hand) | 15s |
| `refinery` | Refinería | 2x2 | 300/150/0/100 + 6 beams | 4 | 18s | 4 oil (+ fuel by hand) | 18s |
| `headquarters` | Cuartel General | 2x2 | 500/300/200/200 + 20 beams, 10 ingots, 10 fuel | 5 | 30s | 10 gold | 20s |

Materials (planks, ingots, beams, fuel) are made with the first manual process of
each extractor and live outside the shared pool: see
[02-economy.md](02-economy.md) "4 Workshop Materials".

### Support Buildings

| ID | Name | Size | Cost G/S/O/W | Workers | Build Time | Special |
|----|------|------|--------------|---------|------------|---------|
| `house` | Vivienda | 2x2 | 50/0/0/30 | 0 | 3s | Room for 6 workers (9 / 12 at levels 2 / 3) |
| `warehouse` | Almacén | 2x2 | 60/0/0/40 | 1 | 4s | +500 shared storage cap (+250 per level above 1) |
| `market` | Mercado | 2x2 | 100/0/0/60 | 1 | 6s | Opens the market: ABRIR MERCADO in its panel |
| `laboratory` | Laboratorio | 2x2 | 150/0/0/100 | 2 | 8s | Opens the tech tree: INVESTIGAR in its panel |

**Market and Laboratory (2026-09-28).** Trading and research used to be entries of
☰ MENÚ → COLONIA; now each opens by tapping its building
(`BuildingInfoPanel.SCREENS`), and the button is disabled while the building has no
road. One of each (`building_limits`). ¿QUÉ HACER? asks for the Laboratory before any
research and does not suggest buying or selling without a Market. Both are
procedural (`DieselpunkBuildingFactory`, `BuildingArt2D`): no GLB yet.

### Military Buildings

| ID | Name | Size | Cost G/S/O/W | Workers | Build Time | Prereqs |
|----|------|------|--------------|---------|------------|---------|
| `barracks` | Cuartel | 2x2 | 250/100/0/80 + 10 planks | 3 | 15s | foundry + sawmill |
| `tower` | Torre | 2x2 | 150/60/20/30 + 4 beams | 1 | 8s | barracks |

The Barracks trains units (`ArmyManager`, one training slot per Barracks). Each
operational Tower cuts storm damage by 15% (cap 60%) and puts one artillery crew on
the defensive boards — the Tithe and each Final Audit wave — outside the deploy cap
(max 2). See [15-combat.md](15-combat.md).

### Decorations (morale only)

| ID | Name | Size | Cost G/S/O/W | Build Time | Morale |
|----|------|------|--------------|------------|--------|
| `road` | Carretera | 1x1 | 1/0/0/0 | instant | +2 |
| `garden` | Jardín | 2x2 | 30/0/0/20 | 2s | +5 |
| `fountain` | Fuente | 2x2 | 60/20/0/10 | 4s | +7 |
| `statue` | Estatua | 2x2 | 120/40/0/0 + 3 ingots | 6s | +10 |

The road is still a decoration in data, but it is the backbone of the map: see "Road
network" below.

## Road network (2026-09-28)

- **Everything touches a road joined to the Núcleo.** `PlacementRules.is_connected_spot()`
  is part of `evaluate_placement()` (reason `"road"`, message `LBL_NEEDS_ROAD`). A new
  road must touch the network or the Núcleo. With no Núcleo on the grid (hand-built
  test scenes) the rule is off.
- **Removing a road: move the buildings first (2026-10-04).** Demolishing a road
  tile, or moving it, is refused when it would leave a building without a link to the
  Núcleo. `PlacementRules.road_removal_stranded(road, new_cells = [])` returns those
  buildings: anything on the grid except the Núcleo, decorations and other roads,
  **under construction included**; a building that was already loose before (old
  saves) does not count, and `new_cells` is where a moved road goes (it still counts
  as road). `Rules.demolish()` answers `{"blocked", "stranded"}`; both placers show
  the toast `LBL_MOVE_FIRST` ("Primero mueve: Aserradero, Mina de oro", at most
  `GameConfig.road_block_max_names` names, then "+N") and `flash_buildings()` paints
  those buildings red for `GameConfig.road_block_highlight_seconds` (3D: a pulsing
  red quad per cell drawn through the mesh; 2D: a red frame above the building).
  Tapping one selects it as usual: its panel opens with MOVER. There is no batch or
  drag demolish. Tests: `tests/map/test_road_removal.gd`.
- **Access road around a deposit (2026-10-04).** The first extractor planted next to
  a deposit (sawmill-forest, gold mine-gold vein, foundry-iron) lays a free ring of
  road around it (`PlacementRules.pave_access_ring()`, called by both placers before
  `building_placed`; toast `LBL_ACCESS_RING_LAID`). The ring runs at
  `extractor size + 1` cells from the deposit (3 with today's 2x2 extractors), so the
  2-cell band touching the deposit stays **entirely free**: any extractor there
  touches the deposit (reach 1) and the ring. Occupied cells (buildings, other
  deposits) and cells off the grid are skipped, and only the pieces that end up
  joined to the Núcleo's network are laid (the extractor's own auto-road crosses
  the ring, so normally all of it); no extra route is paved. The deposit is marked
  (`access_ring` meta, saved in its `deposits` entry, idempotent: a new map has new
  deposits) and an old save with an extractor already touching it gets no ring.
  The refinery eats its oil well, so wells get no ring. Moving an extractor never
  lays one. The ring is ordinary road: removable under the "move first" rule.
  Tests: `tests/map/test_access_ring.gd`.
- **The Núcleo starts with its sidewalk:** `GameManager.pave_core_ring()` lays the 16
  road cells around it in `_new_game()`.
- **Auto-road:** placing (or moving) a building where the network does not reach is
  accepted when a free route exists; the route comes back as `"route"`, is charged with
  the building (`cost_with_route`, 1 gold per tile) and laid with `pave_route()`. No
  route → `LBL_NEEDS_ROAD`. Roads are instant (`build_time = 0`).
- **No road, no work:** `PopulationManager._recalculate_all()` sets the meta `connected`
  on every building; an unconnected one gets no workers, a house gives no room,
  ProductionManager skips it and its badge says "sin carretera".
- Roads and the Núcleo take no damage (`BuildingHealth.is_immune()`): the Storm and the
  Tithe do not spend themselves on the sidewalk. Roads are drawn as full-cell pavement
  with a curb on the unconnected sides, in 3D and 2D.
- **Workers you can see:** `scripts/map/WorkerWalkers.gd` sends workers from their
  houses to the staffed buildings along the road network, through each building's
  door (the road cell its footprint touches). Citizens walk too. View only; detail in
  docs/04, "Life in the streets".

## Workers per building

The player can take a building's workers off and put them back (RETIRAR / PONER
TRABAJADORES in its panel, `PopulationManager.set_workers_off()`, saved per building
as `workers_off`): they become free for other buildings and this one stops. A
Sawmill, Gold Mine or Foundry whose deposit was mined out by hand stops too ("sin
veta"). See [04-population-morale.md](04-population-morale.md).

## Status badge reasons

`BuildingStatusBadge.reason_text()` (3D) and `StatusBadge2D` (2D): "en obras", "en
ruinas", "sin trabajadores", "sin trabajadores (retirados)", "sin carretera", "sin
veta". While under construction the label above the building gives the percentage
and the time left ("En obras 61% · faltan 16 s") with a progress bar.

## Building Limits

Defined in `GameConfig.building_limits`:

| Building | Max |
|----------|-----|
| house | 10 |
| sawmill | 5 |
| gold_mine | 4 |
| foundry | 3 |
| refinery | 2 |
| warehouse | 5 |
| market | 1 |
| laboratory | 1 |
| barracks | 3 |
| tower | 6 |
| headquarters | 1 |
| statue | 5 |
| fountain | 5 |
| garden, road | unlimited |

## Deposit Rules

Defined in `GameConfig.building_deposit_rules` and checked by
`scripts/buildings/PlacementRules.gd` (same rule in 3D, 2D and touch placement):

| Building | Must touch | Reach | Consumes it |
|----------|-----------|-------|-------------|
| sawmill | forest | 1 | no |
| gold_mine | gold_vein | 1 | no |
| foundry | iron_deposit | 1 | no |
| refinery | oil_well | 0 (on top) | yes |

The three reach-1 extractors also need their deposit **alive**: if it is mined out by
hand, they stop ("sin veta", `PlacementRules.has_its_deposit()`).

## Prerequisites

Defined in `GameConfig.building_prerequisites`. The Foundry opens era 2 and the
Refinery era 3, so neither goes up without the base of the previous era standing
(2026-09-28):

| Building | Requires |
|----------|----------|
| foundry | sawmill + gold_mine + house + warehouse |
| market | gold_mine |
| laboratory | house |
| refinery | foundry + barracks |
| barracks | foundry + sawmill |
| tower | barracks |
| headquarters | barracks + refinery |

## Upgrade System

- Max level: 3
- Cost multiplier: L1=1.0x, L2=1.8x, L3=3.0x of base cost
- Production multiplier: L1=1.0x, L2=1.6x, L3=2.5x
- House room x1.5 / x2 (6 → 9 → 12, `upgrade_capacity_multiplier`); decoration morale
  x1.5 / x2 (`upgrade_morale_multiplier`); warehouse +250 storage per level above 1
  (`warehouse_level_bonus`)
- **Only what gains something offers an upgrade** (`PlacementRules.upgrade_does_something()`):
  producers, houses, the warehouse, decorations with morale and the HQ (its level 3
  summons the Final Audit). The Barracks, Tower, Road and Núcleo have no upgrade button.
- The panel lists what the next level gives, with real numbers
  (`PlacementRules.upgrade_effect_lines()`); in 3D the building grows and carries a
  II / III plate
- HQ has special override costs, materials included (see economy doc)

## Manual Processes

Buildings can run timed manual processes (one at a time per building). Defined in `GameConfig.building_processes`. Margins are ~1.5x to make the market meaningful.

## Construction Flow

1. Player selects building from ConstructionMenu. Every card shows its cost (red when
   it cannot be paid); a locked card can still be tapped and its detail says
   everything that is missing (resource to unlock, previous buildings, limit, workers,
   cost). The detail's CONSTRUIR button does not start while something is missing
   ("Te falta: 20 Madera")
2. `EventBus.building_selected_for_placement` emitted
3. BuildingPlacer (or `BuildingPlacer2D`) shows a green/red ghost on the grid; on touch, `PlacementAssist` highlights the valid spots, a tap aims and a tap on the ghost / ✓ builds
4. On confirm: `PlacementRules` checks the spot (deposit, footprint, road or auto-road), then `ResourceManager.spend_cost()` (building + route), `GridManager.place_building()`, and `pave_route()` for the road tiles
5. `EventBus.building_placed` emitted. Placement mode ends after one building; only
   decorations, roads and `repeat_placement` buildings stay in hand
   (`PlacementRules.keeps_placing()`)
6. ProductionManager starts construction timer (label + progress bar); the building shows its construction phase (see below)
7. Timer complete: `EventBus.construction_completed` emitted
8. Building starts producing, PopulationManager recalculates workers

## Aspecto en el mapa: obra, ruina y actividad

Cada edificio se ve en uno de cinco aspectos, en las dos vistas. La regla es
una sola, pura y estatica: `scripts/buildings/BuildingLook.gd` (`derive()`), de
los hechos del edificio (`under_construction`, mejora o no, progreso, ruina,
lo que dice su `StatusBadge`) al aspecto. Orden: la obra manda sobre la ruina,
la ruina sobre la actividad.

| Aspecto | Cuando | 3D | 2D |
|---|---|---|---|
| **Obra, fase 0** | progreso < 34 % | modelo oculto; tierra removida, valla (tablas, chapa o lona, segun el edificio) con puerta, cinta de peligro y banderin, las pilas de material del edificio, una con lona, y algo de desorden | lo mismo visto desde arriba |
| **Obra, fase 1** | 34-67 % | losa (de piedra en los de piedra), zapatas, ferralla o estacas, lo que ya asoma de la silueta (base de la chimenea, anillos, zapata de la torre...), conos, sobrante de una pila y banderin | lo mismo visto desde arriba |
| **Obra, fase 2** | ≥ 67 % | la estructura con la silueta del edificio (chimenea, tejado a dos aguas, torre, depositos, cupula...), andamio, banderin, chispas o polvo y, desde 2x2, grua que gira | lo mismo, con la pluma de la grua girando |
| **Mejora** | obra que es una mejora | el modelo a la vista con andamio alrededor | el dibujo con rayas, andamio en aspa y barra |
| **Ruina** | `BuildingHealth.is_ruined()` | el modelo se hunde un 38 % y se ladea, con el hollin de siempre, suelo quemado, cascotes, muro roto, vigas carbonizadas y humo negro animado | tizne, muro dentado, cascotes, vigas con ascuas, grietas y humo negro animado |
| **Trabajando** | el badge dice WORKING y el edificio tiene efecto | humo, serrin o luz que parpadea sobre la cima | humo/serrin desde las chimeneas del dibujo, luz en la puerta |
| **Quieto** | lo demas | el modelo, sin animacion | el dibujo, sin animacion |

- **Las tres fases son las mismas para todos** (valla -> cimientos ->
  estructura: se reconocen siempre) y la **clase de huella** (el lado mayor,
  1-3) decide el tamano, cuantas pilas, cuantos pilares y si hay grua (desde
  2x2). Umbrales en `GameConfig.construction_phase_thresholds`. Lo que cambia
  es como se visten; ver "Obra por edificio" abajo.
- **Que efecto lleva cada edificio**: `GameConfig.building_active_fx` (`smoke`,
  `dust`, `glow`). Casas y decoracion no llevan: no "trabajan".
- **La animacion** es una hoja de 8 fotogramas en rejilla 4x2 a 12 fps
  (`GameConfig.building_fx_*`), dibujada en codigo por `BuildingFx.gd` y animada
  por un shader con `TIME`: ni timers, ni tweens, ni AnimationPlayer por
  edificio. Un material por efecto para todo el mapa.
- **3D**: `BuildingLookVisual` (hijo `LookVisual` de cada edificio salvo las
  calzadas, lo pone `BuildingPlacer._create_building_mesh`). `BuildingPlacer`
  lo resincroniza al momento con las senales de obra, mejora, ruina y
  reparacion, y con **un solo reloj para todo el mapa**
  (`GameConfig.building_look_sync_interval`, 0,25 s) para el paso de fase y el
  encendido del humo. Todo lo que cuelga de el esta en el grupo `building_fx`:
  ni el hollin de `BuildingHealth` ni `BuildingStatusBadge.measure_top()` lo
  cuentan. Hundir la ruina toca la `position`/`rotation` del modelo (no su
  escala, que es la del nivel) y lo devuelve al repararlo.
- **2D**: `Building2D` mete el aspecto en su firma de repintado y crea los
  sprites del efecto la primera vez que hacen falta (docs/18).
- Sonda con capturas: `godot --path . -s tools/look_probe.gd -- --no-dev`
  (con `override.cfg` propio) deja `docs/media/dev/look_probe_3d.png` y
  `look_probe_2d.png` (todos los aspectos) y `look_probe_obras_3d.png`,
  `look_probe_obras_3d_b.png` (un instante despues: la grua se ha movido) y
  `look_probe_obras_2d.png`: una fila por fase con fundicion, aserradero,
  refineria, DOS casas, estatua y torre.
- Todo es original y generado por el proyecto (mallas procedurales, dibujo en
  codigo, hojas de sprite generadas): ningun asset externo.

### Obra por edificio y por instancia

Dos casas en obras una al lado de otra no se ven iguales, y la obra de una
fundicion no se parece a la de una casa. Dos capas, las dos decididas en
`BuildingLook` para que 3D y 2D coincidan:

**Estilo por tipo** (`BuildingLook.site_style(id)`): una fila por edificio en
`GameConfig.construction_style`, encima de `construction_style_default` (lo que
la fila no diga sale del defecto; la calzada usa el defecto).

| Campo | Que decide | Valores |
|---|---|---|
| `piles` | que se apila en la fase 0 (y lo que sobra en la 1) | planks, beams, bricks, logs, sawdust, rivets, pipes, drums, sacks, stone, crates, sandbags, gravel, soil |
| `fence` | la valla de la fase 0 | planks, dark_planks, sheet (chapa), canvas (lona del color `tarp`) |
| `tarp` | color de la lona (valla de lona, la que tapa una pila, la figura tapada de la estatua) | Color |
| `frame` | la silueta de la fase 2, que insinua el edificio (y lo que asoma ya en la fase 1) | box, chimney, gable, tower, tanks, dome, plinth, basin, hall, headframe, low, mast |
| `frame_mat` | de que son pilares y vigas (y estacas o ferralla en la fase 1, losa de piedra) | steel, wood, stone |
| `site_fx` | lo que se mueve mientras se trabaja | sparks (soldadura; fases 1 y 2), dust (polvo; todas), "" |
| `flag`, `crane` | color del banderin y de la grua | Color |

| Edificio | Pilas | Valla | Silueta | Material | Efecto |
|---|---|---|---|---|---|
| Nucleo | piedra, vigas, remaches | chapa | cupula | piedra | chispas |
| Casa | sacos, ladrillo, tablones | tablas | tejado a dos aguas | madera | polvo |
| Aserradero | troncos, serrin, tablones | tablas oscuras | nave | madera | polvo |
| Mina de oro | grava, vigas, cajas | tablas oscuras | castillete con rueda | madera | polvo |
| Almacen | cajas, tablones, sacos | tablas | nave | acero | — |
| Fundicion | vigas, remaches, ladrillo | chapa | chimenea alta | acero | chispas |
| Cuartel | sacos terreros, cajas, vigas | chapa | nave (grua oliva) | acero | chispas |
| Refineria | tuberias, bidones, vigas | chapa | depositos | acero | chispas |
| Torre | sacos terreros, vigas, remaches | lona oliva | torre de celosia | acero | chispas |
| Cuartel general | piedra, vigas, remaches | lona roja | mastil con bandera (grua roja) | acero | chispas |
| Mercado | cajas, sacos, tablones | lona naranja | tejado a dos aguas | madera | polvo |
| Laboratorio | bidones, tuberias, cajas | chapa | cupula | acero | chispas |
| Jardin | tierra, sacos, tablones | tablas | pergola y bancales | madera | polvo |
| Fuente | piedra, tuberias, grava | tablas | pilon con cabria | piedra | polvo |
| Estatua | piedra, piedra, sacos | lona | pedestal con la figura tapada | piedra | polvo |

**Disposicion por instancia** (`BuildingLook.site_layout(seed, style, n)`): la
semilla es `BuildingLook.site_seed(id, celda de origen)` (FNV-1a, sin `hash()`
ni azar global) y `seed_of(nodo, data)` la saca de `GridManager` — la misma
celda en 3D y en 2D, y la que viaja en la partida, asi que la obra es estable
entre frames, recargas, guardados y cambios de vista. Fuera de la rejilla
(sondas, pruebas) sale de la posicion. Decide: el lado de la puerta y a que
lado de ella va el banderin, la separacion de los postes (mas o menos postes),
el orden, sitio, giro y tamano de las pilas, cual lleva lona, el desorden (un
bidon, una caja, un cono), el lado del andamio, la esquina de la grua y su
giro de reposo, las esquinas de los conos y del sobrante, y donde salen las
chispas o el polvo. Mover un edificio en obras cambia su celda y con ella su
obra.

**Animacion** (`scripts/buildings/SiteFx.gd`, mismo principio que
`BuildingFx`): todo lo mueve un shader con `TIME`, sin timers, tweens,
AnimationPlayer ni `_process` por edificio. La grua gira a un lado y a otro
(pluma, contrapeso y cable con gancho son mallas con el origen en el eje, que
el shader gira; el gancho sube y baja porque solo se mueven los vertices por
debajo del eje), el banderin ondea, las chispas (`sparks`, nueva hoja de
`BuildingFx`, aditiva) y el polvo (`dust` con variante `site`) usan las hojas
de sprite. Cada instancia saca su desfase y su velocidad (0,7-1,3 veces la
base) de su posicion en el mundo, asi que dos gruas vecinas nunca van al
unisono. Velocidad y apertura base: `GameConfig.construction_crane_speed` /
`construction_crane_swing`. Materiales compartidos por color para todo el mapa
y sin uniforms por instancia (que el renderizador Compatibility del APK de QA
no tiene).

**Coste**: una obra son unas 25-45 mallas low-poly (medido: casa 41/31/34 por fase, fundicion
30/39/32, nucleo 3x3 46/41/45) con materiales cacheados, y solo mientras dura la obra; la
animacion son 3 mallas de grua + 1 banderin + 1 quad de efecto, en GPU. En
2D, la obra se dibuja una vez por cambio de firma (fase, progreso, semilla) y
lo que se mueve son 4-6 nodos con shader.

## Key Files

- `scripts/buildings/BuildingData.gd` — Resource class definition
- `data/buildings/*.tres` — 16 building data files
- `scripts/buildings/PlacementRules.gd` — placement, road network, auto-road, upgrade effects
- `scripts/map/WorkerWalkers.gd` — the walking workers
- `scripts/services/GameConfig.gd` — limits, prerequisites, processes
- `scripts/services/ProductionManager.gd` — construction + passive production
- `scripts/buildings/BuildingLook.gd` — rule: construction phase / upgrade / ruin / active / idle (both views)
- `scripts/buildings/BuildingLookVisual.gd` — applies it in 3D; `scripts/buildings/BuildingFx.gd` — animated sprite sheets + shaders
- `scripts/buildings/SiteFx.gd` — construction-site animation shaders (crane, hook, pennant) for both views; site style/layout in `BuildingLook.gd`
- `scenes/buildings/BuildingPlacer.tscn` — placement/move/demolish logic
