extends Node3D
## El icono flotante de "listo para recoger" sobre un edificio en 3D
## (2026-10-04). Aparece cuando el edificio tiene algo acumulado: una ficha
## redonda con el icono del recurso y la cantidad debajo, que sube y baja para
## llamar la atencion. Lleno, late y su aro se pone rojo (el edificio esta
## parado). Un toque encima recoge (BuildingPlacer._try_collect_icon); tocar el
## edificio tambien.
##
## Se llama "StockIcon": el placer lo busca por ese nombre para el toque.

const ICON_PX := 60
const BASE_PIXEL := 0.02
const BOB := 0.15

var _building: Node3D = null
var _base_y := 3.0
var _disc: Sprite3D = null
var _icon: Sprite3D = null
var _label: Label3D = null
var _full := false
var _res := ""

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
		set_process(false)
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
	# Sin nada que recoger no se mece: ni un _process por productor parado.
	set_process(visible)
	if not visible:
		return
	_full = ProductionManager.is_full(_building)
	if top_res != _res:
		_res = top_res
		_icon.texture = UITheme.icon_texture(_res, ICON_PX)
	_label.text = "+%d" % total
	_label.modulate = Color(1.0, 0.45, 0.35) if _full else Color(1, 1, 1)
	_disc.modulate = Color(1.0, 0.4, 0.3) if _full else Color(1.0, 0.92, 0.6)

func _process(_delta: float) -> void:
	if not visible:
		return
	var t := Time.get_ticks_msec() * 0.001
	position.y = _base_y + sin(t * 3.0) * BOB
	var s := 1.0 + (0.12 * (0.5 + 0.5 * sin(t * 7.0)) if _full else 0.0)
	scale = Vector3(s, s, s)

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
