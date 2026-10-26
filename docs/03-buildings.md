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
| `produces_gold/steel/oil/wood/food` | int | Passive production per cycle (the Farm's comes from its crop) |
| `production_interval` | float | Seconds between production cycles |
| `workers_required` | int | Workers needed to operate |
| `population_capacity` | int | Housing capacity (houses only) |
| `morale_bonus` | int | Passive morale bonus (decorations) |
| `mesh_height` | float | Visual height for procedural mesh |
| `mesh_color` | Color | Visual color |
| `model_scene` | PackedScene | The baked "maqueta" model, `assets/models/toy/<id>.tscn` (16 of 17; the road stays procedural, its mesh depends on its neighbours. The Farm's model carries its growing beds as a child mesh, see "The Farm"). See "Modelos: maqueta de juguete". `model_scale` / `model_stretch` stay at 1 (they were for the old GLBs) |
| `model_scale` / `model_stretch` | float / Vector3 | Scale a GLB made for 1x1 or 2x1 up to its 2x2 plot; spawn models only through `instantiate_model()` |
| `repeat_placement` | bool | Keep the same building in hand after placing it (decorations and roads do anyway; the rest place one and leave placement mode) |
| `max_health` | int | HP for storm and siege damage (`BuildingHealth`) |
| `is_core` | bool | Cannot be built/moved/demolished |
| `is_decoration` | bool | No production, no workers, morale only |

## Complete Building List

### Production Buildings

| ID | Name | Size | Cost G/S/O/W | Workers | Build Time | Produces | Interval |
|----|------|------|--------------|---------|------------|----------|----------|
| `nucleo` | Núcleo | 3x3 | Free | 0 | instant | — (manual processes, +10 worker room (5 before 2026-10-24)) | — |
| `sawmill` | Aserradero | 2x2 | 80/0/0/50 | 2 | 5s | 6 wood (+ planks by hand) | 12s |
| `farm` | Granja | 2x2 | 40/0/0/30 | 2 | 5s | food, by crop (below) | the crop's |
| `gold_mine` | Mina de Oro | 2x2 | 120/0/0/80 (**the first: 60/0/0/40**) | 3 | 8s | 8 gold (+ ingots by hand) | 12s |
| `foundry` | Fundición | 2x2 | 200/0/0/120 | 3 | 12s | 5 steel (+ beams by hand) | 15s |
| `refinery` | Refinería | 2x2 | 300/150/0/100 + 6 beams | 4 | 18s | 4 oil (+ fuel by hand) | 18s |
| `headquarters` | Cuartel General | 2x2 | 500/300/200/200 + 20 beams, 10 ingots, 10 fuel | 5 | 30s | 10 gold | 20s |

**The first Gold Mine at half price (2026-10-19, `feat/objetivo-paso-a-paso`).**
Bryan: "bájale el precio a la Mina de oro en el tutorial, la pones demasiado cara".
In the tutorial it comes after the early Barracks, with gold at its lowest.
`GameConfig.first_building_discount` (`{"gold_mine": 0.5}`) halves the cost of the
first one while none stands (`BuildingData.first_discount_factor()`); the next ones
pay the card price. `BuildingData.get_cost()` is the one build cost, so CONSTRUIR (and
its "1.ª a mitad de precio" badge, `LBL_FIRST_HALF_PRICE`), the ghost, the charge,
WHAT NOW? and the tutorial's `need_*` all show the same price. Upgrades and repairs
are priced on the card price (`get_base_cost()`). Tests:
`tests/economy/test_first_mine_discount.gd`.

Materials (planks, ingots, beams, fuel) are made with the first manual process of
each extractor and live outside the shared pool: see
[02-economy.md](02-economy.md) "4 Workshop Materials".

Everything a producer makes **waits in the building** until it is collected with one
tap (on the building or on its floating icon), up to a cap; full, it stops. See
[02-economy.md](02-economy.md) "Production that waits to be collected".

### The Farm (2026-10-04)

Era 1, 2x2, **anywhere with a road** (no deposit rule), cheap (40 gold + 30 wood), 2
workers, limit 6. The player picks a **crop by duration** in its panel (CULTIVO), and
the crop repeats by itself while it fits in the Farm (`GameConfig.farm_crops`):

| Crop | Duration | Food | Food per minute |
|---|---|---|---|
| Lechugas (`crop_short`, the default) | 1 min | 20 | 20 |
| Patatas (`crop_medium`) | 5 min | 125 | 25 |
| Trigo (`crop_long`) | 20 min | 600 | 30 |

Short gives little and soon; long gives more per minute but you wait for it. Changing
crop starts over (what was growing is lost); choosing the same one does nothing. A
Farm without workers, in ruins or without a road does not grow. Its yield takes the
level, tech and morale multipliers like any producer. It holds 800 food at level 1.

It is not a manual process (`ProcessManager`): a process is one-shot, delivers to the
bag, keeps the building "busy" and is lost to the Storm. A crop is the Farm's own
production cycle (`ProductionManager.get_cycle_seconds()` / `base_cycle_production()`),
so it accumulates and stops like every producer, survives the Storm and runs offline.

**Look.** 3D (2026-10-14): the baked toy model `assets/models/toy/farm.tscn`
(recipe `tools/toy_recipes/farm.gd`: lattice windpump, plank shed with green roof,
hay bales, trough, fence) and, as a child `MeshInstance3D` "Crops", **the beds as a
separate mesh** (`farm_crops_mesh.res`, built by `tools/toy_crops.gd`). That one mesh
holds the three crops (lettuce rosettes, potato bushes with a flower, wheat tufts with
an ear) and the windpump rotor, all drawn with ONE shared material
(`toy_crops.tres` / `toy_crops.gdshader`). `FarmCrops3D` reads the services every
0.25 s and only sets the **per-instance** shader parameters that changed: `growth`
(`get_cycle_progress`; 1 when the harvest waits and the farm stopped), `crop` (index in
`farm_crops`: the other two crops fold into their base), `ripe` (`has_stock`: full
height, ripe colour and a soft pulse of the albedo — no glow, so it does not shine at
night), `wind` (more in the ash and the Storm) and `rotor_angle` (every frame, only
while the farm works). Sprout pale green → leaf → ripe colour per crop (lettuce heart
light green, potato flowers cream and leaves olive, wheat gold). Lit like the rest of
the toy (night and Storm darken it with the scene light). Cost: two draw calls for the
building (solid + glow) plus one for the beds; ~980 + 2,200 triangles (only a third of
the crops is ever rasterised). Without the shader (the placement ghost overrides the
material) the beds show lettuces and the rotor, never the three crops on top of each
other. 2D:
`BuildingArt2D._farm()` — the same field with plants that grow and ripen
(`opts.growth`, `opts.ripe`).

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
road. One of each (`GameConfig.get_building_limit()`, in every era). ¿QUÉ HACER? asks for the Laboratory before any
research and does not suggest buying or selling without a Market. Both are
procedural (`DieselpunkBuildingFactory`, `BuildingArt2D`): no GLB yet. The
Laboratory has a glass dome and its lattice antenna in the yard; the Market,
big striped awnings with goods on the counters (see "Parcela y atrezo").

### Utility buildings of 1.1 (2026-10-14, `feat/edificios-utiles-1`)

Doc 21 §6.3 (fila 2.6 del plan). Content of 1.1: not merged before the 1.0 export.
All 2x2, all need a road like everything else. Their areas are computed by
`scripts/buildings/UtilityEffects.gd` when something is placed, finished,
demolished, ruined, repaired or moved, and on load — never per frame — and are left
as building metas (`mill_bonus`, `well_cover`, `tavern_houses`) or runtime values
(`GameConfig.storm_warning_bonus`, `food_spoil_delay_mult`, `ResourceManager`
side storage). Distances are free cells between footprints (Chebyshev). Nothing new
goes in the save: it all derives from the buildings.

| ID | Name | Cost G/S/O/W + mat. | Workers | Build | Caps (era 1/2/3) | Prereqs / rank | Effect (tunables in `GameConfig`, block "Edificios utiles de la 1.1") |
|----|------|------|---|---|---|---|---|
| `windmill` | Molino | 70/0/0/50 | 1 | 6s | 2/3/4 | farm · rank 3 | Farms within `windmill_radius` (4) produce +`windmill_farm_bonus` (20 %), not stacking (`ProductionManager.get_cycle_yield`) |
| `silo` | Silo | 60/0/0/40 | 0 | 5s | 2/4/5 | farm | +`silo_food_storage` (300) food outside the shared bag; in Gobernador farm stock spoils `silo_spoil_delay_mult` (×1.5) later |
| `tavern` | Taberna | 90/0/0/60 | 2 | 6s | 1/2/3 | house + farm | Each consumption tick, with a house within `tavern_radius` (4): spends 6 food + 4 gold; if paid, +2 morale and +1 person on the next growth tick (`PopulationManager._tick_taverns`) |
| `carpentry` | Carpintería | 70/0/0/60 | 2 | 5s | 1/2/2 | sawmill | Own processes: planks (20 wood → 5, 15 s) and furniture (15 wood + 2 planks → 30 gold, 35 s). The Núcleo does not repeat them (`core_skip_workshops`) |
| `well` | Pozo | 40/0/0/30 | 0 | 4s | 3/5/6 | house · rank 2 | Buildings within `well_radius` (3) take −`well_storm_reduction` (20 %) storm damage and recover `well_repair_ratio` (15 %) of their health when the storm ends, free (`StormManager`, `BuildingHealth.heal`; never lifts a ruin) |
| `lighthouse` | Faro | 180/0/0/120 + 6 planks | 1 | 8s | 1/1/1 | warehouse | The Warning lasts `lighthouse_warning_bonus` (20 s) longer (`GameConfig.get_storm_warning`). "Threats one calm earlier" waits for `feat/amenazas-mapa` |
| `fuel_depot` | Depósito de combustible | 200/80/0/80 + 4 beams | 1 | 8s | 2/2/3 | refinery | +`fuel_depot_oil_storage` (500) oil outside the shared bag (eases the full era-3 bag, docs/22 §7) |

Side storage: `ResourceManager.get_total_stored()` only counts what overflows each
side bag, and `add()` / `add_fitting()` use `get_free_space_for(type)`. The Tithe
still takes from the raw amount. Looks: one procedural mesh per type
(`UtilityToys.gd`, LotMesh + ToyPalette, cached) until `tools/build_toy_models.gd
-- --only=windmill,...` bakes `assets/models/toy/<id>.tscn`; then `UtilityToys.create`
picks the bake without touching the `.tres`. 2D: `BuildingArt2D._utility`.

### Muelle de pesca (1.1, `feat/muelle-pesca`)

Doc 21 §6.3 n.º 7 del contexto privado (allí era 2 y coste medio; Bryan lo pidió de
era 1 y barato). Comida desde el agua: el segundo productor de comida, sin cultivo que
elegir. Todas sus cifras viven en `GameConfig`, bloque "Muelle de pesca" al final del
archivo: `_register_fishing_dock()` añade sus filas a las tablas comunes al crear
`GameConfig` (topes, regla de yacimiento, taller, obra, parcela, efecto), para que el
bloque viva solo y no choque con otras ramas que tocan esas tablas.

| ID | Nombre | Coste G/S/O/W | Obreros | Obra | Topes (era 1/2/3) | Produce | Regla |
|----|--------|------|---|---|---|---|---|
| `fishing_dock` | Muelle de pesca | 60/0/0/40 | 2 | 6 s | 3/4/6 (`fishing_dock_limits_by_era`) | 12 comida + 3 oro cada 30 s (24 comida y 6 oro por minuto a moral 50, nivel 1) | En la costa, con un **banco de peces** mar adentro a alcance 4; 2 muelles por banco |

- **Dónde va (fix/peces-en-el-mar, 2026-10-19).** El banco vive mar adentro (docs/02),
  así que tocarlo ya no pone el muelle en la orilla. Su regla
  (`building_deposit_rules["fishing_dock"]`): `fish_shoal`, alcance
  `fishing_dock_reach` (4, Chebyshev desde la huella: hasta tres casillas de agua por
  medio), `"shore": true` (alguna celda de la huella toca el agua,
  `PlacementRules.touches_shore`; si no, motivo `"deposit"` con su propia frase
  `LBL_NEEDS_FISH_NEAR`), `"per_deposit"` = `fishing_dock_per_shoal` (2), no lo
  consume. **Dos muelles por banco:** `PlacementRules.deposit_with_room()` no guarda a
  qué banco va cada muelle: reparte los que hay entre los bancos que alcanzan
  (emparejamiento con capacidades, Kuhn; 6 muelles y 5 bancos como mucho) y el nuevo
  cabe si con él no se queda ningún muelle de antes sin banco; elige el banco más
  cercano que aún tiene sitio. Un muelle de una partida vieja que ya pasaba del tope no
  bloquea a los demás. No está en `PlacementRules.SHORE_ONLY` (las palmeras): la
  colocación táctil busca sitios alrededor de los bancos (`PlacementAssist.valid_spots`,
  con el alcance 4) y no por toda la costa; `MapGenerator.buildable_spots_near` y
  `_spots_for` también piden la costa para un banco de mar. Lleva carretera como todo,
  pero **sin anillo de acceso** (`wants_access_ring`: el anillo alrededor de un banco
  mar adentro caería casi todo en el agua y pavimentaría la costa de los otros muelles).
- **Embarcadero.** Una pasarela de tablas sobre pilotes desde la costa hasta su banco:
  `MapGenerator.pier_path(cells)` da las celdas de agua entre la huella y el banco más
  cercano (en línea, pasos de rey) y la pintan `scripts/buildings/DockPier3D.gd` (una
  tabla y dos pilotes por celda, mallas y material compartidos, sin sombra) y
  `scripts/view2d/DockPier2D.gd` (un `_draw`). Solo dibujo: no ocupa la rejilla. Se
  rehace al colocar, mover o cargar (diferido), nunca por fotograma.
- **Comida y oro en la misma fuente.** El `.tres` rinde `produces_food` 12 +
  `produces_gold` 3 cada 30 s: 0,1 oro/s frente a los 0,67 de una Mina de oro (8/12 s),
  una propina que no rompe la economía del oro. Los dos van al almacén del edificio
  (`fishing_dock_stock_cap` 150 entre los dos, 10 ciclos) y la ficha y CONSTRUIR los
  enseñan con sus iconos (recorren todos los `produces_*`).
- **Comparado con la Granja** (20 / 25 / 30 de comida por minuto según el cultivo):
  rinde algo menos que la Granja con cultivo largo, pero pesca sin parar, sin elegir ni
  esperar cultivo, y el Molino no le afecta. Lo limitan su tope y los bancos (3-5 por
  isla). Guarda `fishing_dock_stock_cap` (150, unos 6 minutos) antes de pararse. Mejora
  como los productores (×1,6 / ×2,5; el nivel 3 pide repuestos, `upgrade_parts_buildings`).
- **Ahumar pescado** (`building_processes["fishing_dock"]`, `PROC_SMOKE_FISH`): 15 de
  madera → 25 de comida en 45 s. Una salida para la madera que sobra y atasca la bolsa
  (en el Mercado, 45 de oro por 50): no es la vía rápida. Lo ahumado va derecho al
  almacén, donde nunca se estropea. El Núcleo no lo repite (`core_skip_workshops`: no
  toca el agua).
- **Gobernador (estropeado activo):** el pescado fresco que espera en el muelle se
  estropea en la mitad de tiempo (`fishing_dock_spoil_mult` 0,5 sobre
  `spoil_after_seconds`, `GameConfig.fishing_dock_spoil_after()`). El Silo lo alarga
  igual que a la Granja. Recogerlo a tiempo, o ahumar, es la respuesta.
- **Aspecto 3D:** maqueta horneada `assets/models/toy/fishing_dock.tscn` (receta
  `tools/toy_recipes/fishing_dock.gd`, ~1.330 triángulos): ahumadero de tablas con
  tejado rojo y chimenea de piedra (humo de "trabajando", `building_active_fx`), la
  pasarela de tablas sobre pilotes (lo exagerado), la barca `pir:boat-row-small`
  varada, tendedero con peces propios, cubo `sur:bucket` y barril `pir:barrel`. Parcela
  de tierra con valla y acento residencial; obra de tablas y troncos con lona azul.
- **2D:** `BuildingArt2D._fishing_dock()` (tarima, ahumadero, tendedero, barca,
  barriles); el humo sale de la chimenea (`fx_anchors`). El icono de CONSTRUIR es ese
  mismo dibujo.
- **Ayuda:** consejo `fishing_dock` (`HELP_T/B_FISHING_DOCK`, categoría economía) al
  terminar el primero, y en el índice de AYUDA desde el principio. La guía de edificios
  lo lista sola (lee todos los `.tres`). **¿QUÉ HACER?** solo lo propone como apoyo de
  comida: cuando falta comida y no cabe otra Granja (`Objectives._producer_step`,
  `OBJ_WHY_FISHING_DOCK`); la línea nunca lo pide.

**El banco de peces** (`fish_shoal`, `DEP_FISH_SHOAL`) es el primer yacimiento de mar:
ver [02-economy.md](02-economy.md) "Yacimientos de mar".

### Military Buildings

| ID | Name | Size | Cost G/S/O/W | Workers | Build Time | Prereqs |
|----|------|------|--------------|---------|------------|---------|
| `barracks` | Cuartel | 2x2 | 120/0/0/80 + 10 planks | 1 | 15s | sawmill |
| `tower` | Torre | 2x2 | 150/60/20/30 + 4 beams | 1 | 8s | barracks + foundry |
| `shipyard` | Astillero | 2x2 | 220/80/0/120 + 10 planks, 4 beams | 3 | 16s | foundry; **must touch the coast** |
| `aerodrome` | Aerodromo | 2x2 | 320/140/60/80 + 8 beams, 6 fuel | 4 | 20s | refinery |

**Cuartel temprano (2026-10-17, rama `feat/cuartel-temprano`, decisión de Bryan).**
The Barracks is an **era 1** building now: 120 gold + 80 wood + 10 planks, no steel,
one worker, and it only needs the Sawmill (its planks come from there). Before it
cost 150/60/0/80 + 20 planks, three workers, and needed the Foundry, so it arrived
around minute 10-14. Why early: after every Storm the Tax Collectors come down and
only troops at home fight them; the era-1 trial storm now brings a toy Tax
(`storm_trial_tithe_*`, docs/22 §12) so the Barracks matters by minute 5; and
missions (loot, spare parts, blueprints) only exist with soldiers. In era 1 it trains
**Infantry** only: Artillery waits for steel (era 2) and the Tank for oil (era 3)
(`ArmyManager.is_unlocked`, by `unit_types[*].era`), and the ARMY panel says so on the
greyed rows ("Necesita acero de la Fundición (era 2)", `LBL_ARMY_LOCKED_ERA_*`).
One worker (not three) so that sawmill (2) + Barracks (1) + Farm (2) fit in the 5 people
of the Núcleo without waiting for a House. **No building cap since 2026-10-18** (see
"Cuartel sin tope" below; before, 3/4/5 per era). The Tower now asks for the Foundry
explicitly: before, the Barracks implied it.

**Air and sea (2026-10-17, `feat/aire-mar-reglas`).** The Shipyard trains the
ships (torpedo boat, gunboat, dreadnought) and the Aerodrome the planes (fighter,
bomber, airship): each military building has one training slot per building, only
for its own units (`unit_types[...]["building"]`), and adds to the army capacity
(`army_capacity_per_building`: Barracks 8, Shipyard 4, Aerodrome 4). The Shipyard
is in `PlacementRules.SHORE_ONLY`, like the palm trees: one cell of its footprint
has to touch the water (`LBL_NEEDS_SHORE`). Limits 1/1/2 per era
(`building_limits_by_era`), `construction_style` and `building_lot_style` rows of
their own; no `model_scene` yet (procedural fallback until `feat/aire-mar-vista`
brings the models). The army panel and the skirmishes open with any of the three
(`ArmyManager.has_military_building()`). Rules and units: [15-combat.md](15-combat.md) §11.

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

#### Decoraciones baratas (feat/decoraciones-1, 2026-10-14)

Las diez primeras del catalogo del doc 21 §6.4 (fila 1.7 del plan): sumideros
baratos de oro y madera, **sin tope** (como toda decoracion, `GameConfig.is_uncapped_building()`; decision D1 = B) y
abiertas por rango segun §6.5. Todas 2x2 (en el doc eran 1x1: el mapa no tiene
huellas menores de 2x2 salvo la calzada), con su parcela de 0,25 casillas de patio
y una o dos piezas de atrezo.

| ID | Nombre | Coste G/S/O/W | Obra | Moral | Rango | Piezas del horneado |
|----|--------|---------------|------|-------|-------|---------------------|
| `lamp_post` | Farola | 20/0/0/5 | 1,5 s | +2 | libre | `kc:streetlight`, `ft:lantern` (luces a GLOW) |
| `park_bench` | Banco | 10/0/0/10 | 1 s | +1 | libre | `kc:bench` x2, `kc:bush` |
| `hedge` | Seto | 10/0/0/15 | 1,5 s | +1 | libre | `ft:hedge-large` x2, `ft:hedge` x2 estirados |
| `avenue_tree` | Arbol de paseo | 15/0/0/20 | 2 s | +2 | libre | `ft:tree-high-round` |
| `flower_planter` | Macetero | 20/0/0/10 | 1,5 s | +2 | 2 | `kc:bush` x3 + flores propias |
| `colony_sign` | Letrero de la colonia | 25/0/0/15 | 2 s | +2 | libre | `sur:signpost`, `kc:bush` + mastil propio (FlagAnchor) |
| `hay_cart` | Carro de heno | 20/0/0/25 | 2 s | +2 | 2 | carro y pacas propios + `kk:sack` |
| `bonfire` | Hoguera | 15/0/0/30 | 1,5 s | +2 | 3 | `sur:campfire-stand`, `sur:resource-wood` x2 + llama propia |
| `flagpole` | Mastil con bandera | 40/0/0/20 | 2,5 s | +3 | 5 | `pir:flag-high` sin su tela (FlagAnchor) |
| `palm_trees` | Palmeras | 20/0/0/15 | 2 s | +2 | 13 | `pir:palm-straight` + arena y palmera propias; **solo en la costa** |

- **3D:** `scripts/buildings/DecorMesh.gd` da UNA malla por tipo, compartida por
  todas las instancias, con los dos materiales de `ToyPalette` (sin texturas, sin
  `_process`, brillo de farol y hoguera en la superficie sin luz). Carga la
  horneada (`assets/models/toy/<id>_mesh.res`) si existe y, si no, una version
  procedural con las mismas proporciones; `DieselpunkBuildingFactory.create()`
  la devuelve para estos ids. Recetas del horneado en
  `tools/toy_recipes/<id>.gd` (ayuda `_decor.gd`); el horneador avisa si una pasa
  de 600 triangulos.
  Horneadas las diez (feat/decoraciones-remates), todas por debajo de 600 con el
  borde de contacto (V8) incluido: el carro, el seto y las palmeras se
  recortaron para caber.
- **2D:** `BuildingArt2D._lamp_post()` ... `_palm_trees()`, con su suelo propio.
- **Lote (MultiMesh por tipo):** en 3D las diez las dibuja `DecorBatch3D` (hijo de
  `BuildingPlacer`, como `RoadBatch3D`): un `MultiMeshInstance3D` por tipo con la
  malla compartida. El edificio sigue siendo su nodo de siempre (rejilla,
  seleccion, mover, obra, ruina, nivel, guardado); su modelo es un
  `DecorProxy3D`, el `MeshInstance3D` con la malla para medir y encajar, pero
  con capas 0 y sin sombra. El proxy avisa al lote al moverse o esconderse y el
  lote rehace el tipo una vez al final del frame (si solo se movio, reescribe su
  transformacion). Sin sombra las menudas (alto < 1,5 m: banco, seto, carro,
  hoguera). La vista previa de CONSTRUIR y el fantasma siguen usando
  `DecorMesh.instantiate()`.
- **Bandera del pais:** `BuildingPlacer` cuelga `ColonyFlag3D` de cualquier
  edificio cuyo modelo traiga `FlagAnchor` (ademas del Nucleo y el CG). El mastil
  y el letrero lo traen: horneado, leido del `SceneState` de `<id>.tscn` por
  `DecorMesh.flag_anchor()`; sin hornear, `DecorMesh.PROCEDURAL_FLAG`. En las
  decoraciones la bandera va pequena (`ColonyFlag3D.SMALL_SCALE`) y ninguna tela
  se hornea. En 2D, `BuildingArt2D.has_flag_mount()` / `flag_mount()` dan lo alto
  del mastil de los dos dibujos y `Building2D` les pone `ColonyFlag2D`.
- **Palmeras solo en la costa:** `PlacementRules.needs_shore()` / `touches_shore()`:
  alguna celda de la huella es tierra pegada al agua (vecinas en 8 direcciones,
  la franja de `MapGenerator.is_shore_cell()` con banda 1). Motivo `"shore"`,
  aviso `LBL_NEEDS_SHORE`; `PlacementAssist.shore_spots()` pinta en verde los
  sitios validos y la ficha de CONSTRUIR lo dice (`rule_text`).

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
veta", "lleno: recógelo" (full of what it produced: it stopped until collected). While
under construction the label above the building gives the percentage and the time left
("En obras 61% · faltan 16 s") with a progress bar.

## Building Limits

**Los topes suben con la era (2026-10-14, decisión D1 de Bryan, rama
`feat/topes-por-era`).** Antes eran fijos y bajos (doc 21 §1.5 del contexto privado:
"hay demasiados recursos para pocos edificios"). Ahora:

- `GameConfig.building_limits_by_era` guarda `[era 1, era 2, era 3]` por edificio. La
  era 1 es el tope de siempre, así que una partida guardada nunca queda por encima de su
  tope. Regla general ≈ ×1,5 en la era 2 y ×2 en la era 3.
- `GameConfig.building_limits` queda como tabla de lo que **no** sube con la era (y
  como la era 1). Un id que no está en la tabla por era usa esta en todas las eras.
- **Un solo lector:** `GameConfig.get_building_limit(id)` = tope de la era en curso
  (`ProgressionManager.current_era`) + huecos del rango (`rank_limit_bonus`). Lo usan
  `PlacementRules.check_building_limit()` (colocar en 3D, 2D y táctil, el detalle de
  CONSTRUIR, `purchase_block_message()`), `Objectives` y el tutorial. Para otra era:
  `get_building_limit_for_era(id, era)`; sin rango ni modo: `base_building_limit(id, era)`;
  la siguiente subida: `next_building_limit(id)` → `{"era", "limit"}` o `{}`.
- **Decoraciones sin tope:** todo `BuildingData` con `is_decoration` (jardín, fuente,
  estatua, carretera y las decoraciones nuevas) da -1 aunque tenga entrada en
  `building_limits`. Se mira el `.tres` (`GameConfig.is_uncapped_building()`, recordado
  por id), así que una decoración nueva no necesita entrada en ninguna tabla. Las limita
  el terreno y el precio. Los huecos de rango sobre una decoración no hacen nada y el
  aviso de rango ya no los anuncia (`RankPanel.reward_lines()`; afecta al rango 13).
- **Sandbox:** sin topes en ninguna era (`GameMode.all_unlocked()`).
- **Nada se guarda:** el tope sale de la era (`progression.current_era`) y del rango
  (`rank.xp`), que ya van en el save. Una partida vieja carga con los topes de su era.

| Edificio | Era 1 | Era 2 | Era 3 | Por qué |
|----------|------:|------:|------:|---------|
| house | 10 | 15 | 20 | ×1,5 / ×2. Más gente = más consumo de comida, oro y madera: se paga sola |
| farm | 6 | 9 | 12 | ×1,5 / ×2, acompaña a las casas |
| sawmill | 5 | 8 | 10 | ×1,5 / ×2; lo limita también el número de bosques (3-6) |
| gold_mine | 4 | 6 | 8 | ×1,5 / ×2; lo limitan las vetas (3-6) |
| foundry | 3 | 5 | 6 | ×1,5 / ×2; lo limitan las vetas de hierro |
| refinery | 2 | 3 | 4 | ×1,5 / ×2; además consume su pozo (3-6 por mapa) |
| fishing_dock | 3 | 4 | 6 | Muelle de pesca (1.1): lo limitan también los bancos de peces (3-5) |
| warehouse | 5 | 5 | 5 | **No sube.** Bolsa de la era 3 sin técnicas: 1000 + 5×500 = 3500 = CG nivel 3 (1500 + 800 + 500 + 700; los materiales van aparte). Con 7 almacenes serían 4500 (5500 con las técnicas) y el CG 3 dejaría de pedir la bolsa llena. La bolsa ya crece sola por era (600/800/1000) y por nivel de almacén (+250 por nivel) |
| tower | 6 | 6 | 6 | **No sube.** 4 torres ya dan el 60 % de mitigación (`storm_tower_mitigation_max`) y hasta 4 dotaciones salen al tablero (`storm_tower_garrison_max`). El rango 16 sigue dando +1 |
| market, laboratory, headquarters | 1 | 1 | 1 | Únicos |
| barracks | — | — | — | **Sin tope** desde 2026-10-18 (antes 3/4/5): el freno está en el ejército, ver abajo |
| garden, fountain, statue, road y las diez decoraciones baratas (`lamp_post` … `palm_trees`) | — | — | — | Sin tope |

Los huecos del rango van encima: casas +2 en los rangos 10 y 17 (era 3: 24), torre +1 en
el 16.

**Cuartel sin tope (2026-10-18, decisión de Bryan, rama `fix/bandera-y-topes-militares`).**
`building_limits["barracks"] = -1` y el Cuartel sale de `building_limits_by_era`: se
pueden levantar tantos como quepan y se paguen, en todas las eras. Todo lo que lee el
tope ya entiende -1 (`PlacementRules.check_building_limit`, la tarjeta de CONSTRUIR sin
contador ni "Al máximo", `BuildingHelpText` —la guía dice "Sin máximo" y la página
*Topes de edificios* lo nombra junto a las decoraciones—, `Objectives`, el tutorial —un
repaso con varios Cuarteles ya no lo salta por "limit"— y `rank_limit_bonus`, que no
tenía huecos de Cuartel). Como cada Cuartel era capacidad (+8) y un hueco de
entrenamiento, sin freno el ejército crecería sin techo salvo por el sueldo. **El freno
elegido** (`GameConfig`, valores conservadores: los máximos de antes son el techo):

| Valor | Qué | Por qué |
|-------|-----|---------|
| `army_full_capacity_barracks` = 3 | Los 3 primeros Cuarteles dan +8 plazas (`army_capacity_per_barracks`) | Igual que antes en la era 1 (3 + 8×3 = 27) |
| `army_capacity_per_extra_barracks` = 4 | Del 4.º en adelante, +4 cada uno | Rendimiento decreciente: un Cuartel de más sigue ayudando, la mitad |
| `army_capacity_max` = 43 | Techo de tropa (se llega con 7 Cuarteles) | 43 era lo máximo con el tope viejo (5 Cuarteles en la era 3) |
| `army_training_slots_max` = 5 | Entrenando a la vez, como mucho 5 | 5 era lo máximo con el tope viejo |

`GameConfig.get_army_capacity(n)`, `army_capacity_gain(n)` (lo que suma el próximo; la
guía dice "+8 soldados", "+4" o nada en el techo) y `get_army_training_slots(n)`;
`ArmyManager.max_slots()` lee este último. Las ayudas del panel EJÉRCITO dicen las
cifras (`LBL_ARMY_CAPACITY_HINT`, `LBL_ARMY_SLOTS_HINT`). Más Cuarteles siguen sirviendo:
repartir la defensa, tener repuesto si uno cae en ruinas. El sueldo en oro sigue siendo
el freno de fondo. Cada Cuartel lleva la bandera del país (ver "FlagAnchor"), así que
con muchos todas comparten malla, material y shader (`ColonyFlag3D`), sin `_process`.

**CONSTRUIR** lo enseña en cada tarjeta y en el detalle: una casita dibujada y
"3/6 · era 2: 9" (cuántos hay / tope de esta era · la era que lo sube y a cuánto), en
ámbar cuando está lleno; el tooltip lo dice en frase. Se pone al día al subir de era
(`EventBus.era_advanced`) y al colocar. El recuento se recuerda mientras no cambia
`GridManager.map_version()` (`ConstructionMenu._count_of()`): el refresco de costes llega
con cada recurso que cambia y contar recorre todos los edificios, carreteras incluidas.
Cuando se alcanza, el aviso sigue siendo `LBL_LIMIT_REACHED` ("Límite alcanzado (6/6)").

## Deposit Rules

Defined in `GameConfig.building_deposit_rules` and checked by
`scripts/buildings/PlacementRules.gd` (same rule in 3D, 2D and touch placement):

| Building | Must touch | Reach | Consumes it |
|----------|-----------|-------|-------------|
| sawmill | forest | 1 | no |
| gold_mine | gold_vein | 1 | no |
| foundry | iron_deposit | 1 | no |
| refinery | oil_well | 0 (on top) | yes |
| fishing_dock | fish_shoal (mar adentro; el muelle en la costa, 2 por banco) | 4 | no (nunca se agota) |

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
| refinery | foundry + barracks + laboratory |
| barracks | sawmill (2026-10-17: before, foundry + sawmill) |
| tower | barracks + foundry |
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
  (`PlacementRules.upgrade_effect_lines()`). The level shows on the model itself
  (2026-10-17, `LevelTrim` + `ProductionManager.apply_level_visual`): the same model
  grows (x1.04 / x1.08 in plan, x1.12 / x1.24 in height), is lifted onto a stone plinth
  with a brass band (two steps at III) and gains brick chimneys with brass bands at its
  back corners (one at II; two at III, the big one with a lit lamp). Decorations get
  brass lamps at the corners instead (two at II, four at III). One cached mesh per
  level and size, no shadow, no extra nodes or `_process`. There is no floating
  "II / III" plate any more, nor the old brass ring with a red pennant (it floated over
  tall models like a box with a flag). 2D draws the same (`BuildingArt2D._level_plinth`
  / `_level_trim`) inside the baked drawing, plus brass chevrons with no box
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

### Etapas de dano (2026-10-16)

Entre sano y ruina el dano se ve por etapas, no solo como la capa de ceniza de
`BuildingHealth` (que sigue encima, por escalones). La etapa sale de la
proporcion de vida con `BuildingLook.damage_stage()` y los umbrales de
`GameConfig.damage_stage_thresholds` (`[0.75, 0.4]`); `derive()` la devuelve en
la clave `"damage"`. Va **encima** del aspecto: un edificio grave puede seguir
trabajando y echa su humo ademas del negro. Solo se ve en pie (quieto o
trabajando); la obra y el andamio de mejora la tapan. Es solo aspecto: el dano,
la reparacion y su coste no cambian.

| Etapa | Vida | 3D | 2D |
|---|---|---|---|
| **Sano** | ≥ 75 % | el modelo (un rasguno: solo la capa de ceniza) | el dibujo; por debajo del 100 %, un velo de ceniza y la barra de vida |
| **Leve** | < 75 % | grietas en zigzag en la fachada y un costado, tejas y cascotes caidos al pie, una tabla suelta apoyada en la pared; el modelo ladeado `damage_tilt[0]` (0,025 rad) | velo de ceniza, grietas, huecos de tejas que faltan, tejas caidas al pie, tabla suelta; el cuerpo ladeado (cizalla) |
| **Grave** | < 40 % | lo anterior y mas, chapa colgando de un costado, viga partida que asoma del tejado, tizne y cascotes, brasas; **humo negro** y **chispas** animados; ladeado `damage_tilt[1]` (0,05 rad) y hundido `damage_sink_ratio[1]` (5 %) | lo anterior y mas, tizne, chapa suelta torcida, viga partida con ascuas, cascotes; humo negro y chispas animados; mas ladeado y algo aplastado |
| **Ruina** | 0 | la de siempre (ver la tabla de aspectos) | la de siempre |

- **3D**: `SiteMesh.damage_overlay(etapa, caja, variante)` (raiz
  `DamageOverlay<etapa>`, hijo de `LookVisual`). Todo lo quieto es **una malla
  cacheada** por etapa, variante (3, de la semilla de la celda) y caja del
  modelo (`SiteMesh.damage_mesh`): diez casas tocadas comparten dos o tres
  mallas, con los materiales de la paleta (`LotMesh`/`ToyTones`). Las piezas se
  colocan alrededor de la caja medida del modelo (`BuildingLookVisual._model_box`,
  una vez por cambio de etapa); la viga nace dentro del modelo para tocarlo
  siempre. El humo (`smoke`, variante `ruin`) y las chispas son quads de
  `BuildingFx` con su material compartido. El ladeo usa la misma postura
  guardada que la ruina (`look_base_pos/rot`), asi que reparar o mejorar lo
  devuelve exacto.
- **2D**: `Building2D` no usa la parcela horneada entera mientras esta herido:
  pinta la parcela derecha y el cuerpo (de la cache por tipo) con
  `BuildingArt2D.damage_lean()`; las marcas (`draw_damage_marks`) se hornean en
  `ArtCache2D` con clave `dmg|etapa|variante|huella|tamano`. Humo y chispas,
  sprites de `BuildingFx` creados la primera vez (`DamageFx`).
- **Mismo lado en las dos vistas**: variante y lado salen de
  `BuildingLook.seed_of()` (celda de origen).
- **Calidad Minima**: solo la malla y el dibujo; humo y chispas estan en el
  grupo `building_fx_anim` y no se ven.
- **Nada por frame**: la 3D cambia la etapa con `building_damaged` (repinta
  ya) y el reloj comun de aspectos; la 2D, con su firma de repintado.
- **Reparado**: vuelve a sano con el salto de juguete y el polvo de la obra
  terminada (`BuildingPlacer._bounce_building`, `BuildingPlacer2D`).
- No hay andamio de reparacion: reparar es instantaneo (no hay un estado
  "reparandose" que pintar).
- Sonda: `tools/look_probe.gd` saca en `look_probe_3d.png` leve y grave del
  cuartel, la casa, la fundicion trabajando y el almacen.

## Parcela y atrezo (guia de estilo, 2026-10-04)

Cada edificio vive en su **parcela** (regla 1 de la guia de estilo de edificios):
un suelo propio que cubre la huella entera, un borde oscuro fino que la separa de
la isla, el **remate** de los lados que no dan a calzada y **atrezo** en el
**patio** que queda entre el modelo y el borde. Lo que hace el edificio se ve
desde fuera (regla 2) y cada uno lleva **un elemento exagerado** que le da
silueta en miniatura (regla 3). La calzada no lleva parcela: ya es suelo.

**La regla es una, compartida por las dos vistas**: `scripts/buildings/LotPlan.gd`
(pura y estatica) decide, en casillas y en el marco local del edificio, que suelo
lleva, que remate, donde va cada pieza de atrezo y donde el elemento exagerado.
La tabla es `GameConfig.building_lot_style`; los acentos, `building_lot_accents`
(rojo valvula en lo industrial, amarillo senal en lo militar, laton en lo civico,
verde en lo residencial).

| Edificio | Suelo | Remate | Atrezo del patio | Elemento exagerado |
|---|---|---|---|---|
| Aserradero | tierra batida | valla baja | troncos, tablones, cajas, barril, farola | la **sierra** del cobertizo abierto (en el modelo) |
| Granja | tierra batida | valla baja | sacos de la cosecha, barril, cajas (patio de 0,25: el campo es el edificio) | el **molino** de aspas y el campo que crece y se dora (en el modelo) |
| Mina de oro | tierra batida | valla baja | vagoneta en sus railes, mineral, cajas, barril, farola | **monton de mineral** con pepitas y pico (esquina SO) |
| Fundicion | chapa remachada | barandilla | lingotes (uno al rojo), carbon, barril, bidones | **chimenea** alta de ladrillo, banda roja y boca encendida, con su tiro (NE) |
| Refineria | chapa remachada | tuberia con valvulas | bidones, valvula, barril, cajas | **colector** de tuberias con la gran rueda de valvula roja (SE) |
| Almacen | losas | bordillo | cajas, palets, sacos, barril | **grua** amarilla cuya pluma pasa por encima del tejado con una caja colgando sobre la entrada (NE) |
| Mercado | losas | bordillo | puestos de fruta, sacos, barril, maceta | toldos grandes con mercancia (en el modelo) |
| Laboratorio | losas | barandilla | botellas de gas, cajas, farola, maceta | **antena** de celosia con luz azulada (NO) y cupula de cristal en el modelo |
| Cuartel | tierra batida | sacos terreros | munecos de practica, diana, cajas de municion | — (desde 2026-10-18: su remate es la bandera del pais en el mastil corto del tejado, del modelo) |
| Torre | chapa remachada | sacos terreros | municion, sacos, farola, barril | **canon** en su nido de sacos (SE) |
| Cuartel General | losas | barandilla | farola, macetas, municion (sin banderas desde 2026-10-18) | **emblema de la Regencia** (rueda dentada de laton con el rayo de la Tormenta) sobre el tejado |
| Vivienda | hierba | valla baja | tendedero, macetas, banco, barril | — |
| Nucleo | losas | bordillo | farolas, macetas, bancos | — (ya es monumental) |
| Jardin / Fuente / Estatua | hierba / losas / losas | bordillo | banco, farola, maceta | — |

- **Variacion por instancia**: la semilla es `LotPlan.seed_for(celda, id)`, que
  es la misma de la obra (`BuildingLook.site_seed(id, celda)`, ver "Obra por
  edificio y por instancia"): la parcela a medio preparar y la obra que va
  encima salen de la misma tirada. Dos aserraderos no tienen el mismo atrezo;
  el mismo, tras guardar y cargar, si. Nada de esto va al guardado.
- **Las puertas quedan libres**: la vida de la ciudad (los obreros que andan)
  entra por el lado que da a la calzada, y ahi la parcela no pone ni remate ni
  atrezo.
- **No pisa nada**: cada pieza cabe entera en el patio (ni toca el rectangulo
  del modelo ni sale de la parcela, asi que nunca pisa una calzada vecina), los
  lados que dan a calzada quedan libres (son la entrada) y la esquina del
  elemento exagerado no lleva atrezo.
- **El modelo se encoge en planta** para dejar el patio libre:
  `BuildingLot.fit_model()` lo escala en X/Z (nunca en altura, nunca lo agranda)
  y lo centra dentro de `LotPlan.model_rect()`. Lo usan el edificio del mapa y
  el fantasma de colocar, asi que miden lo mismo.
- **Obra**: la parcela esta a medio preparar: suelo de tierra, jalones con
  banderola en las esquinas, un palet de losas esperando y el remate puesto lado
  a lado (tantos lados como fases pasadas). Sin sombra ni elemento exagerado.
  Convive con la fase de obra de la huella, que va encima.
- **Ruina**: el suelo se quema, el atrezo se vuelca (lo alto se parte, para no
  salirse del patio), un quinto desaparece, el remate pierde tramos y el
  elemento exagerado queda en un munon quemado.
- **Lectura** (regla 5): bajo el modelo, una **sombra de contacto** con el filo
  mas oscuro donde lo toca (AO de contacto); alrededor de la parcela, un **borde
  oscuro fino**. Las farolas y las bocas encendidas van sin sombreado: siguen
  leyendose con la Tormenta (`StormSky`) y con el tinte de ceniza de la 2D.

**3D** (`scripts/buildings/BuildingLot.gd`, hijo `Lot` de cada edificio salvo la
calzada, en el grupo `building_fx`): `Ground` (un plano con la textura de su
suelo, generada en codigo y cacheada por suelo y huella), `ContactShadow` (un
plano con un unico material para todo el mapa) y `Props` (el borde, el remate,
el atrezo y el elemento exagerado en **una sola malla** con color por vertice,
`LotMesh.gd`, con dos materiales compartidos: con luz y sin luz). Son tres
o cuatro llamadas de dibujo por parcela (la malla del atrezo lleva una segunda
superficie si hay algo encendido), unos 1.500 triangulos de media, y **nada por
frame**: la parcela se monta una vez en unos 6 ms de GDScript (medido en PC) y
se reconstruye solo cuando cambia algo que la parcela ve (su celda o las calzadas de al lado, por las
senales `building_placed` / `building_demolished` / `building_moved` /
`game_load_completed`; la obra y la ruina, por `BuildingLookVisual.apply()`).
Lo que va por encima del modelo (la grua, el emblema) se mide con su AABB real y,
el emblema, con la altura del tejado en el centro (`BuildingLot.roof_height()`).

**2D**: `BuildingArt2D.draw_lot_ground()` / `draw_lot_shadow()` /
`draw_lot_props()` con el mismo plan; `Building2D` dibuja el edificio dentro de
su rectangulo (opcion `inset` de `draw_building`) y la obra, el dano y la ruina
sobre el, no sobre la parcela (docs/18).

**El Aserradero abierto (2026-10-04; desde el 2026-10-12 es el modelo horneado `assets/models/toy/sawmill.tscn`, con la misma idea).** Paso a procedural
(`DieselpunkBuildingFactory._build_sawmill`; su GLB sigue en
`assets/models/buildings/sawmill/` pero `sawmill.tres` ya no lo usa): un
cobertizo con media cubierta de chapa de una sola agua atras, cerchas al aire
delante y **ningun muro en el frente**, para que desde la camara se vea la sierra
grande (el elemento exagerado, buje rojo), el tronco en la mesa, el tablon
recien cortado, la pila de tablones, la de troncos y la maquina de vapor con su
correa. El serrin de "trabajando" sale de la hoja: el modelo trae un `Marker3D`
`FxAnchor` y `BuildingLookVisual` pone ahi el efecto (cualquier modelo puede
traer el suyo). En 2D, el mismo cobertizo visto desde arriba, con la sierra
dominando el dibujo y el icono.

Capturas: `tools/look_probe.gd` (con `override.cfg` propio) deja ademas
`look_probe_style_3d.png`, `look_probe_style_storm_3d.png`,
`look_probe_style_2d.png`, `look_probe_style_storm_2d.png`,
`look_probe_style_close_3d.png` y `look_probe_sawmill_3d.png` en `docs/media/dev/`.

## Modelos: maqueta de juguete (2026-10-12)

Los edificios 3D son **modelos horneados**: una sola malla con color por
vertice y, como mucho, dos superficies con los dos materiales que comparte todo
el mapa (`assets/models/toy/toy_solid.tres` con luz, `toy_glow.tres` sin luz para
ventanas, brasas y faroles). Nada de materiales por instancia ni luces propias:
lo que pide el renderizador Mobile en una tablet barata. Entre 650 y 2.700
triangulos por edificio (el horneador los imprime).

- **Horneado**: `godot --headless --path . -s tools/build_toy_models.gd`
  (`-- --only=house,farm` para unos pocos, `-- --dump=all` para ver las piezas
  CC0 con su tamano y su reparto de paleta). Cada edificio tiene su receta en
  `tools/toy_recipes/<id>.gd`; las piezas propias (tejados, ventanas, chimeneas,
  tuberias, valvulas, depositos, toldos, troncos, sacos) estan en
  `tools/toy_recipes/_parts.gd` y las CC0 se cargan con `tools/toy_kit.gd`.
- **Salida**: `assets/models/toy/<id>.tscn` (raiz = un `MeshInstance3D`) con su
  malla en `<id>_mesh.res`, y un `Marker3D` `FxAnchor` en los que echan humo o
  serrin (`GameConfig.building_active_fx`): la sierra, la chimenea del horno, la
  antorcha de la columna...
- **A la medida**: cada modelo sale ya del tamano del rectangulo que le deja su
  parcela (`LotPlan.model_rect`), centrado, base en y = 0 y frente hacia +Z; lo
  que una receta deje salirse se encoge en planta al hornear, asi que
  `BuildingLot.fit_model()` no tiene que escalar. La granja tambien: a 3,0 m,
  el rectangulo de su parcela (`building_lot_style["farm"]`, patio 0,25), con los
  bancales en su malla aparte (ver "The Farm").
- **Color**: la paleta (`ToyPalette`) esta escrita en sRGB y el horneado la pasa
  a lineal (los materiales leen el color por vertice como lineal, igual que el
  atrezo de `BuildingLot`); ademas oscurece lo que toca el suelo (AO de contacto).
- **Estilo** (guia de estilo de edificios): la funcion se ve desde fuera, un
  elemento exagerado por modelo que complementa el de la parcela (la sierra del
  Aserradero, la rueda del castillete, el portalon del Almacen, la sombrilla del
  Mercado, la cupula del Laboratorio, la boca del horno de la Fundicion, el galon
  del Cuartel, la columna de la Refineria, el canon largo con aros y franja de laton de la Torre, la torre del
  Cuartel General con el emblema de la Regencia en la fachada, la cupula y el manometro del Nucleo, el surtidor de la
  Fuente, la rueda dentada de la Estatua, el molino de la Granja) y un acento
  por familia.
- **FlagAnchor**: un `Marker3D` donde se cuelga la bandera del pais. **La
  bandera del pais va solo en el Nucleo y en los Cuarteles** (Bryan,
  2026-10-18; `ColonyFlag.FLAG_BUILDINGS = ["barracks"]`, ademas del Nucleo y de
  las decoraciones con mastil). En el Cuartel, en lo alto de un mastil corto
  sobre la cumbrera (lado contrario a la chimenea, receta
  `tools/toy_recipes/barracks.gd`); la bandera es mediana
  (`ColonyFlag3D.BARRACKS_SCALE`, 0,62 de la normal) y cuelga hacia +X, sobre su
  propio tejado, sin salirse de la huella. El Cuartel General ya no lleva mastil
  (se veia enorme: escala 1,6 y palo de 2,1 sobre el tejado). En el Nucleo, en
  lo alto del mastil de la colonia (`ColonyFlag3D`, que no es del modelo: el
  horneado lo coloca con la misma cima que mide `BuildingPlacer`,
  `max(mesh_height, malla) + 2,4`). El modelo no dibuja bandera. En obra o en
  ruinas la bandera no se ve y vuelve al terminar o al reparar. En 2D,
  `BuildingArt2D.flag_mount("barracks")` (peana en el tejado; palo y bandera
  los pinta `ColonyFlag2D`).
- **Madera** (2026-10-12): la casilla WOOD de `ToyPalette` es un marron natural
  (140, 100, 70), no naranja; la siguen las piezas CC0, el atrezo y la obra
  (`ToyTones`).
- Los GLB viejos siguen en `assets/models/buildings/`, sin uso y fuera del exportado.
- **Unidades de combate**: la misma herramienta hornea las piezas de juguete del
  tablero 3D con `-- --units` (recetas en `tools/toy_recipes/units/`, salida en
  `assets/models/toy/units/`): ver docs/15 §3, "El tablero 3D".
- **Astillero y Aerodromo** (1.1, `feat/aire-mar-vista`): ver "Astillero y
  Aerodromo: la maqueta", abajo.
- Capturas: `godot --path . -s tools/toy_probe.gd` (con `override.cfg` propio)
  deja `toy_probe_all.png` (distancia de arranque), `toy_probe_close_<n>.png`,
  `toy_probe_storm.png` y, con `-- --near=9 --ids=...`, `toy_probe_near.png`;
  `-- --pieces=kk:barrel,...` fotografia piezas CC0 sueltas.

### Astillero y Aerodromo: la maqueta (1.1, rama `feat/aire-mar-vista`)

Los dos edificios militares de mar y aire, 2x2. Sus reglas (`.tres`, coste,
"toca la costa", que entrena cada uno) son de la rama de reglas; aqui solo su
aspecto. Recetas propias, sin piezas CC0:

| Edificio | Receta | Modelo | Triangulos | Lo exagerado |
|---|---|---|---|---|
| Astillero (`shipyard`) | `tools/toy_recipes/shipyard.gd` | `assets/models/toy/shipyard.tscn` | 1.328 | la grua de portico amarilla sobre la darsena |
| Aerodromo (`aerodrome`) | `tools/toy_recipes/aerodrome.gd` | `assets/models/toy/aerodrome.tscn` | 1.315 | el mastil de amarre con el dirigible |

- **Astillero**: la mitad de delante (+Z del modelo) es la darsena, agua entre
  dos muelles de piedra con la grada y un casco a medio hacer (cuadernas, quilla
  roja); atras, la nave del taller con su chimenea (de ahi el `FxAnchor`: humo),
  chapa y tablones. Al colocarlo, ese lado de delante es el que debe dar al mar
  (la regla de costa es de las reglas; el modelo solo la dibuja).
- **Se orienta solo al agua (ronda de la 1.1):** al colocar un Astillero, el
  fantasma se gira para que la darsena mire al agua mas cercana
  (`PlacementRules.FACES_WATER`, `water_side()` por anillos hasta
  `FACE_WATER_REACH` = 4 celdas, `steps_facing_water()`). Lo hacen los dos
  colocadores y la colocacion tactil (`PlacementAssist` mueve el fantasma por el
  mismo `_set_preview_cell` / `update_ghost`), y tambien el clic que planta. Solo
  cuando el fantasma cambia de celda (unas decenas de consultas a
  `GridManager.is_land_cell`), nada por fotograma. Si el jugador lo gira a mano
  (R, boton de girar), deja de girarse solo hasta el proximo edificio; al MOVER se
  respeta el giro que ya tenia. Test: `tests/buildings/test_shipyard_faces_water.gd`.
- **Un solo giro para las dos vistas:** `rotation_steps` (el guardado) va con el
  convenio de la vista 3D (un paso lleva el delante, +Z, hacia +X). La 2D giraba
  al reves con el mismo numero (el giro de un Node2D va en el sentido del reloj):
  un Astillero girado en 3D salia con la darsena hacia tierra en 2D.
  `Building2D.view_steps()` dibuja con los pasos cambiados de signo; asi el mismo
  guardado mira al mismo lado del mundo en las dos vistas (docs/18).
- **Captura de puerto:** `godot --path . -s tools/costa_probe.gd -- --no-title
  --no-dev --islands=2 --mar` (con `override.cfg` propio) planta un Muelle junto a
  un banco, un Astillero en la costa (girado con la regla) y un Aerodromo, y los
  fotografia de cerca en 3D y 2D (`docs/media/dev/costa_<n>_mar_*.png`).
- **Aerodromo**: la pista delante (asfalto, rayas y balizas encendidas), el
  hangar de media cana con el portalon abierto atras a la izquierda, el mastil de
  celosia con el dirigible amarrado atras a la derecha (`FxAnchor` en el faro de
  su punta) y la manga de viento.
- Sus `.tres` llevan `model_scene` = `res://assets/models/toy/shipyard.tscn`
  / `aerodrome.tscn` y `mesh_height` 2,0 / 2,7 (pegado al juntar las ramas de
  reglas y vista, `integracion/v1.1-aire-mar`). Si un `.tres` no lo llevara,
  `DieselpunkBuildingFactory` carga igual la maqueta horneada (`BAKED_ONLY`).
- El horneador toma la huella y la parcela del `.tres`;
  `build_toy_models.EXTRA` solo serviria si faltara el `.tres`.
- 2D: `BuildingArt2D._shipyard` / `_aerodrome` (mapa, fantasma e icono del menu,
  que es el mismo dibujo). En CONSTRUIR van en la categoria militar.
- `construction_style`, `building_lot_style` y `building_active_fx`: una sola
  fila por edificio en `GameConfig`, la de la rama de reglas (grua en la obra del
  Astillero, cinco piezas de atrezo); `building_active_fx` = humo / brillo.
- **Pendiente:** el modelo no se gira solo hacia el agua. La regla de costa
  (`PlacementRules.SHORE_ONLY`) obliga a tocar la costa, y el jugador puede girar
  el edificio al colocarlo, pero nada orienta la darsena (+Z del modelo) al mar:
  sin girarlo, en una costa que no queda delante, el agua dibujada da a tierra.

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

**Coste** (2026-10-12, maqueta): todo lo quieto de una obra (suelo, valla,
pilas, losa, estructura, andamio, mastil de la grua, palos de los banderines)
es **una sola malla** con color por vertice (`scripts/buildings/SiteMesh.gd`,
sobre `LotMesh`) y los dos materiales compartidos de `ToyPalette`, igual que el
andamio de mejora y los escombros de la ruina. Lo animado son la pluma, el
contrapeso y el gancho de la grua (mallas cacheadas por largo y color), un quad
de banderin compartido y el quad del efecto: shaders con `TIME`, sin crear ni
destruir nodos. Montar una obra cuesta ~4 ms de GDScript y solo pasa al cambiar
de fase. Que grupos y pilas lleva cada obra queda en metas de la raiz
(`site_groups`, `site_piles`). Ninguna luz propia.

**Tonos** (`scripts/buildings/ToyTones.gd`): obra, ruina, atrezo de las
parcelas, calzada y figuritas piden su color por papel (`Tone.of("wood")`,
`"brick"`, `"pave"`...); cada papel es una casilla de `ToyPalette` aclarada u
oscurecida. Los colores sueltos de `GameConfig` (acentos de parcela, lonas,
banderines, gruas) pasan por `Tone.snap()`, la misma regla del horneado. Los
shaders propios (grua, banderin, figuritas) leen el color igual que el material
solido de la paleta (`vertex_color_is_srgb`).

## Key Files

- `scripts/buildings/BuildingData.gd` — Resource class definition
- `data/buildings/*.tres` — 17 building data files
- `scripts/buildings/PlacementRules.gd` — placement, road network, auto-road, upgrade effects
- `scripts/map/WorkerWalkers.gd` — the walking workers
- `scripts/services/GameConfig.gd` — limits, prerequisites, processes
- `scripts/services/ProductionManager.gd` — construction + passive production
- `scripts/buildings/BuildingLook.gd` — rule: construction phase / upgrade / ruin / active / idle (both views)
- `scripts/buildings/BuildingLookVisual.gd` — applies it in 3D; `scripts/buildings/BuildingFx.gd` — animated sprite sheets + shaders
- `scripts/buildings/LotPlan.gd` — rule: lot ground, trim, props and exaggerated element (both views); `scripts/buildings/BuildingLot.gd` — the 3D lot; `scripts/buildings/LotMesh.gd` — one vertex-coloured mesh per lot
- `scripts/buildings/SiteMesh.gd` — 3D construction phases, upgrade scaffold and ruin in the toy palette (one static mesh each); `scripts/buildings/ToyTones.gd` — palette-derived tones for everything around the buildings
- `scripts/buildings/SiteFx.gd` — construction-site animation shaders (crane, hook, pennant) for both views; site style/layout in `BuildingLook.gd`
- `scenes/buildings/BuildingPlacer.tscn` — placement/move/demolish logic
