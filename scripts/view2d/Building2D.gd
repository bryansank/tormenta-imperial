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
## Obra por fases, ruina y actividad: la misma regla que en 3D (docs/03).
const LookRule := preload("res://scripts/buildings/BuildingLook.gd")
const Fx := preload("res://scripts/buildings/BuildingFx.gd")

var data: BuildingData = null
## Fantasma de colocacion: no esta en la rejilla, se pinta translucido.
var ghost := false
var ghost_valid := true

var _selected := false
var _signature: Array = []
var _pulse := 0.0
var _name_label: Label = null
## Veredicto de LookRule.derive() del ultimo repintado.
var _look: Dictionary = {"look": LookRule.Look.IDLE, "phase": 0}
## Humo/luz de "trabajando" (creado la primera vez) y humo negro de la ruina.
var _active_fx: Node2D = null
var _ruin_fx: Node2D = null

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
	_name_label.text = _label_text()
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
			_name_label.text = _label_text()
		_apply_fx()
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
	_look = LookRule.derive(LookRule.facts_of(self, data))
	return [constructing, progress, int(get_meta("level", 1)), int(get_meta("health", data.max_health)),
		BuildingHealth.is_ruined(self), mask, int(get_meta("rotation_steps", 0)), String(get_meta("custom_name", "")),
		Tr.get_locale(), int(_look["look"]), int(_look["phase"])]

func get_look() -> Dictionary:
	return _look

func get_active_fx() -> Node2D:
	return _active_fx

func get_ruin_fx() -> Node2D:
	return _ruin_fx

## Enciende o apaga los efectos animados segun el aspecto. Los sprites los
## anima un shader (BuildingFx): aqui solo se crean una vez y se muestran.
func _apply_fx() -> void:
	var look := int(_look["look"])
	if look == LookRule.Look.ACTIVE and _active_fx == null:
		_active_fx = _make_active_fx()
	if _active_fx:
		_active_fx.visible = look == LookRule.Look.ACTIVE
		_place_fx(_active_fx)
	if look == LookRule.Look.RUIN and _ruin_fx == null:
		_ruin_fx = Node2D.new()
		_ruin_fx.name = "RuinFx"
		_ruin_fx.z_index = 6
		var smoke := Fx.sprite_2d("smoke", minf(footprint_px().x, footprint_px().y) * 0.7, "ruin")
		smoke.position = Vector2(0, -footprint_px().y * 0.2)
		_ruin_fx.add_child(smoke)
		add_child(_ruin_fx)
	if _ruin_fx:
		_ruin_fx.visible = look == LookRule.Look.RUIN

func _make_active_fx() -> Node2D:
	var kind := LookRule.fx_kind(data.id)
	if kind == "":
		return null
	var holder := Node2D.new()
	holder.name = "ActiveFx"
	holder.z_index = 6
	var size := minf(base_size_px().x, base_size_px().y)
	for anchor in Art.fx_anchors(data.id):
		var sprite := Fx.sprite_2d(kind, size * (0.6 if kind == "glow" else 0.85))
		sprite.set_meta("anchor", anchor)
		holder.add_child(sprite)
	add_child(holder)
	return holder

## Cada sprite en su chimenea, con el giro del edificio aplicado. El humo sube
## un poco por encima de la boca para que salga de ella y no la tape.
func _place_fx(holder: Node2D) -> void:
	var size := base_size_px()
	var angle := float(int(get_meta("rotation_steps", 0))) * PI * 0.5
	for sprite in holder.get_children():
		var anchor: Vector2 = sprite.get_meta("anchor", Vector2(0.5, 0.5))
		var local := (anchor - Vector2(0.5, 0.5)) * size
		var rise := 0.04 if String(sprite.name).ends_with("glow") else 0.28
		sprite.position = local.rotated(angle) + Vector2(0, -size.y * rise)

## El rotulo: el nombre que le puso el jugador o, si no tiene, el del edificio en
## el idioma actual. Nunca el campo crudo del .tres, que esta en espanol.
func _label_text() -> String:
	var custom := String(get_meta("custom_name", ""))
	return custom if custom != "" else data.get_display_name()

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
	var look := int(_look["look"]) if not ghost else LookRule.Look.IDLE
	var n := LookRule.footprint_class(data.grid_size)
	if look == LookRule.Look.CONSTRUCTION:
		# Obra nueva: la fase de la huella EN LUGAR del edificio (que aun no esta).
		Art.draw_construction_phase(self, size, int(_look["phase"]),
			ProductionManager.get_construction_progress(self), n)
	else:
		Art.draw_building(self, data.id, size, {"road_mask": mask, "level": level, "shadow": not ghost})
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if ghost:
		return
	var fp2 := footprint_px()
	if look == LookRule.Look.UPGRADE:
		# Mejora: el edificio sigue a la vista, con andamio y rayas encima.
		Art.draw_construction(self, fp2, ProductionManager.get_construction_progress(self))
	var ratio := BuildingHealth.get_health_ratio(self)
	var ruined := BuildingHealth.is_ruined(self)
	if ratio < 1.0 or ruined:
		Art.draw_damage(self, fp2, ratio, ruined, hash(name), n)
	if _selected:
		Art.draw_selection(self, fp2, _pulse)
