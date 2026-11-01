extends Node2D
## El icono de "listo para recoger" en la vista 2D (2026-10-04): la misma ficha
## que StockIcon3D (icono del recurso en un disco claro y la cantidad debajo),
## encima del edificio, contraescalada para leerse a cualquier zoom y subiendo y
## bajando. Lleno, late en rojo. BuildingPlacer2D lo busca por su nombre,
## "StockIcon", para recoger con un toque.
##
## Rebote de premio (V2, rediseno 2026-10-14): al aparecer salta de pequeno a su
## tamano y luego bota cada HOP_PERIOD s en vez de mecerse.
##
## Sin _process (perf/coste-fotograma, 2026-11-01): en la colonia grande habia
## decenas de iconos esperando y cada uno recolocaba su escala cada fotograma.
## Ahora el bote y el latido de "lleno" los hace un shader con TIME (dos
## materiales compartidos, uno por estado), el salto de entrada un Tween de
## APPEAR_TIME s, y el contraescalado al zoom se recalcula en `place()`, que
## llaman el propio icono al cambiar y el reloj de la vista 2D al cambiar el
## zoom o la huella (Building2D.place_badge).

const ICON_PX := 26.0
const DISC_R := 19.0
## El bote: cada HOP_PERIOD s sube HOP_PX en HOP_TIME s y cae; al aparecer
## crece en APPEAR_TIME s.
const HOP_PERIOD := 1.3
const HOP_TIME := 0.4
const HOP_PX := 9.0
const APPEAR_TIME := 0.3

var _building: Node2D = null
var _full := false
var _total := 0
var _res := ""
var _tex: Texture2D = null
## Factor del salto de entrada (1 = a su tamano). Lo mueve un Tween.
var _appear_k := 1.0
var _appear_tween: Tween = null

const _SHADER := """
shader_type canvas_item;
uniform bool full = false;
const float HOP_PERIOD = 1.3;
const float HOP_TIME = 0.4;
const float HOP_PX = 9.0;
void vertex() {
	if (full) {
		VERTEX *= 1.0 + 0.12 * (0.5 + 0.5 * sin(TIME * 7.0));
	} else {
		float p = mod(TIME, HOP_PERIOD);
		if (p < HOP_TIME) {
			VERTEX.y -= sin(p / HOP_TIME * PI) * HOP_PX;
		}
	}
}
"""
static var _materials: Array = []

## Los dos materiales compartidos: [bota, late lleno].
static func _material_for(full: bool) -> ShaderMaterial:
	if _materials.is_empty():
		var sh := Shader.new()
		sh.code = _SHADER
		for f in [false, true]:
			var m := ShaderMaterial.new()
			m.shader = sh
			m.set_shader_parameter("full", f)
			_materials.append(m)
	return _materials[1 if full else 0]

func setup(building: Node2D) -> void:
	_building = building
	name = "StockIcon"
	z_index = 35
	refresh()

func _ready() -> void:
	set_process(false)
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
	var was_visible := visible
	visible = _total > 0
	_full = visible and ProductionManager.is_full(_building)
	material = _material_for(_full)
	if visible and not was_visible:
		_start_appear()
	if top_res != "" and top_res != _res:
		_res = top_res
		_tex = UITheme.icon_texture(_res, 42)
	place()
	queue_redraw()

## El salto de entrada: de pequeno a su tamano, con un rebote, en APPEAR_TIME s.
func _start_appear() -> void:
	if _appear_tween != null and _appear_tween.is_valid():
		_appear_tween.kill()
	_appear_tween = null
	if not is_inside_tree():
		_appear_k = 1.0
		return
	_set_appear(0.0)
	_appear_tween = create_tween()
	_appear_tween.tween_method(_set_appear, 0.0, 1.0, APPEAR_TIME)

func _set_appear(a: float) -> void:
	_appear_k = 1.0 if a >= 1.0 else lerpf(0.3, 1.0, a) + 0.25 * sin(PI * a)
	place()

## Contraescalado al zoom y sitio encima de la huella. Solo cambia con el zoom,
## la huella o el salto de entrada; el bote va en el shader.
func place() -> void:
	if not visible or _building == null or not is_instance_valid(_building) or not is_inside_tree():
		return
	var inv: float = _building.label_scale(self) if _building.has_method("label_scale") else 1.0
	scale = Vector2(inv, inv) * _appear_k
	var fp: Vector2 = _building.footprint_px() if _building.has_method("footprint_px") else Vector2(32, 32)
	position = Vector2(0, -fp.y * 0.5 - 18.0 * inv)

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
