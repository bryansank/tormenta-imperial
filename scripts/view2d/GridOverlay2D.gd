extends Node2D
## La rejilla de celdas en la vista 2D. Mismas reglas que GridOverlayControl:
## visible segun GameConfig.ui_grid_visible (interruptor de Ajustes, senal
## grid_overlay_toggled) y el colocador la fuerza visible mientras se coloca.
## Se llama "GridOverlay" en la escena para que el colocador la encuentre igual
## que en 3D. Medida desde GridManager, nunca a mano.

const View2D := preload("res://scripts/view2d/View2D.gd")

const LINE := Color(0.92, 0.92, 0.80, 0.13)
const LINE_MAJOR := Color(0.95, 0.92, 0.75, 0.22)
const BORDER := Color(0.95, 0.85, 0.55, 0.35)

func _ready() -> void:
	z_index = -10
	visible = GameConfig.ui_grid_visible
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
	for x in range(w + 1):
		var col := LINE_MAJOR if x % 5 == 0 else LINE
		draw_line(origin + Vector2(x * cs, 0), origin + Vector2(x * cs, h * cs), col, 1.0)
	for y in range(h + 1):
		var col := LINE_MAJOR if y % 5 == 0 else LINE
		draw_line(origin + Vector2(0, y * cs), origin + Vector2(w * cs, y * cs), col, 1.0)
	draw_rect(Rect2(origin, Vector2(w, h) * cs), BORDER, false, 2.0)
