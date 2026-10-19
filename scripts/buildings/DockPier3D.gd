extends Node3D
## El embarcadero del Muelle de pesca en 3D (fix/peces-en-el-mar): una pasarela
## de tablas sobre pilotes desde la costa hasta su banco de peces, mar adentro.
## Solo dibujo: las celdas las da MapGenerator.pier_path() (las mismas que la
## vista 2D, DockPier2D) y no ocupan la rejilla.
##
## Coste: una tabla larga y un par de pilotes por celda de agua (como mucho
## tres), con mallas y material compartidos por todos los muelles. Se rehace
## solo cuando cambia la rejilla (colocar, mover, cargar), con un aviso diferido
## por fotograma como mucho; ni _process ni sombras.

const DECK_Y := -0.3          # Encima del agua (WATER_Y = -0.5), por debajo del cesped
const DECK_THICK := 0.1
const DECK_WIDTH := 0.62      # Fraccion de la celda
const POST_BOTTOM := -0.75
const POST_RADIUS := 0.07
const WOOD := Color(0.62, 0.43, 0.26)
const WOOD_DARK := Color(0.36, 0.23, 0.13)

static var _deck_mat: StandardMaterial3D = null
static var _post_mat: StandardMaterial3D = null
static var _post_mesh: CylinderMesh = null

var _building: Node3D = null
var _queued := false
var _key := ""

func setup(building: Node3D) -> void:
	_building = building
	name = "DockPier"
	top_level = true
	for sig in [EventBus.building_placed, EventBus.building_moved, EventBus.game_load_completed]:
		(sig as Signal).connect(_queue)
	_queue()

func _queue(_a = null, _b = null) -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	_rebuild.call_deferred()

func _enter_tree() -> void:
	if _building != null:
		_queue()

## Las celdas del embarcadero ahora mismo ({"cells": []} si no hay).
func current_path() -> Dictionary:
	if _building == null or not is_instance_valid(_building):
		return {"cells": []}
	var info: Dictionary = GridManager.get_building_info(_building)
	var scene := get_tree().current_scene if is_inside_tree() else null
	var map_gen: Node = scene.get_node_or_null("MapGenerator") if scene != null else null
	if info.is_empty() or map_gen == null or not map_gen.has_method("pier_path"):
		return {"cells": []}
	return map_gen.pier_path(info["cells"])

func _rebuild() -> void:
	_queued = false
	if not is_inside_tree():
		return
	var path := current_path()
	var cells: Array = path.get("cells", [])
	var key := str(cells)
	if key == _key:
		return
	_key = key
	for child in get_children():
		child.queue_free()
	global_transform = Transform3D.IDENTITY
	if cells.is_empty():
		return
	_ensure_shared()
	var cs: float = GridManager.cell_size
	var from: Vector2i = path["from"]
	var to: Vector2i = path["to"]
	var step := Vector2(to - from)
	step /= maxf(absf(step.x), absf(step.y))
	var a3: Vector3 = GridManager.cell_to_world(from)
	var b3: Vector3 = GridManager.cell_to_world(to)
	var a := Vector2(a3.x, a3.z) + step * cs * 0.5
	var b := Vector2(b3.x, b3.z) - step * cs * 0.5
	var length := a.distance_to(b)
	var deck := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(cs * DECK_WIDTH, DECK_THICK, length + cs * 0.15)
	deck.mesh = box
	deck.material_override = _deck_mat
	deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mid := (a + b) * 0.5
	deck.position = Vector3(mid.x, DECK_Y, mid.y)
	deck.rotation.y = atan2(b.x - a.x, b.y - a.y)
	add_child(deck)
	# Dos pilotes por celda, a los lados de la tabla.
	var side := Vector2(-step.y, step.x).normalized() * cs * DECK_WIDTH * 0.5
	for cell in cells:
		var c3: Vector3 = GridManager.cell_to_world(cell)
		for sgn: float in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			post.mesh = _post_mesh
			post.material_override = _post_mat
			post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var p: Vector2 = Vector2(c3.x, c3.z) + side * float(sgn)
			post.position = Vector3(p.x, (DECK_Y + 0.08 + POST_BOTTOM) * 0.5, p.y)
			add_child(post)

static func _ensure_shared() -> void:
	if _deck_mat != null:
		return
	_deck_mat = StandardMaterial3D.new()
	_deck_mat.albedo_color = WOOD
	_deck_mat.roughness = 0.9
	_post_mat = StandardMaterial3D.new()
	_post_mat.albedo_color = WOOD_DARK
	_post_mat.roughness = 0.95
	_post_mesh = CylinderMesh.new()
	_post_mesh.top_radius = POST_RADIUS
	_post_mesh.bottom_radius = POST_RADIUS
	_post_mesh.height = (DECK_Y + 0.08) - POST_BOTTOM
	_post_mesh.radial_segments = 6
	_post_mesh.rings = 1
