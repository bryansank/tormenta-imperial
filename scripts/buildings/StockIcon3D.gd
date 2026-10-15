extends Node3D
## El icono flotante de "listo para recoger" sobre un edificio en 3D
## (2026-10-04). Aparece cuando el edificio tiene algo acumulado: una ficha
## redonda con el icono del recurso y la cantidad debajo, que sube y baja para
## llamar la atencion. Lleno, late y su aro se pone rojo (el edificio esta
## parado).
##
## Rebote de premio (V2, rediseno 2026-10-14): al aparecer salta de pequeno a su
## tamano y luego bota cada poco (sube, cae y se aplasta un pelo al tocar). Todo
## con un Tween en bucle que solo existe mientras hay algo que recoger: sin
## _process por icono (antes, un seno por fotograma). Un toque encima recoge (BuildingPlacer._try_collect_icon); tocar el
## edificio tambien.
##
## Se llama "StockIcon": el placer lo busca por ese nombre para el toque.

const ICON_PX := 60
const BASE_PIXEL := 0.02
## El bote: altura, subida, caida y pausa hasta el siguiente.
const HOP := 0.45
const HOP_UP := 0.18
const HOP_DOWN := 0.22
const HOP_REST := 0.9

var _building: Node3D = null
var _base_y := 3.0
var _disc: Sprite3D = null
var _icon: Sprite3D = null
var _label: Label3D = null
var _full := false
var _res := ""
## Animacion en marcha: 0 ninguna, 1 bote, 2 latido de lleno.
var _anim := 0
var _anim_tween: Tween = null

static var _disc_tex: Texture2D = null

func setup(building: Node3D, top_y: float) -> void:
	_building = building
	name = "StockIcon"
	_base_y = top_y + 2.4
	position.y = _base_y
	_disc = Sprite3D.new()
	_disc.name = "Disc"
	_disc.texture = disc_texture()
	_disc.pixel_size = 0.0125
	_disc.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_disc.no_depth_test = true
	_disc.render_priority = 2
	add_child(_disc)
	_icon = Sprite3D.new()
	_icon.name = "Icon"
	_icon.pixel_size = BASE_PIXEL * 0.9
	_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_icon.no_depth_test = true
	_icon.render_priority = 3
	add_child(_icon)
	_label = Label3D.new()
	_label.name = "Amount"
	_label.font_size = 40
	_label.pixel_size = 0.0125
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.outline_size = 10
	_label.outline_modulate = Color(0, 0, 0, 0.9)
	_label.position.y = -0.95
	_label.render_priority = 3
	add_child(_label)
	add_to_group("building_fx")
	refresh()

func _ready() -> void:
	EventBus.building_stock_changed.connect(_on_stock_changed)
	EventBus.building_upgrade_completed.connect(func(n, _l): if n == _building: refresh())
	refresh()

func _on_stock_changed(node: Node, _stock: Dictionary) -> void:
	if node == _building:
		refresh()

## Relee lo acumulado y repinta.
func refresh() -> void:
	if _building == null or not is_instance_valid(_building) or _label == null:
		visible = false
		_set_anim(0)
		return
	var stock: Dictionary = ProductionManager.get_stock(_building)
	var total := 0
	var top_res := ""
	var top_amount := -1
	for res_name in stock:
		total += int(stock[res_name])
		if int(stock[res_name]) > top_amount:
			top_amount = int(stock[res_name])
			top_res = String(res_name)
	visible = total > 0
	# Sin nada que recoger no se mece: el Tween se mata.
	if not visible:
		_set_anim(0)
		return
	_full = ProductionManager.is_full(_building)
	_set_anim(2 if _full else 1)
	if top_res != _res:
		_res = top_res
		_icon.texture = UITheme.icon_texture(_res, ICON_PX)
	_label.text = "+%d" % total
	_label.modulate = Color(1.0, 0.45, 0.35) if _full else Color(1, 1, 1)
	_disc.modulate = Color(1.0, 0.4, 0.3) if _full else Color(1.0, 0.92, 0.6)

## Cambia de animacion solo si cambia el estado (lo acumulado cambia a cada
## ciclo de produccion: el bote no se reinicia por eso).
func _set_anim(kind: int) -> void:
	if kind == _anim and (kind == 0 or (_anim_tween != null and _anim_tween.is_valid())):
		return
	if not is_inside_tree():
		return
	var appearing := _anim == 0
	_anim = kind
	if _anim_tween != null and _anim_tween.is_valid():
		_anim_tween.kill()
	_anim_tween = null
	position.y = _base_y
	scale = Vector3.ONE
	if kind == 0:
		return
	var tw := create_tween()
	if appearing:
		# Aparece: de pequeno a su tamano, con un pasito de mas.
		scale = Vector3.ONE * 0.3
		tw.tween_property(self, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var loop := create_tween().set_loops()
	if kind == 1:
		loop.tween_property(self, "position:y", _base_y + HOP, HOP_UP).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		loop.tween_property(self, "position:y", _base_y, HOP_DOWN).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		loop.tween_property(self, "scale", Vector3(1.12, 0.86, 1.12), 0.06)
		loop.tween_property(self, "scale", Vector3.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		loop.tween_interval(HOP_REST)
	else:
		# Lleno: late en rojo, mas rapido (el edificio esta parado).
		loop.tween_property(self, "scale", Vector3.ONE * 1.14, 0.22).set_trans(Tween.TRANS_SINE)
		loop.tween_property(self, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_SINE)
	if appearing:
		loop.pause()
		tw.tween_callback(loop.play)
	_anim_tween = loop

func is_full() -> bool:
	return _full

## Ficha redonda clara con aro oscuro, 64 px, dibujada una vez.
static func disc_texture() -> Texture2D:
	if _disc_tex != null:
		return _disc_tex
	var n := 96
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(n * 0.5, n * 0.5)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d <= n * 0.48:
				img.set_pixel(x, y, Color(0.08, 0.06, 0.04, 0.95))
			if d <= n * 0.43:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
			if d <= n * 0.37:
				img.set_pixel(x, y, Color(0.16, 0.13, 0.1, 0.92))
	_disc_tex = ImageTexture.create_from_image(img)
	return _disc_tex
