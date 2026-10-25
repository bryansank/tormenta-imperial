extends Node
## Trafico: unos pocos camiones diesel que llevan lo que sacan los extractores
## (aserradero, mina, fundicion, refineria, granja...) al Almacen mas cercano o
## al Nucleo por la red de carreteras, y vuelven vacios (doc 21 §7, V5;
## feat/decoraciones-y-trafico).
##
## Solo es vista, como WorkerWalkers: no mueve recursos, no decide nada y no
## viaja en el guardado. Lee los edificios y las metas que escribe
## PopulationManager (`staffed`, `connected`) y mueve camiones:
##   - FUENTES: extractores terminados, con dotacion y unidos a la red.
##   - DESTINOS: Almacenes terminados y unidos a la red; si no hay, el Nucleo.
##   - CUANTOS: uno por cada `traffic_sources_per_truck` fuentes, con tope por
##     perfil de dispositivo (`traffic_truck_cap`) y otro de calidad: en
##     calidad Minima, `traffic_truck_cap_minimal` (0 = ninguno).
##   - El ciclo: sale de su extractor cargado (la carga del color del recurso),
##     va por la red al destino, entra a descargar, sale vacio y vuelve a cargar.
##   - La Tormenta: en el Aviso aprietan; en la Ceniza, la Tormenta y el Diezmo
##     se meten donde esten (como la gente) y con la calma vuelven a salir.
##
## Los camiones son datos (TruckActor); los dibuja un solo nodo:
## TrafficFigures3D (un MultiMesh) o TrafficFigures2D (un _draw). Ningun nodo
## ni tween por camion; un solo _process para todos, apagado cuando no hay
## ninguno. Las rutas se calculan al salir (BFS por la red, con cache por par
## de puertas), nunca por fotograma. Puertas, red y rutas: las de WorkerWalkers.

const Walkers := preload("res://scripts/map/WorkerWalkers.gd")
const Truck := preload("res://scripts/map/TruckActor.gd")
const StormCycleScript := preload("res://scripts/storm/StormCycle.gd")
const Figures3D := preload("res://scripts/map/TrafficFigures3D.gd")
const Figures2D := preload("res://scripts/view2d/TrafficFigures2D.gd")
const Tone := preload("res://scripts/buildings/ToyTones.gd")

enum State { INSIDE, DRIVE, HIDING }

const RESCAN_EVERY := 30.0
## Segundos que tarda en meterse dentro el que esta en la carretera con la Ceniza.
const HIDE_TIME := 0.6
## Cuanto entra en el edificio en el tramo de la puerta (como WorkerWalkers).
const DOOR_DEPTH := 0.45

var _is_2d := false
var _layer: Node = null
var _figures: Node = null
var _trucks: Array = []
var _rng := RandomNumberGenerator.new()
var _dirty := true
var _rescan_left := RESCAN_EVERY
var _sheltered := false
var _hurry := false
var _cap := 0
var _net := {}
var _doors := {}       # nodo -> {road, edge} o {}
var _routes := {}      # Vector4i(desde, hasta) -> Array de Vector2
var _sources: Array = []   # [nodo, color de carga]
var _dests: Array = []
## Medida del coste (microsegundos), para la sonda de vida.
var avg_frame_usec := 0.0
var last_reconcile_usec := 0

## `layer`: donde cuelga el dibujo (un Node3D o un Node2D del mundo). Sin capa
## (pruebas) la logica corre igual y no se dibuja nada.
func setup(layer: Node, is_2d: bool) -> void:
	_layer = layer
	_is_2d = is_2d

func _ready() -> void:
	name = "RoadTraffic"
	_rng.randomize()
	_cap = truck_cap()
	EventBus.workers_changed.connect(_mark_dirty)
	EventBus.construction_completed.connect(_mark_dirty)
	EventBus.building_placed.connect(_mark_dirty)
	EventBus.building_demolished.connect(_mark_dirty)
	EventBus.storm_phase_changed.connect(_on_storm_phase)
	EventBus.game_load_completed.connect(_on_load)
	EventBus.graphics_quality_changed.connect(_on_quality)
	_on_load()
	if _layer != null:
		_figures = Figures2D.new() if _is_2d else Figures3D.new()
		_figures.name = "Trucks"
		_layer.add_child(_figures)
		_figures.setup(maxi(1, _cap))

func _mark_dirty(_a: Variant = null, _b: Variant = null) -> void:
	_dirty = true
	set_process(true)

func _on_load() -> void:
	_mark_dirty()
	_apply_storm_phase(StormManager.get_phase())

func _on_quality(_q: Variant = null) -> void:
	_cap = truck_cap()
	_mark_dirty()

# ── Consultas (pruebas y sonda) ─────────────────────────────────────────

func truck_count() -> int:
	return _trucks.size()

## Camiones que se ven ahora mismo en la carretera.
func driving_count() -> int:
	var n := 0
	for t: Truck in _trucks:
		if t.out:
			n += 1
	return n

func trucks() -> Array:
	return _trucks

func is_sheltered() -> bool:
	return _sheltered

func seed_rng(value: int) -> void:
	_rng.seed = value

## El tope de camiones: el del perfil de dispositivo y, en calidad Minima, el
## de la calidad (el menor de los dos). `minimal` < 0: lo que diga
## GraphicsQuality ahora.
static func truck_cap(profile: String = "", minimal: int = -1) -> int:
	var p := profile
	if p == "":
		p = DeviceProfile.current()
	var cap := int(GameConfig.traffic_truck_cap.get(p, GameConfig.traffic_truck_cap.get("pc", 10)))
	var is_min := minimal > 0
	if minimal < 0:
		is_min = preload("res://scripts/services/GraphicsQuality.gd").is_minimal()
	if is_min:
		cap = mini(cap, int(GameConfig.traffic_truck_cap_minimal))
	return maxi(0, cap)

## Cuantos camiones para `sources` extractores con un tope `cap`.
static func truck_budget(sources: int, cap: int, per: int = 0) -> int:
	var k := maxi(1, per if per > 0 else GameConfig.traffic_sources_per_truck)
	return clampi(ceili(float(maxi(0, sources)) / k), 0, maxi(0, cap))

## El color de la carga de lo que produce `data`, o null si no produce nada
## que viaje (decoraciones, casas, el Nucleo). Madera, oro, acero, petroleo y
## comida, en ese orden de preferencia.
static func cargo_color(data: BuildingData) -> Variant:
	if data == null or data.workers_required <= 0 or data.is_core or data.is_decoration:
		return null
	if data.produces_wood > 0:
		return Tone.of("log")
	if data.produces_gold > 0:
		return Tone.of("brass")
	if data.produces_steel > 0:
		return Tone.of("steel")
	if data.produces_oil > 0:
		return Tone.of("iron")
	if data.produces_food > 0:
		return Tone.of("leaf")
	return null

## ¿Es `data` un sitio donde descargar? Los Almacenes (y el Nucleo, aparte).
static func is_depot(data: BuildingData) -> bool:
	return data != null and data.id in GameConfig.traffic_depot_ids

# ── Puertas y rutas ─────────────────────────────────────────────────────

func _door(node: Node) -> Dictionary:
	if not _doors.has(node):
		var d: Dictionary = Walkers.door_of(node, _net) if is_instance_valid(node) else {}
		if not d.is_empty():
			# Un poco menos adentro que la gente: el camion se queda en el portal.
			d = {"road": d["road"], "edge": (Vector2(d["road"]) + Walkers.HALF).lerp(d["edge"], DOOR_DEPTH / Walkers.DOOR_DEPTH)}
		_doors[node] = d
	return _doors[node]

func _road_points(from_cell: Vector2i, to_cell: Vector2i) -> Array:
	var key := Vector4i(from_cell.x, from_cell.y, to_cell.x, to_cell.y)
	if not _routes.has(key):
		var pts: Array = []
		for c in Walkers.route(_net, from_cell, to_cell):
			pts.append(Vector2(c) + Walkers.HALF)
		_routes[key] = pts
	return (_routes[key] as Array).duplicate()

## El destino mas cercano a `source` (por la puerta, en linea recta: barato y
## casi siempre el mismo que por la red).
func _nearest_dest(source: Node) -> Node:
	var sd := _door(source)
	if sd.is_empty():
		return null
	var best: Node = null
	var best_d := INF
	for d in _dests:
		var dd := _door(d)
		if dd.is_empty():
			continue
		var dist := Vector2(sd["road"]).distance_squared_to(Vector2(dd["road"]))
		if dist < best_d:
			best_d = dist
			best = d
	return best

# ── Repaso: cuantos camiones y de donde ─────────────────────────────────

func reconcile() -> void:
	var t0 := Time.get_ticks_usec()
	_dirty = false
	_rescan_left = RESCAN_EVERY
	var buildings := GridManager.get_all_buildings()
	_net = Walkers.network_from(buildings)
	_doors.clear()
	_routes.clear()
	_sources.clear()
	_dests.clear()
	var core: Node = null
	for info in buildings:
		var node: Node = info.get("node")
		var data: BuildingData = info.get("data")
		if node == null or data == null or not is_instance_valid(node):
			continue
		if data.is_core:
			core = node
			continue
		if node.has_meta("under_construction") or _door(node).is_empty():
			continue
		if is_depot(data):
			_dests.append(node)
			continue
		var col: Variant = cargo_color(data)
		if col != null and bool(node.get_meta("staffed", false)) and bool(node.get_meta("connected", true)):
			_sources.append([node, col])
	if _dests.is_empty() and core != null and not _door(core).is_empty():
		_dests.append(core)
	var want := 0 if _dests.is_empty() else truck_budget(_sources.size(), _cap)
	# Los que tienen una fuente que sigue valiendo se quedan; los demas se van.
	var valid := {}
	for s in _sources:
		valid[s[0]] = s[1]
	var kept := 0
	for t: Truck in _trucks:
		if t.gone:
			continue
		if kept >= want or not valid.has(t.source) or not is_instance_valid(t.dest) or not _dests.has(t.dest):
			_drop(t)
			continue
		t.cargo = valid[t.source]
		kept += 1
	_sweep()
	# Faltan: se reparten entre las fuentes que aun no tienen camion.
	if kept < want:
		var busy := {}
		for t: Truck in _trucks:
			busy[t.source] = true
		var order: Array = []
		for s in _sources:
			if not busy.has(s[0]):
				order.append(s)
		for s in _sources:
			if busy.has(s[0]):
				order.append(s)
		var i := 0
		while kept < want and i < order.size():
			_spawn(order[i][0], order[i][1])
			kept += 1
			i += 1
	set_process(not _trucks.is_empty())
	last_reconcile_usec = Time.get_ticks_usec() - t0

func _spawn(source: Node, cargo: Color) -> void:
	var dest := _nearest_dest(source)
	if dest == null:
		return
	var t := Truck.new()
	t.source = source
	t.dest = dest
	t.at = source
	t.state = State.INSIDE
	t.loaded = true
	t.cargo = cargo
	t.timer = _rng.randf_range(0.5, 6.0)
	t.pace = _rng.randf_range(0.9, 1.1)
	var paints: Array = GameConfig.traffic_truck_paints
	t.paint = Tone.of(String(paints[_rng.randi() % paints.size()])) if not paints.is_empty() else Tone.of("red")
	_trucks.append(t)

func _drop(t: Truck) -> void:
	t.gone = true
	t.out = false

func _sweep() -> void:
	_trucks = _trucks.filter(func(t: Truck): return not t.gone)

# ── Paso del tiempo ─────────────────────────────────────────────────────

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	tick(delta)
	if _figures != null:
		_figures.render(_trucks)
	avg_frame_usec = lerpf(avg_frame_usec, float(Time.get_ticks_usec() - t0), 0.05)
	# Sin camiones (ni nada pendiente) no hay nada que mover: fuera el _process.
	if _trucks.is_empty() and not _dirty:
		if _figures != null:
			_figures.render(_trucks)
		set_process(false)

## Un paso del trafico. Publico para las pruebas.
func tick(delta: float) -> void:
	_rescan_left -= delta
	if _dirty or _rescan_left <= 0.0:
		reconcile()
	var speed: float = GameConfig.traffic_speed * (GameConfig.traffic_hurry_multiplier if _hurry else 1.0) * delta
	var any_gone := false
	for t: Truck in _trucks:
		match t.state:
			State.DRIVE:
				_advance(t, speed * t.pace)
			State.INSIDE:
				if not _sheltered:
					t.timer -= delta
					if t.timer <= 0.0:
						_leave(t)
			State.HIDING:
				t.timer -= delta
				t.scale = clampf(t.timer / HIDE_TIME, 0.0, 1.0)
				if t.timer <= 0.0:
					t.state = State.INSIDE
					t.out = false
					t.at = t.dest if t.loaded else t.source
		if t.gone:
			any_gone = true
	if any_gone:
		_sweep()

## Sale de donde esta: cargado hacia el destino, vacio hacia su extractor.
func _leave(t: Truck) -> void:
	var from: Node = t.source if t.loaded else t.dest
	var to: Node = t.dest if t.loaded else t.source
	if not is_instance_valid(from) or not is_instance_valid(to):
		_drop(t)
		return
	var a := _door(from)
	var b := _door(to)
	if a.is_empty() or b.is_empty():
		t.timer = _rng.randf_range(3.0, 6.0)
		return
	var pts := _road_points(a["road"], b["road"])
	if pts.is_empty():
		t.timer = _rng.randf_range(3.0, 6.0)
		return
	pts.push_front(a["edge"])
	pts.append(b["edge"])
	t.pts = pts
	t.seg = 0
	t.f = 0.0
	t.door_out = true
	t.door_in = true
	t.state = State.DRIVE
	t.out = true
	t.at = null
	_pose(t)

func _advance(t: Truck, step: float) -> void:
	var pts := t.pts
	var last := pts.size() - 1
	var left := step
	while left > 0.0:
		if t.seg >= last:
			_arrive(t)
			return
		var p0: Vector2 = pts[t.seg]
		var seg_len := maxf(0.001, p0.distance_to(pts[t.seg + 1]))
		var room := (1.0 - t.f) * seg_len
		if left < room:
			t.f += left / seg_len
			left = 0.0
		else:
			left -= room
			t.seg += 1
			t.f = 0.0
	if t.seg >= last:
		_arrive(t)
		return
	_pose(t)

## Posicion, direccion y escala en su tramo. Circula por su carril (a la
## derecha), y en la puerta encoge y se mete al centro.
func _pose(t: Truck) -> void:
	var pts := t.pts
	var last := pts.size() - 2
	if last < 0:
		return
	var seg := mini(t.seg, last)
	var p0: Vector2 = pts[seg]
	var p1: Vector2 = pts[seg + 1]
	var f := t.f
	var d := p1 - p0
	if d.length_squared() > 0.0001:
		t.dir = d.normalized()
	var s := 1.0
	var lane := 1.0
	if seg == 0 and t.door_out:
		s = lerpf(0.3, 1.0, f)
		lane = f
	if seg == last and t.door_in:
		s = minf(s, lerpf(1.0, 0.3, f))
		lane = minf(lane, 1.0 - f)
	# El carril de la derecha segun hacia donde va: los que se cruzan no se pisan.
	var right := Vector2(-t.dir.y, t.dir.x)
	t.pos = p0.lerp(p1, f) + right * GameConfig.traffic_lane_offset * lane
	t.scale = s

func _arrive(t: Truck) -> void:
	t.state = State.INSIDE
	t.out = false
	t.at = t.dest if t.loaded else t.source
	t.loaded = not t.loaded
	var stay: Vector2 = GameConfig.traffic_stay_unload if not t.loaded else GameConfig.traffic_stay_load
	t.timer = _rng.randf_range(stay.x, stay.y)

# ── La Tormenta ─────────────────────────────────────────────────────────

func _on_storm_phase(phase: int, _left: float) -> void:
	_apply_storm_phase(phase)

func _apply_storm_phase(phase: int) -> void:
	_hurry = phase == StormCycleScript.Phase.WARNING
	var shelter := phase == StormCycleScript.Phase.ASH or phase == StormCycleScript.Phase.STORM \
		or phase == StormCycleScript.Phase.TITHE
	if shelter == _sheltered:
		return
	_sheltered = shelter
	for t: Truck in _trucks:
		if shelter:
			if t.state == State.DRIVE:
				t.state = State.HIDING
				t.timer = HIDE_TIME * clampf(t.scale, 0.2, 1.0)
		elif t.state == State.INSIDE:
			t.timer = _rng.randf_range(1.0, 8.0)
	set_process(true)
