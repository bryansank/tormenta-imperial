extends Node2D
## Un edificio en la vista 2D. Es la entidad que ven los servicios: la misma que
## en 3D era un Node3D, con los mismos metadatos (level, rotation_steps, health,
## staffed, under_construction, custom_name) y los mismos hijos con nombre
## ("NameLabel", "StatusBadge", "ConstructionLabel") que ellos buscan.
##
## No escucha senales para pintarse: cada frame compara una firma barata de su
## estado (obra, nivel, vida, calzadas vecinas, seleccion) y solo repinta si ha
## cambiado. Asi una partida cargada, una tormenta o una reparacion se ven sin
## que ningun servicio sepa que existe la vista 2D.

const Art := preload("res://scripts/view2d/BuildingArt2D.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const StatusBadge2D := preload("res://scripts/view2d/StatusBadge2D.gd")
const View2D := preload("res://scripts/view2d/View2D.gd")

var data: BuildingData = null
## Fantasma de colocacion: no esta en la rejilla, se pinta translucido.
var ghost := false
var ghost_valid := true

var _selected := false
var _signature: Array = []
var _pulse := 0.0
var _name_label: Label = null

func setup(building_data: BuildingData, is_ghost: bool = false) -> void:
	data = building_data
	ghost = is_ghost
	name = data.id
	if ghost:
		z_index = 20
		return
	z_index = 2
	_name_label = Label.new()
	_name_label.name = "NameLabel"
	_name_label.text = data.display_name
	_name_label.visible = false
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_name_label.add_theme_constant_override("outline_size", 5)
	_name_label.z_index = 40
	add_child(_name_label)
	var badge: Node2D = StatusBadge2D.new()
	add_child(badge)
	badge.setup(self, data)

func set_selected(value: bool) -> void:
	_selected = value
	if _name_label:
		_name_label.visible = value
	queue_redraw()

func is_selected() -> bool:
	return _selected

## Huella sin girar, en pixeles.
func base_size_px() -> Vector2:
	return Vector2(data.grid_size) * View2D.cell_px() if data else Vector2.ONE * View2D.cell_px()

## Huella con el giro aplicado (la que ocupa en la rejilla), en pixeles.
func footprint_px() -> Vector2:
	var steps: int = get_meta("rotation_steps", 0)
	return Vector2(Rules.rotated_size(data, steps)) * View2D.cell_px()

## ProductionManager llama aqui en vez de montar su Label3D: la obra la pinta el
## propio edificio y el texto de progreso lo actualiza ProductionManager.
func apply_construction_visual() -> void:
	if get_node_or_null("ConstructionLabel") == null:
		var label := Label.new()
		label.name = "ConstructionLabel"
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		label.add_theme_constant_override("outline_size", 4)
		label.z_index = 41
		add_child(label)
	queue_redraw()

func _process(delta: float) -> void:
	if data == null:
		return
	if _selected:
		_pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
		queue_redraw()
	_layout_labels()
	if ghost:
		return
	var sig := _current_signature()
	if sig != _signature:
		_signature = sig
		if _name_label:
			_name_label.text = String(get_meta("custom_name", data.display_name))
		queue_redraw()

func _current_signature() -> Array:
	var constructing := has_meta("under_construction")
	var progress := 0
	if constructing:
		progress = int(ProductionManager.get_construction_progress(self) * 20.0)
	var mask := 0
	if data.id == "road":
		var info := GridManager.get_building_info(self)
		if not info.is_empty():
			mask = Rules.road_neighbor_mask(info["origin_cell"])
	return [constructing, progress, int(get_meta("level", 1)), int(get_meta("health", data.max_health)),
		BuildingHealth.is_ruined(self), mask, int(get_meta("rotation_steps", 0)), String(get_meta("custom_name", ""))]

## Los rotulos no giran ni crecen con el zoom: se contraescalan para leerse igual
## a cualquier distancia.
func _layout_labels() -> void:
	var inv := label_scale(self)
	var fp := footprint_px()
	var below := fp.y * 0.5 + 2.0
	var cl: Label = get_node_or_null("ConstructionLabel")
	if cl:
		cl.scale = Vector2(inv, inv)
		cl.reset_size()
		cl.position = Vector2(-cl.size.x * 0.5 * inv, below)
		below += cl.size.y * inv
	if _name_label and _name_label.visible:
		_name_label.scale = Vector2(inv, inv)
		_name_label.reset_size()
		_name_label.position = Vector2(-_name_label.size.x * 0.5 * inv, below)

## Escala de los rotulos y badges: tamano de pantalla constante de cerca, y
## algo mas pequenos al alejarse para no tapar el mapa.
static func label_scale(ci: CanvasItem) -> float:
	var cam := ci.get_viewport().get_camera_2d() if ci.is_inside_tree() else null
	if cam == null:
		return 1.0
	var boost: float = cam.screen_boost() if cam.has_method("screen_boost") else 1.0
	var z := cam.zoom.x
	return clampf(z / boost / 1.8, 0.6, 1.0) * boost / z

func _draw() -> void:
	if data == null:
		return
	var steps: int = get_meta("rotation_steps", 0)
	var size := base_size_px()
	var mask := 0
	if data.id == "road" and not ghost:
		var info := GridManager.get_building_info(self)
		if not info.is_empty():
			mask = Rules.road_neighbor_mask(info["origin_cell"])
	if ghost:
		var fp := footprint_px()
		var tint := Color(0.2, 0.85, 0.2, 0.28) if ghost_valid else Color(0.9, 0.2, 0.2, 0.34)
		draw_rect(Rect2(-fp * 0.5, fp), tint)
		draw_rect(Rect2(-fp * 0.5, fp), Color(tint, 0.9), false, 2.0)
	# Las calzadas no giran: sus uniones ya dicen hacia donde van.
	var angle := 0.0 if data.id == "road" else steps * PI * 0.5
	draw_set_transform(Vector2.ZERO, angle, Vector2.ONE)
	var level: int = get_meta("level", 1)
	Art.draw_building(self, data.id, size, {"road_mask": mask, "level": level, "shadow": not ghost})
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if ghost:
		return
	var fp2 := footprint_px()
	if has_meta("under_construction"):
		Art.draw_construction(self, fp2, ProductionManager.get_construction_progress(self))
	var ratio := BuildingHealth.get_health_ratio(self)
	var ruined := BuildingHealth.is_ruined(self)
	if ratio < 1.0 or ruined:
		Art.draw_damage(self, fp2, ratio, ruined, hash(name))
	if _selected:
		Art.draw_selection(self, fp2, _pulse)
