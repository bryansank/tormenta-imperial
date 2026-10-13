extends Node2D
## La bandera del pais en la vista 2D, sobre el Nucleo y el Cuartel General: un
## mastil corto en la esquina con la bandera elegida. Se dibuja con la textura
## cacheada de ColonyFlag y solo se repinta al oir colony_identity_changed (nada
## por frame). En el Cuartel General no se ve mientras esta en obra.

const ColonyFlag := preload("res://scripts/ui/ColonyFlag.gd")
const ColonyFlag3D := preload("res://scripts/buildings/ColonyFlag3D.gd")

var _footprint := Vector2(64, 64)
var _owner_node: Node = null

static func flies_over(data: BuildingData) -> bool:
	return ColonyFlag.flies_over(data)

## `footprint` en pixeles (la huella del edificio); `building` = su nodo.
func setup(footprint: Vector2, building: Node = null) -> void:
	name = "ColonyFlag"
	_footprint = footprint
	_owner_node = building
	z_index = 8
	queue_redraw()
	_sync_visible.call_deferred()

func _ready() -> void:
	EventBus.colony_identity_changed.connect(func(_n, _s): queue_redraw())
	EventBus.construction_completed.connect(func(_b): _sync_visible.call_deferred())
	EventBus.construction_started.connect(func(_b): _sync_visible.call_deferred())
	EventBus.game_load_completed.connect(func(): _sync_visible.call_deferred())

func _sync_visible() -> void:
	if _owner_node != null and is_instance_valid(_owner_node):
		visible = not ColonyFlag3D.is_hidden_by_works(_owner_node)

func _draw() -> void:
	var flag_w := _footprint.x * 0.42
	var flag_h := flag_w * float(ColonyFlag.H) / float(ColonyFlag.W)
	# Mastil en el borde derecho (el origen es el centro del edificio), asomando
	# por arriba; la bandera se cuelga hacia dentro para no salirse de la huella.
	var base := Vector2(_footprint.x * 0.42, -_footprint.y * 0.18)
	var top := base + Vector2(0, -_footprint.y * 0.55)
	draw_line(base, top, Color(0.25, 0.2, 0.12), 3.0)
	draw_line(base, top, Color(0.75, 0.62, 0.3), 1.5)
	draw_circle(top, 2.5, Color(0.75, 0.62, 0.3))
	ColonyFlag.draw_spec(self, Rect2(top + Vector2(-flag_w, 0), Vector2(flag_w, flag_h)), RankManager.get_flag_spec())

func flag_spec_key() -> String:
	return ColonyFlag.spec_key(RankManager.get_flag_spec())
