extends Node2D
## La bandera de la colonia sobre el Nucleo en la vista 2D: un mastil corto en la
## esquina con la bandera elegida. Se repinta al oir colony_cosmetics_changed.

const ColonyFlag := preload("res://scripts/ui/ColonyFlag.gd")

var _footprint := Vector2(64, 64)

## `footprint` en pixeles (la huella del Nucleo).
func setup(footprint: Vector2) -> void:
	name = "ColonyFlag"
	_footprint = footprint
	z_index = 8
	queue_redraw()

func _ready() -> void:
	EventBus.colony_cosmetics_changed.connect(func(_f, _c): queue_redraw())

func _draw() -> void:
	var tex := ColonyFlag.current_texture()
	var flag_w := _footprint.x * 0.42
	var flag_h := flag_w * float(ColonyFlag.H) / float(ColonyFlag.W)
	# Mastil en el borde derecho (el origen es el centro del Nucleo), asomando por
	# arriba; la bandera se cuelga hacia dentro para no salirse de la huella.
	var base := Vector2(_footprint.x * 0.42, -_footprint.y * 0.18)
	var top := base + Vector2(0, -_footprint.y * 0.55)
	draw_line(base, top, Color(0.25, 0.2, 0.12), 3.0)
	draw_line(base, top, Color(0.75, 0.62, 0.3), 1.5)
	draw_texture_rect(tex, Rect2(top + Vector2(-flag_w, 0), Vector2(flag_w, flag_h)), false)
