extends Node
## La vida de la ciudad: obreros y ciudadanos que salen de las casas y andan
## por las carreteras (2026-09-28, ampliado 2026-10-04).
##
## Solo es vista: no decide quien trabaja donde (eso es PopulationManager, que
## marca cada edificio con la meta `staffed`) ni viaja en el guardado. Este nodo
## lee la poblacion y esa meta y mueve figuras:
##   - OBREROS: cada uno vive en una casa y tiene su edificio de trabajo, uno con
##     dotacion de verdad. Sale de casa por la puerta, anda por la red hasta la
##     puerta del trabajo, entra (encoge y desaparece), se queda un rato, sale y
##     vuelve a casa. Los retirados, los "sin carretera" y los sin veta no tienen
##     dotacion, asi que nadie va a ellos.
##   - CIUDADANOS: los habitantes sin ocupar. Salen de casa, pasean por la red,
##     se paran delante de una fuente, jardin o estatua, alguno entra al Mercado,
##     y vuelven a casa.
##   - Cuantos: una figura por cada `life_people_per_figure` habitantes, con un
##     tope por perfil de dispositivo (`life_figure_cap`).
##   - La Tormenta: en el Aviso apuran el paso; en la Ceniza, la Tormenta y el
##     Diezmo se meten dentro y las calles quedan vacias; con la calma vuelven a
##     salir poco a poco. De noche (cuando exista) `set_presence()`.
##
## Las figuras son datos (un Actor por figura); las dibuja un solo nodo:
## WalkerFigures3D (un MultiMesh por silueta) o WalkerFigures2D (un _draw).
## Ningun nodo por figura, ningun tween: el coste por fotograma es una cuenta y
## una matriz por figura en la calle. Las rutas se calculan al salir (BFS por la
## red, con cache por par de puertas), nunca por fotograma.

const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const StormCycleScript := preload("res://scripts/storm/StormCycle.gd")
const Figures3D := preload("res://scripts/map/WalkerFigures3D.gd")
const Figures2D := preload("res://scripts/view2d/WalkerFigures2D.gd")
## Una figura (sus campos, en WalkerActor.gd: los comparte con quien la dibuja).
const Actor := preload("res://scripts/map/WalkerActor.gd")

enum Kind { WORKER, MAN, WOMAN, CHILD }
enum State { INSIDE, WALK, IDLE, HIDING }
enum Then { ENTER, LOOK, STROLL }

const ROLE_WORKER := Actor.ROLE_WORKER
const ROLE_CITIZEN := Actor.ROLE_CITIZEN
## Cada cuanto se repasa la ciudad aunque no llegue ninguna senal. Las senales
## (obreros, poblacion, obra acabada, carretera puesta o quitada) repasan al
## momento; esto es solo la red de seguridad, y un repaso con 300 edificios
## cuesta unos milisegundos: no cada pocos segundos.
const RESCAN_EVERY := 30.0
## Segundos que tarda en meterse dentro quien esta en la calle al llegar la Ceniza.
const HIDE_TIME := 0.6
## Cuanto se mete la figura hacia el edificio en el tramo de la puerta (0 = la
## carretera, 1 = el centro de la celda del edificio).
const DOOR_DEPTH := 0.55
const HALF := Vector2(0.5, 0.5)

var _is_2d := false
var _layer: Node = null
var _figures: Node = null
var _actors: Array = []
var _rng := RandomNumberGenerator.new()
var _dirty := true
var _rescan_left := RESCAN_EVERY
var _sheltered := false
var _hurry := false
var _presence := 1.0
## Lo que se calcula al repasar: la red, las puertas y las rutas ya hechas.
var _net := {}
var _net_keys: Array = []
var _doors := {}       # nodo -> {road: Vector2i, edge: Vector2} o {}
var _routes := {}      # Vector4i(desde, hasta) -> Array de Vector2
var _homes: Array = []
var _decos: Array = []
var _markets: Array = []
## Medida del coste (microsegundos del ultimo fotograma, media y el ultimo repaso).
var last_frame_usec := 0
var avg_frame_usec := 0.0
var avg_tick_usec := 0.0
var avg_render_usec := 0.0
var last_reconcile_usec := 0

## `layer`: donde cuelgan las figuras (un Node3D o un Node2D del mundo). Sin
## capa (pruebas) la logica corre igual y no se dibuja nada.
func setup(layer: Node, is_2d: bool) -> void:
	_layer = layer
	_is_2d = is_2d

func _ready() -> void:
	name = "WorkerWalkers"
	_rng.randomize()
	EventBus.workers_changed.connect(_mark_dirty)
	EventBus.population_changed.connect(_mark_dirty)
	EventBus.construction_completed.connect(_mark_dirty)
	EventBus.building_placed.connect(_mark_dirty)
	EventBus.building_demolished.connect(_mark_dirty)
	EventBus.storm_phase_changed.connect(_on_storm_phase)
	EventBus.game_load_completed.connect(_on_load)
	_on_load()
	if _layer != null:
		_figures = Figures2D.new() if _is_2d else Figures3D.new()
		_figures.name = "Figures"
		_layer.add_child(_figures)
		_figures.setup(figure_cap())

func _mark_dirty(_a: Variant = null, _b: Variant = null) -> void:
	_dirty = true

## Lo pasajero se re-deriva al cargar: si se guardo en plena Ceniza, la calle
## arranca vacia.
func _on_load() -> void:
	_dirty = true
	_apply_storm_phase(StormManager.get_phase())

# ── Consultas (pruebas y sonda) ─────────────────────────────────────────

## Figuras que hay (en la calle o dentro).
func actor_count() -> int:
	return _actors.size()

## Figuras que se ven ahora mismo en la calle.
func walker_count() -> int:
	var n := 0
	for a: Actor in _actors:
		if a.out:
			n += 1
	return n

func actors() -> Array:
	return _actors

func is_sheltered() -> bool:
	return _sheltered

func is_hurrying() -> bool:
	return _hurry

## El tope de figuras del perfil de dispositivo actual.
static func figure_cap(profile: String = "") -> int:
	var p := profile
	if p == "":
		p = DeviceProfile.current()
	return int(GameConfig.life_figure_cap.get(p, GameConfig.life_figure_cap.get("pc", 60)))

## Cuantas figuras de cada clase: una por cada `per` personas (obreros por un
## lado, ciudadanos sin ocupar por otro), con el tope; si no caben, a partes
## proporcionales. Devuelve {"workers": int, "citizens": int}.
static func figure_budget(population: int, used_workers: int, cap: int, per: int = 0, presence: float = 1.0) -> Dictionary:
	var k := maxi(1, per if per > 0 else GameConfig.life_people_per_figure)
	var total := mini(cap, ceili(float(maxi(0, population)) / k))
	total = int(round(total * clampf(presence, 0.0, 1.0)))
	var used := clampi(used_workers, 0, maxi(0, population))
	var workers := ceili(float(used) / k)
	var citizens := ceili(float(population - used) / k)
	if workers + citizens > total:
		# Con el tope se reparte en proporcion: ni la calle solo de obreros ni
		# un taller sin nadie que vaya.
		workers = clampi(roundi(float(total) * used / maxf(1.0, population)), mini(1, used), total)
		citizens = total - workers
	return {"workers": workers, "citizens": citizens}

## Semilla fija (pruebas y sonda): la misma ciudad, la misma gente.
func seed_rng(value: int) -> void:
	_rng.seed = value

## El gancho de la noche: la fraccion de gente que sale (1 = toda).
func set_presence(fraction: float) -> void:
	_presence = clampf(fraction, 0.0, 1.0)
	_dirty = true

# ── Puertas y rutas ─────────────────────────────────────────────────────

## La puerta de un edificio: la carretera de la red que toca su huella (la que
## queda mas cerca del centro) y el punto del borde por donde se entra. {} si no
## toca la red. En coordenadas de celda con el centro en +0.5.
static func door_of(node: Node, network: Dictionary) -> Dictionary:
	var info := GridManager.get_building_info(node)
	if info.is_empty():
		return {}
	var cells: Array = info.get("cells", [])
	if cells.is_empty():
		return {}
	var center := Vector2.ZERO
	for c in cells:
		center += Vector2(c)
	center /= cells.size()
	var best := {}
	var best_d := INF
	for c in cells:
		for d in Rules.NEIGHBORS4:
			var r: Vector2i = c + d
			if not network.has(r):
				continue
			# Mas cerca del centro gana; a igualdad, la de menor (y, x): estable.
			var dist := Vector2(r).distance_squared_to(center) + (r.y * 64 + r.x) * 1e-6
			if dist < best_d:
				best_d = dist
				best = {"road": r, "edge": (Vector2(r) + HALF).lerp(Vector2(c) + HALF, DOOR_DEPTH)}
	return best

func _door(node: Node) -> Dictionary:
	if not _doors.has(node):
		_doors[node] = door_of(node, _net) if is_instance_valid(node) else {}
	return _doors[node]

## La red de carreteras unida al Nucleo, en una pasada por los edificios (lo
## mismo que PlacementRules.connected_roads, sin una consulta por celda).
static func network_from(buildings: Array) -> Dictionary:
	var roads := {}
	var core: Array = []
	for info in buildings:
		var data: BuildingData = info.get("data")
		if data == null:
			continue
		if data.id == Rules.ROAD_ID:
			for c in info.get("cells", []):
				roads[c] = true
		elif data.is_core:
			core.append_array(info.get("cells", []))
	var out := {}
	var stack: Array = []
	for c in core:
		for d in Rules.NEIGHBORS4:
			var n: Vector2i = c + d
			if roads.has(n) and not out.has(n):
				out[n] = true
				stack.append(n)
	while not stack.is_empty():
		var cur: Vector2i = stack.pop_back()
		for d in Rules.NEIGHBORS4:
			var n: Vector2i = cur + d
			if roads.has(n) and not out.has(n):
				out[n] = true
				stack.append(n)
	return out

## El camino mas corto por la red entre dos carreteras. [] si no se llega.
static func route(network: Dictionary, from: Vector2i, to: Vector2i) -> Array:
	if not network.has(from) or not network.has(to):
		return []
	if from == to:
		return [from]
	var came := {from: from}
	var queue: Array = [from]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		if cur == to:
			var path: Array = [cur]
			while cur != from:
				cur = came[cur]
				path.append(cur)
			path.reverse()
			return path
		for d in Rules.NEIGHBORS4:
			var n: Vector2i = cur + d
			if network.has(n) and not came.has(n):
				came[n] = cur
				queue.append(n)
	return []

## Los puntos (centros de celda) de la ruta entre dos carreteras, con cache:
## los obreros repiten casa-trabajo y no se recalcula.
func _road_points(from_cell: Vector2i, to_cell: Vector2i) -> Array:
	var key := Vector4i(from_cell.x, from_cell.y, to_cell.x, to_cell.y)
	if not _routes.has(key):
		var pts: Array = []
		for c in route(_net, from_cell, to_cell):
			pts.append(Vector2(c) + HALF)
		_routes[key] = pts
	return (_routes[key] as Array).duplicate()

# ── Repaso: cuantas figuras y a donde ───────────────────────────────────

## Repasa la ciudad y ajusta las figuras a la poblacion y a los edificios con
## dotacion. Lo llama el propio nodo cuando algo cambia; las pruebas, a mano.
func reconcile() -> void:
	var t0 := Time.get_ticks_usec()
	_dirty = false
	_rescan_left = RESCAN_EVERY
	var buildings := GridManager.get_all_buildings()
	_net = network_from(buildings)
	_net_keys = _net.keys()
	_doors.clear()
	_routes.clear()
	_homes.clear()
	_decos.clear()
	_markets.clear()
	var core: Node = null
	var work: Array = []
	for info in buildings:
		var node: Node = info.get("node")
		var data: BuildingData = info.get("data")
		if node == null or data == null or not is_instance_valid(node):
			continue
		if data.id == Rules.ROAD_ID:
			continue
		if data.is_core:
			core = node
			continue
		if node.has_meta("under_construction") or _door(node).is_empty():
			continue
		if data.population_capacity > 0:
			_homes.append(node)
		if data.is_decoration:
			_decos.append(node)
		if data.id == "market":
			_markets.append(node)
		# Solo los edificios con dotacion de verdad reciben obreros. La meta la
		# escribe PopulationManager: sin carretera, retirados o sin veta = false.
		if data.workers_required > 0 and bool(node.get_meta("staffed", false)) \
				and bool(node.get_meta("connected", true)):
			work.append([node, data.workers_required])
	if _homes.is_empty() and core != null and not _door(core).is_empty():
		_homes.append(core)
	if _homes.is_empty():
		for a: Actor in _actors:
			_drop(a)
		_sweep()
		last_reconcile_usec = Time.get_ticks_usec() - t0
		return
	var budget := figure_budget(PopulationManager.get_population(),
		PopulationManager.get_used_workers(), figure_cap(), 0, _presence)
	var n_workers: int = budget["workers"]
	var n_citizens: int = budget["citizens"]
	# Asientos de obrero: por vueltas, para que cada edificio tenga al menos uno
	# antes de que otro tenga dos.
	var per: int = maxi(1, GameConfig.life_people_per_figure)
	var want := {}
	var seats := 0
	var round_i := 0
	var more := true
	while more and seats < n_workers:
		more = false
		for w in work:
			if seats >= n_workers:
				break
			if round_i < ceili(float(w[1]) / per):
				want[w[0]] = int(want.get(w[0], 0)) + 1
				seats += 1
				more = true
		round_i += 1
	# Los que ya tienen un sitio que sigue queriendolos se quedan.
	var citizens := 0
	for a: Actor in _actors:
		if a.retiring:
			continue
		if not is_instance_valid(a.home) or not _homes.has(a.home):
			_rehome(a)
		if a.role == ROLE_WORKER:
			if a.target != null and is_instance_valid(a.target) and int(want.get(a.target, 0)) > 0:
				want[a.target] = int(want[a.target]) - 1
			else:
				_retire(a)
		else:
			citizens += 1
	for t in want:
		for i in int(want[t]):
			_spawn(ROLE_WORKER, t)
	# Ciudadanos: sobran (los de dentro primero) o faltan.
	var extra := citizens - n_citizens
	for pass_i in 2:
		for a: Actor in _actors:
			if extra <= 0:
				break
			if a.role != ROLE_CITIZEN or a.retiring or a.gone:
				continue
			if pass_i == 0 and a.state != State.INSIDE:
				continue
			_retire(a)
			extra -= 1
	for i in maxi(0, -extra):
		_spawn(ROLE_CITIZEN, null)
	_sweep()
	last_reconcile_usec = Time.get_ticks_usec() - t0

func _sweep() -> void:
	_actors = _actors.filter(func(a: Actor): return not a.gone)

func _spawn(role: String, target: Node) -> void:
	var a := Actor.new()
	a.role = role
	a.kind = Kind.WORKER
	if role == ROLE_CITIZEN:
		var r := _rng.randf()
		a.kind = Kind.MAN if r < 0.4 else (Kind.WOMAN if r < 0.8 else Kind.CHILD)
	a.target = target
	a.home = _homes[_rng.randi() % _homes.size()]
	a.at = a.home
	a.state = State.INSIDE
	# Escalonados: no salen todos a la vez de golpe.
	a.timer = _rng.randf_range(0.2, 5.0)
	a.side = _rng.randf_range(-0.22, 0.22)
	a.phase = _rng.randf() * TAU
	a.pace = _rng.randf_range(0.88, 1.12) * (1.15 if a.kind == Kind.CHILD else 1.0)
	_paint(a)
	_actors.append(a)

func _rehome(a: Actor) -> void:
	var old := a.home
	a.home = _homes[_rng.randi() % _homes.size()]
	if a.at == old:
		a.at = a.home

## Sobra: si esta dentro desaparece ya; si esta fuera, vuelve a casa y se va
## al llegar.
func _retire(a: Actor) -> void:
	if a.state == State.INSIDE or a.state == State.HIDING:
		_drop(a)
		return
	a.retiring = true
	a.target = null
	_walk_home_from_here(a)

func _drop(a: Actor) -> void:
	a.gone = true
	a.out = false

# ── Paso del tiempo ─────────────────────────────────────────────────────

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	tick(delta)
	var t1 := Time.get_ticks_usec()
	if _figures != null:
		_figures.render(_actors)
	var t2 := Time.get_ticks_usec()
	last_frame_usec = t2 - t0
	avg_frame_usec = lerpf(avg_frame_usec, float(last_frame_usec), 0.05)
	avg_tick_usec = lerpf(avg_tick_usec, float(t1 - t0), 0.05)
	avg_render_usec = lerpf(avg_render_usec, float(t2 - t1), 0.05)

## Un paso de la ciudad. Publico para las pruebas.
func tick(delta: float) -> void:
	_rescan_left -= delta
	if _dirty or _rescan_left <= 0.0:
		reconcile()
	var speed: float = GameConfig.life_walk_speed * (GameConfig.life_hurry_multiplier if _hurry else 1.0) * delta
	var any_gone := false
	for a: Actor in _actors:
		match a.state:
			State.WALK:
				_advance(a, speed * a.pace)
			State.INSIDE:
				if not _sheltered:
					a.timer -= delta
					if a.timer <= 0.0:
						_leave(a)
			State.IDLE:
				a.timer -= delta
				if a.timer <= 0.0:
					_walk_home_from_here(a)
			State.HIDING:
				a.timer -= delta
				a.scale = clampf(a.timer / HIDE_TIME, 0.0, 1.0)
				if a.timer <= 0.0:
					_arrive_inside(a, a.home)
		if a.gone:
			any_gone = true
	if any_gone:
		_sweep()

func _wait_and_retry(a: Actor) -> void:
	a.timer = _rng.randf_range(3.0, 6.0)

## Sale del edificio donde esta y elige a donde va.
func _leave(a: Actor) -> void:
	var at: Node = a.at if is_instance_valid(a.at) else a.home
	var dest: Node = null
	var then: int = Then.ENTER
	var to_cell := Vector2i.ZERO
	if at != a.home:
		dest = a.home
	elif a.role == ROLE_WORKER:
		dest = a.target
	else:
		var r := _rng.randf()
		if not _decos.is_empty() and r < 0.45:
			dest = _decos[_rng.randi() % _decos.size()]
			then = Then.LOOK
		elif not _markets.is_empty() and r < 0.65:
			dest = _markets[_rng.randi() % _markets.size()]
		else:
			then = Then.STROLL
	var from_door := _door(at) if is_instance_valid(at) else {}
	if from_door.is_empty():
		_wait_and_retry(a)
		return
	var dest_door := {}
	if then == Then.STROLL:
		if _net_keys.is_empty():
			_wait_and_retry(a)
			return
		to_cell = _net_keys[_rng.randi() % _net_keys.size()]
	else:
		if dest == null or not is_instance_valid(dest):
			_wait_and_retry(a)
			return
		dest_door = _door(dest)
		if dest_door.is_empty():
			_wait_and_retry(a)
			return
		to_cell = dest_door["road"]
	var pts := _road_points(from_door["road"], to_cell)
	if pts.is_empty():
		_wait_and_retry(a)
		return
	pts.push_front(from_door["edge"])
	if then == Then.ENTER:
		pts.append(dest_door["edge"])
	elif then == Then.LOOK:
		# Se para delante, a un paso de la puerta: mirando la fuente.
		pts.append((pts[pts.size() - 1] as Vector2).lerp(dest_door["edge"], 0.35))
	_start_walk(a, pts, then, dest, true, then == Then.ENTER)

func _start_walk(a: Actor, pts: Array, then: int, dest: Node, door_out: bool, door_in: bool) -> void:
	if pts.size() < 2:
		pts = [pts[0], pts[0]]
	a.pts = pts
	a.seg = 0
	a.f = 0.0
	a.then = then
	a.dest = dest
	a.door_out = door_out
	a.door_in = door_in
	a.state = State.WALK
	a.out = true
	a.at = null
	_pose(a)

## De vuelta a casa desde donde este (en una carretera o a medio tramo).
func _walk_home_from_here(a: Actor) -> void:
	var hd := _door(a.home) if is_instance_valid(a.home) else {}
	var here := a.pos
	var cell := Vector2i(floori(here.x), floori(here.y))
	if hd.is_empty() or not _net.has(cell):
		# Fuera de la red (la quitaron): se mete donde esta.
		_hide(a)
		return
	var pts := _road_points(cell, hd["road"])
	if pts.is_empty():
		_hide(a)
		return
	pts.push_front(here)
	pts.append(hd["edge"])
	_start_walk(a, pts, Then.ENTER, a.home, false, true)

func _advance(a: Actor, step: float) -> void:
	var pts := a.pts
	var last := pts.size() - 1
	var left := step
	while left > 0.0:
		if a.seg >= last:
			_arrive(a)
			return
		var p0: Vector2 = pts[a.seg]
		var seg_len := maxf(0.001, p0.distance_to(pts[a.seg + 1]))
		var room := (1.0 - a.f) * seg_len
		if left < room:
			a.f += left / seg_len
			a.phase += left * TAU
			left = 0.0
		else:
			a.phase += room * TAU
			left -= room
			a.seg += 1
			a.f = 0.0
	if a.seg >= last:
		_arrive(a)
		return
	_pose(a)

## Posicion, direccion y escala en su tramo (la puerta encoge y agranda).
func _pose(a: Actor) -> void:
	var pts := a.pts
	var last := pts.size() - 2
	var seg := mini(a.seg, last)
	var p0: Vector2 = pts[seg]
	var p1: Vector2 = pts[seg + 1]
	var f := a.f
	var dir := p1 - p0
	if dir.length_squared() > 0.0001:
		a.dir = dir.normalized()
	var s := 1.0
	var lane := 1.0
	if seg == 0 and a.door_out:
		s = lerpf(0.25, 1.0, f)
		lane = f
	if seg == last and a.door_in:
		s = minf(s, lerpf(1.0, 0.25, f))
		lane = minf(lane, 1.0 - f)
	a.pos = p0.lerp(p1, f) + Vector2(-a.dir.y, a.dir.x) * a.side * lane
	a.scale = s

func _arrive(a: Actor) -> void:
	a.seg = maxi(0, a.pts.size() - 2)
	a.f = 1.0
	_pose(a)
	match a.then:
		Then.ENTER:
			_arrive_inside(a, a.dest)
		Then.LOOK:
			a.state = State.IDLE
			a.timer = _rng.randf_range(GameConfig.life_pause_decoration.x, GameConfig.life_pause_decoration.y)
			if is_instance_valid(a.dest) and not _door(a.dest).is_empty():
				var to: Vector2 = Vector2(_door(a.dest)["edge"]) - a.pos
				if to.length_squared() > 0.0001:
					a.dir = to.normalized()
		_:
			a.state = State.IDLE
			a.timer = _rng.randf_range(GameConfig.life_pause_stroll.x, GameConfig.life_pause_stroll.y)

func _arrive_inside(a: Actor, where: Node) -> void:
	if a.retiring:
		_drop(a)
		return
	var node: Node = where if (where != null and is_instance_valid(where)) else a.home
	a.state = State.INSIDE
	a.out = false
	a.at = node
	var stay: Vector2 = GameConfig.life_stay_home
	if node != a.home:
		stay = GameConfig.life_stay_work if a.role == ROLE_WORKER else GameConfig.life_stay_market
	a.timer = _rng.randf_range(stay.x, stay.y)

## Se mete dentro donde este (Ceniza, o se quedo sin red).
func _hide(a: Actor) -> void:
	a.state = State.HIDING
	a.timer = HIDE_TIME * clampf(a.scale, 0.2, 1.0)

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
	for a: Actor in _actors:
		if shelter:
			if a.state == State.WALK or a.state == State.IDLE:
				_hide(a)
		elif a.state == State.INSIDE:
			# Pasado el Diezmo salen poco a poco, no todos de golpe.
			a.timer = _rng.randf_range(0.5, 8.0)

# ── Paleta ──────────────────────────────────────────────────────────────

const PAL := {
	Kind.WORKER: [[Color(0.22, 0.32, 0.52), Color(0.36, 0.30, 0.22), Color(0.30, 0.33, 0.30), Color(0.42, 0.26, 0.18)],
		[Color(0.92, 0.72, 0.18), Color(0.85, 0.48, 0.14), Color(0.72, 0.60, 0.32)]],
	Kind.MAN: [[Color(0.20, 0.30, 0.22), Color(0.36, 0.24, 0.16), Color(0.22, 0.22, 0.25), Color(0.45, 0.16, 0.16), Color(0.30, 0.34, 0.42)],
		[Color(0.10, 0.09, 0.08), Color(0.32, 0.22, 0.14), Color(0.42, 0.42, 0.40)]],
	Kind.WOMAN: [[Color(0.62, 0.16, 0.18), Color(0.72, 0.56, 0.20), Color(0.16, 0.42, 0.42), Color(0.40, 0.20, 0.42), Color(0.55, 0.36, 0.20)],
		[Color(0.20, 0.12, 0.08), Color(0.08, 0.07, 0.06), Color(0.52, 0.22, 0.10), Color(0.80, 0.66, 0.36)]],
	Kind.CHILD: [[Color(0.78, 0.24, 0.20), Color(0.24, 0.44, 0.70), Color(0.30, 0.58, 0.28), Color(0.82, 0.62, 0.18)],
		[Color(0.20, 0.12, 0.08), Color(0.46, 0.30, 0.16), Color(0.86, 0.80, 0.70)]],
}

## Colores de la figura: cuerpo y accesorio de la paleta de su silueta, con un
## pelin de variacion para que dos iguales no se vean clonadas, y tono de piel.
func _paint(a: Actor) -> void:
	var p: Array = PAL[a.kind]
	var bodies: Array = p[0]
	var accents: Array = p[1]
	var body: Color = bodies[_rng.randi() % bodies.size()]
	var k := _rng.randf_range(0.88, 1.12)
	a.body = Color(clampf(body.r * k, 0.0, 1.0), clampf(body.g * k, 0.0, 1.0), clampf(body.b * k, 0.0, 1.0))
	a.accent = accents[_rng.randi() % accents.size()]
	a.skin = _rng.randf()
