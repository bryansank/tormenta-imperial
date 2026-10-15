extends Node2D
## La bandera del pais en la vista 2D, sobre el Nucleo, el Cuartel General y
## los dibujos con mastil (el mastil y el letrero de la colonia).
## Se dibuja con la textura cacheada de ColonyFlag y solo se repinta al oir
## colony_identity_changed o cuando su edificio cambia de giro o de nivel
## (`set_mount`): nada por frame. En el Cuartel General no se ve mientras esta
## en obra.
##
## Como en 3D (FlagAnchor de la receta), la bandera cuelga del mastil del
## PROPIO edificio: en el Nucleo sale de lo alto de la linterna; en el Cuartel
## General, de la esquina delantera derecha del tejado
## (BuildingArt2D.flag_mount). El palo lo pinta este nodo (no se hornea con el
## edificio: es lo mas alto y se saldria del margen de la cache). Sin montura
## (pruebas, `setup` a secas) pone su mastil de reserva en el borde derecho.

const ColonyFlag := preload("res://scripts/ui/ColonyFlag.gd")
const ColonyFlag3D := preload("res://scripts/buildings/ColonyFlag3D.gd")

var _footprint := Vector2(64, 64)
var _owner_node: Node = null
## Mastil del edificio: base (marco del nodo, ya girada), alto hacia arriba en
## pantalla y ancho de la bandera. Vacio = mastil de reserva.
var _mount: Dictionary = {}

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

## El mastil del dibujo del edificio (BuildingArt2D.flag_mount). Solo repinta
## si cambio.
func set_mount(mount: Dictionary) -> void:
	if mount == _mount:
		return
	_mount = mount
	queue_redraw()

func get_mount() -> Dictionary:
	return _mount

func _ready() -> void:
	EventBus.colony_identity_changed.connect(func(_n, _s): queue_redraw())
	EventBus.construction_completed.connect(func(_b): _sync_visible.call_deferred())
	EventBus.construction_started.connect(func(_b): _sync_visible.call_deferred())
	EventBus.game_load_completed.connect(func(): _sync_visible.call_deferred())

func _sync_visible() -> void:
	if _owner_node != null and is_instance_valid(_owner_node):
		visible = not ColonyFlag3D.is_hidden_by_works(_owner_node)

func _draw() -> void:
	var base: Vector2
	var top: Vector2
	var flag_w: float
	if _mount.is_empty():
		# Reserva: mastil en el borde derecho (el origen es el centro del
		# edificio), asomando por arriba.
		flag_w = _footprint.x * 0.42
		base = Vector2(_footprint.x * 0.42, -_footprint.y * 0.18)
		top = base + Vector2(0, -_footprint.y * 0.55)
	else:
		flag_w = float(_mount["flag_w"])
		base = _mount["base"]
		top = base + Vector2(0, -float(_mount["height"]))
	var flag_h := flag_w * float(ColonyFlag.H) / float(ColonyFlag.W)
	# Sombra del palo en el suelo (luz de arriba-izquierda), el palo y su pomo.
	draw_line(base, base + Vector2(0.55, 0.8) * (base.distance_to(top) * 0.3), Color(0.14, 0.07, 0.03, 0.22), 2.0)
	draw_line(base, top, Color(0.13, 0.09, 0.08, 0.95), 3.2)
	draw_line(base, top, Color(0.75, 0.62, 0.3), 1.6)
	draw_circle(top, 2.4, Color(0.13, 0.09, 0.08, 0.95))
	draw_circle(top, 1.7, Color(0.98, 0.82, 0.47))
	# Con montura la bandera cuelga hacia la derecha de la pantalla (como la
	# 3D, hacia +X); la de reserva, hacia dentro para no salirse de la huella.
	var rect := Rect2(top + Vector2(1.0, 1.0), Vector2(flag_w, flag_h)) if not _mount.is_empty() \
		else Rect2(top + Vector2(-flag_w, 0), Vector2(flag_w, flag_h))
	draw_rect(rect.grow(0.8), Color(0.13, 0.09, 0.08, 0.9), false, 1.2)
	ColonyFlag.draw_spec(self, rect, RankManager.get_flag_spec())

func flag_spec_key() -> String:
	return ColonyFlag.spec_key(RankManager.get_flag_spec())
