extends Node2D
## El embarcadero del Muelle de pesca en 2D (fix/peces-en-el-mar): la pasarela
## de tablas desde la costa hasta su banco de peces, mar adentro. Las celdas son
## las de la 3D (MapGenerator.pier_path, DockPier3D). Solo dibujo: un _draw que
## se repite solo cuando cambia la rejilla (colocar, mover, cargar); sin _process.

const View2D := preload("res://scripts/view2d/View2D.gd")

const DECK := Color8(212, 152, 92)        # WOOD claro, como la tarima del muelle
const DECK_LINE := Color8(150, 98, 56)
const POST := Color8(104, 62, 34)         # WOOD oscuro
const OUTLINE := Color(0.13, 0.09, 0.08, 0.95)
const DECK_WIDTH := 0.5                   # Fraccion de la celda

var _building: Node = null
var _queued := false
var _path: Dictionary = {"cells": []}

func setup(building: Node) -> void:
	_building = building
	name = "DockPier"
	top_level = true
	# Debajo del edificio (z 2) y encima del agua y de los bancos.
	z_index = 1
	for sig in [EventBus.building_placed, EventBus.building_moved, EventBus.game_load_completed]:
		(sig as Signal).connect(_queue)
	_queue()

func _queue(_a = null, _b = null) -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	_refresh.call_deferred()

func _enter_tree() -> void:
	if _building != null:
		_queue()

func current_path() -> Dictionary:
	if _building == null or not is_instance_valid(_building) or not is_inside_tree():
		return {"cells": []}
	var info: Dictionary = GridManager.get_building_info(_building)
	var scene := get_tree().current_scene
	var map_gen: Node = scene.get_node_or_null("MapGenerator") if scene != null else null
	if info.is_empty() or map_gen == null or not map_gen.has_method("pier_path"):
		return {"cells": []}
	return map_gen.pier_path(info["cells"])

func _refresh() -> void:
	_queued = false
	if not is_inside_tree():
		return
	var path := current_path()
	if str(path.get("cells", [])) == str(_path.get("cells", [])):
		return
	_path = path
	global_transform = Transform2D.IDENTITY
	queue_redraw()

func _draw() -> void:
	var cells: Array = _path.get("cells", [])
	if cells.is_empty():
		return
	var cpx: float = View2D.cell_px()
	var from: Vector2i = _path["from"]
	var to: Vector2i = _path["to"]
	var step := Vector2(to - from)
	step /= maxf(absf(step.x), absf(step.y))
	var a: Vector2 = View2D.footprint_center_px(from, Vector2i.ONE) + step * cpx * 0.5
	var b: Vector2 = View2D.footprint_center_px(to, Vector2i.ONE) - step * cpx * 0.5
	var w: float = cpx * DECK_WIDTH
	var dir := (b - a).normalized()
	var side := Vector2(-dir.y, dir.x) * w * 0.5
	# Pilotes a los lados (asoman bajo la tabla).
	for cell in cells:
		var c: Vector2 = View2D.footprint_center_px(cell, Vector2i.ONE)
		for sgn: float in [-1.0, 1.0]:
			draw_circle(c + side * sgn * 1.08, cpx * 0.07, POST)
	draw_line(a, b, OUTLINE, w + 2.0)
	draw_line(a, b, DECK, w)
	# Las juntas de las tablas, de lado a lado.
	var length := a.distance_to(b)
	var n := maxi(2, int(length / (cpx * 0.22)))
	for i in range(1, n):
		var p := a.lerp(b, float(i) / float(n))
		draw_line(p - side * 0.9, p + side * 0.9, DECK_LINE, 1.0)
