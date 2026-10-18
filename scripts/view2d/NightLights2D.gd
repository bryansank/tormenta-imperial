extends Node2D
## Las luces de la colonia en la vista 2D: ventanas encendidas y farolas en las
## calzadas, de noche y con la Tormenta encima (feat/vista2d-y-prologo).
##
## Va en su propia CanvasLayer que sigue a la camara (`follow_viewport`), asi
## que el CanvasModulate de StormTint2D NO la apaga: con el mapa azul de noche,
## las luces siguen calidas, y eso es lo que hace que la noche se lea como
## noche sin perder el mapa. Mezcla aditiva: solo suma luz.
##
## Rendimiento ("en una papa", docs/26): ningun _process. StormTint2D le pasa la
## intensidad (`set_intensity`, que solo toca `modulate`, sin repintar) y de dia
## esta oculta: cero coste. La lista de puntos se rehace solo cuando cambia el
## mapa (GridManager.map_version) o llega una ruina, una reparacion, una obra
## acabada o una carga, y solo si las luces se ven. Todo es una textura de
## brillo compartida pintada N veces (un solo lote), con tope MAX_POINTS.

const View2D := preload("res://scripts/view2d/View2D.gd")

const MAX_POINTS := 360
## Una farola cada tantas calzadas (por hash de la celda: siempre las mismas).
const LAMP_EVERY := 4
const WINDOW_COLOR := Color(1.0, 0.78, 0.42, 0.85)
const LAMP_COLOR := Color(1.0, 0.86, 0.55, 0.95)

static var _glow: Texture2D = null

## Cada punto: Vector3(x, y, radio) en px de mapa; tipo en `_kinds` (0 ventana, 1 farola).
var _points: PackedVector3Array = PackedVector3Array()
var _kinds: PackedByteArray = PackedByteArray()
var _intensity := 0.0
var _dirty := true
var _built_version := -1

func _ready() -> void:
	name = "NightLights"
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	visible = false
	modulate = Color(1, 1, 1, 0)
	for sig in [EventBus.building_ruined, EventBus.building_repaired, EventBus.construction_completed,
			EventBus.game_load_completed, EventBus.game_new_started, EventBus.building_demolished]:
		(sig as Signal).connect(_mark_dirty)

func _mark_dirty(_a = null, _b = null) -> void:
	_dirty = true
	if visible:
		_rebuild_if_needed()

func get_intensity() -> float:
	return _intensity

func point_count() -> int:
	return _points.size()

## 0 = apagadas (ocultas, sin coste), 1 = noche cerrada. Solo toca modulate.
func set_intensity(value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	if absf(value - _intensity) < 0.01 and (value > 0.0) == visible:
		return
	_intensity = value
	var on := value > 0.02
	if on != visible:
		visible = on
	if on:
		_rebuild_if_needed()
		modulate = Color(1, 1, 1, value)

func _rebuild_if_needed() -> void:
	var v := GridManager.map_version()
	if not _dirty and v == _built_version:
		return
	_dirty = false
	_built_version = v
	rebuild()

## Rehace la lista de luces desde la rejilla. Publico para las pruebas.
func rebuild() -> void:
	var pts := PackedVector3Array()
	var kinds := PackedByteArray()
	var cell := View2D.cell_px()
	for info in GridManager.buildings_view():
		if pts.size() >= MAX_POINTS:
			break
		var node: Node = info.get("node")
		var data: BuildingData = info.get("data")
		if node == null or data == null or not is_instance_valid(node):
			continue
		if node.has_meta("under_construction") or BuildingHealth.is_ruined(node):
			continue
		var cells: Array = info.get("cells", [])
		if cells.is_empty():
			continue
		for p in lights_for(data.id, cells, cell):
			pts.append(p)
			kinds.append(1 if data.id == "road" else 0)
	_points = pts
	_kinds = kinds
	queue_redraw()

## Las luces de un edificio de `cells` (px de mapa, Vector3 x, y, radio). La
## calzada lleva farola una de cada LAMP_EVERY celdas (por hash); los demas,
## ventanas: una por cada cuatro casillas de huella, hasta tres, en sitios
## fijos de su huella. Pura, para las pruebas.
static func lights_for(id: String, cells: Array, cell_px: float) -> Array:
	var out: Array = []
	var lo: Vector2i = cells[0]
	var hi: Vector2i = cells[0]
	for c in cells:
		var ci: Vector2i = c
		lo = Vector2i(mini(lo.x, ci.x), mini(lo.y, ci.y))
		hi = Vector2i(maxi(hi.x, ci.x), maxi(hi.y, ci.y))
	var origin := View2D.cell_origin_px(lo)
	var size := Vector2(hi - lo + Vector2i.ONE) * cell_px
	if id == "road":
		if posmod(lo.x * 7 + lo.y * 13, LAMP_EVERY) == 0:
			out.append(Vector3(origin.x + cell_px * 0.15, origin.y + cell_px * 0.15, cell_px * 0.9))
		return out
	var n := clampi(int(cells.size() / 4.0), 1, 3)
	var spots := [Vector2(0.3, 0.62), Vector2(0.7, 0.4), Vector2(0.5, 0.78)]
	var h := posmod(lo.x * 31 + lo.y * 17, 3)
	for i in n:
		var s: Vector2 = spots[(i + h) % spots.size()]
		var p := origin + size * s
		out.append(Vector3(p.x, p.y, cell_px * 0.75))
	return out

## El brillo: un disco con borde suave, generado una vez y compartido.
static func glow_texture() -> Texture2D:
	if _glow == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.25, Color(1, 1, 1, 0.75))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_glow = t
	return _glow

func _draw() -> void:
	var tex := glow_texture()
	for i in _points.size():
		var p := _points[i]
		var col := LAMP_COLOR if _kinds[i] == 1 else WINDOW_COLOR
		var r := p.z
		draw_texture_rect(tex, Rect2(p.x - r, p.y - r, r * 2.0, r * 2.0), false, col)
		# El foco: un punto pequeno y vivo en el centro.
		draw_texture_rect(tex, Rect2(p.x - r * 0.22, p.y - r * 0.22, r * 0.44, r * 0.44), false, Color(1, 0.95, 0.8, 1))
