extends Control
## La flecha del tutorial: un triangulo de laton con contorno oscuro que apunta
## en `direction` y se mece hacia su objetivo. Dibujada, sin imagen. El control
## mide lo que la flecha; quien la coloca pone su punta en `tip_at`.

var direction := Vector2.DOWN
var color: Color = UITheme.ACCENT
var outline: Color = UITheme.OUTLINE_COLOR
var _t := 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(44, 44)
	size = Vector2(44, 44)

## Pone la punta de la flecha en `point` (coordenadas del padre), apuntando en
## `dir` (se normaliza).
func point_at(point: Vector2, dir: Vector2) -> void:
	direction = dir.normalized() if dir.length() > 0.01 else Vector2.DOWN
	var half := size * 0.5
	# El centro de la flecha queda detras de la punta, a media flecha.
	position = point - direction * half.y - half
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var bob := sin(_t * 5.0) * 5.0
	var d := direction
	var n := Vector2(-d.y, d.x)
	var tip := c + d * (size.y * 0.5 - 2.0) + d * bob
	var base := tip - d * 24.0
	var tri := PackedVector2Array([tip, base + n * 14.0, base - n * 14.0])
	var shaft := PackedVector2Array([
		base + n * 5.0, base - n * 5.0,
		base - n * 5.0 - d * 16.0, base + n * 5.0 - d * 16.0,
	])
	draw_colored_polygon(shaft, outline)
	draw_colored_polygon(tri, outline)
	var tri_in := PackedVector2Array([tip - d * 3.0, base + n * 10.5 + d * 1.5, base - n * 10.5 + d * 1.5])
	var shaft_in := PackedVector2Array([
		base + n * 3.0, base - n * 3.0,
		base - n * 3.0 - d * 14.0, base + n * 3.0 - d * 14.0,
	])
	draw_colored_polygon(shaft_in, color)
	draw_colored_polygon(tri_in, color)
