extends Control
## El dibujo 2D de un edificio dentro de un Control: la miniatura y la vista
## previa del menu de construccion en la vista 2D. Es el mismo BuildingArt2D que
## pinta el mapa, escalado para caber, asi que lo que se elige en el menu es lo
## que aparece en el suelo.

const Art := preload("res://scripts/view2d/BuildingArt2D.gd")
const View2D := preload("res://scripts/view2d/View2D.gd")

var data: BuildingData = null:
	set(value):
		data = value
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if data == null:
		return
	var art := Vector2(data.grid_size) * View2D.cell_px()
	var fit := minf(size.x / art.x, size.y / art.y) * 0.9
	draw_set_transform(size * 0.5, 0.0, Vector2(fit, fit))
	Art.draw_building(self, data.id, art, {"road_mask": 10 if data.id == "road" else 0})
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
