extends Node2D
## El icono de "listo para recoger" en la vista 2D (2026-10-04): la misma ficha
## que StockIcon3D (icono del recurso en un disco claro y la cantidad debajo),
## encima del edificio, contraescalada para leerse a cualquier zoom y subiendo y
## bajando. Lleno, late en rojo. BuildingPlacer2D lo busca por su nombre,
## "StockIcon", para recoger con un toque.

const ICON_PX := 26.0
const DISC_R := 19.0

var _building: Node2D = null
var _full := false
var _total := 0
var _res := ""
var _tex: Texture2D = null

func setup(building: Node2D) -> void:
	_building = building
	name = "StockIcon"
	z_index = 35
	refresh()

func _ready() -> void:
	EventBus.building_stock_changed.connect(_on_stock_changed)
	refresh()

func _on_stock_changed(node: Node, _stock: Dictionary) -> void:
	if node == _building:
		refresh()

func refresh() -> void:
	if _building == null or not is_instance_valid(_building):
		visible = false
		return
	var stock: Dictionary = ProductionManager.get_stock(_building)
	_total = 0
	var top_amount := -1
	var top_res := ""
	for res_name in stock:
		_total += int(stock[res_name])
		if int(stock[res_name]) > top_amount:
			top_amount = int(stock[res_name])
			top_res = String(res_name)
	visible = _total > 0
	_full = visible and ProductionManager.is_full(_building)
	if top_res != "" and top_res != _res:
		_res = top_res
		_tex = UITheme.icon_texture(_res, 42)
	queue_redraw()

func _process(_delta: float) -> void:
	if not visible or _building == null:
		return
	var inv: float = _building.label_scale(self) if _building.has_method("label_scale") else 1.0
	var t := Time.get_ticks_msec() * 0.001
	var pulse := 1.0 + (0.12 * (0.5 + 0.5 * sin(t * 7.0)) if _full else 0.0)
	scale = Vector2(inv, inv) * pulse
	var fp: Vector2 = _building.footprint_px() if _building.has_method("footprint_px") else Vector2(32, 32)
	position = Vector2(0, -fp.y * 0.5 - 18.0 * inv + sin(t * 3.0) * 4.0 * inv)

func _draw() -> void:
	if _total <= 0:
		return
	var ring := Color(1.0, 0.4, 0.3) if _full else Color(1.0, 0.92, 0.6)
	draw_circle(Vector2.ZERO, DISC_R + 2.0, Color(0.08, 0.06, 0.04, 0.95))
	draw_circle(Vector2.ZERO, DISC_R, ring)
	draw_circle(Vector2.ZERO, DISC_R - 3.0, Color(0.16, 0.13, 0.1, 0.92))
	if _tex != null:
		draw_texture_rect(_tex, Rect2(Vector2(-ICON_PX, -ICON_PX) * 0.5, Vector2(ICON_PX, ICON_PX)), false)
	var font := ThemeDB.fallback_font
	var text := "+%d" % _total
	var fs := 14
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(-w * 0.5, DISC_R + fs + 1.0)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.5, 0.4) if _full else Color(1, 1, 1))

func is_full() -> bool:
	return _full
