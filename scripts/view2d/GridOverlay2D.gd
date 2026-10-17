extends Node2D
## La rejilla de celdas en la vista 2D. Mismas reglas que GridOverlayControl:
## visible segun GameConfig.ui_grid_visible (interruptor de Ajustes, senal
## grid_overlay_toggled) y el colocador la fuerza visible mientras se coloca.
## Se llama "GridOverlay" en la escena para que el colocador la encuentre igual
## que en 3D. Medida desde GridManager, nunca a mano.

const View2D := preload("res://scripts/view2d/View2D.gd")
## En calidad Minima la rejilla "siempre visible" no se pinta (docs/26 §7.1).
const GraphicsQuality := preload("res://scripts/services/GraphicsQuality.gd")

## Tenue (arte, 2026-10-05): solo se ve al colocar o mover, salvo que el
## jugador la deje siempre en Ajustes; tiene que ayudar a encajar, no pintar
## una malla sobre el cesped.
const LINE := Color(0.95, 0.95, 0.85, 0.08)
const LINE_MAJOR := Color(0.95, 0.92, 0.78, 0.14)
const BORDER := Color(0.95, 0.85, 0.55, 0.25)

func _ready() -> void:
	z_index = -10
	visible = GraphicsQuality.grid_always_visible()
	EventBus.grid_overlay_toggled.connect(func(vis: bool): visible = vis)
	EventBus.grid_resized.connect(_on_grid_resized)
	queue_redraw()

func _on_grid_resized(_w: int, _h: int) -> void:
	queue_redraw()

func _draw() -> void:
	var cs := View2D.cell_px()
	var origin := View2D.cell_origin_px(Vector2i.ZERO)
	var w := GridManager.grid_width
	var h := GridManager.grid_height
	if GridManager.is_irregular():
		_draw_on_land(origin, cs, w, h)
		return
	for x in range(w + 1):
		var col := LINE_MAJOR if x % 5 == 0 else LINE
		draw_line(origin + Vector2(x * cs, 0), origin + Vector2(x * cs, h * cs), col, 1.0)
	for y in range(h + 1):
		var col := LINE_MAJOR if y % 5 == 0 else LINE
		draw_line(origin + Vector2(0, y * cs), origin + Vector2(w * cs, y * cs), col, 1.0)
	draw_rect(Rect2(origin, Vector2(w, h) * cs), BORDER, false, 2.0)

## Isla irregular: solo los lados de celda que tocan tierra (y el borde
## tierra-agua mas marcado). Se arma una vez por redibujado en tres listas de
## segmentos (draw_multiline), no una llamada por linea.
func _draw_on_land(origin: Vector2, cs: float, w: int, h: int) -> void:
	var minor := PackedVector2Array()
	var major := PackedVector2Array()
	var border := PackedVector2Array()
	# Verticales: entre la celda (x-1, y) y la (x, y).
	for y in range(h):
		for x in range(w + 1):
			var a := GridManager.is_land_cell(Vector2i(x - 1, y))
			var b := GridManager.is_land_cell(Vector2i(x, y))
			if not a and not b:
				continue
			var seg := [origin + Vector2(x * cs, y * cs), origin + Vector2(x * cs, (y + 1) * cs)]
			# (Las Packed* se copian al asignarlas: se anade a cada una por su nombre.)
			if a != b:
				border.append_array(PackedVector2Array(seg))
			elif x % 5 == 0:
				major.append_array(PackedVector2Array(seg))
			else:
				minor.append_array(PackedVector2Array(seg))
	# Horizontales: entre la celda (x, y-1) y la (x, y).
	for y in range(h + 1):
		for x in range(w):
			var a := GridManager.is_land_cell(Vector2i(x, y - 1))
			var b := GridManager.is_land_cell(Vector2i(x, y))
			if not a and not b:
				continue
			var seg := [origin + Vector2(x * cs, y * cs), origin + Vector2((x + 1) * cs, y * cs)]
			# (Las Packed* se copian al asignarlas: se anade a cada una por su nombre.)
			if a != b:
				border.append_array(PackedVector2Array(seg))
			elif y % 5 == 0:
				major.append_array(PackedVector2Array(seg))
			else:
				minor.append_array(PackedVector2Array(seg))
	if not minor.is_empty():
		draw_multiline(minor, LINE, 1.0)
	if not major.is_empty():
		draw_multiline(major, LINE_MAJOR, 1.0)
	if not border.is_empty():
		draw_multiline(border, BORDER, 2.0)
