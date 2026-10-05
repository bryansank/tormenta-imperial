# Buildings System

## BuildingData Resource

Each building is defined as a `.tres` file in `data/buildings/` using the `BuildingData` class (`scripts/buildings/BuildingData.gd`).

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | String | Unique identifier (matches filename) |
| `display_name` | String | Fallback name; the UI shows `get_display_name()` (the `BLD_<ID>_NAME` translation) |
| `description` | String | Fallback text; the UI shows `get_description()` (`BLD_<ID>_DESC`) |
| `grid_size` | Vector2i | Cells occupied (e.g., 2x2) |
| `cost_gold/steel/oil/wood` | int | Construction cost |
| `build_time` | float | Seconds to construct (0 = instant) |
| `produces_gold/steel/oil/wood` | int | Passive production per cycle |
| `production_interval` | float | Seconds between production cycles |
| `workers_required` | int | Workers needed to operate |
| `population_capacity` | int | Housing capacity (houses only) |
| `morale_bonus` | int | Passive morale bonus (decorations) |
| `mesh_height` | float | Visual height for procedural mesh |
| `mesh_color` | Color | Visual color |
| `model_scene` | PackedScene | GLB model (12 of 14 buildings; `nucleo` and `road` fall back to `DieselpunkBuildingFactory`) |
| `max_health` | int | HP for storm and siege damage (`BuildingHealth`) |
| `is_core` | bool | Cannot be built/moved/demolished |
| `is_decoration` | bool | No production, no workers, morale only |

## Complete Building List

### Production Buildings

| ID | Name | Size | Cost G/S/O/W | Workers | Build Time | Produces | Interval |
|----|------|------|--------------|---------|------------|----------|----------|
| `nucleo` | Nucleo | 3x3 | Free | 0 | instant | — (manual processes, +5 pop) | — |
| `sawmill` | Aserradero | 2x1 | 80/0/0/50 | 2 | 5s | 6 wood | 12s |
| `gold_mine` | Mina de Oro | 2x2 | 120/0/0/80 | 3 | 8s | 8 gold | 12s |
| `foundry` | Fundicion | 2x1 | 200/0/0/120 | 3 | 12s | 5 steel | 15s |
| `refinery` | Refineria | 2x2 | 300/150/0/100 | 4 | 18s | 4 oil | 18s |
| `headquarters` | Cuartel General | 2x2 | 500/300/200/200 | 5 | 30s | 10 gold | 20s |

### Support Buildings

| ID | Name | Size | Cost G/S/O/W | Workers | Build Time | Special |
|----|------|------|--------------|---------|------------|---------|
| `house` | Vivienda | 1x1 | 50/0/0/30 | 0 | 3s | +6 pop capacity |
| `warehouse` | Deposito | 1x1 | 60/0/0/40 | 1 | 4s | +500 shared storage cap |

### Military Buildings

| ID | Name | Size | Cost G/S/O/W | Workers | Build Time | Prereqs |
|----|------|------|--------------|---------|------------|---------|
| `barracks` | Cuartel | 2x2 | 250/100/0/80 | 3 | 15s | foundry + sawmill |
| `tower` | Torre | 1x1 | 150/60/20/30 | 1 | 8s | barracks |

The Barracks trains units (`ArmyManager`, one training slot per Barracks). Each
operational Tower cuts storm damage by 15% (cap 60%) and puts one artillery crew on
the defensive boards — the Tithe and each Final Audit wave — outside the deploy cap
(max 2). See [15-combat.md](15-combat.md).

### Decorations (morale only)

| ID | Name | Size | Cost G/S/O/W | Build Time | Morale |
|----|------|------|--------------|------------|--------|
| `road` | Camino | 1x1 | 10/0/0/5 | 1s | +2 |
| `garden` | Jardin | 1x1 | 30/0/0/20 | 2s | +5 |
| `fountain` | Fuente | 1x1 | 60/20/0/10 | 4s | +7 |
| `statue` | Estatua | 1x1 | 120/40/0/0 | 6s | +10 |

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

## Prerequisites

Defined in `GameConfig.building_prerequisites`:

| Building | Requires |
|----------|----------|
| foundry | sawmill |
| refinery | foundry |
| barracks | foundry + sawmill |
| tower | barracks |
| headquarters | barracks + refinery |

## Upgrade System

- Max level: 3
- Cost multiplier: L1=1.0x, L2=1.8x, L3=3.0x of base cost
- Production multiplier: L1=1.0x, L2=1.6x, L3=2.5x
- HQ has special override costs (see economy doc)

## Manual Processes

Buildings can run timed manual processes (one at a time per building). Defined in `GameConfig.building_processes`. Margins are ~1.5x to make the market meaningful.

## Construction Flow

1. Player selects building from ConstructionMenu
2. `EventBus.building_selected_for_placement` emitted
3. BuildingPlacer (or `BuildingPlacer2D`) shows a green/red ghost on the grid; on touch, `PlacementAssist` highlights the valid spots, a tap aims and a tap on the ghost / ✓ builds
4. On confirm: `PlacementRules` checks the spot, then `ResourceManager.spend_cost()`, `GridManager.place_building()`
5. `EventBus.building_placed` emitted
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
| **Obra, fase 0** | progreso < 34 % | modelo oculto; tierra removida, valla de tablas con puerta y cinta de peligro, pilas de tablones / vigas / ladrillo (una por clase de huella) | tierra, valla con postes y puerta, pilas de material |
| **Obra, fase 1** | 34-67 % | losa de cimentacion, zapatas, esperas de ferralla, conos | losa con zapatas y ferralla, conos |
| **Obra, fase 2** | ≥ 67 % | pilares, medio forjado, vigas de coronacion, andamio y, desde 2x2, grua | pilares, medio forjado, andamio y grua |
| **Mejora** | obra que es una mejora | el modelo a la vista con andamio alrededor | el dibujo con rayas, andamio en aspa y barra |
| **Ruina** | `BuildingHealth.is_ruined()` | el modelo se hunde un 38 % y se ladea, con el hollin de siempre, suelo quemado, cascotes, muro roto, vigas carbonizadas y humo negro animado | tizne, muro dentado, cascotes, vigas con ascuas, grietas y humo negro animado |
| **Trabajando** | el badge dice WORKING y el edificio tiene efecto | humo, serrin o luz que parpadea sobre la cima | humo/serrin desde las chimeneas del dibujo, luz en la puerta |
| **Quieto** | lo demas | el modelo, sin animacion | el dibujo, sin animacion |

- **Las fases de obra van por huella, no por edificio** (1x1 / 2x2 / 3x3):
  `DieselpunkBuildingFactory.create_construction_phase(footprint, phase, cell_size)`
  y `BuildingArt2D.draw_construction_phase()`. La clase de huella (el lado
  mayor, 1-3) decide cuantas pilas, cuantos pilares y si hay grua. Umbrales en
  `GameConfig.construction_phase_thresholds`.
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
  `look_probe_2d.png`.
- Todo es original y generado por el proyecto (mallas procedurales, dibujo en
  codigo, hojas de sprite generadas): ningun asset externo.

## Key Files

- `scripts/buildings/BuildingData.gd` — Resource class definition
- `data/buildings/*.tres` — 14 building data files
- `scripts/services/GameConfig.gd` — limits, prerequisites, processes
- `scripts/services/ProductionManager.gd` — construction + passive production
- `scripts/buildings/BuildingLook.gd` — rule: construction phase / upgrade / ruin / active / idle (both views)
- `scripts/buildings/BuildingLookVisual.gd` — applies it in 3D; `scripts/buildings/BuildingFx.gd` — animated sprite sheets + shaders
- `scenes/buildings/BuildingPlacer.tscn` — placement/move/demolish logic
