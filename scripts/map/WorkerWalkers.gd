extends Node
## Trabajadores que se ven: munecos que salen del Nucleo y van andando por las
## carreteras hasta el edificio donde trabajan (2026-09-28).
##
## Solo es vista: no decide quien trabaja donde (eso es PopulationManager, que
## marca cada edificio con la meta `staffed`). Este nodo mira esa meta:
##   - cuando un edificio pasa a tener dotacion, salen tantos munecos como
##     trabajadores pide, uno detras de otro;
##   - cada SHIFT_EVERY segundos un edificio con dotacion recibe a uno mas (el
##     cambio de turno), para que la isla no se quede quieta.
## Cada muneco sigue la ruta por carretera que da PlacementRules.walk_route y
## desaparece al llegar. Vale para las dos vistas: en 3D es una figura de
## mallas, en 2D un dibujo; la ruta y el paso son los mismos.

const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const View2D := preload("res://scripts/view2d/View2D.gd")

const MAX_WALKERS := 24
## Celdas por segundo.
const SPEED := 1.8
const SHIFT_EVERY := 25.0
## Segundos entre un muneco y el siguiente del mismo grupo.
const STAGGER := 0.45

var _is_2d := false
var _layer: Node = null
var _walkers: Array = []   # {node, path: Array[Vector2i], t: float, side: float}
var _staffed := {}         # edificio -> bool (lo ultimo visto)
var _queue: Array = []     # {target, delay}
var _shift_left := SHIFT_EVERY
var _rng := RandomNumberGenerator.new()

## `layer`: donde cuelgan los munecos (un Node3D o un Node2D del mundo).
func setup(layer: Node, is_2d: bool) -> void:
	_layer = layer
	_is_2d = is_2d

func _ready() -> void:
	name = "WorkerWalkers"
	_rng.randomize()
	EventBus.workers_changed.connect(func(_u, _t): _scan())
	EventBus.construction_completed.connect(func(_n): _scan())
	EventBus.game_load_completed.connect(_scan)

func walker_count() -> int:
	return _walkers.size()

## Mira que edificios acaban de quedar con dotacion y les manda su gente.
func _scan() -> void:
	var now := {}
	for info in GridManager.get_all_buildings():
		var node: Node = info.get("node")
		var data: BuildingData = info.get("data")
		if node == null or data == null or data.workers_required <= 0:
			continue
		var staffed: bool = bool(node.get_meta("staffed", false))
		now[node] = staffed
		if staffed and not bool(_staffed.get(node, false)):
			for i in data.workers_required:
				_queue.append({"target": node, "delay": i * STAGGER})
	_staffed = now

func _process(delta: float) -> void:
	if _layer == null or not is_instance_valid(_layer):
		return
	# Salidas pendientes
	for i in range(_queue.size() - 1, -1, -1):
		var q: Dictionary = _queue[i]
		q["delay"] = float(q["delay"]) - delta
		if float(q["delay"]) <= 0.0:
			_queue.remove_at(i)
			send_walker(q["target"])
	# Cambio de turno
	_shift_left -= delta
	if _shift_left <= 0.0:
		_shift_left = SHIFT_EVERY
		var staffed: Array = []
		for n in _staffed:
			if is_instance_valid(n) and bool(_staffed[n]):
				staffed.append(n)
		if not staffed.is_empty():
			send_walker(staffed[_rng.randi() % staffed.size()])
	# Andar
	for i in range(_walkers.size() - 1, -1, -1):
		var w: Dictionary = _walkers[i]
		var node: Node = w["node"]
		var path: Array = w["path"]
		w["t"] = float(w["t"]) + delta * SPEED
		var t: float = w["t"]
		if not is_instance_valid(node) or t >= float(path.size() - 1):
			if is_instance_valid(node):
				node.queue_free()
			_walkers.remove_at(i)
			continue
		var k := int(floor(t))
		var a: Vector2i = path[k]
		var b: Vector2i = path[mini(k + 1, path.size() - 1)]
		_place(node, a, b, t - k, float(w["side"]), t)

## Manda un muneco del Nucleo a `target`. Devuelve el muneco o null (sin ruta,
## o ya hay demasiados).
func send_walker(target: Node) -> Node:
	if _walkers.size() >= MAX_WALKERS or not is_instance_valid(target):
		return null
	var path: Array = Rules.walk_route(target)
	if path.size() < 2:
		return null
	var node := _make_figure()
	_layer.add_child(node)
	var w := {"node": node, "path": path, "t": 0.0, "side": _rng.randf_range(-0.25, 0.25)}
	_walkers.append(w)
	_place(node, path[0], path[1], 0.0, float(w["side"]), 0.0)
	return node

func _place(node: Node, a: Vector2i, b: Vector2i, f: float, side: float, t: float) -> void:
	var dir := Vector2(b - a)
	var perp := Vector2(-dir.y, dir.x) * side
	var cell := Vector2(a).lerp(Vector2(b), f) + perp + Vector2(0.5, 0.5)
	if _is_2d:
		var px := View2D.cell_px()
		(node as Node2D).position = View2D.cell_origin_px(Vector2i.ZERO) + cell * px
	else:
		var origin: Vector3 = GridManager.get_origin()
		var cs: float = GridManager.cell_size
		var bob := absf(sin(t * PI * 2.0)) * 0.08
		(node as Node3D).position = Vector3(origin.x + cell.x * cs, bob, origin.z + cell.y * cs)
		if dir != Vector2.ZERO:
			(node as Node3D).rotation.y = atan2(dir.x, dir.y)

# ── Figuras ────────────────────────────────────────────────────────────

const OVERALLS := Color(0.22, 0.32, 0.52)
const SKIN := Color(0.86, 0.68, 0.52)
const HELMET := Color(0.92, 0.72, 0.18)

func _make_figure() -> Node:
	if _is_2d:
		return Walker2D.new()
	var root := Node3D.new()
	root.name = "Worker"
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.16
	cap.height = 0.62
	body.mesh = cap
	body.position.y = 0.31
	body.material_override = _mat(OVERALLS)
	root.add_child(body)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	head.mesh = sphere
	head.position.y = 0.74
	head.material_override = _mat(SKIN)
	root.add_child(head)
	var helmet := MeshInstance3D.new()
	var hat := CylinderMesh.new()
	hat.top_radius = 0.1
	hat.bottom_radius = 0.15
	hat.height = 0.08
	helmet.mesh = hat
	helmet.position.y = 0.86
	helmet.material_override = _mat(HELMET)
	root.add_child(helmet)
	return root

static var _mats := {}

static func _mat(c: Color) -> StandardMaterial3D:
	if not _mats.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.8
		_mats[c] = m
	return _mats[c]

## El muneco en la vista 2D: cuerpo, cabeza y casco, visto desde arriba.
class Walker2D extends Node2D:
	func _ready() -> void:
		z_index = 30
	func _draw() -> void:
		var r := 3.2
		draw_circle(Vector2(0, 1.5), r + 1.2, Color(0, 0, 0, 0.35))
		draw_circle(Vector2(0, 1.0), r, Color(0.22, 0.32, 0.52))
		draw_circle(Vector2(0, -1.2), r * 0.62, Color(0.92, 0.72, 0.18))
